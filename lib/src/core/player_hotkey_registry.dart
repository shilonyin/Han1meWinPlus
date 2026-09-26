import 'package:flutter/services.dart';

/// 快捷键作用域：应用内（窗口激活且焦点在播放器上时生效）与全局
/// （系统级热键，窗口未激活也生效，由 hotkey_manager 注册）。
enum PlayerHotkeyScope { inApp, global }

/// 一个可绑定键位的快捷键动作。
class PlayerHotkeyAction {
  const PlayerHotkeyAction({required this.id, required this.scope, required this.defaultCombo});

  /// 稳定标识，持久化在 setting.json 的 `hotkeyBindings` 里，不要改动已发布的值。
  final String id;
  final PlayerHotkeyScope scope;

  /// 默认组合键（如 `space`、`ctrl+alt+h`）。Esc 退出全屏是所有播放器的铁律，
  /// 不做成可绑定动作，在播放器里写死。
  final String defaultCombo;
}

/// 播放器快捷键的动作注册表与组合键编解码。
///
/// 组合键字符串格式：`ctrl+alt+space` —— 全小写、`+` 分隔，修饰符固定按
/// ctrl / alt / shift / meta 排序，主键用物理键名（`m`、`f`、`arrowleft`、
/// `pageup`…，见 [_keysByName]）。存物理键而不是字符，键位不受输入法影响。
///
/// [AppSettings.hotkeyBindings] 只存**被用户改过**的动作；读取时经
/// [bindingFor] 回落默认值，缺失项不回写，未知 id 在 fromJson 时丢弃。
class PlayerHotkeyRegistry {
  PlayerHotkeyRegistry._();

  // ---- 应用内动作（B 站 / PotPlayer 惯例） ----
  static const playPause = PlayerHotkeyAction(id: 'inApp.playPause', scope: PlayerHotkeyScope.inApp, defaultCombo: 'space');
  static const seekBackward = PlayerHotkeyAction(id: 'inApp.seekBackward', scope: PlayerHotkeyScope.inApp, defaultCombo: 'arrowleft');
  static const seekForward = PlayerHotkeyAction(id: 'inApp.seekForward', scope: PlayerHotkeyScope.inApp, defaultCombo: 'arrowright');
  static const volumeUp = PlayerHotkeyAction(id: 'inApp.volumeUp', scope: PlayerHotkeyScope.inApp, defaultCombo: 'arrowup');
  static const volumeDown = PlayerHotkeyAction(id: 'inApp.volumeDown', scope: PlayerHotkeyScope.inApp, defaultCombo: 'arrowdown');
  static const mute = PlayerHotkeyAction(id: 'inApp.mute', scope: PlayerHotkeyScope.inApp, defaultCombo: 'm');
  static const fullscreen = PlayerHotkeyAction(id: 'inApp.fullscreen', scope: PlayerHotkeyScope.inApp, defaultCombo: 'f');
  static const previousEpisode = PlayerHotkeyAction(id: 'inApp.previousEpisode', scope: PlayerHotkeyScope.inApp, defaultCombo: 'pageup');
  static const nextEpisode = PlayerHotkeyAction(id: 'inApp.nextEpisode', scope: PlayerHotkeyScope.inApp, defaultCombo: 'pagedown');

  // ---- 全局动作（系统级热键；统一带 Ctrl+Alt 修饰，避免抢占其它软件的裸键） ----
  static const windowToggle = PlayerHotkeyAction(id: 'global.toggleWindow', scope: PlayerHotkeyScope.global, defaultCombo: 'ctrl+alt+h');
  static const globalPlayPause = PlayerHotkeyAction(id: 'global.playPause', scope: PlayerHotkeyScope.global, defaultCombo: 'ctrl+alt+space');
  static const globalPreviousEpisode = PlayerHotkeyAction(id: 'global.previousEpisode', scope: PlayerHotkeyScope.global, defaultCombo: 'ctrl+alt+arrowleft');
  static const globalNextEpisode = PlayerHotkeyAction(id: 'global.nextEpisode', scope: PlayerHotkeyScope.global, defaultCombo: 'ctrl+alt+arrowright');

