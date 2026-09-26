import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/global_hotkeys.dart';
import '../../core/settings.dart';
import '../../core/system_tray.dart';
import '../../core/window_backdrop.dart';
import '../../core/window_chrome.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'theme_scheme_page.dart';

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
      appBar: AppBar(title: Text(l10n.themeAndColor)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          SettingsCardList(title: l10n.appearance, children: [
            // 行形态统一：当前值放在 subtitle，尾部用 chevron_right 表示「点开可选」。
            SettingsCardItem(
              title: l10n.themeMode,
              subtitle: _themeModeLabel(l10n, settings.themeMode),
              leading: const Icon(Icons.brightness_auto_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _pickThemeMode(context, controller, settings),
            ),
            SettingsCardItem(
              title: l10n.colorScheme,
              subtitle: settings.useMonetColors ? l10n.dynamicColor : themeColorLabel(l10n, settings.themeColor),
              leading: const Icon(Icons.palette_outlined),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => showThemeSchemeDialog(context),
            ),
            SettingsCardItem(
              title: l10n.dynamicColor,
              leading: const Icon(Icons.colorize_outlined),
              trailing: Switch(
                value: settings.useMonetColors,
                onChanged: (value) => controller.saveChanges((current) => current.copyWith(useMonetColors: value)),
              ),
            ),
            SettingsCardItem(
              title: l10n.useSystemFont,
              subtitle: l10n.useSystemFontDescription,
              leading: const Icon(Icons.text_fields_outlined),
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
                leading: const Icon(Icons.contrast_outlined),
                trailing: Switch(value: settings.amoledMode, onChanged: (value) => controller.saveChanges((current) => current.copyWith(amoledMode: value))),
              ),
              SettingsSliderItem(
               title: l10n.textSize,
               value: settings.textScale,
               min: .8,
               max: 1.4,
               divisions: 6,
               label: '${(settings.textScale * 100).round()}%',
               onChanged: (value) => controller.saveChanges((current) => current.copyWith(textScale: value)),
             ),
           ]),
          if (WindowChrome.isSupported) ...[
            SettingsCardList(title: l10n.window, children: [
              SettingsCardItem(
                title: l10n.useSystemTitleBar,
                subtitle: l10n.useSystemTitleBarDescription,
                leading: const Icon(Icons.web_asset_outlined),
                trailing: Switch(value: settings.useSystemTitleBar, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useSystemTitleBar: value))),
              ),
              if (SystemTray.isSupported)
                SettingsCardItem(
                  title: l10n.minimizeToTray,
                  subtitle: l10n.minimizeToTrayDescription,
                  leading: const Icon(Icons.call_to_action_outlined),
                  trailing: Switch(value: settings.minimizeToTray, onChanged: (value) => controller.saveChanges((current) => current.copyWith(minimizeToTray: value))),
                ),
              if (GlobalHotkeys.isSupported)
                SettingsCardItem(
                  title: l10n.globalHotkeys,
                  subtitle: l10n.globalHotkeysDescription,
                  leading: const Icon(Icons.keyboard_outlined),
                  trailing: Switch(value: settings.globalHotkeysEnabled, onChanged: (value) => controller.saveChanges((current) => current.copyWith(globalHotkeysEnabled: value))),
                ),
              if (WindowBackdropEffect.isSupported)
                SettingsCardItem(
                  title: l10n.windowBackdrop,
                  subtitle: _backdropLabel(l10n, settings.windowBackdrop),
                  leading: const Icon(Icons.blur_on_outlined),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _pickWindowBackdrop(context, controller, settings),
                ),
            ]),
          ],
        ],
      ),
    );
  }

  /// 三个单选项走统一的弹层（和硬件解码器 / 代理 / 超分辨率一致），
  /// 原来是裸的 showModalBottomSheet + ListTile，看着跟别处不是一套。
  Future<void> _pickThemeMode(BuildContext context, SettingsController controller, AppSettings settings) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await showOptionSettingsDialog<AppThemeMode>(
      context: context,
      title: l10n.themeMode,
      current: settings.themeMode,
      options: AppThemeMode.values,
      label: (mode) => _themeModeLabel(l10n, mode),
    );
    if (selected == null || selected == settings.themeMode) return;
    await controller.saveChanges((current) => current.copyWith(themeMode: selected));
  }

  /// 窗口材质三档：与主题模式一样走统一的选项弹层。
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
}

String _backdropLabel(AppLocalizations l10n, WindowBackdrop backdrop) => switch (backdrop) {
      WindowBackdrop.none => l10n.windowBackdropOff,
      WindowBackdrop.mica => l10n.windowBackdropMica,
      WindowBackdrop.acrylic => l10n.windowBackdropAcrylic,
    };

String _themeModeLabel(AppLocalizations l10n, AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => l10n.followSystem,
      AppThemeMode.light => l10n.light,
      AppThemeMode.dark => l10n.dark,
    };

