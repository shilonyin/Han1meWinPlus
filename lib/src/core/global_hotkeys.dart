import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import 'playback_hotkey_target.dart';
import 'player_hotkey_registry.dart';
import 'window_chrome.dart';

/// 系统级（全局）热键：窗口未激活时也能生效。
///
/// 键位从设置里读（`AppSettings.hotkeyBindings`，见 [PlayerHotkeyRegistry]），
/// 默认统一带 Ctrl+Alt 修饰（避开 Windows 与浏览器的常用组合）。应用内
/// 快捷键（Space 暂停、方向键快进等）不走这里 —— 那套在播放器里用 Flutter
/// 焦点体系实现（见 VideoPlayerSurface）。
///
/// 注册是进程级的，所以开 / 关、改配置前都先 [hotKeyManager.unregisterAll]，
/// 避免同一个键被注册两遍。
class GlobalHotkeys {
  GlobalHotkeys._();

  /// hotkey_manager 只有桌面实现。
  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool _enabled = false;

  static bool get enabled => _enabled;

  /// 本轮注册失败（键位非法 / 被其它软件占用）的动作 id，设置页用来提示用户。
  static List<String> lastFailures = const [];

  /// [bindings] 传 [AppSettings.hotkeyBindings]；省略时全部用默认键位。
  static Future<void> setEnabled(bool enabled, [Map<String, String> bindings = const {}]) async {
    if (!isSupported) return;
    try {
      await hotKeyManager.unregisterAll();
    } catch (error) {
      debugPrint('[hotkey] unregister failed: $error');
    }
    _enabled = enabled;
    lastFailures = const [];
    if (!enabled) return;
    await _register(bindings, PlayerHotkeyRegistry.windowToggle, WindowChrome.toggleVisible);
    await _register(bindings, PlayerHotkeyRegistry.globalPlayPause, () => PlaybackHotkeyTarget.togglePlay?.call());
    await _register(bindings, PlayerHotkeyRegistry.globalPreviousEpisode, () => PlaybackHotkeyTarget.previousEpisode?.call());
    await _register(bindings, PlayerHotkeyRegistry.globalNextEpisode, () => PlaybackHotkeyTarget.nextEpisode?.call());
  }

  static Future<void> _register(Map<String, String> bindings, PlayerHotkeyAction action, void Function() handler) async {
    final combo = PlayerHotkeyRegistry.parseCombo(PlayerHotkeyRegistry.bindingFor(bindings, action));
    // 全局热键必须带修饰符：裸键（比如单一个 Space）会被系统级注册独占，
    // 其它软件就用不了这个键了，直接拒绝并记入失败列表。
    if (combo == null || combo.modifiers.isEmpty) {
      lastFailures = [...lastFailures, action.id];
      return;
    }
    final key = PlayerHotkeyRegistry.keyByName(combo.key);
    if (key == null) {
      lastFailures = [...lastFailures, action.id];
      return;
    }
    try {
      await hotKeyManager.register(
        HotKey(
          key: key,
          modifiers: [for (final name in combo.modifiers) _modifiersByName[name]!],
          scope: HotKeyScope.system,
        ),
        keyDownHandler: (_) => handler(),
      );
    } catch (error) {
      debugPrint('[hotkey] register ${action.id} failed: $error');
      lastFailures = [...lastFailures, action.id];
    }
  }

  static const _modifiersByName = <String, HotKeyModifier>{
    'ctrl': HotKeyModifier.control,
    'alt': HotKeyModifier.alt,
    'shift': HotKeyModifier.shift,
    'meta': HotKeyModifier.meta,
  };
}