  static const inAppActions = <PlayerHotkeyAction>[
    playPause, seekBackward, seekForward, volumeUp, volumeDown, mute, fullscreen, previousEpisode, nextEpisode,
  ];

  static const globalActions = <PlayerHotkeyAction>[
    windowToggle, globalPlayPause, globalPreviousEpisode, globalNextEpisode,
  ];

  static const allActions = <PlayerHotkeyAction>[...inAppActions, ...globalActions];

  /// 修饰符的规范名与固定顺序（formatCombo 的输出顺序）。
  static const modifierOrder = <String>['ctrl', 'alt', 'shift', 'meta'];

  /// 某动作当前生效的键位：优先用户绑定，缺失或存了无法解析的值时回落默认。
  static String bindingFor(Map<String, String> bindings, PlayerHotkeyAction action) {
    final stored = bindings[action.id];
    return stored == null || parseCombo(stored) == null ? action.defaultCombo : stored;
  }

  /// 同一作用域里是否已有别的动作占用 [combo]；返回占用的动作，无冲突返回 null。
  /// [ignoreActionId] 用来排除「自己改回自己的键」这种情况。
  static PlayerHotkeyAction? findConflict(Map<String, String> bindings, PlayerHotkeyScope scope, String combo, String ignoreActionId) {
    final actions = scope == PlayerHotkeyScope.inApp ? inAppActions : globalActions;
    for (final action in actions) {
      if (action.id == ignoreActionId) continue;
      if (bindingFor(bindings, action).toLowerCase() == combo.toLowerCase()) return action;
    }
    return null;
  }

  /// 某作用域的全部默认键位（「恢复默认」整表写回用）。
  static Map<String, String> defaultBindings(PlayerHotkeyScope scope) => {
        for (final action in scope == PlayerHotkeyScope.inApp ? inAppActions : globalActions) action.id: action.defaultCombo,
      };

  /// 过滤持久化数据：只保留已知动作且能解析的组合键，防止手改 setting.json 带进垃圾。
  static Map<String, String> sanitizeStoredBindings(Map<dynamic, dynamic>? raw) {
    if (raw == null) return const {};
    final known = {for (final action in allActions) action.id};
    return {
      for (final entry in raw.entries)
        if (entry.key is String && known.contains(entry.key) && entry.value is String && parseCombo(entry.value as String) != null)
          entry.key as String: (entry.value as String).toLowerCase(),
    };
  }

  /// 把当前按键状态格式化成组合键字符串（捕获新键位时用）。
  /// [modifiers] 传 `HardwareKeyboard` 的实时修饰符状态；只按修饰符时 [keyName]
  /// 为 null，返回 `ctrl+alt` 这样的前缀，供捕获 UI 做预览。
  static String formatCombo(Set<String> modifiers, String? keyName) {
    final ordered = modifierOrder.where(modifiers.contains).toList();
    return keyName == null ? ordered.join('+') : [...ordered, keyName].join('+');
  }

  /// 解析组合键字符串；格式非法（未知键名、没有主键、修饰符当主键）返回 null。
  static ({Set<String> modifiers, String key})? parseCombo(String combo) {
    final parts = combo.toLowerCase().trim().split('+').map((part) => part.trim()).where((part) => part.isNotEmpty).toList();
    if (parts.isEmpty) return null;
    final modifiers = <String>{};
    String? key;
    for (final part in parts) {
      if (modifierOrder.contains(part)) {
        modifiers.add(part);
      } else if (_keysByName.containsKey(part) && key == null) {
        key = part;
      } else {
        return null;
      }
    }
    if (key == null) return null;
    return (modifiers: modifiers, key: key);
  }

  /// 物理键 → 规范键名；不在表里的键返回 null（不参与快捷键）。
  static String? keyName(PhysicalKeyboardKey key) => _namesByKey[key];

