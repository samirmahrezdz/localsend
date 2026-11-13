import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/cross_file.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/pages/home_page.dart';
import 'package:localsend_app/pages/home_page_controller.dart';
import 'package:localsend_app/provider/device_info_provider.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/http_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/send_provider.dart';
import 'package:localsend_app/provider/selection/selected_sending_files_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/ui/snackbar.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:localsend_isolates/rust/api/model.dart';
import 'package:localsend_isolates/util/rust.dart';
import 'package:logging/logging.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

const quickSendFlag = '--quick-send';
final _logger = Logger('QuickSend');

@immutable
class QuickSendStatus {
  final bool isBusy;
  final String? targetAlias;

  const QuickSendStatus({
    this.isBusy = false,
    this.targetAlias,
  });

  @override
  bool operator ==(Object other) {
    return identical(this, other) || other is QuickSendStatus && isBusy == other.isBusy && targetAlias == other.targetAlias;
  }

  @override
  int get hashCode => Object.hash(isBusy, targetAlias);
}

/// Returns true when CLI/handover arguments should trigger an instant send to the default target.
bool shouldAutoSendForArgs({
  required List<String> args,
  required SettingsState settings,
}) {
  return args.contains(quickSendFlag) || (settings.autoSendToDefault && settings.defaultTargetFingerprint != null);
}

/// Returns true when an incoming share intent should auto-send to the default target.
bool shouldAutoSendForShare({required SettingsState settings}) {
  return settings.autoSendToDefault && settings.defaultTargetFingerprint != null;
}

/// Looks up [fingerprint] among currently discovered LAN/WebRTC devices.
Device? resolveDiscoveredDevice({
  required Map<String, Device> allDevices,
  required String fingerprint,
}) {
  return allDevices[fingerprint];
}

/// Returns a friendly display name for [fingerprint] from favorites or discovered devices.
String resolveTargetDisplayName({
  required String fingerprint,
  required List<FavoriteDevice> favorites,
  required Map<String, Device> allDevices,
}) {
  final favorite = favorites.firstWhereOrNull((e) => e.fingerprint == fingerprint);
  if (favorite != null) {
    return favorite.alias;
  }
  final device = allDevices[fingerprint];
  if (device != null) {
    return device.alias;
  }
  return fingerprint.length > 8 ? fingerprint.substring(0, 8) : fingerprint;
}

final quickSendProvider = NotifierProvider<QuickSendService, QuickSendStatus>((ref) {
  return QuickSendService();
});

class QuickSendService extends Notifier<QuickSendStatus> {
  static const batchDebounceDuration = Duration(milliseconds: 450);
  static const discoveryPollInterval = Duration(milliseconds: 250);
  static const discoveryWaitTimeout = Duration(milliseconds: 3500);

  Timer? _debounceTimer;
  bool _pendingAfterBusy = false;
  bool _explicitQuickSend = false;

  @override
  QuickSendStatus init() => const QuickSendStatus();

  @override
  void dispose() {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    super.dispose();
  }

  /// Schedules an automatic send to the configured default target after [batchDebounceDuration].
  /// Calling this repeatedly while Windows Explorer launches per-file invocations merges them into one batch.
  void scheduleQuickSend({bool explicitQuickSend = false}) {
    _explicitQuickSend = _explicitQuickSend || explicitQuickSend;
    if (state.isBusy) {
      _pendingAfterBusy = true;
      return;
    }

    _debounceTimer?.cancel();
    _debounceTimer = Timer(batchDebounceDuration, () {
      _debounceTimer = null;
      // ignore: discarded_futures
      dispatchQuickSendNow();
    });
  }

