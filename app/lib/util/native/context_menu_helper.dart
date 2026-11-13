import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:localsend_app/gen/strings.g.dart';
import 'package:logging/logging.dart';
import 'package:win32_registry/win32_registry.dart';

final _logger = Logger('ContextMenuHelper');

const _windowsRegistryClassesPath = r'Software\Classes';
const _windowsRegistryVerbSubpaths = [
  r'*\shell\LocalSendQuickSend',
  r'Directory\shell\LocalSendQuickSend',
];

/// Formats the Windows right-click menu verb label using [targetAlias] when set.
String buildContextMenuLabel({
  String? targetAlias,
  required String defaultLabel,
  required String Function(String target) targetLabel,
}) {
  final trimmed = targetAlias?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return defaultLabel;
  }
  final clipped = trimmed.length > 32 ? '${trimmed.substring(0, 31)}…' : trimmed;
  return targetLabel(clipped);
}

/// Builds the command registered for Windows Explorer file/folder context menu items.
String buildQuickSendCommand(String executablePath, {String flag = '--quick-send'}) {
  return '"$executablePath" $flag "%1"';
}

Future<bool> enableContextMenu({String? targetAlias}) async {
  if (defaultTargetPlatform != TargetPlatform.windows) {
    return false;
  }

  final label = buildContextMenuLabel(
    targetAlias: targetAlias,
    defaultLabel: t.settingsTab.send.contextMenuDefault,
    targetLabel: (target) => t.settingsTab.send.contextMenuTitle(target: target),
  );

  bool sendToOk = false;
  try {
    final String script =
        '''
\$TargetPath = "${Platform.resolvedExecutable}"
\$ShortcutFile = "${_getWindowsFilePath(_windowsFileName)}"
\$WScriptShell = New-Object -ComObject WScript.Shell
\$Shortcut = \$WScriptShell.CreateShortcut(\$ShortcutFile)
\$Shortcut.TargetPath = \$TargetPath
\$Shortcut.IconLocation = "\$TargetPath,0"
\$Shortcut.Save()
''';
    final result = await Process.run('powershell', ['-Command', script]);
    if (result.stderr != null && result.stderr!.toString().isNotEmpty) {
      throw Exception('Failed to create shortcut: ${result.stderr}');
    }
    sendToOk = await File(_getWindowsFilePath(_windowsFileName)).exists();
  } catch (e) {
    _logger.severe('Failed to create SendTo shortcut: $e');
  }

  final registryOk = _writeWindowsRegistryContextMenu(label: label);
  return sendToOk || registryOk;
}

/// Updates the direct Windows Explorer context menu label if context menu integration is currently active.
Future<void> refreshContextMenuIfEnabled({String? targetAlias}) async {
  if (defaultTargetPlatform != TargetPlatform.windows || !await isContextMenuEnabled()) {
    return;
  }

  final label = buildContextMenuLabel(
    targetAlias: targetAlias,
    defaultLabel: t.settingsTab.send.contextMenuDefault,
    targetLabel: (target) => t.settingsTab.send.contextMenuTitle(target: target),
  );
  _writeWindowsRegistryContextMenu(label: label);
}

bool _writeWindowsRegistryContextMenu({required String label}) {
  try {
    final classesKey = Registry.openPath(
      RegistryHive.currentUser,
      path: _windowsRegistryClassesPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      final exe = Platform.resolvedExecutable;
      final command = buildQuickSendCommand(exe);
      for (final subpath in _windowsRegistryVerbSubpaths) {
        final verbKey = classesKey.createKey(subpath);
        try {
          verbKey.createValue(RegistryValue.string('', label));
          verbKey.createValue(RegistryValue.string('Icon', '"$exe",0'));
          verbKey.createValue(RegistryValue.string('MultiSelectModel', 'Player'));
          final commandKey = verbKey.createKey('command');
          try {
            commandKey.createValue(RegistryValue.string('', command));
          } finally {
            commandKey.close();
          }
        } finally {
          verbKey.close();
        }
      }
    } finally {
      classesKey.close();
    }
    return true;
  } catch (e) {
    _logger.warning('Failed to register HKCU shell context menu: $e');
    return false;
  }
}

Future<bool> disableContextMenu() async {
  try {
    switch (defaultTargetPlatform) {
      case TargetPlatform.windows:
        final file = File(_getWindowsFilePath(_windowsFileName));
        if (await file.exists()) {
          await file.delete();
        }
        _deleteWindowsRegistryContextMenu();
        return true;
      default:
        return false;
    }
  } catch (e) {
    return false;
  }
}

void _deleteWindowsRegistryContextMenu() {
  try {
    final classesKey = Registry.openPath(
      RegistryHive.currentUser,
      path: _windowsRegistryClassesPath,
      desiredAccessRights: AccessRights.allAccess,
    );
    try {
      for (final subpath in _windowsRegistryVerbSubpaths) {
        try {
          classesKey.deleteKey('$subpath\\command');
        } catch (_) {}
        try {
          classesKey.deleteKey(subpath);
        } catch (_) {}
      }
    } finally {
      classesKey.close();
    }
  } catch (e) {
    _logger.fine('Could not remove HKCU shell context menu: $e');
  }
}

bool _hasWindowsRegistryContextMenu() {
  for (final subpath in _windowsRegistryVerbSubpaths) {
    try {
      final key = Registry.openPath(
        RegistryHive.currentUser,
        path: '$_windowsRegistryClassesPath\\$subpath',
        desiredAccessRights: AccessRights.readOnly,
      );
      key.close();
      return true;
    } catch (_) {}
  }
  return false;
}

Future<bool> isContextMenuEnabled() async {
  switch (defaultTargetPlatform) {
    case TargetPlatform.windows:
      return await File(_getWindowsFilePath(_windowsFileName)).exists() || _hasWindowsRegistryContextMenu();
    default:
      return false;
  }
}

const _windowsFileName = 'LocalSend';

String _getWindowsFilePath(String appName) {
  final appData = Platform.environment['APPDATA'];
  return '$appData/Microsoft/Windows/SendTo/$appName.lnk';
}
