import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../domain/models/download.dart';
import '../shared/app_image_cache.dart';
import 'cache_format.dart';

/// 缓存卡片右下角的角标（时长 / 体积这类叠在封面上的信息）。
class CacheCoverBadge extends StatelessWidget {
  const CacheCoverBadge({super.key, this.icon, required this.text});

  final IconData? icon;
  final String text;

  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: .55), borderRadius: BorderRadius.circular(6)),
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
    return InkWell(
      // 之前这里是 `GestureDetector(onLongPress: ...)` 且**没有** onTap ——
      // 传入的播放回调被完全忽略，卡片点上去毫无反应（长按却能进多选）。
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (cover != null)
                    Image(image: cover, fit: BoxFit.cover)
                  else
                    ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Icons.movie_outlined, size: 32, color: theme.colorScheme.onSurfaceVariant)),
                  if (bytes > 0) Positioned(left: 6, bottom: 6, child: CacheCoverBadge(icon: Icons.save_alt_outlined, text: formatBytes(bytes))),
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
    );
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
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
                    borderRadius: BorderRadius.circular(8),
                    child: cover != null
                        ? Image(image: cover, fit: BoxFit.cover)
                        : ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Icons.movie_outlined, size: 28, color: theme.colorScheme.onSurfaceVariant)),
                  ),
                  // 下载中/暂停的在封面底部画一条进度，未完成的也一眼能看出状态。
                  if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused)
                    Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: task.progress <= 0 ? null : task.progress, minHeight: 3)),
                  if (bytes > 0) Positioned(left: 6, bottom: 6, child: CacheCoverBadge(icon: Icons.save_alt_outlined, text: formatBytes(bytes))),
                  if (duration != null && duration.isNotEmpty) Positioned(right: 6, bottom: 6, child: CacheCoverBadge(text: duration)),
                  // 未下完的状态角标（排队/暂停/失败）放左上角，别和体积撞在一起。
                  if (task.status != DownloadStatus.completed)
                    Positioned(left: 6, top: 6, child: CacheCoverBadge(text: taskStatusLabel(l10n, task.status))),
                  if (selecting) Positioned(right: 6, top: 6, child: Icon(selected ? Icons.check_circle : Icons.radio_button_unchecked, size: 20, color: Colors.white)),
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
                    icon: const Icon(Icons.more_vert),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
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
    return InkWell(
      borderRadius: BorderRadius.circular(10),
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
                    borderRadius: BorderRadius.circular(10),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (cover != null)
                          Image(image: cover, fit: BoxFit.cover)
                        else
                          ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Icons.folder_outlined, size: 36, color: theme.colorScheme.onSurfaceVariant)),
                        if (progress != null)
                          Align(alignment: Alignment.bottomCenter, child: LinearProgressIndicator(value: progress <= 0 ? null : progress, minHeight: 3)),
                        Positioned(
                          right: 6,
                          bottom: 8,
                          child: CacheCoverBadge(icon: Icons.folder_outlined, text: l10n.folderContents(tasks.length)),
                        ),
                        if (bytes > 0)
                          Positioned(left: 6, bottom: 8, child: CacheCoverBadge(icon: Icons.save_alt_outlined, text: formatBytes(bytes))),
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
    );
  }
}

class _StackSheet extends StatelessWidget {
  const _StackSheet({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => DecoratedBox(decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(10)));
}

/// 缓存管理页里单条任务在「正在缓存」列表用的横排卡片。
///
/// 下载中的项信息密度比已完成的高（速度、进度、剩余体积），横排能把封面压小、
/// 把文字信息铺开，比网格卡片更容易看清进度。
class CacheTaskRow extends StatelessWidget {
  const CacheTaskRow({super.key, required this.task, required this.selected, required this.onTap, this.onLongPress, this.trailing});

  final DownloadTask task;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final cover = _coverImage();
    final label = switch (task.status) {
      DownloadStatus.queued => l10n.queued,
      DownloadStatus.downloading => l10n.downloading,
      DownloadStatus.completed => l10n.completed,
      DownloadStatus.failed => l10n.failed,
      DownloadStatus.paused => l10n.paused,
    };
    final progressText = switch (task.status) {
      DownloadStatus.downloading => l10n.downloadProgressFull(formatSpeed(task.speedBytesPerSecond), formatBytes(task.downloadedBytes), task.totalBytes > 0 ? formatBytes(task.totalBytes) : '--'),
      DownloadStatus.paused => '${formatBytes(task.downloadedBytes)} / ${task.totalBytes > 0 ? formatBytes(task.totalBytes) : '--'}',
      DownloadStatus.queued => l10n.queued,
      DownloadStatus.failed => task.errorMessage ?? l10n.failed,
      DownloadStatus.completed => formatBytes(task.totalBytes > 0 ? task.totalBytes : task.downloadedBytes),
    };
    return Material(
      color: selected ? theme.colorScheme.secondaryContainer.withValues(alpha: .5) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: SizedBox(
                  width: 96,
                  height: 54,
                  child: cover != null
                      ? Image(image: cover, fit: BoxFit.cover)
                      : ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Icons.movie_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant)),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(task.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 6),
                    if (task.status == DownloadStatus.downloading || task.status == DownloadStatus.paused) ...[
                      ClipRRect(borderRadius: BorderRadius.circular(2), child: LinearProgressIndicator(value: task.progress <= 0 ? null : task.progress, minHeight: 4)),
                      const SizedBox(height: 6),
                    ],
                    Text(
                      '${task.quality.isEmpty ? '' : '${task.quality} · '}$progressText',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline),
                    ),
                    const SizedBox(height: 2),
                    Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: task.status == DownloadStatus.failed ? theme.colorScheme.error : theme.colorScheme.primary)),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ],
          ),
        ),
      ),
    );
  }

  ImageProvider? _coverImage() {
    final local = task.localCoverPath;
    if (local != null && File(local).existsSync()) return FileImage(File(local));
    final remote = task.coverUrl;
    if (remote == null || remote.isEmpty) return null;
    return CachedNetworkImageProvider(remote, cacheManager: appImageCacheManager);
  }
}
