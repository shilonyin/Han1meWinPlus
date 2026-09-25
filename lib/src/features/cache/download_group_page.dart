import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/local/download_repository.dart';
import '../../domain/models/download.dart';
import '../settings/settings_card_list.dart';
import 'cache_format.dart';

/// 打开分组设置弹窗。
///
/// [groupId] 为 null 表示新建分组，否则编辑该分组。
/// 原来是一个整页路由（`/cache/groups/...`），但内容只有「名称 + 排序 + 删除」三项，
/// 整页铺开大片留白、跳转还打断上下文，改成弹窗后就地编辑。
Future<void> showGroupEditor(BuildContext context, WidgetRef ref, {String? groupId}) async {
  final state = ref.read(downloadProvider).valueOrNull;
  final group = groupId == null ? null : state?.groups.where((item) => item.id == groupId).firstOrNull;
  // 分组已经被删掉时不再弹空壳。
  if (groupId != null && group == null) return;
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (context) => _GroupEditorDialog(group: group),
  );
}

class _GroupEditorDialog extends ConsumerStatefulWidget {
  const _GroupEditorDialog({this.group});

  final DownloadGroup? group;

  @override
  ConsumerState<_GroupEditorDialog> createState() => _GroupEditorDialogState();
}

class _GroupEditorDialogState extends ConsumerState<_GroupEditorDialog> {
  late final TextEditingController nameController;
  late DownloadGroupSort sort;
  var saving = false;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    final l10n = AppLocalizations.of(context);
    nameController = TextEditingController(
      // 默认分组的名字是内置文案，编辑框里显示当前语言的说法；
      // 取不到本地化（极早期构建）时退回存储里的原名，不要弹空输入框。
      text: group == null ? '' : (l10n == null ? group.name : localizedGroupName(group, l10n)),
    );
    sort = group?.sort ?? DownloadGroupSort.defaultOrder;
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final group = widget.group;
    // 默认分组是内置的「已缓存」，只允许改排序，不许改名或删除。
    final locked = group?.id == 'default';
    return AlertDialog(
      title: Text(group == null ? l10n.createGroup : l10n.groupSettings),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: nameController,
              autofocus: group == null,
              enabled: !locked,
              decoration: InputDecoration(labelText: l10n.groupName, border: const OutlineInputBorder()),
            ),
            const SizedBox(height: 16),
            SettingsCardList(
              children: [
                SettingsMenuItem<DownloadGroupSort>(
                  title: l10n.sortOrder,
                  subtitle: _sortLabel(sort, l10n),
                  leading: const Icon(Icons.sort),
                  value: sort,
                  options: DownloadGroupSort.values,
                  label: (value) => _sortLabel(value, l10n),
                  onSelected: (value) => setState(() => sort = value),
                ),
                if (group != null && !locked)
                  SettingsCardItem(
                    title: l10n.deleteGroup,
                    subtitle: l10n.deleteGroupDescription,
                    leading: const Icon(Icons.delete_outline),
                    onTap: () => _delete(group, l10n),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: saving ? null : () => Navigator.pop(context), child: Text(l10n.cancel)),
        FilledButton(onPressed: saving ? null : _save, child: Text(l10n.save)),
      ],
    );
  }

  String _sortLabel(DownloadGroupSort value, AppLocalizations l10n) => switch (value) {
        DownloadGroupSort.defaultOrder => l10n.defaultValue,
        DownloadGroupSort.recentlyUpdated => l10n.recentlyUpdated,
        DownloadGroupSort.name => l10n.name,
      };

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    final name = nameController.text.trim();
    final group = widget.group;
    // 默认分组的名字是内置文案，直接以原名保存，避免把「已缓存」写死进数据。
    if (group == null && name.isEmpty) return;
    setState(() => saving = true);
    if (group == null) {
      await ref.read(downloadProvider.notifier).addGroup(name, sort);
    } else {
      await ref.read(downloadProvider.notifier).updateGroup(group.id, name.isEmpty ? group.name : name, sort);
    }
    if (mounted) Navigator.pop(context);
    // 名字没变、只是改了排序时不会有可见反馈，这里补一句提示。
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(l10n.save))).closed.ignore();
  }

  Future<void> _delete(DownloadGroup group, AppLocalizations l10n) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteGroup),
        content: Text(l10n.deleteGroupConfirmation),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteGroup(group.id);
    if (mounted) Navigator.pop(context);
  }
}
