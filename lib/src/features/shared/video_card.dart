import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import 'app_image_cache.dart';

int videoCardCacheWidth(double cardWidth, double devicePixelRatio) => (cardWidth * devicePixelRatio).round().clamp(240, 480).toInt();

const _horizontalCardMetaHeight = 120.0;

/// 站点有些分类列表（如里番、泡麵番）只给封面和标题，卡片下方不需要留出两行空间。
const _horizontalCardCompactMetaHeight = 78.0;

/// 该卡片是否带作者 / 评分 / 上传时间。
bool hasVideoCardMeta(VideoCard video) => video.artist != null || video.rating != null || video.uploadTime != null;

/// 一批卡片在封面下方需要的高度（整批都没有 meta 时用矮一点的值）。
/// [assumeMeta] 为真时按完整高度算（卡片会去详情页补全信息）。
double videoCardMetaHeight(Iterable<VideoCard> videos, {bool assumeMeta = false}) => assumeMeta || videos.any(hasVideoCardMeta) ? _horizontalCardMetaHeight : _horizontalCardCompactMetaHeight;

/// 简单并发闸门：补全卡片信息会同时发起不少详情页请求，限制同时在跑的个数。
class _RequestGate {
  _RequestGate(this.maxConcurrent);

  final int maxConcurrent;
  var _active = 0;
  final _waiting = <Completer<void>>[];

  Future<void> enter() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void leave() {
    if (_waiting.isEmpty) {
      _active--;
    } else {
      _waiting.removeAt(0).complete();
    }
  }
}

final _metaGate = _RequestGate(4);

/// 站点有些分类列表（里番、泡麵番）只给封面和标题，
/// 这些卡片用详情页把时长/播放量/作者/评分/视频截图补回来，结果写进 [VideoMetaCache]。
/// 缓存命中时不会再发请求，所以刷新、滚动来回、重启都直接有值。
final videoCardMetaProvider = FutureProvider.autoDispose.family<VideoCard, String>((ref, id) async {
  final cache = ref.watch(videoMetaCacheProvider);
  final cached = cache.read(id);
  if (cached != null) return cached;
  final settings = await ref.watch(settingsProvider.future);
  final repository = ref.watch(han1meRepositoryProvider);
  await _metaGate.enter();
  try {
    final detail = await repository.video(settings.resolvedBaseUrl, id);
    final meta = VideoCard(
      id: id,
      title: detail.title,
      coverUrl: detail.coverUrl ?? '',
      duration: detail.duration,
      views: detail.views,
      rating: detail.rating,
      artist: detail.artist,
      uploadTime: detail.uploadDate,
    );
    await cache.put(meta);
    return meta;
  } finally {
    _metaGate.leave();
  }
});

class VideoCardMetrics {
  const VideoCardMetrics({required this.horizontal, required this.cardsPerRow, required this.cardWidth, required this.cardHeight});

  final bool horizontal;
  final int cardsPerRow;
  final double cardWidth;
  final double cardHeight;
}

VideoCardMetrics videoCardMetrics({
  required double viewportWidth,
  required bool horizontal,
  required int cardsPerRow,
  required bool expanded,
}) {
  const spacing = 10.0;
  const padding = 32.0;
  if (expanded) {
    final effective = viewportWidth >= 1200 ? (viewportWidth / 300).floor().clamp(cardsPerRow, 6).toInt() : cardsPerRow;
    final cardWidth = (viewportWidth - padding - spacing * (effective - 1)) / effective;
    final cardHeight = horizontal ? cardWidth * 9 / 16 + _horizontalCardMetaHeight : cardWidth / .58;
    return VideoCardMetrics(horizontal: horizontal, cardsPerRow: effective, cardWidth: cardWidth, cardHeight: cardHeight);
  }
  final desktop = viewportWidth >= 700;
  final cardWidth = horizontal ? (desktop ? 220.0 : 154.0) : (desktop ? 170.0 : 132.0);
  final cardHeight = horizontal ? cardWidth * 9 / 16 + _horizontalCardMetaHeight : cardWidth / .58;
  return VideoCardMetrics(horizontal: horizontal, cardsPerRow: 1, cardWidth: cardWidth, cardHeight: cardHeight);
}

class VideoCardTile extends ConsumerWidget {
  const VideoCardTile({super.key, required this.video, this.horizontal = false, this.selected = false, this.dense = false, this.fillCover = false, this.autoFetchMeta = false, this.onTap, this.onLongPress, this.coverImage});

