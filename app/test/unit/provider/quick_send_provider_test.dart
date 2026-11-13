import 'package:localsend_app/model/persistence/favorite_device.dart';
import 'package:localsend_app/model/state/settings_state.dart';
import 'package:localsend_app/provider/network/quick_send_provider.dart';
import 'package:localsend_app/provider/network/server/controller/receive_controller.dart';
import 'package:localsend_isolates/model/device.dart';
import 'package:mockito/mockito.dart';
import 'package:test/test.dart';

class _FakeSettingsState extends Fake implements SettingsState {
  @override
  final String? defaultTargetFingerprint;

  @override
  final bool autoSendToDefault;

  _FakeSettingsState({
    this.defaultTargetFingerprint,
    this.autoSendToDefault = true,
  });
}

Device _device({
  required String fingerprint,
  required String alias,
  String ip = '192.168.1.20',
}) {
  return Device(
    signalingId: null,
    ip: ip,
    version: '2.0',
    port: 53317,
    https: true,
    fingerprint: fingerprint,
    alias: alias,
    deviceModel: 'Pixel 8',
    deviceType: DeviceType.mobile,
    download: false,
    channels: const [],
  );
}

void main() {
  group('shouldAutoSendForArgs', () {
    test('returns true when explicit --quick-send flag is present even if autoSendToDefault is false', () {
      final settings = _FakeSettingsState(
        defaultTargetFingerprint: 'fp-phone',
        autoSendToDefault: false,
      );
      expect(
        shouldAutoSendForArgs(args: ['--quick-send', r'C:\file.txt'], settings: settings),
        isTrue,
      );
    });

    test('returns true without flag when autoSendToDefault is enabled and default target exists', () {
      final settings = _FakeSettingsState(
        defaultTargetFingerprint: 'fp-phone',
        autoSendToDefault: true,
      );
      expect(
        shouldAutoSendForArgs(args: [r'C:\file.txt'], settings: settings),
        isTrue,
      );
    });

    test('returns false without flag when default target is missing or autoSendToDefault is off', () {
      expect(
        shouldAutoSendForArgs(
          args: [r'C:\file.txt'],
          settings: _FakeSettingsState(defaultTargetFingerprint: null, autoSendToDefault: true),
        ),
        isFalse,
      );
      expect(
        shouldAutoSendForArgs(
          args: [r'C:\file.txt'],
          settings: _FakeSettingsState(defaultTargetFingerprint: 'fp-phone', autoSendToDefault: false),
        ),
        isFalse,
      );
    });
  });

  group('shouldAutoSendForShare', () {
    test('requires both autoSendToDefault and a configured defaultTargetFingerprint', () {
      expect(
        shouldAutoSendForShare(
          settings: _FakeSettingsState(defaultTargetFingerprint: 'fp-phone', autoSendToDefault: true),
        ),
        isTrue,
      );
      expect(
        shouldAutoSendForShare(
          settings: _FakeSettingsState(defaultTargetFingerprint: 'fp-phone', autoSendToDefault: false),
        ),
        isFalse,
      );
      expect(
        shouldAutoSendForShare(
          settings: _FakeSettingsState(defaultTargetFingerprint: null, autoSendToDefault: true),
        ),
        isFalse,
      );
    });
  });

  group('target resolution helpers', () {
    test('resolveDiscoveredDevice looks up by fingerprint', () {
      final phone = _device(fingerprint: 'fp-1', alias: 'My Phone');
      expect(
        resolveDiscoveredDevice(allDevices: {'fp-1': phone}, fingerprint: 'fp-1'),
        equals(phone),
      );
      expect(
        resolveDiscoveredDevice(allDevices: {'fp-1': phone}, fingerprint: 'fp-2'),
        isNull,
      );
    });

    test('resolveTargetDisplayName prefers favorite alias over discovered alias and falls back to short fingerprint', () {
      final favorites = [
        FavoriteDevice(
          id: 'fav-1',
          fingerprint: 'fp-1234567890',
          ip: '192.168.1.20',
          port: 53317,
          alias: 'Favorite Phone',
          customAlias: true,
        ),
      ];
      final allDevices = {
        'fp-1234567890': _device(fingerprint: 'fp-1234567890', alias: 'LAN Phone'),
        'fp-discovered': _device(fingerprint: 'fp-discovered', alias: 'Discovered Tablet'),
      };

      expect(
        resolveTargetDisplayName(fingerprint: 'fp-1234567890', favorites: favorites, allDevices: allDevices),
        'Favorite Phone',
      );
      expect(
        resolveTargetDisplayName(fingerprint: 'fp-discovered', favorites: favorites, allDevices: allDevices),
        'Discovered Tablet',
      );
      expect(
        resolveTargetDisplayName(fingerprint: '1234567890abcdef', favorites: favorites, allDevices: allDevices),
        '12345678',
      );
      expect(
        resolveTargetDisplayName(fingerprint: 'short', favorites: favorites, allDevices: allDevices),
        'short',
      );
    });
  });

  group('QuickSendStatus', () {
    test('implements value equality and hashCode', () {
      const a = QuickSendStatus(isBusy: true, targetAlias: 'Phone');
      const b = QuickSendStatus(isBusy: true, targetAlias: 'Phone');
      const c = QuickSendStatus(isBusy: false, targetAlias: 'Phone');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
    });
  });

  group('shouldQuickSaveRequest', () {
    test('allows file transfers when quickSave, favorite quickSave, or web auto-accept applies', () {
      expect(
        shouldQuickSaveRequest(
          quickSave: true,
          quickSaveFromFavorites: false,
          isFavoriteSender: false,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: false,
          quickSaveMessages: false,
        ),
        isTrue,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: false,
          quickSaveFromFavorites: true,
          isFavoriteSender: true,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: false,
          quickSaveMessages: false,
        ),
        isTrue,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: false,
          quickSaveFromFavorites: true,
          isFavoriteSender: false,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: false,
          quickSaveMessages: false,
        ),
        isFalse,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: false,
          quickSaveFromFavorites: false,
          isFavoriteSender: false,
          isWebUpload: true,
          receiveViaLinkAutoAccept: true,
          isMessage: false,
          quickSaveMessages: false,
        ),
        isTrue,
      );
    });

    test('requires quickSaveMessages before auto-accepting text messages', () {
      expect(
        shouldQuickSaveRequest(
          quickSave: true,
          quickSaveFromFavorites: false,
          isFavoriteSender: true,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: true,
          quickSaveMessages: false,
        ),
        isFalse,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: true,
          quickSaveFromFavorites: false,
          isFavoriteSender: false,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: true,
          quickSaveMessages: true,
        ),
        isTrue,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: false,
          quickSaveFromFavorites: true,
          isFavoriteSender: true,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: true,
          quickSaveMessages: true,
        ),
        isTrue,
      );
      expect(
        shouldQuickSaveRequest(
          quickSave: false,
          quickSaveFromFavorites: false,
          isFavoriteSender: false,
          isWebUpload: false,
          receiveViaLinkAutoAccept: false,
          isMessage: true,
          quickSaveMessages: true,
        ),
        isFalse,
      );
    });
  });
}
