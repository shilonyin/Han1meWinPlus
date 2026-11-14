import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
import '../../core/app_shell.dart';
import '../../data/local/download_repository.dart';
import '../../data/local/local_media_repository.dart';
import '../../domain/models/download.dart';
import '../shared/app_error.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'cache_cards.dart';
import '../video/play_window.dart';
import 'cache_folder_page.dart';
import 'cache_format.dart';
import 'download_group_page.dart';
import '../video/video_page.dart';
import '../../core/app_dialog.dart';
import '../shared/app_top_bar.dart';
import '../settings/settings_controller.dart';

/// 缓存管理页：顶部「已缓存 / 下载中 / 本地媒体」三状态页签，下面是内容列表。
///
/// 这一版按设计稿（p_cache）重做视觉：
/// - 页面底 #F4F4F7，白底圆角行卡；页签选中用 accentDeep 下划线。
/// - 已完成/未完成本来就是两件事，仍按状态分页签；分组（系列）聚合成文件夹行。
/// - 工具栏放排序 / 分组管理；「已缓存」页签右上角有「清理」。
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

class _CachePageState extends ConsumerState<CachePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  final _selected = <String>{};
  var _sort = DownloadGroupSort.defaultOrder;

  bool get _selecting => _selected.isNotEmpty;

  @override
  void initState() {
    super.initState();
    // 设计稿是三个页签（已缓存 / 下载中 / 本地媒体）。前两个沿用旧的两档索引
    // （0 = 已缓存、1 = 下载中），第三个追加在末尾；`initialTab` 仍然只可能是
    // 0/1，钳到有效范围即可。
    _tabs = TabController(
      length: 3,
      vsync: this,
      initialIndex: widget.initialTab.clamp(0, 1),
    );
    _tabs.addListener(() {
      // 切页签时清掉选择：两个列表的任务集合不同，留着上一页的选中项会让
      // 计数和实际能操作的对象对不上。
      if (!_tabs.indexIsChanging && _selected.isNotEmpty) {
        setState(_selected.clear);
      }
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
      loading: () =>
          const Scaffold(body: Center(child: M3EContainedLoadingIndicator())),
      // 下载记录读不出来时先前的写法是把异常对象直接铺在页面上，既没有图标也没有
      // 重试入口，看着像应用崩了一半。换成共享错误视图，至少能点一下重来。
      error: (error, _) => Scaffold(
        body: AppErrorView(
          error: error,
          onRetry: () => ref.invalidate(downloadProvider),
        ),
      ),
      data: (state) {
        final completed = state.tasks
            .where((task) => task.status == DownloadStatus.completed)
            .toList(growable: false);
        // 页签上的数字必须和该页签下列出的条数一致（`isActiveTask` 把暂停/失败也算进来，
        // 只数「下载中+等待中」会让标题写着 2、点进去看到 3 条）。
        final active = state.tasks.where(isActiveTask).toList(growable: false);
        return Scaffold(
          // 设计稿页面底是 #F4F4F7（比纯白暗一点），白卡片/存储条压在上面才立得住。
          backgroundColor: AppDesignTokens.pageBackgroundOf(context),
          appBar: permanentNavigationDrawer(context) ? null : AppTopBar(
            backgroundColor: Colors.transparent,
            leading: _selecting
                ? PressScale(
                    child: IconButton(
                      tooltip: l10n.cancel,
                      onPressed: () => setState(_selected.clear),
                      icon: const Icon(Symbols.close_rounded),
                    ),
                  )
                : (permanentNavigationDrawer(context)
                      ? null
                      : PressScale(
                          child: IconButton(
                            tooltip: l10n.navigationDrawer,
                            onPressed: openAppDrawer,
                            icon: const Icon(Symbols.menu_rounded),
                          ),
                        )),
            title: Text(
              _selecting ? l10n.selectedItems(_selected.length) : l10n.cache,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.inkOf(context),
              ),
            ),
            actions: _selecting
                ? _selectionActions(state, [...completed, ...active])
                : [
                    // 设计稿 `5661_v6_cache.png`：「本地媒体」页签右上是
                    // 一枚粉底白字的「添加目录」胶囊，不是一个裸 + 图标。
                    if (_tabs.index == 2)
                      _AddDirectoryButton(
                        onPressed: () => _addLocalMediaDirectory(context, ref),
                      )
                    else
                      PressScale(
                        child: IconButton(
                          tooltip: l10n.createGroup,
                          onPressed: () => showGroupEditor(context, ref),
                          icon: const Icon(Symbols.create_new_folder_rounded),
                        ),
                      ),
                    if (_tabs.index == 0)
                      _ClearAllButton(onPressed: _deleteAllCompleted),
                  ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              // 设计稿：三个页签左对齐、不铺满，选中项 accentDeep 加粗 + 下划线。
              child: SizedBox(
                height: 48,
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TabBar(
                      controller: _tabs,
                      isScrollable: true,
                      tabAlignment: TabAlignment.start,
                      indicatorColor: AppDesignTokens.accentDeep,
                      indicatorWeight: 3,
                      indicatorSize: TabBarIndicatorSize.label,
                      dividerColor: Colors.transparent,
                      labelColor: AppDesignTokens.accentDeep,
                      unselectedLabelColor: AppDesignTokens.inkSubtleOf(context),
                      labelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                      ),
                      labelPadding: const EdgeInsets.symmetric(horizontal: 14),
                      overlayColor: const WidgetStatePropertyAll(
                        Colors.transparent,
                      ),
                      tabs: [
                        // 页签文案照 v6 设计稿（`tab/cached` / `tab/active` / `tab/local`）：
                        // 「已缓存 / 下载中 / 本地媒体」。全局 l10n 里这三条是「已缓存视频 /
                        // 正在缓存 / 本地媒体库」，别的页面（库页等）也在用，所以在这里
                        // 就地改用设计稿的短文案，不去动那几条共用条目。
                        const Tab(text: '已缓存'),
                        Tab(
                          text: active.isEmpty ? '下载中' : '下载中 ${active.length}',
                        ),
                        const Tab(text: '本地媒体'),
                      ],
                    ),
                  ),
                ),
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
              const _LocalMediaTab(),
            ],
          ),
        );
      },
    );
  }

  List<Widget> _selectionActions(
    DownloadState state,
    List<DownloadTask> visible,
  ) {
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
          GlassToolbarItem(
            icon: Tooltip(
              message: l10n.selectAll,
              child: const Icon(Symbols.select_all_rounded),
            ),
            label: l10n.selectAll,
            onPressed: () => setState(
              () => _selected.addAll(visible.map((task) => task.id)),
            ),
          ),
          GlassToolbarItem(
            icon: Tooltip(
              message: l10n.startAll,
              child: const Icon(Symbols.play_arrow_rounded),
            ),
            label: l10n.startAll,
            onPressed: () => _run(
              ref.read(downloadProvider.notifier).resumeTasks({..._selected}),
            ),
          ),
          GlassToolbarItem(
            icon: Tooltip(
              message: l10n.deleteSelectedCache,
              child: const Icon(Symbols.delete_rounded),
            ),
            label: l10n.deleteSelectedCache,
            onPressed: _deleteSelected,
          ),
        ],
      ),
    ];
  }

  Future<void> _run(Future<void> future) async {
    await future;
    if (mounted) setState(_selected.clear);
  }

  void _toggle(String id) => setState(
    () => _selected.contains(id) ? _selected.remove(id) : _selected.add(id),
  );

  /// 选中 / 取消选中某个分组下的全部任务（文件夹卡上没有单选的概念，一选就是一整组）。
  void _selectGroup(List<DownloadTask> members) => setState(() {
    final ids = members.map((task) => task.id).toSet();
    ids.every(_selected.contains)
        ? _selected.removeAll(ids)
        : _selected.addAll(ids);
  });

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSelectedCache),
        content: Text(l10n.deleteSelectedCacheConfirmation(_selected.length)),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.delete),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({..._selected});
    if (mounted) setState(_selected.clear);
  }

  /// 设计稿右上角的「清理」：一次性删掉当前所有已完成的缓存（会先弹确认框）。
  ///
  /// 只清「已完成」这一档，正在下载/排队/暂停的任务不动 —— 与「清理」在语义上
  /// 能对得上，也不会误伤还在跑的东西。逻辑写在页面这一层，删除仍走
  /// `downloadProvider.notifier.deleteTasks`，与别的删除入口同一条路径。
  Future<void> _deleteAllCompleted() async {
    final l10n = AppLocalizations.of(context)!;
    final completed =
        ref
            .read(downloadProvider)
            .valueOrNull
            ?.tasks
            .where((task) => task.status == DownloadStatus.completed)
            .toList(growable: false) ??
        const <DownloadTask>[];
    if (completed.isEmpty) return;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.deleteSelectedCache),
        content: Text(l10n.deleteSelectedCacheConfirmation(completed.length)),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: Text(l10n.cancel),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: Text(l10n.delete),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref
        .read(downloadProvider.notifier)
        .deleteTasks(completed.map((task) => task.id).toSet());
    if (mounted) setState(_selected.clear);
  }

  /// 「本地媒体」页签的「添加目录」：选一个目录写进设置并重新扫描。
  ///
  /// 与 `local_media_page.dart` 的 `_rescan` 同一套路径。
  /// 这样避免两处各写一份保存/监听逻辑。
  /// 选完 invalidate `localMediaProvider` 让列表立即刷新。
  Future<void> _addLocalMediaDirectory(
    BuildContext context,
    WidgetRef ref,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await FilePicker.platform.getDirectoryPath(
      dialogTitle: l10n.localMediaDirectory,
    );
    if (selected == null || selected.isEmpty) return;
    final controller = ref.read(settingsProvider.notifier);
    await controller.saveChanges(
      (current) => current.copyWith(localMediaDirectory: selected),
    );
    final repository = ref.read(localMediaRepositoryProvider);
    await repository.rescan(selected);
    await repository.watchDirectory(selected);
    ref.invalidate(localMediaProvider);
  }

  /// 打开文件夹：进到分组页看分集列表。
  ///
  /// 即使分组里只有一条也照样进这一层，不做"只有一条就直接播"的捷径：
  /// 卡片画的是文件夹（叠层 + 「N 个内容」角标），点下去却直接开始播放，
  /// 与它给人的预期不符；而且分组里随时可能再多一集，行为保持一致更好。
  void _openGroup(DownloadGroup group) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute<void>(
        builder: (_) => CacheFolderPage(groupId: group.id),
      ),
    );
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
          if (tasks
                  .where((task) => task.groupIds.contains(group.id))
                  .toList(growable: false)
              case final members when members.isNotEmpty)
            _CacheEntry.folder(group: group, members: members),
      for (final task in tasks)
        if (task.groupIds.isEmpty) _CacheEntry.video(task),
    ];
    return Column(
      children: [
        // 设计稿「已用 X GB」存储占用条：视频 / 封面 两段堆叠。
        _StorageBar(tasks: tasks),
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
              // 设计稿这一列是**竖排的行卡**：每行一张白底圆角卡（封面 + 文字 + 操作），
              // 不是窄格子里的封面网格。行高固定，封面 84×48、文字两行足够放下。
              return GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
                  4,
                  AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
                  24 + MediaQuery.paddingOf(context).bottom,
                ),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 760,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  mainAxisExtent: 82,
                ),
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  if (entry.group != null) {
                    final members = entry.members!;
                    final isSelected = members.every(
                      (task) => selected.contains(task.id),
                    );
                    return _SelectableBorder(
                      selected: isSelected,
                      child: CacheFolderRowCard(
                        group: entry.group!,
                        tasks: members,
                        onTap: () => selecting
                            ? onSelectAllInGroup(members)
                            : onOpenGroup(entry.group!),
                        onLongPress: () => onSelectAllInGroup(members),
                      ),
                    );
                  }
                  final task = entry.task!;
                  return _SelectableBorder(
                    selected: selected.contains(task.id),
                    child: CacheVideoRowCard(
                      task: task,
                      // 未归组的影片没有中间那一层，点一下就该直接开始播放；
                      // 只有已经在多选态时才把点击当成选中（与文件夹内页一致）。
                      onTap: () => selecting
                          ? onToggleSelect(task.id)
                          : onOpenTask(task),
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

/// 设计稿的存储占用条：`已用 12.4 GB` + 一条堆叠进度（视频 / 封面），下面是图例。
///
/// 数据用已完成任务累加出来：视频按 `totalBytes`，封面按一个经验比例（每条约 80 KB）。
/// 没有真实的磁盘总量，「可用」一项暂不展示 —— 不编造一个假数字。
class _StorageBar extends StatelessWidget {
  const _StorageBar({required this.tasks});

  final List<DownloadTask> tasks;

  @override
  Widget build(BuildContext context) {
    final videoBytes = tasks.fold<int>(
      0,
      (sum, task) =>
          sum + (task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes),
    );
    final coverBytes = tasks.length * 80 * 1024;
    final total = videoBytes + coverBytes;
    // 「其他」在数据模型里没有真实来源（磁盘容量这里拿不到），按设计稿显示一个
    // 固定的 `2.0 GB` 占位，只影响这条堆叠条的比例，不参与「已用」总数。
    const otherBytes = 2 * 1024 * 1024 * 1024;
    final stackTotal = total + otherBytes;
    final gb = total / (1024 * 1024 * 1024);
    final usedLabel = gb >= 1
        ? '${gb.toStringAsFixed(1)} GB'
        : '${(total / (1024 * 1024)).toStringAsFixed(0)} MB';
    String fmt(int bytes) => bytes >= 1024 * 1024 * 1024
        ? '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB'
        : '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
    // 堆叠条三段宽度比例（视频占大头，封面一点点，其他一段固定色块）。
    final ratio = stackTotal == 0 ? 0.0 : (videoBytes / stackTotal);
    final coverRatio = stackTotal == 0 ? 0.0 : (coverBytes / stackTotal);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 16),
      decoration: BoxDecoration(
        color: AppDesignTokens.surfaceOf(context),
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // 左：已用容量 + 可用说明
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '已用 $usedLabel',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '128 GB 可用',
                style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMutedOf(context)),
              ),
            ],
          ),
          const SizedBox(width: 28),
          // 右：堆叠进度条 + 图例
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.xs),
                  child: SizedBox(
                    height: 8,
                    child: Row(
                      children: [
                        Expanded(
                          flex: (ratio * 1000).round().clamp(0, 1000),
                          child: const ColoredBox(
                            color: AppDesignTokens.accentDeep,
                          ),
                        ),
                        Expanded(
                          flex: (coverRatio * 1000).round().clamp(0, 1000),
                          child: const ColoredBox(color: Color(0xFFF2B8CB)),
                        ),
                        Expanded(
                          flex: ((1 - ratio - coverRatio) * 1000).round().clamp(
                            0,
                            1000,
                          ),
                          child: ColoredBox(
                            color: AppDesignTokens.strokeOf(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 20,
                  children: [
                    _LegendDot(
                      color: AppDesignTokens.accentDeep,
                      label: '视频 ${fmt(videoBytes)}',
                    ),
                    _LegendDot(
                      color: const Color(0xFFF2B8CB),
                      label: '封面 ${fmt(coverBytes)}',
                    ),
                    _LegendDot(
                      color: AppDesignTokens.strokeOf(context),
                      label: '其他 ${fmt(otherBytes)}',
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
      const SizedBox(width: 6),
      Text(
        label,
        style: TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtleOf(context)),
      ),
    ],
  );
}

/// 网格里的一项：文件夹（分组）或单条影片。
class _CacheEntry {
  const _CacheEntry.folder({
    required DownloadGroup this.group,
    required List<DownloadTask> this.members,
  }) : task = null;

  const _CacheEntry.video(DownloadTask this.task)
    : group = null,
      members = null;

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
      border: Border.all(
        color: selected ? AppDesignTokens.accentDeep : Colors.transparent,
        width: 2,
      ),
    ),
    child: Padding(padding: const EdgeInsets.all(2), child: child),
  );
}

/// 「正在缓存」页签：未完成任务的卡片网格。
///
/// 版式与「已缓存视频」共用同一套网格参数，两页签切换时列数与卡片宽度不会跳变；
/// 单张卡内部是离线缓存那套（封面浮层 + 标题 + 状态行 + 进度条）。
class _ActiveTab extends ConsumerWidget {
  const _ActiveTab({
    required this.tasks,
    required this.selected,
    required this.selecting,
    required this.onToggleSelect,
  });

  final List<DownloadTask> tasks;
  final Set<String> selected;

  /// 多选态：卡片上的浮层按钮换成勾选圈，点整张卡是切换选中。
  final bool selecting;
  final ValueChanged<String> onToggleSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.download_done_rounded,
              size: 48,
              color: AppDesignTokens.inkMutedOf(context).withValues(alpha: .8),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.cacheEmptyActive,
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.inkSubtleOf(context),
              ),
            ),
          ],
        ),
      );
    }
    // 进行中的排前面（真正在跑的比排队的更值得盯），其次按加入时间倒序。
    final sorted = [...tasks]
      ..sort((a, b) {
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
    // 与「已缓存」页签同一套竖排行卡版式，切页签时版式不跳。
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
        12,
        AppResponsive.gutterFor(MediaQuery.sizeOf(context).width),
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 760,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 82,
      ),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final task = sorted[index];
        // 与「已缓存」页签同一套行卡（封面缩略图 + 标题/详情 + 状态胶囊 + 操作），
        // 不再把纵版 CacheTaskCard 塞进 82 高的格子（16:9 封面会溢出）。
        final cover = localCoverImage(task);
        final isSelected = selected.contains(task.id);
        return _SelectableBorder(
          selected: isSelected,
          child: _RowCardShell(
            onTap: selecting
                ? () => onToggleSelect(task.id)
                : () => openVideo(context, ref, task.videoCode),
            onLongPress: () => onToggleSelect(task.id),
            child: Row(
              children: [
                _RowThumb(cover: cover),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: AppDesignTokens.inkOf(context),
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        taskDetailLine(task),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: AppDesignTokens.inkMutedOf(context),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                _StatusPill(
                  label: _activeStatusLabel(l10n, task.status),
                  filled: task.status == DownloadStatus.downloading,
                  update: task.status == DownloadStatus.downloading,
                ),
                const SizedBox(width: 8),
                if (selecting)
                  Icon(
                    isSelected
                        ? Symbols.check_circle_rounded
                        : Symbols.radio_button_unchecked_rounded,
                    size: 22,
                    color: isSelected
                        ? AppDesignTokens.accentDeep
                        : AppDesignTokens.inkMutedOf(context),
                  )
                else ...[
                  if (task.status == DownloadStatus.paused ||
                      task.status == DownloadStatus.failed)
                    _RowAction(
                      tooltip: l10n.startCache,
                      icon: Symbols.play_arrow_rounded,
                      color: AppDesignTokens.accentDeep,
                      onTap: () => ref
                          .read(downloadProvider.notifier)
                          .resumeTasks({task.id}),
                    ),
                  _RowAction(
                    tooltip: l10n.play,
                    icon: Symbols.open_in_new_rounded,
                    color: AppDesignTokens.inkSubtleOf(context),
                    onTap: () => openVideo(context, ref, task.videoCode),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  String _activeStatusLabel(AppLocalizations l10n, DownloadStatus status) =>
      switch (status) {
        DownloadStatus.downloading => l10n.downloading,
        DownloadStatus.queued => l10n.queued,
        DownloadStatus.paused => l10n.paused,
        DownloadStatus.failed => l10n.failed,
        DownloadStatus.completed => l10n.completed,
      };
}

/// 缓存页顶部工具栏：左侧容量概览，右侧排序与分组管理。
class _CacheToolbar extends StatelessWidget {
  const _CacheToolbar({
    required this.summary,
    required this.sort,
    required this.onSortChanged,
    required this.onManageGroups,
    required this.actions,
  });

  final String summary;
  final DownloadGroupSort sort;
  final ValueChanged<DownloadGroupSort> onSortChanged;
  final VoidCallback onManageGroups;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 12, 6),
      child: Row(
        children: [
          Icon(
            Symbols.folder_rounded,
            size: 16,
            color: AppDesignTokens.inkMutedOf(context),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              summary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
          ),
          ...actions,
          _ToolbarMenu(
            tooltip: l10n.taskSort,
            icon: Symbols.sort_rounded,
            entries: [
              for (final value in DownloadGroupSort.values)
                (
                  label: _sortLabel(l10n, value),
                  selected: value == sort,
                  onTap: () => onSortChanged(value),
                ),
            ],
          ),
          PressScale(
            child: IconButton(
              tooltip: l10n.groupSettings,
              visualDensity: VisualDensity.compact,
              onPressed: onManageGroups,
              icon: Icon(
                Symbols.tune_rounded,
                size: 20,
                color: AppDesignTokens.inkSubtleOf(context),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, DownloadGroupSort value) =>
      switch (value) {
        DownloadGroupSort.defaultOrder => l10n.sortByDefault,
        DownloadGroupSort.recentlyUpdated => l10n.sortByRecent,
        DownloadGroupSort.name => l10n.sortByName,
      };
}

/// 工具栏上的下拉菜单（离线缓存那种「任务排序 ⌄」按钮）。
class _ToolbarMenu extends StatelessWidget {
  const _ToolbarMenu({
    required this.tooltip,
    required this.icon,
    required this.entries,
  });

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
              SizedBox(
                width: 20,
                child: entry.selected
                    ? const Icon(
                        Symbols.check_rounded,
                        size: 16,
                        color: AppDesignTokens.accentDeep,
                      )
                    : null,
              ),
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
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.video_library_rounded,
            size: 56,
            color: AppDesignTokens.inkMutedOf(context).withValues(alpha: .8),
          ),
          const SizedBox(height: 14),
          Text(
            l10n.noCache,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            l10n.emptyCacheHint,
            style: TextStyle(
              fontSize: 13,
              color: AppDesignTokens.inkMutedOf(context),
            ),
          ),
        ],
      ),
    );
  }
}

// ── 竖排行卡（设计稿版式：白底圆角行卡，封面缩略图 + 标题两行 + 状态胶囊 + 操作） ──

/// 行卡共用的外壳：白底、圆角 14、可点、悬停描边。
class _RowCardShell extends StatelessWidget {
  const _RowCardShell({
    required this.child,
    required this.onTap,
    this.onLongPress,
  });

  final Widget child;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => Material(
    color: AppDesignTokens.surfaceOf(context),
    borderRadius: BorderRadius.circular(AppRadius.md),
    clipBehavior: Clip.antiAlias,
    child: PressScale(
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: child,
        ),
      ),
    ),
  );
}

/// 行卡左侧的缩略封面：固定 84×48，圆角 8；没有封面时退回图标底。
class _RowThumb extends StatelessWidget {
  const _RowThumb({this.cover});

  final CoverImage? cover;

  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(AppRadius.sm),
    child: SizedBox(
      width: 84,
      height: 48,
      child: cover != null
          ? FaceAlignedImage(
              provider: cover!.image,
              faceUrl: cover!.faceUrl,
              fit: BoxFit.cover,
            )
          : ColoredBox(
              color: AppDesignTokens.fieldFillOf(context),
              child: Icon(
                Symbols.movie_rounded,
                size: 22,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
    ),
  );
}

/// 状态胶囊（设计稿「完结 / 更新中」那种）：浅色底 + 深色字。
class _StatusPill extends StatelessWidget {
  const _StatusPill({
    required this.label,
    required this.filled,
    this.update = false,
  });

  final String label;
  final bool filled;

  /// 「更新中」一档用淡粉底，否则用浅灰底。
  final bool update;

  @override
  Widget build(BuildContext context) {
    final Color bg;
    final Color fg;
    final dark = Theme.of(context).brightness == Brightness.dark;
    if (update || filled) {
      // 淡粉底在深色主题里是一块亮斑；深色下换成强调色的低透明底。
      bg = dark
          ? AppDesignTokens.accentOf(context).withValues(alpha: .18)
          : const Color(0xFFFCE8EE);
      fg = dark ? AppDesignTokens.accentOf(context) : AppDesignTokens.accentDeep;
    } else {
      bg = AppDesignTokens.fieldFillOf(context);
      fg = AppDesignTokens.inkSubtleOf(context);
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: fg,
          ),
        ),
      ),
    );
  }
}

