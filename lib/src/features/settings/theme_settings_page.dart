import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_notifications.dart';
import '../../core/global_hotkeys.dart';
import '../../core/settings.dart';
import '../../core/system_tray.dart';
import '../shared/glass/glass_tuning.dart';
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
              // 玻璃：照 g1455 演示站那个控制面板重做的一整节（含外观在内），
              // 和上面的「窗口背景材质」（Windows 系统材质）是两回事。
              _ThemeModePanel(
                settings: settings,
                controller: controller,
                l10n: l10n,
              ),
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


/// 「主题模式」一节：照 g1455 演示站那个控制面板重做。
///
/// 面板本体就在包里（`g1455-0.1.4/example/lib/src/settings_menu.dart` 与
/// `style.dart`）—— 那一页是作者自己摆出来的权威档位表，连枚举名和色值都是他定的。
/// 这里照抄它的结构：一栏一个小标题 + 一段等分的紧凑分段控件，预设下面再跟一行说明。
///
/// 和原来那版（图标卡片 + 只在磨砂档出现的不透明度滑条）的区别不只是好看：
/// - **预设**是新的：一档就是一组取值，点了把那一组整体写进设置；
/// - **材质**取代了原来的「玻璃质感」三档，选项直接对应包校准过的五块料；
/// - 不透明度滑条删掉了 —— 它只对磨砂档有效，而材质现在是直接选的。
class _ThemeModePanel extends StatelessWidget {
  const _ThemeModePanel({
    required this.settings,
    required this.controller,
    required this.l10n,
  });

  final AppSettings settings;
  final SettingsController controller;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final preset = glassPresetFor(glassRecipeOf(settings));

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.themeMode,
            style: textTheme.titleSmall?.copyWith(
              color: scheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 6),
          // 整节限宽：演示站那个面板就是个窄条，分段控件拉满整栏会散掉。
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 预设。`null` 那一档是"自定义"，照演示站做成**只显示不可选**。
                _GlassSegmentedLabel(l10n.glassPreset),
                _GlassSegmented<GlassPresetKind?>(
                  values: const [...GlassPresetKind.values, null],
                  selected: preset,
                  labelOf: (value) => value == null ? l10n.glassPresetCustom : _presetLabel(l10n, value),
                  onSelected: (value) {
                    if (value == null) return;
                    final recipe = glassPresetRecipes[value]!;
                    controller.saveChanges(
                      (current) => current.copyWith(
                        glassMaterial: recipe.material,
                        glassTint: recipe.tint,
                        glassRendering: recipe.rendering,
                        glassRipple: recipe.ripple,
                        glassContrast: recipe.contrast,
                      ),
                    );
                  },
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    preset == null ? l10n.glassPresetCustomHint : _presetHint(l10n, preset),
                    style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ),

