import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/settings.dart';
import '../../core/window_chrome.dart';
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
            SettingsCardItem(
              title: l10n.themeMode,
              leading: const Icon(Icons.brightness_auto_outlined),
              trailing: Text(switch (settings.themeMode) { AppThemeMode.system => l10n.followSystem, AppThemeMode.light => l10n.light, AppThemeMode.dark => l10n.dark }),
              onTap: () async {
                final selected = await showModalBottomSheet<AppThemeMode>(
                  context: context,
                  builder: (sheetContext) => SafeArea(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      for (final mode in AppThemeMode.values)
                        ListTile(
                          title: Text(switch (mode) { AppThemeMode.system => l10n.followSystem, AppThemeMode.light => l10n.light, AppThemeMode.dark => l10n.dark }),
                          onTap: () => Navigator.pop(sheetContext, mode),
                        ),
                    ]),
                  ),
                );
                if (selected != null) await controller.saveChanges((current) => current.copyWith(themeMode: selected));
              },
            ),
            SettingsCardItem(
              title: l10n.colorScheme,
              leading: const Icon(Icons.palette_outlined),
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
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 0, 32, 16),
            child: Text(l10n.dynamicColorFootnote, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
          const SizedBox(height: 16),
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
            const SizedBox(height: 16),
            SettingsCardList(title: l10n.window, children: [
              SettingsCardItem(
                title: l10n.useSystemTitleBar,
                subtitle: l10n.useSystemTitleBarDescription,
                leading: const Icon(Icons.web_asset_outlined),
                trailing: Switch(value: settings.useSystemTitleBar, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useSystemTitleBar: value))),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}

