import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_dialog.dart';
import '../../core/app_radius.dart';
import '../../data/local/download_repository.dart';
import '../../domain/models/download.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import '../video/play_window.dart';
import 'cache_format.dart';

/// 缓存卡片右下角的角标（时长 / 体积这类叠在封面上的信息）。
class CacheCoverBadge extends StatelessWidget {
  const CacheCoverBadge({super.key, this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(AppRadius.xs)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 12, color: Colors.white), const SizedBox(width: 3)],
              Text(text, style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600, height: 1.2)),
            ],
          ),
        ),
      );
}

/// 单条已完成缓存的卡片：与文件夹卡同一套版式，只是没有叠层、角标显示时长。
///
/// 没有归入任何分组的影片用这张卡直接铺在网格里（对应 b 站里那些不属于任何
/// 合集的单个视频），点一下就能播；归入分组的则聚成 [CacheFolderCard]。
class CacheVideoCard extends StatelessWidget {
  const CacheVideoCard({super.key, required this.task, required this.onTap, this.onLongPress});

  final DownloadTask task;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = localCoverImage(task);
    final bytes = task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes;
    final duration = task.duration;
    return PressScale(child: InkWell(
      // 之前这里是 `GestureDetector(onLongPress: ...)` 且**没有** onTap ——
      // 传入的播放回调被完全忽略，卡片点上去毫无反应（长按却能进多选）。
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image(image: cover, fit: BoxFit.cover)
                  else
                    ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.movie_rounded, size: 32, color: theme.colorScheme.onSurfaceVariant)),
                  if (bytes > 0) Positioned(left: 6, bottom: 6, child: CacheCoverBadge(icon: Symbols.save_alt_rounded, text: formatBytes(bytes))),
                  if (duration != null && duration.isNotEmpty) Positioned(right: 6, bottom: 6, child: CacheCoverBadge(text: duration)),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 2),
          Text(
            task.quality.isEmpty ? formatBytes(bytes) : '${task.quality} · ${formatBytes(bytes)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    ));
  }
}

/// 取一条任务可用的本地封面（没有本地图就退回网络封面）。
ImageProvider? localCoverImage(DownloadTask task) {
  final local = task.localCoverPath;
  if (local != null && File(local).existsSync()) return FileImage(File(local));
  final remote = task.coverUrl;
  if (remote == null || remote.isEmpty) return null;
  return CachedNetworkImageProvider(remote, cacheManager: appImageCacheManager);
}

/// 一组任务可用的封面：优先本地已下好的图，否则退回第一条的网络封面。
///
/// 文件夹卡与集合内页的头部封面都要这个判断，抽出来共用。
ImageProvider? folderCoverImage(List<DownloadTask> tasks) {
  final local = tasks.map((task) => task.localCoverPath).whereType<String>().where((path) => File(path).existsSync()).firstOrNull;
  if (local != null) return FileImage(File(local));
  final remote = tasks.map((task) => task.coverUrl).whereType<String>().where((url) => url.isNotEmpty).firstOrNull;
  return remote == null ? null : CachedNetworkImageProvider(remote, cacheManager: appImageCacheManager);
}

/// 集合内页的剧集卡片：16:9 封面（左下体积、右下时长）+ 标题一行 + ⋮ 菜单。
///
/// 与 [CacheVideoCard] 的区别在于它面向"一集一集看完"的场景：
/// 体积和时长都直接画在封面上（b 站同款），标题只占一行，
/// 右侧的 ⋮ 收着播放 / 暂停 / 删除这些单条操作。
class CacheEpisodeCard extends StatelessWidget {
  const CacheEpisodeCard({
    super.key,
    required this.task,
    required this.selected,
    required this.selecting,
    required this.onTap,
    required this.onLongPress,
    required this.onMenu,
  });

  final DownloadTask task;
  final bool selected;

