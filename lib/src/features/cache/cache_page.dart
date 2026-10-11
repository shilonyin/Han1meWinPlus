import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_shell.dart';
import '../../data/local/download_repository.dart';
import '../../domain/models/download.dart';
import '../shared/app_error.dart';
import '../shared/press_scale.dart';
import 'cache_cards.dart';
import 'cache_folder_page.dart';
import 'cache_format.dart';
import 'download_group_page.dart';
import '../../core/app_dialog.dart';

/// 缓存管理页的分栏宽度上限。
///
/// 参考离线缓存的卡片网格：窄窗口下两列、宽窗口按可用宽度铺更多列，
/// 但单张卡不超过 260，免得超大窗口下卡片被拉得又扁又宽。
const _maxCardWidth = 260.0;

const _minCardWidth = 150.0;

/// 缓存管理页：顶部「已缓存视频 / 正在缓存」双状态页签，下面是内容网格。
///
/// 这一版按离线缓存的信息架构重组：
/// - 状态页签取代了原来的「置顶 / 全部」折叠区 —— 已完成和未完成本来就是两件事，
///   混在一个列表里既看不清进度也不好批量操作。
/// - 分组（系列）聚合成文件夹卡片，点开才是分集列表，对应离线缓存的一层目录。
/// - 工具栏放排序 / 分组管理 / 批量操作。
class CachePage extends ConsumerStatefulWidget {
  const CachePage({super.key, this.initialTab = 0});

  /// 初始页签：0 = 已缓存视频，1 = 正在缓存。
  ///
  /// 独立播放窗口把用户送到缓存页时（点「下载」或「我的下载」）默认落在「正在缓存」：
  /// 用户刚加进队列的东西就在那一页，停在「已缓存视频」会让人以为没生效。
  final int initialTab;

  @override
  ConsumerState<CachePage> createState() => _CachePageState();
}

