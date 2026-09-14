import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';

int videoCardCacheWidth(double cardWidth, double devicePixelRatio) => (cardWidth * devicePixelRatio).round().clamp(240, 480).toInt();

const _horizontalCardMetaHeight = 120.0;

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

class VideoCardTile extends StatelessWidget {
  const VideoCardTile({super.key, required this.video, this.horizontal = false, this.selected = false, this.dense = false, this.fillCover = false, this.onTap, this.onLongPress, this.coverImage});

  final VideoCard video;
  final bool horizontal;
  final bool selected;
  /// 小卡片（侧栏「系列影片」）用：字号、间距、角标都缩小一号
  final bool dense;
  /// 固定高度的网格里让封面吃掉剩余高度（高度不够时裁切图片，而不是撑破卡片）
  final bool fillCover;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final ImageProvider? coverImage;

  @override
  Widget build(BuildContext context) {
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
                ? _horizontalContent(theme, cacheWidth)
                : _verticalContent(theme, cacheWidth),
          ),
        );
      },
    );
  }

  Widget _verticalContent(ThemeData theme, int cacheWidth) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: _cover(theme, cacheWidth)),
          const SizedBox(height: 8),
          _details(theme),
        ],
      );

  Widget _horizontalContent(ThemeData theme, int cacheWidth) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 小卡片（侧栏系列影片）或固定高度的搜索网格：封面吃掉剩余高度，图片尽量大
          if (dense || fillCover)
            Expanded(child: _cover(theme, cacheWidth))
          else
            AspectRatio(aspectRatio: 16 / 9, child: _cover(theme, cacheWidth)),
          SizedBox(height: dense ? 4 : 8),
          // 细节区最多吃掉剩余高度：网格给的是固定卡高，超出时裁剪而不是溢出报错
          Flexible(child: ClipRect(child: _details(theme))),
        ],
      );

  Widget _cover(ThemeData theme, int cacheWidth) => RepaintBoundary(
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

  Widget _details(ThemeData theme) => Column(
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
          SizedBox(height: dense ? 2 : 2),
          // 作者名缺失时也占一行，避免同一行卡片里的元素上下错位
          Text(video.artist ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(fontSize: dense ? 10 : null, color: theme.colorScheme.outline)),
          SizedBox(height: dense ? 2 : 2),
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
      );
}

class VideoCardGrid extends ConsumerWidget {
  const VideoCardGrid({super.key, required this.videos, this.itemBuilder, this.cardsPerRow, this.rowsPerScreen});

  final List<VideoCard> videos;
  final Widget Function(BuildContext context, int index, VideoCard video, bool horizontal)? itemBuilder;

  /// 指定每行几个（为空时用设置里的值，宽屏会自动加宽）。
  final int? cardsPerRow;

  /// 指定一屏显示几行（固定高度网格，卡片高度按可用高度反推）。
  final int? rowsPerScreen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final horizontal = settings?.useHorizontalSearchCards ?? true;
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
            : (horizontal ? cardWidth * 9 / 16 + _horizontalCardMetaHeight : cardWidth / .58);
        return GridView.builder(
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
