import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../../core/global_hotkeys.dart';
import '../../core/player_hotkey_registry.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'settings_controller.dart';
import 'settings_pane_scope.dart';

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
    if (settings == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final bindings = settings.hotkeyBindings;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.settingsHotkeys)),
      body: SettingsSubPageBody(child: ListView(
        children: [
          // ① 全局快捷键卡：**只有一行**（标题 + 副标题 + 开关）。
          //
          // 设计稿（`17828_v6_hotkey.png`）里这张卡就是一行 ——
          // 全局热键是「开不开」的一个总开关，下面那四个组合键
          // （显示隐藏窗口 / 播放暂停 / 上集 / 下集）设计稿并没有列。
          // 它们在应用内的「快捷键」里已经能改，而且全局组合必须是
          // Ctrl+Alt+X 这种带修饰键的形式，能改的空间很小 ——
          // 列出来只是把卡片撑长一倍。
          if (GlobalHotkeys.isSupported) ...[
            SettingsCardList(
              // 行高 **76**：这张卡在设计稿里只有一行，但它是整页最舒展的一行 ——
              // 白区实测 y104~180 = 76 高，标题 + 副标题之间还有 4 的间距。
              // 内容 36 + 上下各 20 = 76。下面那 8 行操作是 42（`rowPadding: 3`），
              // 两者不是同一种行：这里是**页首的开关卡**，宽松一点才不显得憋。
              //
              // 原来用默认的 2（行高约 44），整张卡片只有设计稿的一半高，
              // 卡片二也跟着上移 16，全页重心整体偏上。
              rowPadding: 20,
              children: [
                if (GlobalHotkeys.lastFailures.isNotEmpty)
                  SettingsCardItem(
                    title: l10n.hotkeyRegisterFailed,
                    leading: const Icon(Symbols.warning_rounded),
                    // 警告色标题：SettingsCardItem 没有 per-item 样式入口，借用 leading 图标 + 语义色。
                    trailing: Icon(
                      Symbols.warning_rounded,
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                SettingsCardItem(
                  // 设计稿的标题就是「全局快捷键」，副标题说明它「在任意应用前台时
                  // 也能响应播放控制」—— 原来用的是 `globalHotkeys` / `globalHotkeysDescription`
                  // 那一组更长的文案，和设计稿不是一套说法。
                  title: l10n.hotkeyGlobalSection,
                  subtitle: '在任意应用前台时也能响应播放控制',
                  trailing: Switch(
                    value: settings.globalHotkeysEnabled,
                    onChanged: (value) => controller.saveChanges(
                      (current) =>
                          current.copyWith(globalHotkeysEnabled: value),
                    ),
                  ),
                ),
              ],
            ),
          ],
          // ② 应用内快捷键卡：设计稿 8 行，顺序固定。
          //
          // 第一行「退出全屏」是**固定键**（Esc 不可改），设计稿把它排在最前、
          // 键帽同样是灰底胶囊 —— 所以不能像原来那样把它单独挂在列表末尾，
          // 也不能给它加一行「固定键，不可修改」的副标题（设计稿没有）。
          SettingsCardList(
            title: l10n.hotkeyInAppSection,
            // 卡片间距 24：设计稿卡片一白区底边 y=180、卡片二顶边 y=204。
            // `SettingsSection` 自带 `fromLTRB(39, 0, 29, 16)`，底部已经有 16，
            // 这里再补 8 → 16 + 8 = 24。（直接写 24 会变成 40，整张卡下移 16。）
            padding: const EdgeInsets.only(top: 8),
            rowPadding: 3,
            children: [
              SettingsCardItem(
                title: l10n.hotkeyActionExitFullscreen,
                trailing: const _ComboChip(label: 'Esc'),
                enabled: false,
              ),
              for (final action in PlayerHotkeyRegistry.inAppActions)
                _actionRow(context, l10n, action, bindings),
            ],
          ),
          // ③ 恢复默认：设计稿没有这一行，但它是**必要的出口** ——
          // 用户把某个键改乱之后没有别的办法退回初始值。
          // 保留成单独一张卡（与设计稿的两张卡在视觉上分开），
          // 而不是塞进上面那张快捷键列表里。
          SettingsCardList(
            padding: const EdgeInsets.only(top: 8),
            rowPadding: 3,
            children: [
              SettingsCardItem(
                title: l10n.hotkeyResetDefaults,
                onTap: () => controller.saveChanges(
                  (current) => current.copyWith(hotkeyBindings: const {}),
                ),
              ),
            ],
          ),
        ],
      )),
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
      // 设计稿（`17828_v6_hotkey.png`）的操作行**没有左侧图标** ——
      // 「退出全屏 / 播放暂停 / 快退 10 秒 …」直接顶着左边距起排，
      // 图标只出现在左侧导航栏。原来每行挂一个 Symbol，整列图标反而
      // 比文字更抢眼，和设计稿的克制感不一致。
      title: title,
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
    if (event is KeyUpEvent || event is KeyRepeatEvent) {
      return KeyEventResult.handled;
    }
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

  /// `ctrl+alt+arrowleft` → `Ctrl+Alt+←`，给用户看的友好写法。
  String _displayCombo(String combo) {
    final parsed = PlayerHotkeyRegistry.parseCombo(combo);
    if (parsed == null) return combo;
    const keyLabels = <String, String>{
      // 「空格」用中文——设计稿（`17828_v6_hotkey.png`）第二行的键帽就是这两个字。
      // 其余修饰键/功能键保留英文缩写（Esc / Ctrl / PgUp 之类），
      // 那是键盘上印的字符，翻译反而认不出来。
      'space': '空格',
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
      // 内边距 8/4：设计稿（`17828_v6_hotkey.png`）的键帽实测
      //   左边缘 x1131、右边缘 x1179 → 宽 49（含左右各 8 的内边距，
      //   所以文字区 33）；纵向 y257~279 → 高 23。
      // 现在 `_ComboChip` 渲染出来是 52 宽 / 22 高，只差 3 宽 1 高，
      // 属于字体实际宽度不同（设计稿用的是另一套字形），不再硬调内边距 ——
      // 再收就让「空格」两个字挤在一起了。
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        // **固定浅灰**（#F2F2F5），不跟主题色。
        //
        // 原来用 `surfaceContainerHighest`：那一层由主题种子派生，蓝主题下就是
        // 一块蓝灰、紫主题下一块紫灰 —— 而键帽表达的是「键盘上的一个键」，
        // 它不该带配色倾向。设计稿里它就是一格中性浅灰。
        // 出错时仍然用容器的错误色，那是语义色，需要和普通键帽区分开。
        color: warning ? colorScheme.errorContainer : const Color(0xFFF2F2F5),
        // 圆角取 `AppRadius.xs`（6）：设计稿键帽的圆角实测只有 3~4px
        //（左边缘从 y257 的 x1133 收到 y260 的 x1131），比原来的 8 小一半，
        // 6 是令牌里最接近的一档。守卫测试不允许写数字字面量。
        borderRadius: BorderRadius.circular(AppRadius.xs),
        border: warning ? Border.all(color: colorScheme.error) : null,
      ),
      child: Text(
        label,
        style: TextStyle(
          // 12 号：比行标题（14）小一号，键帽才像「附在右侧的标记」而不是
          // 又一个标题。
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: warning
              ? colorScheme.onErrorContainer
              : AppDesignTokens.inkSubtle,
        ),
      ),
    );
  }
}