  /// 规范键名 → 物理键。
  static PhysicalKeyboardKey? keyByName(String name) => _keysByName[name];

  static final Map<PhysicalKeyboardKey, String> _namesByKey = {
    for (final entry in _keysByName.entries) entry.value: entry.key,
  };

  static const _keysByName = <String, PhysicalKeyboardKey>{
    'space': PhysicalKeyboardKey.space,
    'enter': PhysicalKeyboardKey.enter,
    'escape': PhysicalKeyboardKey.escape,
    'tab': PhysicalKeyboardKey.tab,
    'backspace': PhysicalKeyboardKey.backspace,
    'insert': PhysicalKeyboardKey.insert,
    'delete': PhysicalKeyboardKey.delete,
    'home': PhysicalKeyboardKey.home,
    'end': PhysicalKeyboardKey.end,
    'pageup': PhysicalKeyboardKey.pageUp,
    'pagedown': PhysicalKeyboardKey.pageDown,
    'arrowleft': PhysicalKeyboardKey.arrowLeft,
    'arrowright': PhysicalKeyboardKey.arrowRight,
    'arrowup': PhysicalKeyboardKey.arrowUp,
    'arrowdown': PhysicalKeyboardKey.arrowDown,
    'a': PhysicalKeyboardKey.keyA,
    'b': PhysicalKeyboardKey.keyB,
    'c': PhysicalKeyboardKey.keyC,
    'd': PhysicalKeyboardKey.keyD,
    'e': PhysicalKeyboardKey.keyE,
    'f': PhysicalKeyboardKey.keyF,
    'g': PhysicalKeyboardKey.keyG,
    'h': PhysicalKeyboardKey.keyH,
    'i': PhysicalKeyboardKey.keyI,
    'j': PhysicalKeyboardKey.keyJ,
    'k': PhysicalKeyboardKey.keyK,
    'l': PhysicalKeyboardKey.keyL,
    'm': PhysicalKeyboardKey.keyM,
    'n': PhysicalKeyboardKey.keyN,
    'o': PhysicalKeyboardKey.keyO,
    'p': PhysicalKeyboardKey.keyP,
    'q': PhysicalKeyboardKey.keyQ,
    'r': PhysicalKeyboardKey.keyR,
    's': PhysicalKeyboardKey.keyS,
    't': PhysicalKeyboardKey.keyT,
    'u': PhysicalKeyboardKey.keyU,
    'v': PhysicalKeyboardKey.keyV,
    'w': PhysicalKeyboardKey.keyW,
    'x': PhysicalKeyboardKey.keyX,
    'y': PhysicalKeyboardKey.keyY,
    'z': PhysicalKeyboardKey.keyZ,
    '0': PhysicalKeyboardKey.digit0,
    '1': PhysicalKeyboardKey.digit1,
    '2': PhysicalKeyboardKey.digit2,
    '3': PhysicalKeyboardKey.digit3,
    '4': PhysicalKeyboardKey.digit4,
    '5': PhysicalKeyboardKey.digit5,
    '6': PhysicalKeyboardKey.digit6,
    '7': PhysicalKeyboardKey.digit7,
    '8': PhysicalKeyboardKey.digit8,
    '9': PhysicalKeyboardKey.digit9,
    'f1': PhysicalKeyboardKey.f1,
    'f2': PhysicalKeyboardKey.f2,
    'f3': PhysicalKeyboardKey.f3,
    'f4': PhysicalKeyboardKey.f4,
    'f5': PhysicalKeyboardKey.f5,
    'f6': PhysicalKeyboardKey.f6,
    'f7': PhysicalKeyboardKey.f7,
    'f8': PhysicalKeyboardKey.f8,
    'f9': PhysicalKeyboardKey.f9,
    'f10': PhysicalKeyboardKey.f10,
    'f11': PhysicalKeyboardKey.f11,
    'f12': PhysicalKeyboardKey.f12,
  };
}