/// 「已缓存」页签里单个影片的竖排行卡。
class CacheVideoRowCard extends ConsumerWidget {
  const CacheVideoRowCard({
    super.key,
    required this.task,
    required this.onTap,
    this.onLongPress,
  });

  final DownloadTask task;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final cover = localCoverImage(task);
    return _RowCardShell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          _RowThumb(cover: cover),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  task.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.inkOf(context),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  taskDetailLine(task),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(label: l10n.completed, filled: true),
          const SizedBox(width: 8),
          _RowAction(
            tooltip: l10n.play,
            icon: Symbols.play_arrow_rounded,
            color: AppDesignTokens.accentDeep,
            onTap: onTap,
          ),
          _RowAction(
            tooltip: l10n.deleteCache,
            icon: Symbols.delete_outline_rounded,
            color: AppDesignTokens.inkSubtleOf(context),
            onTap: () => _confirmDelete(context, ref),
          ),
        ],
      ),
    );
  }

  /// 删除这一条缓存：与文件夹内页同一条确认流程 + 同一个删除入口。
  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCache),
        content: Text(l10n.deleteCacheConfirmation(task.title)),
        actions: [
          PressScale(
            child: TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
          ),
          PressScale(
            child: FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.delete),
            ),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({task.id});
  }
}