  final VideoCard video;
  final bool horizontal;
  final bool selected;
  /// 小卡片（侧栏「系列影片」）用：字号、间距、角标都缩小一号
  final bool dense;
  /// 固定高度的网格里让封面吃掉剩余高度（高度不够时裁切图片，而不是撑破卡片）
  final bool fillCover;
  /// 卡片没有作者/评分时去详情页补（站点部分分类列表只给封面和标题）。
  /// 搜索结果页不用它，保持只显示站点列表给出的内容。
  final bool autoFetchMeta;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ImageProvider? coverImage;

  /// 需要补全时用详情页的数据填掉缺的字段。
  /// 命中本地缓存时是同步的，所以刷新后卡片会直接显示补全后的内容。
  VideoCard _resolved(WidgetRef ref) {
    if (!autoFetchMeta || video.id.isEmpty || hasVideoCardMeta(video)) return video;
    final cached = ref.watch(videoMetaCacheProvider).read(video.id);
    if (cached != null) return _mergeMeta(cached);
    final fetched = ref.watch(videoCardMetaProvider(video.id)).valueOrNull;
    return fetched == null ? video : _mergeMeta(fetched);
  }

  /// 补全信息以详情页为准（封面换成视频内容截图，而不是列表页给的海报）。
  VideoCard _mergeMeta(VideoCard meta) => VideoCard(
        id: video.id,
        title: video.title,
        coverUrl: meta.coverUrl.isEmpty ? video.coverUrl : meta.coverUrl,
        duration: meta.duration ?? video.duration,
        views: meta.views ?? video.views,
        rating: meta.rating ?? video.rating,
        artist: meta.artist ?? video.artist,
        uploadTime: meta.uploadTime ?? video.uploadTime,
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final resolved = _resolved(ref);
    return LayoutBuilder(
      builder: (context, constraints) {
        final theme = Theme.of(context);
        final cacheWidth = videoCardCacheWidth(constraints.maxWidth, MediaQuery.devicePixelRatioOf(context));
        return Material(
          color: selected ? theme.colorScheme.secondaryContainer : Colors.transparent,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: selected ? BorderSide(color: theme.colorScheme.primary, width: 2) : BorderSide.none,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap ?? (video.id.isEmpty ? null : () => context.push('/video/${video.id}')),
            onLongPress: onLongPress,
            child: horizontal
                ? _horizontalContent(theme, cacheWidth, resolved)
                : _verticalContent(theme, cacheWidth, resolved),
          ),
        );
      },
    );
  }

  Widget _verticalContent(ThemeData theme, int cacheWidth, VideoCard video) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cover(theme, cacheWidth, video)),
          const SizedBox(height: 8),
          _details(theme, video),
        ],
      );

  Widget _horizontalContent(ThemeData theme, int cacheWidth, VideoCard video) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 小卡片（侧栏系列影片）或固定高度的搜索网格：封面吃掉剩余高度，图片尽量大。
          // 站点有些分类只给封面和标题（例如里番的后续分页），这时也让封面撑满剩余高度，
          // 否则卡片下方会空出一段没有内容的区域。
          if (dense || fillCover || !hasVideoCardMeta(video))
            Expanded(child: _cover(theme, cacheWidth, video))
          else
            AspectRatio(aspectRatio: 16 / 9, child: _cover(theme, cacheWidth, video)),
          SizedBox(height: dense ? 4 : 8),
          // 细节区最多吃掉剩余高度：网格给的是固定卡高，超出时裁剪而不是溢出报错
          Flexible(child: ClipRect(child: _details(theme, video))),
        ],
      );

  Widget _cover(ThemeData theme, int cacheWidth, VideoCard video) => RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              if (coverImage != null)
                Image(image: coverImage!, fit: BoxFit.cover)
              else
                CachedNetworkImage(
                  imageUrl: video.coverUrl,
                  cacheManager: appImageCacheManager,
                  fit: BoxFit.cover,
                  memCacheWidth: cacheWidth,
                  fadeInDuration: Duration.zero,
                  fadeOutDuration: Duration.zero,
                  placeholder: (context, url) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                  ),
                  errorWidget: (context, url, error) => ColoredBox(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(child: Icon(Icons.broken_image_outlined)),
                  ),
                ),
              if (video.duration != null) Positioned(right: dense ? 3 : 6, bottom: dense ? 3 : 6, child: _OverlayText(text: video.duration!, dense: dense)),
              if (video.views != null)
                Positioned(
                  left: dense ? 3 : 6,
                  bottom: dense ? 3 : 6,
                  child: _OverlayText(icon: Icons.visibility_outlined, text: video.views!, dense: dense),
                ),
            ],
          ),
        ),
      );

  Widget _details(ThemeData theme, VideoCard video) {
    final hasMeta = hasVideoCardMeta(video);
    return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (dense)
            // 小卡片只留一行标题：短标题时不会在标题和作者名之间空一大截
            Text(video.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodyMedium?.copyWith(fontSize: 11, fontWeight: FontWeight.w600))
          else
            SizedBox(
              height: 40,
              child: Text(
                video.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          if (hasMeta) ...[
            const SizedBox(height: 2),
            // 作者名缺失时也占一行，避免同一行卡片里的元素上下错位
            Text(video.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: dense ? 10 : null, color: theme.colorScheme.outline)),
            const SizedBox(height: 2),
            SizedBox(
              height: dense ? 14 : 16,
              child: Row(
                children: [
                  Expanded(child: video.rating == null ? const SizedBox.shrink() : Row(children: [Icon(Icons.thumb_up_outlined, size: dense ? 11 : 14, color: theme.colorScheme.outline), SizedBox(width: dense ? 3 : 4), Flexible(child: Text(video.rating!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(fontSize: dense ? 10 : null, color: theme.colorScheme.outline)))])),
                  if (video.uploadTime != null) Text(video.uploadTime!, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(fontSize: dense ? 10 : null, color: theme.colorScheme.outline)),
                ],
              ),
            ),
          ],
        ],
      );
  }
}