                // 外观。原来它是上面「外观」卡片里的第一项，现在并到这里 ——
                // 演示站的面板里 Appearance 就是它的一栏，两边各放一个入口只会打架。
                _GlassSegmentedLabel(l10n.appearance),
                _GlassSegmented<AppThemeMode>(
                  values: AppThemeMode.values,
                  selected: settings.themeMode,
                  labelOf: (value) => _themeModeLabel(l10n, value),
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(themeMode: value)),
                ),

                // 材质。五档照抄演示站的 Material（regular/dark/light/clear/frosted），
                // 顺序也一样。中间有过一次只列三档的版本（超透被当成重复项删过、
                // 磨砂也被点名删过），后来按"材质按他的来"改回完整五档。
                _GlassSegmentedLabel(l10n.glassMaterial),
                _GlassSegmented<GlassMaterial>(
                  values: GlassMaterial.values,
                  selected: settings.glassMaterial,
                  labelOf: (value) => _materialLabel(l10n, value),
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(glassMaterial: value)),
                ),

                _GlassSegmentedLabel(l10n.glassTint),
                _GlassSegmented<GlassTintKind>(
                  values: GlassTintKind.values,
                  selected: settings.glassTint,
                  labelOf: (value) => _tintLabel(l10n, value),
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(glassTint: value)),
                ),

                _GlassSegmentedLabel(l10n.glassTier),
                _GlassSegmented<GlassRendering>(
                  values: GlassRendering.values,
                  selected: settings.glassRendering,
                  labelOf: (value) => _renderingLabel(l10n, value),
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(glassRendering: value)),
                ),

                _GlassSegmentedLabel(l10n.glassRipple),
                _GlassSegmented<GlassRippleKind>(
                  values: GlassRippleKind.values,
                  selected: settings.glassRipple,
                  labelOf: (value) => _rippleLabel(l10n, value),
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(glassRipple: value)),
                ),

                _GlassSegmentedLabel(l10n.glassContrast),
                _GlassSegmented<GlassContrast>(
                  values: GlassContrast.values,
                  selected: settings.glassContrast,
                  labelOf: (value) => value == GlassContrast.auto
                      ? l10n.followSystem
                      : l10n.glassContrastIncreased,
                  onSelected: (value) =>
                      controller.saveChanges((current) => current.copyWith(glassContrast: value)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 一栏的小标题。照演示站：`labelMedium`、正文色的 70%、上 8 下 6。
class _GlassSegmentedLabel extends StatelessWidget {
  const _GlassSegmentedLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 6),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: scheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// 一栏的分段控件。照演示站：高 34、圆角 10、底色是正文色的 8%、内边距 2、内部等分。
class _GlassSegmented<T> extends StatelessWidget {
  const _GlassSegmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 34,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: scheme.onSurface.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: _GlassSegment(
                label: labelOf(value),
                selected: value == selected,
                onTap: () => onSelected(value),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分段控件里的一格。选中 = 主色 22% 填充 + 圆角 8 + 加粗；未选可点。
class _GlassSegment extends StatelessWidget {
  const _GlassSegment({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: selected ? null : onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: AppMotion.brief,
          curve: AppMotion.standardCurve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: .22) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              color: selected ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

String _presetLabel(AppLocalizations l10n, GlassPresetKind preset) => switch (preset) {
  GlassPresetKind.ultra => l10n.glassPresetUltra,
  GlassPresetKind.high => l10n.glassPresetHigh,
  GlassPresetKind.medium => l10n.glassPresetMedium,
  GlassPresetKind.low => l10n.glassPresetLow,
};

String _presetHint(AppLocalizations l10n, GlassPresetKind preset) => switch (preset) {
  GlassPresetKind.ultra => l10n.glassPresetUltraHint,
  GlassPresetKind.high => l10n.glassPresetHighHint,
  GlassPresetKind.medium => l10n.glassPresetMediumHint,
  GlassPresetKind.low => l10n.glassPresetLowHint,
};

String _materialLabel(AppLocalizations l10n, GlassMaterial material) => switch (material) {
  GlassMaterial.regular => l10n.glassMaterialRegular,
  GlassMaterial.dark => l10n.glassMaterialDark,
  GlassMaterial.light => l10n.glassMaterialLight,
  GlassMaterial.clear => l10n.glassMaterialClear,
  GlassMaterial.frosted => l10n.glassMaterialFrosted,
};

String _tintLabel(AppLocalizations l10n, GlassTintKind tint) => switch (tint) {
  GlassTintKind.neutral => l10n.glassTintNeutral,
  GlassTintKind.indigo => l10n.glassTintIndigo,
  GlassTintKind.rose => l10n.glassTintRose,
};

String _renderingLabel(AppLocalizations l10n, GlassRendering rendering) => switch (rendering) {
  GlassRendering.glass => l10n.glassTierFull,
  GlassRendering.translucent => l10n.glassTierCheap,
  GlassRendering.opaque => l10n.glassTierOpaque,
};

String _rippleLabel(AppLocalizations l10n, GlassRippleKind ripple) => switch (ripple) {
  GlassRippleKind.off => l10n.glassRippleOff,
  GlassRippleKind.water => l10n.glassRippleWater,
  GlassRippleKind.jelly => l10n.glassRippleJelly,
  GlassRippleKind.honey => l10n.glassRippleHoney,
};

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

String _themeModeLabel(AppLocalizations l10n, AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => l10n.followSystem,
      AppThemeMode.light => l10n.light,
      AppThemeMode.dark => l10n.dark,
    };
