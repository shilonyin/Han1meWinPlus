import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/local/site_group_store.dart';
import '../../data/remote/jav/jav_site.dart';
import 'option_settings_dialog.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';

/// 分组显示名：用户没改过名时用内置名（于是跟随界面语言）。
String siteGroupName(SiteGroup group, AppLocalizations l10n) => group.name.isNotEmpty ? group.name : group.id == javSiteGroupId ? l10n.javSources : l10n.site;

/// 站点地址的显示名（AV 源显示「名字 · 主机」）。
String siteHostLabel(String host, AppLocalizations l10n) {
  for (final site in javSites) {
    if (site.baseUrl == host) return '${site.label} · ${site.host}';
  }
  return host;
}

/// 站点的一行说明（只有需要先过验证的 AV 源才有）。
String siteHostHint(String host, AppLocalizations l10n) => javSites.any((site) => site.baseUrl == host && site.requiresVerification) ? l10n.javSourceVerification : '';

final siteGroupsProvider = AsyncNotifierProvider<SiteGroupsController, List<SiteGroup>>(SiteGroupsController.new);

class SiteGroupsController extends AsyncNotifier<List<SiteGroup>> {
  @override
  Future<List<SiteGroup>> build() async {
    // 漫画模式会改变可选站点，所以分组与清单对齐时要带上它。
    final comicMode = await ref.watch(settingsProvider.selectAsync((settings) => settings.comicMode));
    return ref.read(siteGroupStoreProvider).read(comicMode: comicMode);
  }

  Future<void> replace(List<SiteGroup> groups) async {
    state = AsyncData(groups);
    await ref.read(siteGroupStoreProvider).write(groups);
  }
}