class VideoCardGrid extends ConsumerWidget {
  const VideoCardGrid({super.key, required this.videos, this.itemBuilder, this.cardsPerRow, this.rowsPerScreen, this.horizontal, this.controller});

  final List<VideoCard> videos;
  final Widget Function(BuildContext context, int index, VideoCard video, bool horizontal)? itemBuilder;

  /// 指定每行几个（为空时用设置里的值，宽屏会自动加宽）。
  final int? cardsPerRow;

  /// 指定一屏显示几行（固定高度网格，卡片高度按可用高度反推）。
  final int? rowsPerScreen;

  /// 指定卡片方向（为空时用设置里的值）。
  final bool? horizontal;

  /// 外部控制器（用于「回到顶部」这类滚动控制）。
  final ScrollController? controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final horizontal = this.horizontal ?? settings?.useHorizontalSearchCards ?? true;
    final cardsPerRow = this.cardsPerRow ?? settings?.searchCardsPerRow ?? 2;
    return LayoutBuilder(
      builder: (context, constraints) {
        const horizontalPadding = 24.0;
        const crossAxisSpacing = 10.0;
        const mainAxisSpacing = 12.0;
        final autoWiden = this.cardsPerRow == null && constraints.maxWidth >= 1200;
        final effectiveCardsPerRow = autoWiden ? (constraints.maxWidth / 300).floor().clamp(cardsPerRow, 6).toInt() : cardsPerRow;
        final cardWidth = (constraints.maxWidth - horizontalPadding - crossAxisSpacing * (effectiveCardsPerRow - 1)) / effectiveCardsPerRow;
        final rows = rowsPerScreen;
        final cardHeight = rows != null && constraints.hasBoundedHeight
            ? ((constraints.maxHeight - 36 - MediaQuery.paddingOf(context).bottom - mainAxisSpacing * (rows - 1)) / rows).clamp(96.0, 420.0)
            : (horizontal ? cardWidth * 9 / 16 + videoCardMetaHeight(videos) : cardWidth / .58);
        return GridView.builder(
          controller: controller,
          padding: EdgeInsets.fromLTRB(12, 12, 12, 24 + MediaQuery.paddingOf(context).bottom),
          cacheExtent: 720,
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: effectiveCardsPerRow,
            mainAxisSpacing: mainAxisSpacing,
            crossAxisSpacing: crossAxisSpacing,
            mainAxisExtent: cardHeight,
          ),
          itemCount: videos.length,
          itemBuilder: (context, index) => itemBuilder?.call(context, index, videos[index], horizontal) ?? VideoCardTile(video: videos[index], horizontal: horizontal),
        );
      },
    );
  }
}

class _OverlayText extends StatelessWidget {
  const _OverlayText({this.icon, required this.text, this.dense = false});
  final IconData? icon;
  final String text;
  final bool dense;

  @override
  Widget build(BuildContext context) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, size: dense ? 10 : 12, color: Colors.white),
              SizedBox(width: dense ? 2 : 3),
            ],
            Text(text, style: TextStyle(color: Colors.white, fontSize: dense ? 9 : 11, fontWeight: FontWeight.w600)),
          ],
        );
}