class _CachePageState extends ConsumerState<CachePage> with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _selected = <String>{};
  var _sort = DownloadGroupSort.defaultOrder;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 2, vsync: this, initialIndex: widget.initialTab.clamp(0, 1));
    _tabs.addListener(() {
      // 切页签时清掉选择：两个列表的任务集合不同，留着上一页的选中项会让
      // 计数和实际能操作的对象对不上。
      if (!_tabs.indexIsChanging && _selected.isNotEmpty) setState(_selected.clear);
      setState(() {});
    });
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final downloads = ref.watch(downloadProvider);
    return downloads.when(
      loading: () => const Scaffold(body: Center(child: M3EContainedLoadingIndicator())),
      // 下载记录读不出来时先前的写法是把异常对象直接铺在页面上，既没有图标也没有
      // 重试入口，看着像应用崩了一半。换成共享错误视图，至少能点一下重来。
      error: (error, _) => Scaffold(body: AppErrorView(error: error, onRetry: () => ref.invalidate(downloadProvider))),
      data: (state) {
        final completed = state.tasks.where((task) => task.status == DownloadStatus.completed).toList(growable: false);
        // 页签上的数字必须和该页签下列出的条数一致（`isActiveTask` 把暂停/失败也算进来，
        // 只数「下载中+等待中」会让标题写着 2、点进去看到 3 条）。
        final active = state.tasks.where(isActiveTask).toList(growable: false);
        return Scaffold(
          appBar: AppBar(
            leading: _selecting
                ? PressScale(child: IconButton(tooltip: l10n.cancel, onPressed: () => setState(_selected.clear), icon: const Icon(Symbols.close_rounded)))
                : (permanentNavigationDrawer(context) ? null : PressScale(child: IconButton(tooltip: l10n.navigationDrawer, onPressed: openAppDrawer, icon: const Icon(Symbols.menu_rounded)))),
            title: Text(_selecting ? l10n.selectedItems(_selected.length) : l10n.cache),
            actions: _selecting
                ? _selectionActions(state, [...completed, ...active])
                : [PressScale(child: IconButton(tooltip: l10n.createGroup, onPressed: () => showGroupEditor(context, ref), icon: const Icon(Symbols.create_new_folder_rounded)))],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: TabBar(
                controller: _tabs,
                tabs: [
                  Tab(text: l10n.cachedVideos),
                  Tab(text: active.isEmpty ? l10n.activeDownloads : '${l10n.activeDownloads} ${active.length}'),
                ],
              ),
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _CachedTab(
                groups: state.groups,
                tasks: completed,
                sort: _sort,
                selected: _selected,
                selecting: _selecting,
                onSortChanged: (value) => setState(() => _sort = value),
                onToggleSelect: _toggle,
                onSelectAllInGroup: _selectGroup,
                onOpenGroup: _openGroup,
                onOpenTask: _openTask,
                onManageGroups: () => showGroupEditor(context, ref),
              ),
              _ActiveTab(
                tasks: active,
                selected: _selected,
                selecting: _selecting,
                onToggleSelect: _toggle,
              ),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _selectionActions(DownloadState state, List<DownloadTask> visible) {
    final l10n = AppLocalizations.of(context)!;
    // 三个操作合**一块**玻璃，而不是三个独立的按钮：Apple 的工具栏就是这么做的
    // （相邻项并进同一个胶囊），g1455 照它量出来的 GlassButtonGroup 也是 ——
    // 三个 GlassButton 是三块玻璃、三次绘制，一个 group 只有一次。
    //
    // 每个 icon 自己包一层 Tooltip：GlassToolbarItem.label 是给屏幕阅读器的，
    // 桌面用户悬停时要看到的是那个气泡，光有 Semantics 不够。
    return [
      GlassButtonGroup(
        items: [
          GlassToolbarItem(icon: Tooltip(message: l10n.selectAll, child: const Icon(Symbols.select_all_rounded)), label: l10n.selectAll, onPressed: () => setState(() => _selected.addAll(visible.map((task) => task.id)))),
          GlassToolbarItem(icon: Tooltip(message: l10n.startAll, child: const Icon(Symbols.play_arrow_rounded)), label: l10n.startAll, onPressed: () => _run(ref.read(downloadProvider.notifier).resumeTasks({..._selected}))),
          GlassToolbarItem(icon: Tooltip(message: l10n.deleteSelectedCache, child: const Icon(Symbols.delete_rounded)), label: l10n.deleteSelectedCache, onPressed: _deleteSelected),
        ],
      ),
    ];
  }

  Future<void> _run(Future<void> future) async {
    await future;
    if (mounted) setState(_selected.clear);
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));

  /// 选中 / 取消选中某个分组下的全部任务（文件夹卡上没有单选的概念，一选就是一整组）。
  void _selectGroup(List<DownloadTask> members) => setState(() {
        final ids = members.map((task) => task.id).toSet();
        ids.every(_selected.contains) ? _selected.removeAll(ids) : _selected.addAll(ids);
      });

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSelectedCache),
        content: Text(l10n.deleteSelectedCacheConfirmation(_selected.length)),
        actions: [
          PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel))),
          PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete))),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({..._selected});
    if (mounted) setState(_selected.clear);
  }

  /// 打开文件夹：进到分组页看分集列表。
  ///
  /// 即使分组里只有一条也照样进这一层，不做"只有一条就直接播"的捷径：
  /// 卡片画的是文件夹（叠层 + 「N 个内容」角标），点下去却直接开始播放，
  /// 与它给人的预期不符；而且分组里随时可能再多一集，行为保持一致更好。
  void _openGroup(DownloadGroup group) {
    Navigator.of(context, rootNavigator: true).push(MaterialPageRoute<void>(builder: (_) => CacheFolderPage(groupId: group.id)));
  }

  Future<void> _openTask(DownloadTask task) async {
    await openCachedVideo(context, ref, task);
  }
}

/// 「已缓存视频」页签：分组（系列）聚合成文件夹卡片网格 + 顶部工具栏。
class _CachedTab extends StatelessWidget {
  const _CachedTab({
    required this.groups,
    required this.tasks,
    required this.sort,
    required this.selected,
    required this.selecting,
    required this.onSortChanged,
    required this.onToggleSelect,
    required this.onSelectAllInGroup,
    required this.onOpenGroup,
    required this.onOpenTask,
    required this.onManageGroups,
  });

  final List<DownloadGroup> groups;
  final List<DownloadTask> tasks;
  final DownloadGroupSort sort;
  final Set<String> selected;

