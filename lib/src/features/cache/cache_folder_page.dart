import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/local/download_repository.dart';
import '../../domain/models/download.dart';
import 'cache_cards.dart';
import 'cache_format.dart';
import 'download_group_page.dart';

/// 网格里单张卡片的目标宽度区间。
///
/// 与 b 站离线缓存的集合内页一致：一行铺 4 张左右，窄窗口自动减列；
/// 卡片过少时不会被拉伸成一张巨大的图。
const _minCardWidth = 150.0;
const _maxCardWidth = 260.0;

/// 进入某个分组（系列）后的集合内页，对应 b 站离线缓存里点开文件夹的那一层。
///
/// 版式按 b 站做成三段：**头部**（大封面 + 集合名 + 「播放全部」）、
/// **分段标题**（「正片」）、**剧集卡片网格**（封面带体积/时长角标，标题下一行）。
/// 原来的横排列表在只有一两条内容时下方会空出一大片，也没有「播放全部」这种
/// 集合级动作；网格 + 头部信息把这一页填满，也更接近用户的直觉。
class CacheFolderPage extends ConsumerStatefulWidget {
  const CacheFolderPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<CacheFolderPage> createState() => _CacheFolderPageState();
}

class _CacheFolderPageState extends ConsumerState<CacheFolderPage> {
  final _selected = <String>{};

