import 'package:dart_mappable/dart_mappable.dart';
import 'package:flutter/material.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:localsend_app/model/persistence/color_mode.dart';
import 'package:localsend_app/model/send_mode.dart';
import 'package:localsend_isolates/model/device.dart';

part 'settings_state.mapper.dart';

@MappableClass()
class SettingsState with SettingsStateMappable {
  final String showToken; // the token to show / maximize the window because only one instance is allowed
  final String alias;
  final ThemeMode theme;
  final ColorMode colorMode;
  final Color customColor; // seed color for ColorMode.custom
  final AppLocale? locale;
  final int port;
  final List<String>? networkWhitelist; // null = disabled
  final List<String>? networkBlacklist; // null = disabled
  final String multicastGroup;
  final String? destination; // null = default
  final bool saveToGallery; // only Android, iOS
  final bool saveToHistory;
  final bool quickSave; // automatically accept file requests
  final bool quickSaveFromFavorites; // automatically accept file requests from favorites
  final String? receivePin; // null = disabled
  final bool autoFinish; // automatically finish sessions
  final bool minimizeToTray; // minimize to tray instead of exiting the app
  final bool https;
  final SendMode sendMode;
  final bool saveWindowPlacement;
  final bool alwaysOnTop;
  final bool enableAnimations;
  final DeviceType? deviceType;
  final String? deviceModel;
  final bool shareViaLinkAutoAccept;
  final bool receiveViaLinkAutoAccept;
  final bool createChecksums; // create checksums when sending files
  final bool verifyChecksums; // verify checksums when receiving files
  final int discoveryTimeout;
  final bool advancedSettings;
  final String? defaultTargetFingerprint; // fingerprint of the default quick-send target device
  final bool autoSendToDefault; // automatically send files passed from SendTo / share intent to default target
  final bool silentQuickSave; // suppress OpenFileDialog popup after quick save
  final bool quickSaveMessages; // auto-accept incoming text messages/links during quick save
  final bool backgroundListener; // keep Android foreground service alive while server runs

  const SettingsState({
    required this.showToken,
    required this.alias,
    required this.theme,
    required this.colorMode,
    required this.customColor,
    required this.locale,
    required this.port,
    required this.networkWhitelist,
    required this.networkBlacklist,
    required this.multicastGroup,
    required this.destination,
    required this.saveToGallery,
    required this.saveToHistory,
    required this.quickSave,
    required this.quickSaveFromFavorites,
    required this.receivePin,
    required this.autoFinish,
    required this.minimizeToTray,
    required this.https,
    required this.sendMode,
    required this.saveWindowPlacement,
    required this.alwaysOnTop,
    required this.enableAnimations,
    required this.deviceType,
    required this.deviceModel,
    required this.shareViaLinkAutoAccept,
    required this.receiveViaLinkAutoAccept,
    required this.createChecksums,
    required this.verifyChecksums,
    required this.discoveryTimeout,
    required this.advancedSettings,
    this.defaultTargetFingerprint,
    this.autoSendToDefault = true,
    this.silentQuickSave = false,
    this.quickSaveMessages = false,
    this.backgroundListener = false,
  });
}