  /// 多选态：此时点卡片是「选中/取消」而不是播放，否则点一下就该开始播。
  final bool selecting;
  final ValueChanged<DownloadGroupSort> onSortChanged;
  final ValueChanged<String> onToggleSelect;
  final ValueChanged<List<DownloadTask>> onSelectAllInGroup;
  final ValueChanged<DownloadGroup> onOpenGroup;
  final ValueChanged<DownloadTask> onOpenTask;
  final VoidCallback onManageGroups;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (tasks.isEmpty) return const _EmptyCache();
    // 网格里的每一项要么是一个分组（系列）的文件夹，要么是一条没归组的影片。
    //
    // 注意这里**不**把 `default` 当成一个文件夹：在本应用的数据模型里
    // `default` 的语义是"全部任务"（见 `_inGroup`），拿它当文件夹会把每一条
    // 内容再算一遍，网格上就会出现"文件夹里装着另一张同样的卡"。
    // 所以：有归属的聚成文件夹，没归属的单铺一张卡 —— 与离线缓存的形态一致。
    final entries = <_CacheEntry>[
      for (final group in groups)
        if (group.id != 'default')
          if (tasks.where((task) => task.groupIds.contains(group.id)).toList(growable: false) case final members when members.isNotEmpty)
            _CacheEntry.folder(group: group, members: members),
      for (final task in tasks)
        if (task.groupIds.isEmpty) _CacheEntry.video(task),
    ];
    return Column(
      children: [
        _CacheToolbar(
          summary: groupSummaryLine(l10n, tasks),
          sort: sort,
          onSortChanged: onSortChanged,
          onManageGroups: onManageGroups,
          actions: const [],
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = ((constraints.maxWidth - 24) / (_minCardWidth + 12)).floor().clamp(2, 8);
              final width = ((constraints.maxWidth - 24 - 12 * (columns - 1)) / columns).clamp(_minCardWidth, _maxCardWidth);
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(12, 4, 12, 24 + MediaQuery.paddingOf(context).bottom),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 12,
                  // 卡片高度 = 封面（文件夹比 16:9 略高，要显出叠层的厚度）+ 两行文字。
                  mainAxisExtent: width * .62 + 44,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry.group != null) {
                    final members = entry.members!;
                    final isSelected = members.every((task) => selected.contains(task.id));
                    return _SelectableBorder(
                      selected: isSelected,
                      child: CacheFolderCard(
                        group: entry.group!,
                        tasks: members,
                        onTap: () => selecting ? onSelectAllInGroup(members) : onOpenGroup(entry.group!),
                        onLongPress: () => onSelectAllInGroup(members),
                      ),
                    );
                  }
                  final task = entry.task!;
                  return _SelectableBorder(
                    selected: selected.contains(task.id),
                    child: CacheVideoCard(
                      task: task,
                      // 未归组的影片没有中间那一层，点一下就该直接开始播放；
                      // 只有已经在多选态时才把点击当成选中（与文件夹内页一致）。
                      onTap: () => selecting ? onToggleSelect(task.id) : onOpenTask(task),
                      onLongPress: () => onToggleSelect(task.id),
                    ),
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

/// 网格里的一项：文件夹（分组）或单条影片。
class _CacheEntry {
  const _CacheEntry.folder({required DownloadGroup this.group, required List<DownloadTask> this.members}) : task = null;

  const _CacheEntry.video(DownloadTask this.task) : group = null, members = null;

  final DownloadGroup? group;
  final List<DownloadTask>? members;
  final DownloadTask? task;
}

/// 给网格卡片套一圈选中描边（长按多选时的视觉反馈）。
class _SelectableBorder extends StatelessWidget {
  const _SelectableBorder({required this.selected, required this.child});

  final bool selected;
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent, width: 2),
        ),
        child: Padding(padding: const EdgeInsets.all(4), child: child),
      );
}

/// 「正在缓存」页签：未完成任务的卡片网格。
///
/// 版式与「已缓存视频」共用同一套网格参数，两页签切换时列数与卡片宽度不会跳变；
/// 单张卡内部是离线缓存那套（封面浮层 + 标题 + 状态行 + 进度条）。
class _ActiveTab extends StatelessWidget {
  const _ActiveTab({required this.tasks, required this.selected, required this.selecting, required this.onToggleSelect});

  final List<DownloadTask> tasks;
  final Set<String> selected;

