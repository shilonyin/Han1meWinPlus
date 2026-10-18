import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../shared/app_image_cache.dart';

/// 详情页顶部的整宽背景图 + 渐变遮罩。
///
/// 背景图铺满顶部一行，底部用一条由透明渐变为页面底色的遮罩，让下方的
/// 标题区自然过渡到正文。这里刻意不做模糊 —— 模糊会把封面上的字糊成色块。
class VideoDetailBackdrop extends StatelessWidget {
  const VideoDetailBackdrop({super.key, required this.imageUrl, required this.height});

  final String? imageUrl;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final surface = theme.colorScheme.surface;
    final source = imageUrl;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (source == null || source.isEmpty)
            ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
          else
            // cover + topCenter：竖版封面铺横条时先保住上半部分（画面重心通常在上面）
            AppCachedNetworkImage(
              imageUrl: source,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 720,
              placeholder: (context, url) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              errorWidget: (context, url, error) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
            ),
          // 单向压暗：顶部留 20% 让图清楚，中点 80%，到底完全变成页面底色
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [surface.withValues(alpha: .2), surface.withValues(alpha: .8), surface],
                stops: const [0, .5, 1],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 浮在背景上的竖版封面卡片。
///
/// 阴影挂在最外层 Container 上、图片在 ClipRRect 里，这样阴影不会被裁掉。
class VideoDetailCover extends StatelessWidget {
  const VideoDetailCover({super.key, required this.imageUrl, required this.width});

  final String? imageUrl;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final source = imageUrl;
    return Container(
      width: width,
      height: width * 1.4, // 竖版封面常用 5:7
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .16), blurRadius: 18, offset: const Offset(0, 8)),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - .5),
        child: source == null || source.isEmpty
            ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.broken_image_rounded, color: theme.colorScheme.outline))
            : AppCachedNetworkImage(
                imageUrl: source,
                fit: BoxFit.cover,
                memCacheWidth: (width * 3).round(),
                placeholder: (context, url) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest, child: Icon(Symbols.broken_image_rounded, color: theme.colorScheme.outline)),
              ),
      ),
    );
  }
}