  /// Immediately resolves the default target device and sends all queued files.
  Future<void> dispatchQuickSendNow({bool explicitQuickSend = false}) async {
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _explicitQuickSend = _explicitQuickSend || explicitQuickSend;

    if (state.isBusy) {
      _pendingAfterBusy = true;
      return;
    }

    final filesInitial = ref.read(selectedSendingFilesProvider);
    if (filesInitial.isEmpty) {
      _explicitQuickSend = false;
      return;
    }

    final settings = ref.read(settingsProvider);
    final targetFingerprint = settings.defaultTargetFingerprint;
    if (targetFingerprint == null) {
      _explicitQuickSend = false;
      _showNotice(t.sendTab.quickSend.noDefaultTarget);
      return;
    }

    final favorites = ref.read(favoritesProvider);
    final allDevices = ref.read(nearbyDevicesProvider).allDevices;
    final alias = resolveTargetDisplayName(
      fingerprint: targetFingerprint,
      favorites: favorites,
      allDevices: allDevices,
    );

    _explicitQuickSend = false;
    state = QuickSendStatus(isBusy: true, targetAlias: alias);

    try {
      final target = await _resolveTargetDevice(targetFingerprint, settings: settings, favorites: favorites);
      if (target == null) {
        _showNotice(t.sendTab.quickSend.targetOffline(alias: alias));
        return;
      }

      // Snapshot after resolution so any files arriving right before handoff join this batch.
      final filesToSend = List<CrossFile>.of(ref.read(selectedSendingFilesProvider));
      if (filesToSend.isEmpty) {
        return;
      }

      ref.redux(selectedSendingFilesProvider).dispatch(ClearSelectionAction());
      await ref.notifier(sendProvider).startSession(target: target, files: filesToSend, background: false);
    } finally {
      state = const QuickSendStatus();
      if (_pendingAfterBusy) {
        _pendingAfterBusy = false;
        scheduleQuickSend(explicitQuickSend: _explicitQuickSend);
      }
    }
  }

  Future<Device?> _resolveTargetDevice(
    String targetFingerprint, {
    required SettingsState settings,
    required List<FavoriteDevice> favorites,
  }) async {
    final immediate = resolveDiscoveredDevice(
      allDevices: ref.read(nearbyDevicesProvider).allDevices,
      fingerprint: targetFingerprint,
    );
    if (immediate != null) {
      return immediate;
    }

    // Kick off LAN multicast discovery in parallel with direct favorite probing.
    ref.redux(nearbyDevicesProvider).dispatch(StartMulticastScan());

    final favorite = favorites.firstWhereOrNull((e) => e.fingerprint == targetFingerprint);
    if (favorite != null) {
      try {
        final payload = ref.read(deviceFullInfoProvider).toRegisterDto();
        final response = await ref
            .read(httpProvider)
            .pinnedTo(favorite.fingerprint)
            .register(
              protocol: settings.https ? ProtocolType.https : ProtocolType.http,
              ip: favorite.ip,
              port: favorite.port,
              payload: payload,
            );
        final device = response.body.toDevice(favorite.ip, favorite.port, settings.https);
        if (device.fingerprint == targetFingerprint) {
          return device;
        }
      } catch (e) {
        _logger.fine('Direct probe to default favorite ${favorite.ip}:${favorite.port} failed: $e');
      }
    }

    final deadline = DateTime.now().add(discoveryWaitTimeout);
    while (DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(discoveryPollInterval);
      final discovered = resolveDiscoveredDevice(
        allDevices: ref.read(nearbyDevicesProvider).allDevices,
        fingerprint: targetFingerprint,
      );
      if (discovered != null) {
        return discovered;
      }
    }

    return null;
  }

  void _showNotice(String text) {
    final context = Routerino.navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger != null) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(text)));
    } else {
      context.showSnackBar(text);
    }
  }
}

/// Shared handler for CLI / single-instance handover arguments.
class HandleExternalArgsAction extends AsyncGlobalAction {
  final List<String> args;

  HandleExternalArgsAction({required this.args});

  @override
  Future<void> reduce() async {
    final hasQuickSendFlag = args.contains(quickSendFlag);
    final filesAdded = await ref.redux(selectedSendingFilesProvider).dispatchAsyncTakeResult(LoadSelectionFromArgsAction(args));
    if (!filesAdded && !(hasQuickSendFlag && ref.read(selectedSendingFilesProvider).isNotEmpty)) {
      return;
    }

    ref.redux(homePageControllerProvider).dispatch(ChangeTabAction(HomeTab.send));

    final settings = ref.read(settingsProvider);
    if (shouldAutoSendForArgs(args: args, settings: settings)) {
      ref.notifier(quickSendProvider).scheduleQuickSend(explicitQuickSend: hasQuickSendFlag);
    }
  }
}
