import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/global_hotkeys.dart';
import '../../core/player_hotkey_registry.dart';
import 'settings_card_list.dart';
import 'settings_controller.dart';

/// 快捷键设置：应用内键位（播放页）与全局热键分开两组，点击条目就地捕获
/// 新组合键；同组撞键、全局键缺修饰符都会被拦下并提示，底部一键恢复默认。
///
/// Esc 退出全屏是所有播放器的铁律，不做成可绑定项，只展示为固定条目。
class HotkeySettingsPage extends ConsumerStatefulWidget {
  const HotkeySettingsPage({super.key});

  @override
  ConsumerState<HotkeySettingsPage> createState() => _HotkeySettingsPageState();
}

class _HotkeySettingsPageState extends ConsumerState<HotkeySettingsPage> {
  /// 正在捕获新键位的动作；null = 没有行处于捕获态。
  String? _capturingId;

  /// 捕获态的实时预览（可能只有修饰符，如 `ctrl+alt`）。
  String? _capturePreview;

  /// 捕获态的红色警告（冲突 / 全局键缺修饰符）；有值时继续等待下一个组合。
  String? _captureWarning;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null)
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final bindings = settings.hotkeyBindings;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.settingsHotkeys)),
      body: ListView(
        children: [
          SettingsCardList(
            title: l10n.hotkeyInAppSection,
            children: [
              for (final action in PlayerHotkeyRegistry.inAppActions)
                _actionRow(context, l10n, action, bindings),
              SettingsCardItem(
                title: l10n.hotkeyActionExitFullscreen,
                subtitle: l10n.hotkeyExitFullscreenFixed,
                leading: const Icon(Icons.close_fullscreen_outlined),
                trailing: const _ComboChip(label: 'Esc'),
                enabled: false,
              ),
            ],
          ),
          if (GlobalHotkeys.isSupported) ...[
            SettingsCardList(
              title: l10n.hotkeyGlobalSection,
              children: [
                if (GlobalHotkeys.lastFailures.isNotEmpty)
                  SettingsCardItem(
                    title: l10n.hotkeyRegisterFailed,
                    leading: const Icon(Icons.warning_amber_rounded),
                    // 警告色标题：SettingsCardItem 没有 per-item 样式入口，借用 leading 图标 + 语义色。
                    trailing: Icon(
                      Icons.warning_amber_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                SettingsCardItem(
                  title: l10n.globalHotkeys,
                  subtitle: l10n.globalHotkeysDescription,
                  leading: const Icon(Icons.keyboard_outlined),
                  trailing: Switch(
                    value: settings.globalHotkeysEnabled,
                    onChanged: (value) => controller.saveChanges(
                      (current) =>
                          current.copyWith(globalHotkeysEnabled: value),
                    ),
                  ),
                ),
                for (final action in PlayerHotkeyRegistry.globalActions)
                  _actionRow(context, l10n, action, bindings),
              ],
            ),
          ],
          SettingsCardList(
            children: [
              SettingsCardItem(
                title: l10n.hotkeyResetDefaults,
                leading: const Icon(Icons.restart_alt_outlined),
                onTap: () => controller.saveChanges(
                  (current) => current.copyWith(hotkeyBindings: const {}),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _actionRow(
    BuildContext context,
    AppLocalizations l10n,
    PlayerHotkeyAction action,
    Map<String, String> bindings,
  ) {
    final title = _actionLabel(l10n, action);
    if (_capturingId == action.id) {
      return Focus(
        autofocus: true,
        onKeyEvent: (node, event) => _handleCapture(event, action, l10n),
        child: SettingsCardItem(
          title: title,
          subtitle: _captureWarning ?? l10n.hotkeyPressKeys,
          leading: Icon(_iconFor(action)),
          trailing: _capturePreview == null
              ? const SizedBox.shrink()
              : _ComboChip(
                  label: _displayCombo(_capturePreview!),
                  warning: _captureWarning != null,
                ),
        ),
      );
    }
    return SettingsCardItem(
      title: title,
      leading: Icon(_iconFor(action)),
      trailing: _ComboChip(
        label: _displayCombo(PlayerHotkeyRegistry.bindingFor(bindings, action)),
      ),
      onTap: () => setState(() {
        _capturingId = action.id;
        _capturePreview = null;
        _captureWarning = null;
      }),
    );
  }

  KeyEventResult _handleCapture(
    KeyEvent event,
    PlayerHotkeyAction action,
    AppLocalizations l10n,
  ) {
    if (event is KeyUpEvent || event is KeyRepeatEvent)
      return KeyEventResult.handled;
    // Esc 取消捕获。
    if (event.physicalKey == PhysicalKeyboardKey.escape) {
      setState(() {
        _capturingId = null;
        _capturePreview = null;
        _captureWarning = null;
      });
      return KeyEventResult.handled;
    }
    final hardware = HardwareKeyboard.instance;
    final modifiers = <String>{
      if (hardware.isControlPressed) 'ctrl',
      if (hardware.isAltPressed) 'alt',
      if (hardware.isShiftPressed) 'shift',
      if (hardware.isMetaPressed) 'meta',
    };
    final keyName = PlayerHotkeyRegistry.keyName(event.physicalKey);
    // 只按到修饰符：更新预览，继续等主键。
    if (keyName == null) {
      setState(() {
        _capturePreview = PlayerHotkeyRegistry.formatCombo(modifiers, null);
        _captureWarning = null;
      });
      return KeyEventResult.handled;
    }
    final combo = PlayerHotkeyRegistry.formatCombo(modifiers, keyName);
    // 全局热键必须带修饰符：裸键会被系统级注册独占，其它软件就用不了了。
    if (action.scope == PlayerHotkeyScope.global && modifiers.isEmpty) {
      setState(() {
        _capturePreview = combo;
        _captureWarning = l10n.hotkeyNeedModifier;
      });
      return KeyEventResult.handled;
    }
    final bindings =
        ref.read(settingsProvider).valueOrNull?.hotkeyBindings ??
        const <String, String>{};
    final conflict = PlayerHotkeyRegistry.findConflict(
      bindings,
      action.scope,
      combo,
      action.id,
    );
    if (conflict != null) {
      setState(() {
        _capturePreview = combo;
        _captureWarning = l10n.hotkeyConflict(_actionLabel(l10n, conflict));
      });
      return KeyEventResult.handled;
    }
    ref
        .read(settingsProvider.notifier)
        .saveChanges(
          (current) => current.copyWith(
            hotkeyBindings: {...current.hotkeyBindings, action.id: combo},
          ),
        );
    setState(() {
      _capturingId = null;
      _capturePreview = null;
      _captureWarning = null;
    });
    return KeyEventResult.handled;
  }

  String _actionLabel(AppLocalizations l10n, PlayerHotkeyAction action) =>
      switch (action.id) {
        'inApp.playPause' => l10n.hotkeyActionPlayPause,
        'inApp.seekBackward' => l10n.hotkeyActionSeekBackward,
        'inApp.seekForward' => l10n.hotkeyActionSeekForward,
        'inApp.volumeUp' => l10n.hotkeyActionVolumeUp,
        'inApp.volumeDown' => l10n.hotkeyActionVolumeDown,
        'inApp.mute' => l10n.hotkeyActionMute,
        'inApp.fullscreen' => l10n.hotkeyActionFullscreen,
        'inApp.previousEpisode' => l10n.hotkeyActionPreviousEpisode,
        'inApp.nextEpisode' => l10n.hotkeyActionNextEpisode,
        'global.toggleWindow' => l10n.hotkeyActionToggleWindow,
        'global.playPause' => l10n.hotkeyActionPlayPause,
        'global.previousEpisode' => l10n.hotkeyActionPreviousEpisode,
        'global.nextEpisode' => l10n.hotkeyActionNextEpisode,
        _ => action.id,
      };

  IconData _iconFor(PlayerHotkeyAction action) => switch (action.id) {
    'inApp.playPause' || 'global.playPause' => Icons.play_arrow_outlined,
    'inApp.seekBackward' => Icons.replay_5_outlined,
    'inApp.seekForward' => Icons.forward_5_outlined,
    'inApp.volumeUp' => Icons.volume_up_outlined,
    'inApp.volumeDown' => Icons.volume_down_outlined,
    'inApp.mute' => Icons.volume_off_outlined,
    'inApp.fullscreen' => Icons.fullscreen_outlined,
    'inApp.previousEpisode' ||
    'global.previousEpisode' => Icons.skip_previous_outlined,
    'inApp.nextEpisode' || 'global.nextEpisode' => Icons.skip_next_outlined,
    'global.toggleWindow' => Icons.desktop_windows_outlined,
    _ => Icons.keyboard_outlined,
  };

  /// `ctrl+alt+arrowleft` → `Ctrl+Alt+←`，给用户看的友好写法。
  String _displayCombo(String combo) {
    final parsed = PlayerHotkeyRegistry.parseCombo(combo);
    if (parsed == null) return combo;
    const keyLabels = <String, String>{
      'space': 'Space',
      'enter': 'Enter',
      'escape': 'Esc',
      'tab': 'Tab',
      'backspace': 'Backspace',
      'insert': 'Insert',
      'delete': 'Delete',
      'home': 'Home',
      'end': 'End',
      'pageup': 'PgUp',
      'pagedown': 'PgDn',
      'arrowleft': '←',
      'arrowright': '→',
      'arrowup': '↑',
      'arrowdown': '↓',
    };
    final parts = <String>[
      for (final modifier in PlayerHotkeyRegistry.modifierOrder)
        if (parsed.modifiers.contains(modifier))
          modifier == 'meta'
              ? 'Win'
              : modifier[0].toUpperCase() + modifier.substring(1),
      keyLabels[parsed.key] ?? parsed.key.toUpperCase(),
    ];
    return parts.join('+');
  }
}

/// 键位小胶囊：等宽风格、弱底色，捕获警告时描红。
class _ComboChip extends StatelessWidget {
  const _ComboChip({required this.label, this.warning = false});

  final String label;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: warning
            ? colorScheme.errorContainer
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: warning ? Border.all(color: colorScheme.error) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: warning
              ? colorScheme.onErrorContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
