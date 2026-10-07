import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_notifications.dart';
import '../../core/global_hotkeys.dart';
import '../../core/settings.dart';
import '../../core/system_tray.dart';
import '../../core/window_backdrop.dart';
import '../../core/window_chrome.dart';
import 'color_compass_dialog.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_pane_scope.dart';

class ThemeSettingsPage extends ConsumerStatefulWidget {
  const ThemeSettingsPage({super.key});

  @override
  ConsumerState<ThemeSettingsPage> createState() => _ThemeSettingsPageState();
}

class _ThemeSettingsPageState extends ConsumerState<ThemeSettingsPage> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context) ? null : AppBar(title: Text(l10n.themeAndColor)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          SettingsCardList(title: l10n.appearance, children: [
            // 行形态统一：当前值放在 subtitle，尾部用 chevron_right 表示「点开可选」。
            // 「主题模式」这一项已经并进下面那一节（演示站的面板里 Appearance 就是
            // 它的一栏），留在这里会让同一个设置有两个入口。
            SettingsCardItem(
              title: l10n.colorScheme,
              subtitle: settings.useMonetColors ? l10n.dynamicColor : themeColorLabel(l10n, settings.themeColor),
              leading: const Icon(Symbols.palette_rounded),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () => _pickThemeColor(context, controller, settings),
            ),
            SettingsCardItem(
              title: l10n.dynamicColor,
              leading: const Icon(Symbols.colorize_rounded),
              trailing: Switch(
                value: settings.useMonetColors,
                onChanged: (value) => controller.saveChanges((current) => current.copyWith(useMonetColors: value)),
              ),
            ),
            SettingsCardItem(
              title: l10n.useSystemFont,
              subtitle: l10n.useSystemFontDescription,
              leading: const Icon(Symbols.text_fields_rounded),
              trailing: Switch(
                value: settings.useSystemFont,
                onChanged: (value) => controller.saveChanges((current) => current.copyWith(useSystemFont: value)),
              ),
            ),
          ]),
          SettingsCardList(title: l10n.display, children: [
              SettingsCardItem(
                title: l10n.amoledMode,
                subtitle: l10n.amoledModeDescription,
                leading: const Icon(Symbols.contrast_rounded),
                trailing: Switch(value: settings.amoledMode, onChanged: (value) => controller.saveChanges((current) => current.copyWith(amoledMode: value))),
              ),
              SettingsSliderItem(
               title: l10n.textSize,
               value: settings.textScale,
               min: .8,
               // 上限 2.0 是 WCAG 1.4.4（调整文本大小）要求的下限：文字要能放大到 200%。
               // 原来封顶 1.4，低视力用户没有可用的放大余量。下限仍是 .8（可缩小），
               // 档位从 6 加到 12 —— 区间翻倍还保持原来的步长（0.1），手感不变。
               max: 2.0,
               divisions: 12,
               label: '${(settings.textScale * 100).round()}%',
               onChanged: (value) => controller.saveChanges((current) => current.copyWith(textScale: value)),
             ),
           ]),
          if (WindowChrome.isSupported) ...[
            SettingsCardList(title: l10n.window, children: [
              SettingsCardItem(
                title: l10n.useSystemTitleBar,
                subtitle: l10n.useSystemTitleBarDescription,
                leading: const Icon(Symbols.web_asset_rounded),
                trailing: Switch(value: settings.useSystemTitleBar, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useSystemTitleBar: value))),
              ),
              if (SystemTray.isSupported)
                SettingsCardItem(
                  title: l10n.minimizeToTray,
                  subtitle: l10n.minimizeToTrayDescription,
                  leading: const Icon(Symbols.call_to_action_rounded),
                  trailing: Switch(value: settings.minimizeToTray, onChanged: (value) => controller.saveChanges((current) => current.copyWith(minimizeToTray: value))),
                ),
              if (GlobalHotkeys.isSupported)
                SettingsCardItem(
                  title: l10n.globalHotkeys,
                  subtitle: l10n.globalHotkeysDescription,
                  leading: const Icon(Symbols.keyboard_rounded),
                  trailing: Switch(value: settings.globalHotkeysEnabled, onChanged: (value) => controller.saveChanges((current) => current.copyWith(globalHotkeysEnabled: value))),
                ),
              if (AppNotifications.isSupported)
                SettingsCardItem(
                  title: l10n.notifications,
                  subtitle: l10n.notificationsDescription,
                  leading: const Icon(Symbols.notifications_rounded),
                  trailing: Switch(value: settings.notificationsEnabled, onChanged: (value) => controller.saveChanges((current) => current.copyWith(notificationsEnabled: value))),
                ),
              if (WindowBackdropEffect.isSupported)
                SettingsCardItem(
                  title: l10n.windowBackdrop,
                  subtitle: _backdropLabel(l10n, settings.windowBackdrop),
                  leading: const Icon(Symbols.window_rounded),
                  trailing: const Icon(Symbols.chevron_right_rounded),
                  onTap: () => _pickWindowBackdrop(context, controller, settings),
                ),
              // 「主题模式」那一节（材质 / 染色 / 渲染 / 波纹 / 对比度）已删除：
              // 玻璃停用后这些选项无处生效，决策见 `docs/ui-polish.md`。
            ]),
          ],
        ],
      ),
    );
  }

  /// 窗口材质三档（Windows 系统材质）：走统一的选项弹层。
  Future<void> _pickWindowBackdrop(BuildContext context, SettingsController controller, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<WindowBackdrop>(
      context: context,
      title: l10n.windowBackdrop,
      current: settings.windowBackdrop,
      options: WindowBackdrop.values,
      label: (backdrop) => _backdropLabel(l10n, backdrop),
    );
    if (selected == null || selected == settings.windowBackdrop) return;
    await controller.saveChanges((current) => current.copyWith(windowBackdrop: selected));
  }

  /// 配色方案：直接打开调色罗盘 —— 里面既有预设色板也有色轮，
  /// 不用像原来那样先弹一个只放预设的弹层、再点「自定义」进罗盘（中间白跑一趟）。
  Future<void> _pickThemeColor(BuildContext context, SettingsController controller, AppSettings settings) async {
    final result = await showColorCompassDialog(
      context,
      initial: _hexColor(settings.customThemeColor),
      customHex: settings.customThemeColor,
      currentPreset: settings.useMonetColors ? null : settings.themeColor,
    );
    switch (result) {
      case ColorPresetResult(:final preset):
        await controller.saveChanges((current) => current.copyWith(useMonetColors: false, themeColor: preset));
      case CustomColorResult(:final color):
        final hex = color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase();
        await controller.saveChanges((current) => current.copyWith(useMonetColors: false, themeColor: AppThemeColor.custom, customThemeColor: hex));
      case null:
        break;
    }
  }
}



/// 6 位十六进制色值 → Color。
Color _hexColor(String hex) {
  final value = int.tryParse('ff$hex', radix: 16);
  return value == null ? const Color(0xff6750a4) : Color(value);
}

String _backdropLabel(AppLocalizations l10n, WindowBackdrop backdrop) => switch (backdrop) {
      WindowBackdrop.none => l10n.windowBackdropOff,
      WindowBackdrop.mica => l10n.windowBackdropMica,
      WindowBackdrop.acrylic => l10n.windowBackdropAcrylic,
    };

