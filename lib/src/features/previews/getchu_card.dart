import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/app_radius.dart';
import '../../domain/models/getchu_preview.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import 'getchu_detail_hero.dart';

/// Getchu 商品封面比例（宽 / 高）。
///
/// `package.jpg` 绝大多数是 500×715，少数是 700×500；按竖版统一，
/// 横版那张会被裁掉一点，但整行卡片的封面比例一致。
const double kGetchuCoverRatio = 0.7;

/// 封面下方文字区的固定高度：标题一行 + 间距 + 价格一行 + 底距。
///
/// 卡高由「封面按比例算出的高度 + 这个值」组成，不用 `childAspectRatio`：
/// 后者约束的是整卡的高宽比，而文字区是固定像素高，窗口一变宽封面比例
/// 就跟着变，一排封面的高矮会不齐。
const double kGetchuDetailsHeight = 56;

/// 网格里单张卡该有多高。封面宽度定下来，高度就是 [kGetchuCoverRatio] 算出的
/// 封面高加文字区。
double getchuCardHeight(double cardWidth) =>
    cardWidth / kGetchuCoverRatio + kGetchuDetailsHeight;

/// Getchu 商品卡片：列表页与详情页的系列商品共用同一套。
///
/// 结构照首页卡片：封面是独立的一块圆角（带阴影），标题与价格直接落在
/// 内容底色上，不套底板 —— 封面和文字同属一块白色看着像两层。
class GetchuCard extends StatelessWidget {
  const GetchuCard({super.key, required this.item});

  final GetchuPreviewItem item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: Material(
        type: MaterialType.transparency,
        child: PressScale(
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            // 灰罩在无底卡片上只能从文字区透出来，看着像「选中时下面变暗」。
            hoverColor: Colors.transparent,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            // 上面三个都关了，焦点态得单独给，否则键盘 Tab 到卡片上毫无反应。
            focusColor: theme.colorScheme.primary.withValues(alpha: .16),
            onTap: () => context.push('/previews/getchu/detail/${item.id}'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 封面用 AspectRatio 定高，不用 Expanded。
                //
                // Expanded 吃的是「卡高减去文字区实际高度」，而文字区高度不固定：
                // 没价格的条目少一行，封面就跟着变高一截，同一排的封面底边对不上、
                // 标题落在不同高度。AspectRatio 只由卡片宽度决定，跟下方文字无关。
                AspectRatio(
                  aspectRatio: kGetchuCoverRatio,
                  child: DecoratedBox(
                    // 白底封面压在白色卡片上，两者同色，不补阴影就看不出边界在哪。
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(
                            alpha: theme.brightness == Brightness.dark
                                ? .38
                                : .16,
                          ),
                          blurRadius: 14,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: item.coverUrl == null
                          ? ColoredBox(
                              color: theme.colorScheme.surfaceContainerHighest,
                              child: const Icon(
                                Symbols.image_not_supported_rounded,
                              ),
                            )
                          : AppCachedNetworkImage(
                              imageUrl: item.coverUrl!,
                              httpHeaders: kGetchuImageHeaders,
                              fit: BoxFit.cover,
                              fadeInDuration: Duration.zero,
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // 标题只占一行：两行标题会把价格行往下推，同一排卡片的
                // 价格落在不同高度上。
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (item.price != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    item.price!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