  bool get _selecting => _selected.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final downloads = ref.watch(downloadProvider);
    return downloads.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (error, _) => Scaffold(appBar: AppBar(), body: Center(child: Text('$error'))),
      data: (state) {
        final group = state.groups.where((item) => item.id == widget.groupId).firstOrNull;
        // 分组可能在别处被删掉了，这时直接把这一页收起来。
        if (group == null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          });
          return Scaffold(appBar: AppBar(), body: const SizedBox.shrink());
        }
        final tasks = sortTasks(state.tasks.where((task) => _inGroup(task, group)), group.sort);
        final name = localizedGroupName(group, l10n);
        return Scaffold(
          appBar: AppBar(
            leading: _selecting ? IconButton(tooltip: l10n.cancel, onPressed: () => setState(_selected.clear), icon: const Icon(Icons.close)) : null,
            // 标题栏放不下长系列名时交给省略号：原来直接把整个名字塞进 title，
            // 超长分组名（自动建组用系列名，常常就是整条标题）会把操作按钮挤掉。
            title: Text(_selecting ? l10n.selectedItems(_selected.length) : name, maxLines: 1, overflow: TextOverflow.ellipsis),
            actions: [
              if (_selecting) ...[
                IconButton(tooltip: l10n.selectAll, onPressed: () => setState(() => _selected.addAll(tasks.map((task) => task.id))), icon: const Icon(Icons.select_all)),
                IconButton(tooltip: l10n.startAll, onPressed: () => _run(ref.read(downloadProvider.notifier).resumeTasks({..._selected})), icon: const Icon(Icons.play_arrow_outlined)),
                IconButton(tooltip: l10n.deleteSelectedCache, onPressed: _deleteSelected, icon: const Icon(Icons.delete_outline)),
              ] else
                IconButton(tooltip: l10n.groupSettings, onPressed: () => showGroupEditor(context, ref, groupId: group.id), icon: const Icon(Icons.tune)),
            ],
          ),
          body: tasks.isEmpty
              ? _EmptyFolder(name: name)
              : ListView(
                  padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + MediaQuery.paddingOf(context).bottom),
                  children: [
                    _FolderHeader(
                      name: name,
                      tasks: tasks,
                      onPlayAll: _playAll,
                      onToggleAll: () => _toggleAll(tasks),
                      selecting: _selecting,
                      allSelected: tasks.isNotEmpty && tasks.every((task) => _selected.contains(task.id)),
                    ),
                    const SizedBox(height: 24),
                    // 分段标题：b 站这里是「正片」，本应用没有预告/花絮之分，
                    // 但保留这条分隔能明确"下面是这一集集的内容"。
                    _SectionTitle(text: l10n.mainEpisodes),
                    const SizedBox(height: 12),
                    _EpisodeGrid(
                      tasks: tasks,
                      selected: _selected,
                      selecting: _selecting,
                      onTap: (task) => _selecting ? _toggle(task.id) : _open(task),
                      onToggle: (task) => _toggle(task.id),
                      onMenu: (task) => _showTaskMenu(task),
                    ),
                  ],
                ),
        );
      },
    );
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  void _toggleAll(List<DownloadTask> tasks) => setState(() {
        final ids = tasks.map((task) => task.id).toSet();
        ids.every(_selected.contains) ? _selected.removeAll(ids) : _selected.addAll(ids);
      });

  /// 「播放全部」：从第一条已下完的开始播。
  ///
  /// 只挑已完成的 —— 没下完的没有本地文件，点了也播不了。
  Future<void> _playAll() async {
    final state = ref.read(downloadProvider).valueOrNull;
    if (state == null) return;
    final group = state.groups.where((item) => item.id == widget.groupId).firstOrNull;
    if (group == null) return;
    final completed = sortTasks(state.tasks.where((task) => _inGroup(task, group) && task.status == DownloadStatus.completed), group.sort);
    if (completed.isEmpty) return;
    await _open(completed.first);
  }

  Future<void> _open(DownloadTask task) async {
    if (task.status != DownloadStatus.completed) return;
    await openCachedVideo(context, task);
  }

  Future<void> _run(Future<void> future) async {
    await future;
    if (mounted) setState(_selected.clear);
  }

  /// 卡片右下角的 ⋮：单条任务的操作（与缓存页的「正在缓存」行一致）。
  Future<void> _showTaskMenu(DownloadTask task) async {
    final l10n = AppLocalizations.of(context)!;
    final controller = ref.read(downloadProvider.notifier);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.play_arrow_outlined),
              title: Text(l10n.play),
              enabled: task.status == DownloadStatus.completed,
              onTap: () => Navigator.pop(sheetContext, 'play'),
            ),
            if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
              ListTile(leading: const Icon(Icons.pause_circle_outline), title: Text(l10n.pause), onTap: () => Navigator.pop(sheetContext, 'pause')),
            if (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)
              ListTile(leading: const Icon(Icons.play_circle_outline), title: Text(task.status == DownloadStatus.failed ? l10n.retry : l10n.resume), onTap: () => Navigator.pop(sheetContext, 'resume')),
            ListTile(leading: const Icon(Icons.delete_outline), title: Text(l10n.deleteCache), onTap: () => Navigator.pop(sheetContext, 'delete')),
          ],
        ),
      ),
    );
    switch (action) {
      case 'play':
        await _open(task);
      case 'pause':
        await controller.pauseTasks({task.id});
      case 'resume':
        await controller.resumeTasks({task.id});
      case 'delete':
        await _deleteOne(task);
    }
  }

  Future<void> _deleteOne(DownloadTask task) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCache),
        content: Text(l10n.deleteCacheConfirmation(task.title)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({task.id});
  }

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteSelectedCache),
        content: Text(l10n.deleteSelectedCacheConfirmation(_selected.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.delete)),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({..._selected});
    if (mounted) setState(_selected.clear);
  }
}

/// 头部：左封面（叠两层纸的文件夹观感）+ 右侧集合名与操作。
class _FolderHeader extends StatelessWidget {
  const _FolderHeader({
    required this.name,
    required this.tasks,
    required this.onPlayAll,
    required this.onToggleAll,
    required this.selecting,
    required this.allSelected,
  });

