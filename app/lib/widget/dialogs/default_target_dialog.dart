import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/provider/favorites_provider.dart';
import 'package:localsend_app/provider/network/nearby_devices_provider.dart';
import 'package:localsend_app/provider/network/quick_send_provider.dart';
import 'package:localsend_app/provider/settings_provider.dart';
import 'package:localsend_app/util/device_type_ext.dart';
import 'package:localsend_app/util/native/context_menu_helper.dart';
import 'package:localsend_app/widget/dialogs/custom_bottom_sheet.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:refena_flutter/refena_flutter.dart';
import 'package:routerino/routerino.dart';

/// Persists [fingerprint] (or clears it when null) as the default quick-send target
/// and refreshes the Windows Explorer right-click label if enabled.
///
/// When [device] has an IP and is not yet saved in favorites, also adds it to
/// favorites so its IP/port remain reachable before multicast discovery settles.
Future<void> applyDefaultTargetSelection({
  required Ref ref,
  required String? fingerprint,
  String? alias,
  Device? device,
}) async {
  if (fingerprint != null && device != null && device.ip != null) {
    final existsInFavorites = ref.read(favoritesProvider).any((e) => e.fingerprint == fingerprint);
    if (!existsInFavorites) {
      await ref
          .redux(favoritesProvider)
          .dispatchAsync(
            AddFavoriteAction(
              FavoriteDevice.fromValues(
                fingerprint: device.fingerprint,
                ip: device.ip!,
                port: device.port,
                alias: alias ?? device.alias,
              ),
            ),
          );
    }
  }

  await ref.notifier(settingsProvider).setDefaultTargetFingerprint(fingerprint);
  final resolvedAlias = fingerprint == null
      ? null
      : (alias ??
            resolveTargetDisplayName(
              fingerprint: fingerprint,
              favorites: ref.read(favoritesProvider),
              allDevices: ref.read(nearbyDevicesProvider).allDevices,
            ));
  await refreshContextMenuIfEnabled(targetAlias: resolvedAlias);
}

class DefaultTargetDialog extends StatelessWidget {
  const DefaultTargetDialog({super.key});

  @override
  Widget build(BuildContext context) {
    final ref = context.ref;
    final favorites = ref.watch(favoritesProvider);
    final nearbyDevices = ref.watch(nearbyDevicesProvider).allDevices.values.toList();
    final currentFingerprint = ref.watch(settingsProvider.select((s) => s.defaultTargetFingerprint));

    final nearbyByFingerprint = {
      for (final d in nearbyDevices) d.fingerprint: d,
    };

    final favoriteFingerprints = {for (final f in favorites) f.fingerprint};
    final nonFavoriteNearby = nearbyDevices.where((d) => !favoriteFingerprints.contains(d.fingerprint)).toList();

    return CustomBottomSheet(
      title: t.settingsTab.send.defaultTarget,
      description: t.settingsTab.send.chooseDefaultTargetHint,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 360),
        child: ListView(
          shrinkWrap: true,
          children: [
            if (favorites.isEmpty && nonFavoriteNearby.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  t.dialogs.favoriteDialog.noFavorites,
                  textAlign: TextAlign.center,
                ),
              ),
            for (final fav in favorites)
              _TargetTile(
                alias: fav.alias,
                subtitle: '${fav.ip}:${fav.port} · ${nearbyByFingerprint.containsKey(fav.fingerprint) ? t.general.online : t.general.offline}',
                icon: nearbyByFingerprint[fav.fingerprint]?.deviceType.icon ?? Icons.favorite,
                selected: currentFingerprint == fav.fingerprint,
                onTap: () async {
                  await applyDefaultTargetSelection(
                    ref: ref,
                    fingerprint: fav.fingerprint,
                    alias: fav.alias,
                    device: nearbyByFingerprint[fav.fingerprint],
                  );
                  if (context.mounted) {
                    context.pop();
                  }
                },
              ),
            for (final device in nonFavoriteNearby)
              _TargetTile(
                alias: device.alias,
                subtitle: device.ip != null ? '${device.ip}:${device.port}' : (device.deviceModel ?? t.general.online),
                icon: device.deviceType.icon,
                selected: currentFingerprint == device.fingerprint,
                onTap: () async {
                  await applyDefaultTargetSelection(
                    ref: ref,
                    fingerprint: device.fingerprint,
                    alias: device.alias,
                    device: device,
                  );
                  if (context.mounted) {
                    context.pop();
                  }
                },
              ),
            if (currentFingerprint != null) ...[
              const Divider(),
              ListTile(
                leading: const Icon(Icons.clear),
                title: Text(t.settingsTab.send.defaultTargetClear),
                onTap: () async {
                  await applyDefaultTargetSelection(ref: ref, fingerprint: null);
                  if (context.mounted) {
                    context.pop();
                  }
                },
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final String alias;
  final String subtitle;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  const _TargetTile({
    required this.alias,
    required this.subtitle,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon),
      title: Text(alias),
      subtitle: Text(subtitle),
      trailing: selected ? Icon(Icons.star, color: Theme.of(context).colorScheme.primary) : null,
      onTap: onTap,
    );
  }
}