  /// 多选态：卡片上的浮层按钮换成勾选圈，点整张卡是切换选中。
  final bool selecting;
  final ValueChanged<String> onToggleSelect;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.download_done_rounded, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: .6)),
            const SizedBox(height: 12),
            Text(l10n.cacheEmptyActive, style: Theme.of(context).textTheme.bodyMedium),
          ],
        ),
      );
    }
    // 进行中的排前面（真正在跑的比排队的更值得盯），其次按加入时间倒序。
    final sorted = [...tasks]..sort((a, b) {
        int rank(DownloadTask task) => switch (task.status) {
              DownloadStatus.downloading => 0,
              DownloadStatus.queued => 1,
              DownloadStatus.paused => 2,
              DownloadStatus.failed => 3,
              DownloadStatus.completed => 4,
            };
        final byRank = rank(a).compareTo(rank(b));
        return byRank != 0 ? byRank : b.createdAt.compareTo(a.createdAt);
      });
    return LayoutBuilder(
      builder: (context, constraints) {
        // 与「已缓存视频」页签同一套列数/宽度算法，切页签时网格不会跳。
        final columns = ((constraints.maxWidth - 24) / (_minCardWidth + 12)).floor().clamp(2, 8);
        final width = ((constraints.maxWidth - 24 - 12 * (columns - 1)) / columns).clamp(_minCardWidth, _maxCardWidth);
        return GridView.builder(
          padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: 16,
            crossAxisSpacing: 12,
            // 封面是 AspectRatio 锁死的 16:9，这里只需要给足文字部分的高度：
            // 8 间距 + 标题 + 4 + 状态行 + 6 + 3 进度条 ≈ 57（100% 字号），
            // 留到 76 是为了字号调到上限 1.4 倍时也不溢出 —— 宁可底部多留白。
            mainAxisExtent: width * 9 / 16 + 76,
          ),
          itemCount: sorted.length,
          itemBuilder: (context, index) {
            final task = sorted[index];
            return _SelectableBorder(
              selected: selected.contains(task.id),
              child: CacheTaskCard(
                task: task,
                selected: selected.contains(task.id),
                selecting: selecting,
                onSelect: () => onToggleSelect(task.id),
              ),
            );
          },
        );
      },
    );
  }
}

/// 缓存页顶部工具栏：左侧容量概览，右侧排序与分组管理。
class _CacheToolbar extends StatelessWidget {
  const _CacheToolbar({required this.summary, required this.sort, required this.onSortChanged, required this.onManageGroups, required this.actions});

  final String summary;
  final DownloadGroupSort sort;
  final ValueChanged<DownloadGroupSort> onSortChanged;
  final VoidCallback onManageGroups;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          Icon(Symbols.folder_rounded, size: 16, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: 6),
          Expanded(child: Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant))),
          ...actions,
          _ToolbarMenu(
            tooltip: l10n.taskSort,
            icon: Symbols.sort_rounded,
            entries: [
              for (final value in DownloadGroupSort.values)
                (label: _sortLabel(l10n, value), selected: value == sort, onTap: () => onSortChanged(value)),
            ],
          ),
          PressScale(child: IconButton(tooltip: l10n.groupSettings, visualDensity: VisualDensity.compact, onPressed: onManageGroups, icon: const Icon(Symbols.tune_rounded, size: 20))),
        ],
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, DownloadGroupSort value) => switch (value) {
        DownloadGroupSort.defaultOrder => l10n.sortByDefault,
        DownloadGroupSort.recentlyUpdated => l10n.sortByRecent,
        DownloadGroupSort.name => l10n.sortByName,
      };
}

/// 工具栏上的下拉菜单（离线缓存那种「任务排序 ⌄」按钮）。
class _ToolbarMenu extends StatelessWidget {
  const _ToolbarMenu({required this.tooltip, required this.icon, required this.entries});

  final String tooltip;
  final IconData icon;
  final List<({String label, bool selected, VoidCallback onTap})> entries;

  @override
  Widget build(BuildContext context) => PopupMenuButton<void>(
        tooltip: tooltip,
        icon: Icon(icon, size: 20),
        itemBuilder: (context) => [
          for (final entry in entries)
            PopupMenuItem<void>(
              height: 40,
              onTap: entry.onTap,
              child: Row(
                children: [
                  SizedBox(width: 20, child: entry.selected ? Icon(Symbols.check_rounded, size: 16, color: Theme.of(context).colorScheme.primary) : null),
                  const SizedBox(width: 8),
                  Text(entry.label),
                ],
              ),
            ),
        ],
      );
}

class _EmptyCache extends StatelessWidget {
  const _EmptyCache();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.video_library_rounded, size: 56, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: .6)),
          const SizedBox(height: 14),
          Text(l10n.noCache, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(l10n.emptyCacheHint, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 打开本地缓存的视频（定义在 [cache_format.dart]，分组页也要用）。
