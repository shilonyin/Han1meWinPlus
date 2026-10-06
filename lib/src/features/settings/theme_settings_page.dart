import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_notifications.dart';
import '../../core/app_surface_tokens.dart';
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
            SettingsCardItem(
              title: l10n.themeMode,
              subtitle: _themeModeLabel(l10n, settings.themeMode),
              leading: const Icon(Symbols.brightness_auto_rounded),
              trailing: const Icon(Symbols.chevron_right_rounded),
              onTap: () => _pickThemeMode(context, controller, settings),
            ),
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
              // 玻璃质感：三档控制的是**应用内磨砂面板的渲染方式**（模糊 / 透明度 / 折射），
              // 和上面的「窗口背景材质」（Windows 系统材质）是两回事。
              _GlassQualityPanel(
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

/// 玻璃质感面板：三选一的材质卡片 + 磨砂面板开关 + 不透明度滑条。
/// 设计与 morrow（明隙）的质感选择器一致。
class _GlassQualityPanel extends StatelessWidget {
  const _GlassQualityPanel({
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
    final quality = settings.glassQuality;
    void setQuality(GlassQuality value) =>
        controller.saveChanges((current) => current.copyWith(glassQuality: value));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.glassTexture,
          style: textTheme.titleSmall?.copyWith(
            color: scheme.primary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 10),
        // 四档直接决定用哪种渲染（见 `GlassMaterial.quality`）：
        // 关闭＝纯色卡片、磨砂＝纯模糊、超透＝低模糊+更透、液体玻璃＝边缘折射。
        // 档位本身就是开关，不再另设一个「毛玻璃材质」开关 —— 那样开关关着时切档位毫无反应。
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: _glassModeCardWidth,
              child: _GlassModeCard(
                icon: Symbols.rectangle_rounded,
                title: l10n.glassOff,
                selected: quality == GlassQuality.off,
                onTap: () => setQuality(GlassQuality.off),
              ),
            ),
            SizedBox(
              width: _glassModeCardWidth,
              child: _GlassModeCard(
                icon: Symbols.blur_on_rounded,
                title: l10n.glassFrosted,
                selected: quality == GlassQuality.frosted,
                onTap: () => setQuality(GlassQuality.frosted),
              ),
            ),
            SizedBox(
              width: _glassModeCardWidth,
              child: _GlassModeCard(
                icon: Symbols.water_drop_rounded,
                title: l10n.glassClear,
                selected: quality == GlassQuality.clear,
                onTap: () => setQuality(GlassQuality.clear),
              ),
            ),
            SizedBox(
              width: _glassModeCardWidth,
              child: _GlassModeCard(
                icon: Symbols.lens_blur_rounded,
                title: l10n.glassLiquid,
                selected: quality == GlassQuality.liquid,
                onTap: () => setQuality(GlassQuality.liquid),
              ),
            ),
          ],
        ),
        // 滑条**只在磨砂档**出现：它调的是磨砂的不透明度，
        // 「超透」「液体玻璃」的透明度是固定的（照 morrow —— 那两档调它没有意义）。
        if (quality == GlassQuality.frosted) ...[
          const SizedBox(height: 2),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.glassFrostOpacity,
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ),
              Text(
                '${(settings.glassSurfaceOpacity * 100).round()}%',
                style: TextStyle(fontSize: 11, color: scheme.primary),
              ),
            ],
          ),
          Slider(
            min: .2,
            max: 1,
            divisions: 80,
            value: settings.glassSurfaceOpacity,
            onChanged: (value) => controller.saveChanges(
              (current) => current.copyWith(glassSurfaceOpacity: value),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.glassOpacityLight,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
              ),
              Expanded(
                child: Text(
                  l10n.glassOpacitySolid,
                  textAlign: TextAlign.end,
                  style: TextStyle(fontSize: 9, color: scheme.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}

/// 质感卡片的固定尺寸：照 morrow 的紧凑方块比例（约 112×76）。
/// 宽度写死而不是跟着父级拉伸，否则在宽右栏里会变成又宽又扁的带子。
const double _glassModeCardWidth = 112;

/// 单个质感卡片：图标在上、名称在下；选中时主题色描边 + 淡底（照 morrow）。
class _GlassModeCard extends StatelessWidget {
  const _GlassModeCard({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: AnimatedContainer(
          duration: AppMotion.brief,
          curve: AppMotion.standardCurve,
          // 固定高度：三张卡片必须一样高，否则 Mica / Acrylic 这种长标签
          //（会折成两行）会把那一张顶高，一排卡片就参差了。
          height: 76,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? scheme.primary.withValues(alpha: .14)
                : AppSurfaceTokens.glassModeCardBase(scheme),
            border: Border.all(
              color: selected
                  ? scheme.primary.withValues(alpha: .5)
                  : scheme.outlineVariant,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
              const SizedBox(height: 5),
              Text(
                title,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  color: selected ? scheme.primary : scheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
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

String _themeModeLabel(AppLocalizations l10n, AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => l10n.followSystem,
      AppThemeMode.light => l10n.light,
      AppThemeMode.dark => l10n.dark,
    };