  /// 多选模式下封面右上角显示勾选圈，点整张卡就是切换选中。
  final bool selecting;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onMenu;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cover = localCoverImage(task);
    final bytes = task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes;
    final duration = task.duration;
    return Material(
      color: selected ? theme.colorScheme.secondaryContainer.withValues(alpha: .5) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: PressScale(child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: cover != null
                        ? Image(image: cover, fit: BoxFit.cover)
                        : ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.movie_rounded, size: 28, color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  // 下载中/暂停的在封面底部画一条进度，未完成的也一眼能看出状态。
                  if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused)
                    Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: task.progress <= 0 ? null : task.progress, minHeight: 3)),
                  if (bytes > 0) Positioned(left: 6, bottom: 6, child: CacheCoverBadge(icon: Symbols.save_alt_rounded, text: formatBytes(bytes))),
                  if (duration != null && duration.isNotEmpty) Positioned(right: 6, bottom: 6, child: CacheCoverBadge(text: duration)),
                  // 未下完的状态角标（排队/暂停/失败）放左上角，别和体积撞在一起。
                  if (task.status != DownloadStatus.completed)
                    Positioned(left: 6, top: 6, child: CacheCoverBadge(text: taskStatusLabel(l10n, task.status))),
                  if (selecting) Positioned(right: 6, top: 6, child: Icon(selected ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded, fill: selected ? 1 : 0, size: 20, color: Colors.white)),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Row(
              children: [
                Expanded(
                  child: Text(
                    task.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                // ⋮ 菜单：把单条操作收起来，标题不至于被一排按钮挤短。
                SizedBox(
                  width: 28,
                  height: 24,
                  child: IconButton(
                    tooltip: l10n.more,
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                    iconSize: 18,
                    onPressed: onMenu,
                    icon: const Icon(Symbols.more_vert_rounded),
                  ),
                ),
              ],
            ),
          ],
        ),
      )),
    );
  }
}

/// 「剧集聚合」文件夹卡片：一个分组（通常是一个系列）聚成一张卡。
///
/// 这是参考 b 站离线缓存的「文件夹」形态：封面叠一摞纸的厚度感、右下角标总体积、
/// 标题下一行写「N 个内容」，点进去才是分集列表。分组内的进度也会汇总显示，
/// 这样在网格上一眼能看出这个系列下了多少。
class CacheFolderCard extends StatelessWidget {
  const CacheFolderCard({super.key, required this.group, required this.tasks, required this.onTap, this.onLongPress});

  final DownloadGroup group;
  final List<DownloadTask> tasks;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cover = folderCoverImage(tasks);
    final bytes = totalBytesOf(tasks);
    final active = tasks.where((task) => task.status == DownloadStatus.downloading).toList();
    final progress = active.isEmpty ? null : active.first.progress;
    return PressScale(child: InkWell(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Stack(
              children: [
                // 底下错开的两层"纸"：做出文件夹里叠着多份内容的感觉（b 站同款处理）。
                Positioned(left: 8, right: 8, top: 0, bottom: 8, child: _StackSheet(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .55))),
                Positioned(left: 4, right: 4, top: 4, bottom: 4, child: _StackSheet(color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .8))),
                Positioned(
                  left: 0,
                  right: 0,
                  top: 8,
                  bottom: 0,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          Image(image: cover, fit: BoxFit.cover)
                        else
                          ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.folder_rounded, size: 36, color: theme.colorScheme.onSurfaceVariant)),
                        if (progress != null)
                          Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress <= 0 ? null : progress, minHeight: 3)),
                        Positioned(
                          right: 6,
                          bottom: 8,
                          child: CacheCoverBadge(icon: Symbols.folder_rounded, text: l10n.folderContents(tasks.length)),
                        ),
                        if (bytes > 0)
                          Positioned(left: 6, bottom: 8, child: CacheCoverBadge(icon: Symbols.save_alt_rounded, text: formatBytes(bytes))),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            group.id == 'default' ? l10n.cachedDownloads : group.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            // 有任务在跑时显示进度，否则显示体积（与封面角标互补）。
            active.isEmpty ? formatBytes(bytes) : '${(progress! * 100).clamp(0, 100).toStringAsFixed(0)}%',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
          ),
        ],
      ),
    ));
  }
}

class _StackSheet extends StatelessWidget {
  const _StackSheet({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(AppRadius.sm)));
}

/// 缓存在下载中的任务是否是「暂停/失败」这类**需要用户再点一下才会动**的状态。
///
/// 只有这两种状态才在封面中央压一个主操作按钮（「开始缓存」/「重试」）：
/// 正在跑和排队中的任务封面保持干净，进度本身已经说明了它在动。
bool _needsPrimaryAction(DownloadStatus status) =>
    status == DownloadStatus.paused || status == DownloadStatus.failed;