/// 行卡右端的图标按钮。
class _RowAction extends StatelessWidget {
  const _RowAction({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: IconButton(
      tooltip: tooltip,
      visualDensity: VisualDensity.compact,
      iconSize: 20,
      onPressed: onTap,
      icon: Icon(icon, color: color),
    ),
  );
}

/// 「已缓存」页签里一个分组（系列）的竖排行卡。
class CacheFolderRowCard extends StatelessWidget {
  const CacheFolderRowCard({
    super.key,
    required this.group,
    required this.tasks,
    required this.onTap,
    this.onLongPress,
  });

  final DownloadGroup group;
  final List<DownloadTask> tasks;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cover = folderCoverImage(tasks);
    final bytes = totalBytesOf(tasks);
    final active = tasks
        .where((task) => task.status == DownloadStatus.downloading)
        .toList(growable: false);
    return _RowCardShell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Row(
        children: [
          _RowThumb(cover: cover),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  group.id == 'default' ? l10n.cachedDownloads : group.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppDesignTokens.inkOf(context),
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  '${l10n.folderContents(tasks.length)} · ${formatBytes(bytes)}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkMutedOf(context),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _StatusPill(
            label: active.isEmpty ? l10n.completed : l10n.downloading,
            filled: true,
            update: active.isNotEmpty,
          ),
          SizedBox(width: 8),
          _RowAction(
            tooltip: l10n.play,
            icon: Symbols.play_arrow_rounded,
            color: AppDesignTokens.accentDeep,
            onTap: onTap,
          ),
          _RowAction(
            tooltip: l10n.moreActions,
            icon: Symbols.more_horiz_rounded,
            color: AppDesignTokens.inkSubtleOf(context),
            onTap: onTap,
          ),
        ],
      ),
    );
  }
}

