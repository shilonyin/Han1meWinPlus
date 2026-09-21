import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import 'about_page.dart';
import 'comment_settings_page.dart';
import 'language_settings_page.dart';
import 'layout_settings_page.dart';
import 'network_settings_page.dart';
import 'playback_settings_page.dart';
import 'selection_settings_pages.dart';
import 'settings_controller.dart';
import 'settings_list.dart';
import 'storage_settings_page.dart';
import 'theme_settings_page.dart';
import 'webdav_settings_page.dart';

/// One entry in the settings navigation, used by both layouts.
class _SettingsEntry {
  const _SettingsEntry(this.icon, this.label, this.page, this.route);

  final IconData icon;
  final String label;
  final Widget page;
  final String route;
}

/// Grouped only where the group adds meaning; order matches the reading order
/// of the old single-column list.
List<(String, List<_SettingsEntry>)> _settingsSections(AppLocalizations l10n) => [
      (l10n.appearance, [
        _SettingsEntry(Icons.palette_outlined, l10n.themeAndColor, const ThemeSettingsPage(), '/settings/theme'),
        _SettingsEntry(Icons.dashboard_customize_outlined, l10n.interfaceLayout, const LayoutSettingsPage(), '/settings/layout'),
      ]),
      (l10n.playback, [
        _SettingsEntry(Icons.smart_display_outlined, l10n.playbackSettings, const PlaybackSettingsPage(), '/settings/playback'),
      ]),
      (l10n.network, [
        _SettingsEntry(Icons.language_outlined, l10n.networkSettings, const NetworkSettingsPage(), '/settings/network'),
        _SettingsEntry(Icons.cloud_sync_outlined, l10n.webDavSettings, const WebDavSettingsPage(), '/settings/webdav'),
      ]),
      (l10n.content, [
        _SettingsEntry(Icons.calendar_month_outlined, l10n.previewSource, const PreviewSourceSettingsPage(), '/settings/previews'),
        _SettingsEntry(Icons.forum_outlined, l10n.commentSettings, const CommentSettingsPage(), '/settings/comments'),
        _SettingsEntry(Icons.translate_outlined, l10n.languageSettings, const LanguageSettingsPage(), '/settings/language'),
      ]),
      (l10n.storage, [
        _SettingsEntry(Icons.sd_storage_outlined, l10n.storage, const StorageSettingsPage(), '/settings/storage'),
      ]),
      (l10n.other, [
        _SettingsEntry(Icons.info_outline, l10n.about, const AboutPage(), '/settings/about'),
      ]),
    ];

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  /// Below this width the two panes do not fit, so the categories fall back to
  /// a plain pushed list.
  static const double minPaneWidth = 760;

  @override
  Widget build(BuildContext context) => MediaQuery.sizeOf(context).width >= minPaneWidth ? const _SettingsPanes() : const _SettingsCategoryList();
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
                        style: textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                        child: Text(sections[group].$1),
                      ),
                    ),
                  ),
                  for (var item = 0; item < sections[group].$2.length; item++)
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
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: KeyedSubtree(key: ValueKey(selected.route), child: selected.page)),
        ],
      ),
    );
  }
}

class _NavItem extends StatefulWidget {
  const _NavItem({required this.icon, required this.label, required this.selected, required this.onTap});

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
    // 选中与悬停都靠「左侧竖条 + 文字/图标变色」表示，不铺底色块 —— 底色块比图标还抢眼。
    final highlighted = widget.selected || _hovered;
    final foreground = highlighted ? colorScheme.primary : colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(28),
          // 不能出现矩形水波纹，否则悬停/点击会冒出底色块。
          hoverColor: Colors.transparent,
          splashColor: Colors.transparent,
          highlightColor: Colors.transparent,
          child: SizedBox(
            height: 56,
            child: Row(
              children: [
                // 选中竖条：常驻占位，避免选中时内容左右跳动。
                SizedBox(
                  width: 3,
                  child: widget.selected ? Center(child: Container(width: 3, height: 18, decoration: BoxDecoration(color: colorScheme.primary, borderRadius: BorderRadius.circular(2)))) : null,
                ),
                const SizedBox(width: 13),
                Icon(widget.icon, size: 24, color: foreground),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(widget.label, style: textTheme.labelLarge?.copyWith(color: foreground, fontWeight: widget.selected ? FontWeight.w600 : null), maxLines: 1, overflow: TextOverflow.ellipsis),
                ),
                const SizedBox(width: 12),
              ],
            ),
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
    Text sectionTitle(String value) => Text(value, style: TextStyle(color: Theme.of(context).colorScheme.primary));
    final sections = _settingsSections(l10n);
    return Scaffold(
      appBar: AppBar(leading: ref.watch(settingsProvider).valueOrNull?.useNavigationDrawer ?? false ? (permanentNavigationDrawer(context) ? null : IconButton(onPressed: openAppDrawer, icon: const Icon(Icons.menu))) : null, title: Text(l10n.settings)),
      body: SettingsList(
        contentPadding: EdgeInsets.only(bottom: MediaQuery.paddingOf(context).bottom),
        sections: [
          for (final section in sections)
            SettingsSection(
              title: sectionTitle(section.$1),
              tiles: [
                for (final entry in section.$2)
                  SettingsTile.navigation(leading: Icon(entry.icon), title: Text(entry.label), value: const Icon(Icons.chevron_right), onPressed: (context) => context.push(entry.route)),
              ],
            ),
        ],
      ),
    );
  }
}