/// 「正在缓存」页签里的单条任务卡片（b 站离线缓存那套版式）。
///
/// 与「已缓存视频」的网格卡不同，这一版把**操作直接压在封面上**：
/// 右上角「前往详情页」是去影片页的入口，封面中央是当前状态的主操作
/// （暂停中显示「开始缓存」、失败显示「重试」），标题右侧的 ⋮ 收着
/// 暂停 / 继续 / 重试 / 删除。卡片底部一条细进度条 + 一行状态文字。
///
/// 之所以从横排列表换成网格卡：横排只在"一屏盯一条"时好读，而缓存页经常同时
/// 挂着好几条任务，横排的封面小到看不清是哪个片子，网格卡能一眼认出封面。
class CacheTaskCard extends ConsumerWidget {
  const CacheTaskCard({
    super.key,
    required this.task,
    required this.selected,
    required this.selecting,
    required this.onSelect,
  });

  final DownloadTask task;
  final bool selected;

  /// 多选态：此时候封面上的浮层按钮换成勾选圈，点卡片是切换选中而不是进详情。
  final bool selecting;

  /// 切换这一条的选中状态（长按、或多选态下点整张卡）。
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cover = localCoverImage(task);
    final controller = ref.read(downloadProvider.notifier);
    // 主操作按状态分派：暂停/失败时封面中央那个按钮点下去就是"继续跑起来"。
    final primary = !_needsPrimaryAction(task.status)
        ? null
        : switch (task.status) {
            DownloadStatus.paused => (label: l10n.startCache, action: () => controller.resumeTasks({task.id})),
            DownloadStatus.failed => (label: l10n.retry, action: () => controller.retry(task.id)),
            _ => null,
          };
    return Material(
      color: selected ? theme.colorScheme.secondaryContainer.withValues(alpha: .5) : Colors.transparent,
      borderRadius: BorderRadius.circular(AppRadius.sm),
      clipBehavior: Clip.antiAlias,
      child: PressScale(child: InkWell(
        onTap: selecting ? onSelect : () => openVideo(context, ref, task.videoCode),
        onLongPress: onSelect,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 封面自己守住 16:9：格子高度是按宽度估的，字号或状态行一变就不准。
            // 让 AspectRatio 直接定高，文字紧跟在下面，比例永远是准的；
            // 格子给的那点富余高度留在卡片底部，不至于把画面拉扁。
            AspectRatio(
              aspectRatio: 16 / 9,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    if (cover != null)
                      Image(image: cover, fit: BoxFit.cover)
                    else
                      ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.movie_rounded, size: 32, color: theme.colorScheme.onSurfaceVariant)),
                    if (selecting)
                      Positioned(right: 8, top: 8, child: Icon(selected ? Symbols.check_circle_rounded : Symbols.radio_button_unchecked_rounded, fill: selected ? 1 : 0, size: 22, color: Colors.white))
                    else
                      // 有中央主操作时，右上角只留一个箭头图标：网格里一张卡可能只有
                      // 一百多逻辑像素宽，两个胶囊并排会直接叠在一起（实测过）。
                      Positioned(right: 8, top: 8, child: _CoverChip(icon: Symbols.chevron_right_rounded, label: primary == null ? l10n.goToDetail : null, tooltip: l10n.goToDetail, onTap: () => openVideo(context, ref, task.videoCode))),
                    if (!selecting && primary != null)
                      Center(child: _CoverChip(label: primary.label, onTap: primary.action, prominent: true)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(child: Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                // ⋮ 把单条操作收起来，标题不至于被一排按钮挤短（与文件夹内页一致）。
                SizedBox(
                  width: 28,
                  height: 24,
                  child: _TaskMenu(task: task),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _statusLine(l10n),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall?.copyWith(
                color: task.status == DownloadStatus.failed
                    ? theme.colorScheme.error
                    : task.status == DownloadStatus.queued
                        ? theme.colorScheme.outline
                        : theme.colorScheme.primary,
              ),
            ),
            if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused) ...[
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.xs),
                child: LinearProgressIndicator(value: task.progress <= 0 ? null : task.progress, minHeight: 3),
              ),
            ],
          ],
        ),
      )),
    );
  }

  /// 状态行：正在跑的带速度与已下/总量，暂停的只报已下/总量。
  String _statusLine(AppLocalizations l10n) => switch (task.status) {
        DownloadStatus.downloading => l10n.downloadProgressFull(formatSpeed(task.speedBytesPerSecond), formatBytes(task.downloadedBytes), task.totalBytes > 0 ? formatBytes(task.totalBytes) : '--'),
        DownloadStatus.paused => l10n.paused,
        DownloadStatus.queued => l10n.queued,
        DownloadStatus.failed => task.errorMessage ?? l10n.failed,
        DownloadStatus.completed => l10n.completed,
      };
}