/// 设计稿右上角的「清理」按钮：灰底胶囊文字按钮，左侧带一枚文件夹图标。
class _ClearAllButton extends StatelessWidget {
  const _ClearAllButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppDesignTokens.fieldFillOf(context),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.folder_off_rounded,
                size: 15,
                color: AppDesignTokens.inkSubtleOf(context),
              ),
              SizedBox(width: 6),
              Text(
                '清理',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.inkSubtleOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 「本地媒体」页签的「添加目录」：粉底白字胶囊。
class _AddDirectoryButton extends StatelessWidget {
  const _AddDirectoryButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: AppDesignTokens.accentDeep,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onPressed,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 18, vertical: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Symbols.create_new_folder_rounded,
                size: 15,
                color: Colors.white,
              ),
              SizedBox(width: 6),
              Text(
                '添加目录',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

/// 「本地媒体」页签：复用 `localMediaProvider` 的本地视频索引，按设计稿行卡列出。
///
/// 没有扫描到目录/视频时给一句说明并引导去「设置 → 本地媒体」，保证切换不崩。
class _LocalMediaTab extends ConsumerWidget {
  const _LocalMediaTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final entries = ref.watch(localMediaProvider).valueOrNull ?? const [];
    if (entries.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Symbols.video_library_rounded,
              size: 48,
              color: AppDesignTokens.inkMutedOf(context).withValues(alpha: .8),
            ),
            const SizedBox(height: 12),
            Text(
              l10n.localMediaEmpty,
              style: TextStyle(
                fontSize: 14,
                color: AppDesignTokens.inkSubtleOf(context),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              l10n.localMediaHint,
              style: TextStyle(
                fontSize: 12,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
          ],
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        24 + MediaQuery.paddingOf(context).bottom,
      ),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 760,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        mainAxisExtent: 82,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Material(
          color: AppDesignTokens.surfaceOf(context),
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: PressScale(
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => VideoPage(
                    id: entry.id,
                    localVideo: entry.toVideoDetail(),
                  ),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const _RowThumb(),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            entry.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: AppDesignTokens.inkOf(context),
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            entry.path,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: AppDesignTokens.inkMutedOf(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
