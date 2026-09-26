import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'playback_hotkey_target.dart';
import 'window_chrome.dart';

/// 系统级（全局）热键：窗口未激活时也能生效。
///
/// 默认键位与 Issue 约定的一致，修饰符统一 Ctrl+Alt（避开 Windows 与浏览器
/// 的常用组合）：H 显示/隐藏、Space 播放/暂停、←/→ 上一集/下一集。
///
/// 注册是进程级的，所以开 / 关、改配置前都先 [hotKeyManager.unregisterAll]，
/// 避免同一个键被注册两遍。
class GlobalHotkeys {
  GlobalHotkeys._();

  /// hotkey_manager 只有桌面实现。
  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool _enabled = false;

  static bool get enabled => _enabled;

  static Future<void> setEnabled(bool enabled) async {
    if (!isSupported) return;
    try {
      await hotKeyManager.unregisterAll();
      _enabled = enabled;
      if (!enabled) return;
      await hotKeyManager.register(
        _hotKey(PhysicalKeyboardKey.keyH),
        keyDownHandler: (_) => WindowChrome.toggleVisible(),
      );
      await hotKeyManager.register(
        _hotKey(PhysicalKeyboardKey.space),
        keyDownHandler: (_) => PlaybackHotkeyTarget.togglePlay?.call(),
      );
      await hotKeyManager.register(
        _hotKey(PhysicalKeyboardKey.arrowLeft),
        keyDownHandler: (_) => PlaybackHotkeyTarget.previousEpisode?.call(),
      );
      await hotKeyManager.register(
        _hotKey(PhysicalKeyboardKey.arrowRight),
        keyDownHandler: (_) => PlaybackHotkeyTarget.nextEpisode?.call(),
      );
    } catch (error) {
      debugPrint('[hotkey] register failed: $error');
    }
  }

  static HotKey _hotKey(PhysicalKeyboardKey key) => HotKey(
        key: key,
        modifiers: [HotKeyModifier.control, HotKeyModifier.alt],
        scope: HotKeyScope.system,
      );
}
