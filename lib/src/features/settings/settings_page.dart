import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import 'about_page.dart';
import 'comment_settings_page.dart';
import 'hotkey_settings_page.dart';
import 'language_settings_page.dart';
import 'layout_settings_page.dart';
import 'network_settings_page.dart';
import 'playback_settings_page.dart';
import 'selection_settings_pages.dart';
import 'settings_controller.dart';
import 'settings_list.dart';
import 'settings_pane_scope.dart';
import 'storage_settings_page.dart';
import 'theme_settings_page.dart';
import 'webdav_settings_page.dart';

/// 左栏分组卡片的圆角：与右侧设置卡片的外层圆角一致，两边是同一套造型。
const double _navGroupRadius = 20;

/// One entry in the settings navigation, used by both layouts.
class _SettingsEntry {  const _SettingsEntry(this.icon, this.label, this.page, this.route);

  final IconData icon;
  final String label;
  final Widget page;
  final String route;
}

/// Grouped only where the group adds meaning; order matches the reading order
/// of the old single-column list.
List<(String, List<_SettingsEntry>)> _settingsSections(AppLocalizations l10n) =>
    [
      (
        l10n.appearance,
        [
          _SettingsEntry(
            Symbols.palette_rounded,
            l10n.themeAndColor,
            const ThemeSettingsPage(),
            '/settings/theme',
          ),
          _SettingsEntry(
            Symbols.dashboard_customize_rounded,
            l10n.interfaceLayout,
            const LayoutSettingsPage(),
            '/settings/layout',
          ),
        ],
      ),
      (
        l10n.playback,
        [
          _SettingsEntry(
            Symbols.smart_display_rounded,
            l10n.playbackSettings,
            const PlaybackSettingsPage(),
            '/settings/playback',
          ),
          _SettingsEntry(
            Symbols.keyboard_rounded,
            l10n.settingsHotkeys,
            const HotkeySettingsPage(),
            '/settings/hotkeys',
          ),
        ],
      ),
      (
        l10n.network,
        [
          _SettingsEntry(
            Symbols.language_rounded,
            l10n.networkSettings,
            const NetworkSettingsPage(),
            '/settings/network',
          ),
          _SettingsEntry(
            Symbols.cloud_sync_rounded,
            l10n.webDavSettings,
            const WebDavSettingsPage(),
            '/settings/webdav',
          ),
        ],
      ),
      (
        l10n.content,
        [
          _SettingsEntry(
            Symbols.calendar_month_rounded,
            l10n.previewSource,
            const PreviewSourceSettingsPage(),
            '/settings/previews',
          ),
          _SettingsEntry(
            Symbols.forum_rounded,
            l10n.commentSettings,
            const CommentSettingsPage(),
            '/settings/comments',
          ),
          _SettingsEntry(
            Symbols.translate_rounded,
            l10n.languageSettings,
            const LanguageSettingsPage(),
            '/settings/language',
          ),
        ],
      ),
      (
        l10n.storage,
        [
          _SettingsEntry(
            Symbols.sd_storage_rounded,
            l10n.storage,
            const StorageSettingsPage(),
            '/settings/storage',
          ),
        ],
      ),
      (
        l10n.other,
        [
          _SettingsEntry(
            Symbols.info_rounded,
            l10n.about,
            const AboutPage(),
            '/settings/about',
          ),
        ],
      ),
    ];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Below this width the two panes do not fit, so the categories fall back to
  /// a plain pushed list.
  static const double minPaneWidth = settingsPaneMinWidth;

  @override
  Widget build(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= minPaneWidth
      ? const _SettingsPanes()
      : const _SettingsCategoryList();
}

/// Wide layout: categories on the left, the selected page on the right.
class _SettingsPanes extends StatefulWidget {
  const _SettingsPanes();

  @override
  State<_SettingsPanes> createState() => _SettingsPanesState();
}

