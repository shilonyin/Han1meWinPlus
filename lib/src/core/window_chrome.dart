import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:window_manager/window_manager.dart';

/// Commands for the native window, used by the in-app title bar.
///
/// The Windows runner shows the window as soon as it is created so that the
/// startup splash covers engine boot. That means the title bar style cannot be
/// chosen by the runner and has to be applied from Dart instead.
///
/// `ensureInitialized` is what binds the plugin to the top level window (the
/// runner parents the Flutter view to its own window), so it has to run before
/// any other command, including the first style change.
class WindowChrome {
  WindowChrome._();

  /// window_manager only ships desktop implementations.
  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// Lets immersive pages (the full screen player) hide the in-app title bar.
  static final ValueNotifier<bool> visible = ValueNotifier(true);

  static Future<void> bind() async {
    if (!isSupported) return;
    try {
      await windowManager.ensureInitialized();
    } catch (error) {
      debugPrint('[window] initialisation failed: $error');
    }
  }

  /// Switches between the system title bar and the in-app one. Safe to call on
  /// every settings change, and at startup to apply the persisted preference.
  static Future<void> setUseSystemTitleBar(bool value) async {
    if (!isSupported) return;
    await bind();
    try {
      await windowManager.setTitleBarStyle(value ? TitleBarStyle.normal : TitleBarStyle.hidden);
    } catch (error) {
      debugPrint('[window] title bar style failed: $error');
    }
  }

  static Future<void> minimize() => _run((manager) => manager.minimize());

  static Future<void> close() => _run((manager) => manager.close());

  static Future<void> startDragging() => _run((manager) => manager.startDragging());

  static Future<void> toggleMaximize() => _run((manager) async {
        if (await manager.isMaximized()) {
          await manager.unmaximize();
        } else {
          await manager.maximize();
        }
      });

  static Future<bool> isMaximized() async {
    if (!isSupported) return false;
    try {
      await windowManager.ensureInitialized();
      return await windowManager.isMaximized();
    } catch (_) {
      return false;
    }
  }

  static Future<void> _run(Future<void> Function(WindowManager manager) action) async {
    if (!isSupported) return;
    await bind();
    try {
      await action(windowManager);
    } catch (error) {
      debugPrint('[window] command failed: $error');
    }
  }
}