  final String name;
  final List<DownloadTask> tasks;
  final VoidCallback onPlayAll;
  final VoidCallback onToggleAll;
  final bool selecting;
  final bool allSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final completed = tasks.where((task) => task.status == DownloadStatus.completed).length;
    final total = totalBytesOf(tasks);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _HeaderCover(tasks: tasks),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              Text(
                '${l10n.folderContents(tasks.length)} · ${l10n.folderSize(formatBytes(total))}',
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  // 「播放全部」是集合级的主操作，用实心按钮突出（b 站同款）。
                  FilledButton.icon(
                    onPressed: completed == 0 ? null : onPlayAll,
                    icon: const Icon(Icons.play_arrow, size: 20),
                    label: Text(l10n.playAll),
                  ),
                  OutlinedButton.icon(
                    onPressed: tasks.isEmpty ? null : onToggleAll,
                    icon: Icon(selecting && allSelected ? Icons.check_circle : Icons.check_circle_outline, size: 18),
                    label: Text(l10n.selectAll),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 头部的集合封面：与文件夹卡同一套"叠纸"观感，右下角标内容数。
class _HeaderCover extends StatelessWidget {
  const _HeaderCover({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final cover = folderCoverImage(tasks);
    const width = 200.0;
    const height = 124.0;
    return SizedBox(
      width: width,
      height: height,
      child: Stack(
        children: [
          Positioned(left: 10, right: 10, top: 0, bottom: 10, child: _sheet(theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55))),
          Positioned(left: 5, right: 5, top: 5, bottom: 5, child: _sheet(theme.colorScheme.surfaceContainerHighest.withValues(alpha: .8))),
          Positioned(
            left: 0,
            right: 0,
            top: 10,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image(image: cover, fit: BoxFit.cover)
                  else
                    ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Icons.folder_outlined, size: 40, color: theme.colorScheme.onSurfaceVariant)),
                  Positioned(right: 8, bottom: 8, child: CacheCoverBadge(icon: Icons.folder_outlined, text: l10n.folderContents(tasks.length))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sheet(Color color) => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(12)));
}

/// 分段标题（「正片」）：主题色小标题，与 b 站的粉色分段名对应。
class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(text, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700));
  }
}

/// 剧集卡片网格。
class _EpisodeGrid extends StatelessWidget {
  const _EpisodeGrid({required this.tasks, required this.selected, required this.selecting, required this.onTap, required this.onToggle, required this.onMenu});

  final List<DownloadTask> tasks;
  final Set<String> selected;
  final bool selecting;
  final ValueChanged<DownloadTask> onTap;
  final ValueChanged<DownloadTask> onToggle;
  final ValueChanged<DownloadTask> onMenu;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 12) / (_minCardWidth + 12)).floor().clamp(2, 8);
        final width = ((constraints.maxWidth - 12 * (columns - 1)) / columns).clamp(_minCardWidth, _maxCardWidth);
        return GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            // 卡片 = 16:9 封面 + 标题一行 + 副标题一行。
            mainAxisExtent: width * 9 / 16 + 52,
          ),
          itemCount: tasks.length,
          itemBuilder: (context, index) {
            final task = tasks[index];
            return CacheEpisodeCard(
              task: task,
              selected: selected.contains(task.id),
              selecting: selecting,
              onTap: () => onTap(task),
              onLongPress: () => onToggle(task),
              onMenu: () => onMenu(task),
            );
          },
        );
      },
    );
  }
}

class _EmptyFolder extends StatelessWidget {
  const _EmptyFolder({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_outlined, size: 48, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .6)),
          const SizedBox(height: 12),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 32), child: Text(name, textAlign: TextAlign.center, style: theme.textTheme.titleMedium)),
          const SizedBox(height: 6),
          Text(AppLocalizations.of(context)!.emptyCacheHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

bool _inGroup(DownloadTask task, DownloadGroup group) => group.id == 'default' || task.groupIds.contains(group.id);

/// 按分组自己的排序设置排一遍任务。
List<DownloadTask> sortTasks(Iterable<DownloadTask> source, DownloadGroupSort sort) {
  final tasks = source.toList();
  switch (sort) {
    case DownloadGroupSort.recentlyUpdated:
      tasks.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    case DownloadGroupSort.name:
      tasks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case DownloadGroupSort.defaultOrder:
      // 默认序：正在下的排前面，然后按加入时间倒序 —— 刚下的先看到。
      tasks.sort((a, b) {
        final activeA = a.status == DownloadStatus.downloading ? 0 : 1;
        final activeB = b.status == DownloadStatus.downloading ? 0 : 1;
        if (activeA != activeB) return activeA - activeB;
        return b.createdAt.compareTo(a.createdAt);
      });
  }
  return tasks;
}
