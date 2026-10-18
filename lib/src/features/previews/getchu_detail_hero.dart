import 'package:flutter/material.dart';

import '../../core/app_radius.dart';
import '../shared/app_image_cache.dart';

/// Getchu 详情页顶部的整宽背景图 + 渐变遮罩。
///
/// 与 hanime 视频详情页（`video_detail_hero.dart`）同一套做法：背景铺满顶部
/// 一行，底部用一条由透明渐变为页面底色的遮罩，让下方内容自然过渡。
/// Getchu 的图片带防盗链头，所以这里多一个 [httpHeaders]。
class GetchuBackdrop extends StatelessWidget {
  const GetchuBackdrop({super.key, required this.imageUrl, required this.height, this.httpHeaders});

  final String? imageUrl;
  final double height;
  final Map<String, String>? httpHeaders;

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
            AppCachedNetworkImage(
              imageUrl: source,
              httpHeaders: httpHeaders,
              fit: BoxFit.cover,
              alignment: Alignment.topCenter,
              memCacheWidth: 720,
              fadeInDuration: Duration.zero,
              placeholder: (context, url) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              errorWidget: (context, url, error) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
            ),
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
class GetchuCover extends StatelessWidget {
  const GetchuCover({super.key, required this.imageUrl, required this.width, this.httpHeaders});

  final String? imageUrl;
  final double width;
  final Map<String, String>? httpHeaders;

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
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .16), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - .5),
        child: source == null || source.isEmpty
            ? ColoredBox(color: theme.colorScheme.surfaceContainerHighest)
            : AppCachedNetworkImage(
                imageUrl: source,
                httpHeaders: httpHeaders,
                fit: BoxFit.cover,
                memCacheWidth: (width * 3).round(),
                fadeInDuration: Duration.zero,
                placeholder: (context, url) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
                errorWidget: (context, url, error) => ColoredBox(color: theme.colorScheme.surfaceContainerHighest),
              ),
      ),
    );
  }
}
