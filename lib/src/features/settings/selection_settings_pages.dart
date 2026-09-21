import 'settings_list.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/settings.dart';
import '../../data/remote/jav/jav_site.dart';
import '../account/account_controller.dart';
import '../explore/explore_controller.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'site_groups_page.dart';

/// 站点选择：默认站点与 AV 视频源放在同一个单选项弹层里。
///
/// 「内容少 → 弹层」的典型：原先为选一行地址要跳一个独立页面，不划算。AV 源与 hanime1
/// 是两套完全不同的站点（账号/评论/清单都不通用），所以切换后要重置首页、并让账号按新
/// 站点重新解析。
Future<void> showSitePicker(BuildContext context, WidgetRef ref, AppSettings settings, {VoidCallback? onManageGroups}) async {
  final l10n = AppLocalizations.of(context)!;
  final current = settings.comicMode ? 'https://hanimeone.me' : settings.baseUrl;
  // 分组来自用户配置（没配置过时就是「按类型自动分组」的结果），空分组不进弹层。
  final groups = [for (final group in await ref.read(siteGroupsProvider.future)) if (group.hosts.isNotEmpty) group];
  // 分组要 await 读出来，回来之后 context 可能已经失效（用户已经退出这一页）。
  if (!context.mounted) return;
  final hints = <String, String>{for (final site in javSites) if (site.requiresVerification) site.baseUrl: l10n.javSourceVerification};
  final selected = await showOptionSettingsDialog<String>(
    context: context,
    title: l10n.site,
    current: current,
    groups: [for (final group in groups) OptionSettingGroup(title: siteGroupName(group, l10n), options: group.hosts)],
    label: (value) => siteHostLabel(value, l10n),
    optionDescription: (value) => hints[value] ?? '',
    // 分组管理与「选站点」本来就是同一件事的两半（名字、顺序、谁在哪一组），所以入口
    // 直接放在这份列表下面，而不是另开一张设置卡片 —— 否则用户得在两个入口之间猜。
    footer: onManageGroups == null ? null : Builder(builder: (dialogContext) => Align(alignment: Alignment.centerLeft, child: TextButton.icon(
      onPressed: () { Navigator.pop(dialogContext); onManageGroups(); },
      icon: const Icon(Icons.tune, size: 18),
      label: Text(l10n.siteGroups),
    ))),
  );
  if (selected == null || selected == current) return;
  await ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(baseUrl: selected, videoBaseUrl: settings.comicMode ? settings.videoBaseUrl : selected, useCustomMirrorSite: false, customMirrorSite: ''));
  ref.invalidate(accountProvider);
  resetHomeFeed(ref);
}

/// 新番预告的数据源：默认站点的预告表常年不可用，所以默认选「自动」，
/// 由 `PreviewsPage` 在加载失败时换到 Getchu。
class PreviewSourceSettingsPage extends ConsumerWidget {
  const PreviewSourceSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final current = ref.watch(settingsProvider).valueOrNull?.previewSource ?? 'auto';
    return _RadioSettingsPage<String>(
      title: l10n.previewSource,
      current: current,
      options: const ['auto', 'default', 'getchu'],
      label: (value) => switch (value) { 'getchu' => l10n.previewSourceGetchu, 'default' => l10n.previewSourceDefault, _ => l10n.previewSourceAuto },
      description: (value) => switch (value) { 'getchu' => l10n.previewSourceGetchuDescription, 'default' => l10n.previewSourceDefaultDescription, _ => l10n.previewSourceAutoDescription },
      onChanged: (value) => ref.read(settingsProvider.notifier).saveChanges((settings) => settings.copyWith(previewSource: value)),
    );
  }
}

class _RadioSettingsPage<T> extends StatelessWidget {
  const _RadioSettingsPage({required this.title, required this.current, required this.options, required this.label, required this.onChanged, this.description});

  final String title;
  final T current;
  final List<T> options;
  final String Function(T value) label;
  final String Function(T value)? description;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title)),
        body: SettingsList(
          sections: [
            SettingsSection(
              title: Text(title, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
              tiles: [
                for (final option in options)
                  SettingsTile<T>.radioTile(radioValue: option, groupValue: current, title: Text(label(option)), description: description == null ? null : Text(description!(option)), onChanged: (value) { if (value != null) onChanged(value); }),
              ],
            ),
          ],
        ),
      );
}