/// 站点分组管理：改名、调顺序、增删分组、把站点挪到别的分组。
///
/// 没配置过时按类型自动分组（Hanime1 系 / AV 视频源）；站点清单变化时新站点会自动补进
/// 它默认该在的组（见 [SiteGroupStore.align]），所以升级后不需要手动维护。
class SiteGroupsPage extends ConsumerWidget {
  const SiteGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final groups = ref.watch(siteGroupsProvider).valueOrNull;
    if (groups == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(leading: settingsSubPageBack(context), title: Text(l10n.siteGroups)),
      // 用 Sliver 组合而不是 ReorderableListView 的 header/footer —— 后者的 footer 区域
      // 在桌面端收不到指针事件（同「首页快捷分类」那页踩过的坑）。
      body: CustomScrollView(slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
          sliver: SliverToBoxAdapter(child: Text(l10n.siteGroupsDescription, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, height: 1.4))),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          sliver: SliverReorderableList(
            itemCount: groups.length,
            onReorderItem: (oldIndex, newIndex) {
              final next = [...groups];
              next.insert(newIndex, next.removeAt(oldIndex));
              unawaited(ref.read(siteGroupsProvider.notifier).replace(next));
            },
            itemBuilder: (context, index) => Padding(
              key: ValueKey(groups[index].id),
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Material(color: theme.colorScheme.surfaceContainerLow, borderRadius: BorderRadius.circular(12), child: _groupCard(context, ref, groups, index, l10n)),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          sliver: SliverToBoxAdapter(child: FilledButton.tonalIcon(onPressed: () => _addGroup(context, ref, groups), icon: const Icon(Icons.add), label: Text(l10n.siteGroupAdd))),
        ),
      ]),
    );
  }

  Widget _groupCard(BuildContext context, WidgetRef ref, List<SiteGroup> groups, int index, AppLocalizations l10n) {
    final group = groups[index];
    final theme = Theme.of(context);
    final multiple = groups.length > 1;
    return Column(mainAxisSize: MainAxisSize.min, children: [
      ListTile(
        dense: true,
        leading: ReorderableDragStartListener(index: index, child: const Icon(Icons.drag_indicator)),
        title: Text(siteGroupName(group, l10n), style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
        subtitle: Text(l10n.siteHostsCount(group.hosts.length), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          IconButton(tooltip: l10n.siteGroupRename, onPressed: () => _rename(context, ref, groups, index), icon: const Icon(Icons.edit_outlined, size: 20)),
          IconButton(tooltip: l10n.delete, onPressed: multiple ? () => _delete(context, ref, groups, index) : null, icon: const Icon(Icons.remove_circle_outline, size: 20)),
        ]),
      ),
      if (group.hosts.isEmpty)
        Padding(padding: const EdgeInsets.fromLTRB(56, 0, 16, 12), child: Align(alignment: Alignment.centerLeft, child: Text(l10n.siteGroupEmpty, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)))),
      for (final host in group.hosts)
        ListTile(
          dense: true,
          contentPadding: const EdgeInsets.only(left: 56, right: 8),
          title: Text(siteHostLabel(host, l10n)),
          subtitle: siteHostHint(host, l10n).isEmpty ? null : Text(siteHostHint(host, l10n)),
          trailing: IconButton(tooltip: l10n.siteGroupMoveTo, onPressed: multiple ? () => _move(context, ref, groups, index, host) : null, icon: const Icon(Icons.drive_file_move_outlined, size: 20)),
        ),
    ]);
  }

  /// 改分组名。留空表示回到内置默认名（跟随界面语言）。
  Future<void> _rename(BuildContext context, WidgetRef ref, List<SiteGroup> groups, int index) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(context, title: l10n.siteGroupRename, initial: groups[index].name.isEmpty ? siteGroupName(groups[index], l10n) : groups[index].name);
    if (name == null) return;
    final next = [...groups];
    next[index] = next[index].copyWith(name: name);
    await ref.read(siteGroupsProvider.notifier).replace(next);
  }

  Future<void> _addGroup(BuildContext context, WidgetRef ref, List<SiteGroup> groups) async {
    final l10n = AppLocalizations.of(context)!;
    final name = await _askName(context, title: l10n.siteGroupAdd);
    if (name == null || name.isEmpty) return;
    await ref.read(siteGroupsProvider.notifier).replace([...groups, SiteGroup(id: newSiteGroupId(), name: name, hosts: const [])]);
  }

  /// 删除分组。**组内站点并入第一个分组** —— 站点清单是固定的，不能因为删组而消失
  /// （否则下次读取时「自动归类」又会把它加回来，看起来像删不掉）。
  Future<void> _delete(BuildContext context, WidgetRef ref, List<SiteGroup> groups, int index) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.delete),
        content: Text(l10n.siteGroupDeleteHint(siteGroupName(groups[index], l10n))),
        actions: [TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete))],
      ),
    );
    if (confirmed != true) return;
    final next = [...groups];
    final removed = next.removeAt(index);
    next[0] = next[0].copyWith(hosts: [...next[0].hosts, ...removed.hosts]);
    await ref.read(siteGroupsProvider.notifier).replace(next);
  }

  Future<void> _move(BuildContext context, WidgetRef ref, List<SiteGroup> groups, int from, String host) async {
    final l10n = AppLocalizations.of(context)!;
    final targets = [for (var i = 0; i < groups.length; i++) if (i != from) groups[i]];
    final target = await showOptionSettingsDialog<String>(
      context: context,
      title: l10n.siteGroupMoveTo,
      current: '',
      options: [for (final group in targets) group.id],
      label: (id) => siteGroupName(targets.firstWhere((group) => group.id == id), l10n),
    );
    if (target == null) return;
    final next = [...groups];
    final fromIndex = next.indexWhere((group) => group.id == groups[from].id);
    final toIndex = next.indexWhere((group) => group.id == target);
    if (fromIndex < 0 || toIndex < 0) return;
    next[fromIndex] = next[fromIndex].copyWith(hosts: [...next[fromIndex].hosts]..remove(host));
    next[toIndex] = next[toIndex].copyWith(hosts: [...next[toIndex].hosts, host]);
    await ref.read(siteGroupsProvider.notifier).replace(next);
  }

  Future<String?> _askName(BuildContext context, {required String title, String initial = ''}) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = TextEditingController(text: initial);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: TextField(controller: controller, autofocus: true, textInputAction: TextInputAction.done, onSubmitted: (value) => Navigator.pop(context, value.trim()), decoration: InputDecoration(labelText: l10n.siteGroupName, helperText: l10n.siteGroupNameHint)),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, controller.text.trim()), child: Text(l10n.save))],
      ),
    );
    controller.dispose();
    return result;
  }
}