/// 封面上的浮层胶囊：半透明黑底 + 白字，带可选图标。
///
/// 两种尺寸：普通（「前往详情页」，右上角）与 [prominent]（「开始缓存」，封面中央）——
/// 后者是这一条当前唯一该做的动作，做得更大更亮，一眼能找到。
///
/// [label] 可以为空：窄卡上两个胶囊并排会叠字，此时右上角退化成只有箭头的圆钮，
/// 文案改由 [tooltip] 承担。
class _CoverChip extends StatelessWidget {
  const _CoverChip({required this.onTap, this.label, this.icon, this.tooltip, this.prominent = false});

  final String? label;
  final VoidCallback onTap;
  final IconData? icon;
  final String? tooltip;
  final bool prominent;

  @override
  Widget build(BuildContext context) {
    // 和全应用其它按钮一样包一层 PressScale：封面上的胶囊也是按钮，
    // 按下时同样该缩到 .96（test/press_scale_test.dart 会把裸 InkWell 挑出来）。
    final chip = PressScale(child: Material(
      color: Colors.black.withValues(alpha: prominent ? .52 : .42),
      borderRadius: BorderRadius.circular(AppRadius.pill),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: prominent ? 20 : 10, vertical: prominent ? 10 : 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label != null) Text(label!, style: TextStyle(color: Colors.white, fontSize: prominent ? 14 : 12, fontWeight: prominent ? FontWeight.w600 : FontWeight.w500)),
              if (icon != null) ...[if (label != null) const SizedBox(width: 2), Icon(icon, size: prominent ? 18 : 14, color: Colors.white)],
            ],
          ),
        ),
      ),
    ));
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// 单条任务右侧的 ⋮ 菜单：按状态给出「暂停 / 继续 / 重试 / 删除」。
///
/// 从原来"直接铺在行尾的一排按钮"收成菜单：缓存页常常同时有好几条任务，
/// 每行都摆着播放/暂停两个圆钮时，右边会挤成一条按钮链，标题被压得只剩几个字。
class _TaskMenu extends ConsumerWidget {
  const _TaskMenu({required this.task});

  final DownloadTask task;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final controller = ref.read(downloadProvider.notifier);
    return PopupMenuButton<void>(
      tooltip: l10n.moreActions,
      padding: EdgeInsets.zero,
      iconSize: 18,
      icon: const Icon(Symbols.more_vert_rounded),
      itemBuilder: (context) => [
        if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)
          PopupMenuItem<void>(height: 40, onTap: () => controller.pauseTasks({task.id}), child: Row(children: [const Icon(Symbols.pause_rounded, size: 18), const SizedBox(width: 10), Text(l10n.pause)])),
        if (task.status == DownloadStatus.paused)
          PopupMenuItem<void>(height: 40, onTap: () => controller.resumeTasks({task.id}), child: Row(children: [const Icon(Symbols.play_arrow_rounded, size: 18), const SizedBox(width: 10), Text(l10n.resume)])),
        if (task.status == DownloadStatus.failed)
          PopupMenuItem<void>(height: 40, onTap: () => controller.retry(task.id), child: Row(children: [const Icon(Symbols.refresh_rounded, size: 18), const SizedBox(width: 10), Text(l10n.retry)])),
        PopupMenuItem<void>(
          height: 40,
          onTap: () => _confirmDelete(context, ref),
          child: Row(children: [Icon(Symbols.delete_rounded, size: 18, color: theme.colorScheme.error), const SizedBox(width: 10), Text(l10n.deleteCache, style: TextStyle(color: theme.colorScheme.error))]),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.deleteCache),
        content: Text(l10n.deleteCacheConfirmation(task.title)),
        actions: [
          PressScale(child: TextButton(onPressed: () => Navigator.pop(dialogContext, false), child: Text(l10n.cancel))),
          PressScale(child: FilledButton(onPressed: () => Navigator.pop(dialogContext, true), child: Text(l10n.delete))),
        ],
      ),
    );
    if (confirmed != true) return;
    await ref.read(downloadProvider.notifier).deleteTasks({task.id});
  }
}