class _SettingsPanesState extends State<_SettingsPanes> {
  var _group = 0;
  var _item = 0;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final sections = _settingsSections(l10n);
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final selected = sections[_group].$2[_item];
    return Scaffold(
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 280,
            child: ListView(
              padding: const EdgeInsets.fromLTRB(4, 0, 0, 12),
              children: [
                for (var group = 0; group < sections.length; group++) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(28, 16, 28, 8),
                    child: Semantics(
                      header: true,
                      child: DefaultTextStyle.merge(
                        // 与右侧卡片的分组标题（「外观 / 窗口」）同一种样式：主题色小字 + 半粗。
                        style: textTheme.titleSmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                        child: Text(sections[group].$1),
                      ),
                    ),
                  ),
                  // 同一分组的条目共用**一整块底色**，和右侧设置卡片是同一套造型
                  // （圆角一致、底色一致），两侧因此看起来是一个界面而不是两种设计。
                  // 选中态仍由条目自己的文字/图标变色表达，卡片只负责"这几条属于一组"。
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    // 换成 g1455 的 GlassCard：它是"一块浮层玻璃面板"的正规实现
                    // （一个 host 录制全屏一次，这块面板取自己那一格，真折射 + 模糊）。
                    //
                    // 只有这一处先换，其余 18 个 GlassPanel 调用点仍是自制那套 ——
                    // 先看实际观感，满意再铺开。
                    //
                    // `padding: zero` 是必须的：`GlassCard` 默认内边距 16，而这里
                    // 原来是零内边距（边距由各条目自己带），不置零会多出一圈。
                    child: GlassCard(
                      borderRadius: BorderRadius.circular(_navGroupRadius),
                      padding: EdgeInsets.zero,
                      child: Column(
                        children: [
                          for (
                            var item = 0;
                            item < sections[group].$2.length;
                            item++
                          )
                            _NavItem(
                              icon: sections[group].$2[item].icon,
                              label: sections[group].$2[item].label,
                              selected: group == _group && item == _item,
                              onTap: () => setState(() {
                                _group = group;
                                _item = item;
                              }),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: KeyedSubtree(
              key: ValueKey(selected.route),
              child: selected.page,
            ),
          ),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_NavItem> createState() => _NavItemState();
}

class _NavItemState extends State<_NavItem> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 选中与悬停都靠「文字 / 图标变主题色」表示。
    // 底色由所属的**分组卡片**统一提供，条目自己不再铺色 ——
    // 分组底色上再叠一层条目底色，反而看不出"这几条属于一组"。
    final highlighted = widget.selected || _hovered;
    final foreground = highlighted
        ? colorScheme.primary
        : colorScheme.onSurfaceVariant;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(10),
        // 不能出现矩形水波纹，否则悬停/点击会在分组底色上再冒一块。
        hoverColor: Colors.transparent,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        child: SizedBox(
          height: 50,
          child: Row(
            children: [
              // 选中竖条：常驻占位，避免选中时内容左右跳动。
              SizedBox(
                width: 3,
                child: widget.selected
                    ? Center(
                        child: Container(
                          width: 3,
                          height: 18,
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      )
                    : null,
              ),
              const SizedBox(width: 13),
              Icon(widget.icon, size: 22, color: foreground),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.label,
                  style: textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: widget.selected ? FontWeight.w600 : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
      ),
    );
  }
}

/// Narrow layout: the original single-column list of categories.
class _SettingsCategoryList extends ConsumerWidget {
  const _SettingsCategoryList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    // 与宽窗布局一致：分类标题用中性强文本色，不跟选中项抢主题色。
    Text sectionTitle(String value) => Text(
      value,
      style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
    );
    final sections = _settingsSections(l10n);
    return Scaffold(
      appBar: AppBar(
        leading:
            ref.watch(settingsProvider).valueOrNull?.useNavigationDrawer ??
                false
            ? (permanentNavigationDrawer(context)
                  ? null
                  : IconButton(
                      onPressed: openAppDrawer,
                      icon: const Icon(Symbols.menu_rounded),
                    ))
            : null,
        title: Text(l10n.settings),
      ),
      body: SettingsList(
        contentPadding: EdgeInsets.only(
          bottom: MediaQuery.paddingOf(context).bottom,
        ),
        sections: [
          for (final section in sections)
            SettingsSection(
              title: sectionTitle(section.$1),
              tiles: [
                for (final entry in section.$2)
                  SettingsTile.navigation(
                    leading: Icon(entry.icon),
                    title: Text(entry.label),
                    value: const Icon(Symbols.chevron_right_rounded),
                    onPressed: (context) => context.push(entry.route),
                  ),
              ],
            ),
        ],
      ),
    );
  }
}
