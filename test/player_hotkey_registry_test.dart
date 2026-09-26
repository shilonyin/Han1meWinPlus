import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/player_hotkey_registry.dart';

/// 注册表的核心约定：组合键编解码往返、默认值回落、持久化过滤与冲突检测。
/// 这些是设置页改键与播放器键盘分发的公共地基，行为错了两边一起坏。
void main() {
  group('parseCombo / formatCombo 往返', () {
    test('标准组合键能解析出修饰符与主键', () {
      final parsed = PlayerHotkeyRegistry.parseCombo('ctrl+alt+space')!;
      expect(parsed.modifiers, {'ctrl', 'alt'});
      expect(parsed.key, 'space');
    });

    test('修饰符顺序不敏感，输出按固定顺序归一', () {
      expect(
        PlayerHotkeyRegistry.formatCombo({'alt', 'ctrl'}, 'space'),
        'ctrl+alt+space',
      );
      expect(PlayerHotkeyRegistry.parseCombo('alt+ctrl+space')!.key, 'space');
    });

    test('大小写与空白被归一', () {
      final parsed = PlayerHotkeyRegistry.parseCombo(' Ctrl + M ')!;
      expect(parsed.modifiers, {'ctrl'});
      expect(parsed.key, 'm');
    });

    test('非法输入返回 null', () {
      expect(PlayerHotkeyRegistry.parseCombo(''), null);
      expect(PlayerHotkeyRegistry.parseCombo('+++'), null);
      // 未知键名
      expect(PlayerHotkeyRegistry.parseCombo('ctrl+notakey'), null);
      // 只有修饰符没有主键
      expect(PlayerHotkeyRegistry.parseCombo('ctrl+alt'), null);
      // 两个主键
      expect(PlayerHotkeyRegistry.parseCombo('a+b'), null);
    });

    test('物理键名映射双向一致', () {
      expect(PlayerHotkeyRegistry.keyName(PhysicalKeyboardKey.keyM), 'm');
      expect(PlayerHotkeyRegistry.keyByName('m'), PhysicalKeyboardKey.keyM);
      expect(
        PlayerHotkeyRegistry.keyName(PhysicalKeyboardKey.pageUp),
        'pageup',
      );
      expect(
        PlayerHotkeyRegistry.keyByName('arrowleft'),
        PhysicalKeyboardKey.arrowLeft,
      );
      // 表外的键不参与快捷键
      expect(PlayerHotkeyRegistry.keyName(PhysicalKeyboardKey.numpad1), null);
    });
  });

  group('bindingFor 回落', () {
    test('没有绑定时用默认值', () {
      expect(
        PlayerHotkeyRegistry.bindingFor(
          const {},
          PlayerHotkeyRegistry.playPause,
        ),
        'space',
      );
      expect(
        PlayerHotkeyRegistry.bindingFor(
          const {},
          PlayerHotkeyRegistry.windowToggle,
        ),
        'ctrl+alt+h',
      );
    });

    test('用户绑定优先；存了垃圾值时回落默认', () {
      expect(
        PlayerHotkeyRegistry.bindingFor({
          PlayerHotkeyRegistry.playPause.id: 'ctrl+p',
        }, PlayerHotkeyRegistry.playPause),
        'ctrl+p',
      );
      expect(
        PlayerHotkeyRegistry.bindingFor({
          PlayerHotkeyRegistry.playPause.id: '垃圾',
        }, PlayerHotkeyRegistry.playPause),
        'space',
      );
    });
  });

  group('sanitizeStoredBindings 过滤', () {
    test('丢弃未知动作与无法解析的组合键', () {
      final sanitized = PlayerHotkeyRegistry.sanitizeStoredBindings({
        PlayerHotkeyRegistry.playPause.id: 'ctrl+p',
        'inApp.unknown': 'a',
        PlayerHotkeyRegistry.mute.id: '不合法',
      });
      expect(sanitized, {PlayerHotkeyRegistry.playPause.id: 'ctrl+p'});
    });

    test('null / 空表安全', () {
      expect(PlayerHotkeyRegistry.sanitizeStoredBindings(null), const {});
      expect(PlayerHotkeyRegistry.sanitizeStoredBindings({}), const {});
    });
  });

  group('findConflict 冲突检测', () {
    test('同作用域撞键会被找出，改回自己的键不算冲突', () {
      final bindings = {PlayerHotkeyRegistry.playPause.id: 'space'};
      final conflict = PlayerHotkeyRegistry.findConflict(
        bindings,
        PlayerHotkeyScope.inApp,
        'space',
        PlayerHotkeyRegistry.mute.id,
      );
      expect(conflict, PlayerHotkeyRegistry.playPause);
      expect(
        PlayerHotkeyRegistry.findConflict(
          bindings,
          PlayerHotkeyScope.inApp,
          'space',
          PlayerHotkeyRegistry.playPause.id,
        ),
        null,
      );
    });

    test('不同作用域互不冲突（应用内 space 与全局 space 是两回事）', () {
      expect(
        PlayerHotkeyRegistry.findConflict(
          const {},
          PlayerHotkeyScope.global,
          'ctrl+alt+space',
          PlayerHotkeyRegistry.windowToggle.id,
        ),
        PlayerHotkeyRegistry.globalPlayPause,
      );
      expect(
        PlayerHotkeyRegistry.findConflict(
          const {},
          PlayerHotkeyScope.global,
          'space',
          PlayerHotkeyRegistry.windowToggle.id,
        ),
        null,
      );
    });
  });

  test('defaultBindings 覆盖对应作用域的全部动作', () {
    final inApp = PlayerHotkeyRegistry.defaultBindings(PlayerHotkeyScope.inApp);
    final global = PlayerHotkeyRegistry.defaultBindings(
      PlayerHotkeyScope.global,
    );
    expect(inApp.length, PlayerHotkeyRegistry.inAppActions.length);
    expect(global.length, PlayerHotkeyRegistry.globalActions.length);
    for (final action in PlayerHotkeyRegistry.allActions) {
      expect(inApp[action.id] ?? global[action.id], action.defaultCombo);
    }
  });
}
