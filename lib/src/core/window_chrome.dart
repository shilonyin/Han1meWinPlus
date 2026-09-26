import 'dart:io';
import 'dart:ui' show Rect;

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

  /// 正在显示沉浸页（播放页）时为真：应用内标题栏也跟着走深色，
  /// 免得浅色主题下出现「浅色标题栏 + 全黑播放页」的割裂感。
  ///
  /// 播放页之间会用 `pushReplacement` 互跳（下一集 / 换集），新旧页面的
  /// initState / dispose 顺序不确定，所以用计数而不是布尔值。
  static final ValueNotifier<bool> immersivePage = ValueNotifier(false);
  static int _immersivePages = 0;

  static void enterImmersivePage() {
    _immersivePages++;
    immersivePage.value = _immersivePages > 0;
  }

  static void leaveImmersivePage() {
    if (_immersivePages > 0) _immersivePages--;
    immersivePage.value = _immersivePages > 0;
  }

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

  /// 显示 / 隐藏切换：给全局热键用。隐藏后再按键时先显示再聚焦，
  /// 否则窗口只会出现在别的应用后面。
  static Future<void> toggleVisible() => _run((manager) async {
        if (await manager.isVisible()) {
          await manager.hide();
        } else {
          await manager.show();
          await manager.focus();
        }
      });

  /// 进入全屏前的窗口状态，退出时用来自己还原。
  static Rect? _boundsBeforeFullScreen;
  static bool _maximizedBeforeFullScreen = false;

  /// 视频全屏：让窗口真正全屏（覆盖任务栏），同时收起应用内标题栏。
  ///
  /// 只用 [visible] 隐藏标题栏的话，画面只是“铺满这个窗口”，窗口本身还在，
  /// 所以在桌面上必须再调 setFullScreen。
  ///
  /// 但插件自己那套“全屏/还原”在不同状态下不靠谱：进入前是最大化时它会先把窗口
  /// 去掉边框（于是窗口先变回普通大小），退出时按「是否最大化」分支还原，
  /// 结果就是窗口停在“铺满屏幕但并不是最大化”的状态——尺寸与进全屏前不一致，
  /// 界面就按大窗口布局、右侧空一大片，看起来像界面坏了。所以这里自己把状态
  /// 记下来，退出时强制还原到位。
  static Future<void> setFullscreen(bool value) async {
    visible.value = !value;
    if (!isSupported) return;
    await bind();
    try {
      if (value) {
        _maximizedBeforeFullScreen = await windowManager.isMaximized();
        _boundsBeforeFullScreen = _maximizedBeforeFullScreen ? null : await windowManager.getBounds();
        await windowManager.setFullScreen(true);
      } else {
        await windowManager.setFullScreen(false);
        if (_maximizedBeforeFullScreen) {
          if (!await windowManager.isMaximized()) await windowManager.maximize();
        } else {
          final bounds = _boundsBeforeFullScreen;
          if (bounds != null && !await _matchesBounds(bounds)) await windowManager.setBounds(bounds);
        }
        _boundsBeforeFullScreen = null;
        _maximizedBeforeFullScreen = false;
      }
    } catch (error) {
      debugPrint('[window] full screen failed: $error');
    }
  }

  /// 当前窗口矩形是否已经（近似）是 [expected]；容差 2 逻辑像素。
  static Future<bool> _matchesBounds(Rect expected) async {
    try {
      final current = await windowManager.getBounds();
      return (current.left - expected.left).abs() <= 2 &&
          (current.top - expected.top).abs() <= 2 &&
          (current.width - expected.width).abs() <= 2 &&
          (current.height - expected.height).abs() <= 2;
    } catch (_) {
      // 读不到就当作已经对上了，不要多做动作。
      return true;
    }
  }

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
