import 'dart:async';

import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_price_colors.dart';
import '../../core/app_radius.dart';
import '../../domain/models/getchu_preview.dart';
import '../shared/app_image_cache.dart';
import '../shared/hover_zoom.dart';
import '../shared/press_scale.dart';
import 'getchu_detail_hero.dart';

/// Getchu 商品封面比例（宽 / 高）。
///
/// `package.jpg` 绝大多数是 500×715，少数是 700×500；按竖版统一，
/// 横版那张会被裁掉一点，但整行卡片的封面比例一致。
///
/// 注意这是**宽 / 高**。`PreviewGridMetrics.coverRatio` 要的是**高 / 宽**，
/// 传进去的时候得取倒数，否则算出的行高只有实际的一半。
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
///
/// 封面没到位之前整张卡只留一块中性底：阴影和文字都跟着封面一起出现，
/// 不然会先看到「一块空白的虚影 + 已经排好的标题」，等图补上再跳一下。
class GetchuCard extends StatefulWidget {
  const GetchuCard({super.key, required this.item});

  final GetchuPreviewItem item;

  @override
  State<GetchuCard> createState() => _GetchuCardState();
}

class _GetchuCardState extends State<GetchuCard> {
  /// 没有封面的条目（站方尚未发售）一上来就算就绪 —— 它要显示的是那行说明字。
  late bool _coverReady = widget.item.coverUrl == null;

  /// 等不到「图到齐」时的兜底计时器。
  ///
  /// 封面既不出图也不报错（下载卡住、或同一 cacheKey 的请求被别人的失败带进
  /// 去）时，[imageBuilder] 和 [errorWidget] 都不会被调起，卡片就永远是那块
  /// 中性底板 —— 连标题和价格一起看不见。文字比封面重要，所以到点直接放出来。
  Timer? _readyTimer;

  static const Duration _readyFallback = Duration(seconds: 4);

  @override
  void initState() {
    super.initState();
    _armReadyTimer();
  }

  void _armReadyTimer() {
    if (_coverReady) return;
    _readyTimer?.cancel();
    _readyTimer = Timer(_readyFallback, () {
      if (!mounted || _coverReady) return;
      setState(() => _coverReady = true);
    });
  }

  @override
  void dispose() {
    _readyTimer?.cancel();
    super.dispose();
  }

  void _markCoverReady() {
    if (_coverReady) return;
    // 这个回调在 build 途中被调起，不能就地 setState。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _coverReady) return;
      _readyTimer?.cancel();
      setState(() => _coverReady = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = widget.item;
    return CardHover(
      builder: (context, hovered) => MouseRegion(
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
                        boxShadow: _coverReady
                            ? [
                                BoxShadow(
                                  color: Colors.black.withValues(
                                    alpha: theme.brightness == Brightness.dark
                                        ? .38
                                        : .16,
                                  ),
                                  blurRadius: 14,
                                  offset: const Offset(0, 4),
                                ),
                              ]
                            : null,
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        // 推近放在裁切框里面：多出来的部分被裁掉，不会盖到邻卡。
                        child: ZoomOnHover(
                          hovered: hovered,
                          child: _cover(context),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  // 文字与封面同进同退；用 Opacity 而不是条件插入，
                  // 这样加载前后卡片高度不变，网格不会跟着跳。
                  Opacity(
                    opacity: _coverReady ? 1 : 0,
                    // 标题只占一行：两行标题会把价格行往下推，同一排卡片的
                    // 价格落在不同高度上。
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      mainAxisSize: MainAxisSize.min,
                      children: [
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
                          // 价格用红，取站点自己的 `.redb` 那个色（#C00）。
                          // 整套界面里只有价格是红的，一眼能扫到。
                          Text(
                            item.price!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.labelLarge?.copyWith(
                              color: AppPriceColors.of(theme.brightness),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _cover(BuildContext context) {
    final theme = Theme.of(context);
    final url = widget.item.coverUrl;
    if (url == null) {
      return _NoCover(label: AppLocalizations.of(context)!.getchuNotYetReleased);
    }
    return Stack(
      fit: StackFit.expand,
      children: [
        // 图没到之前只留一层中性底，连阴影都不画（阴影由调用处一起关掉）。
        ColoredBox(color: theme.colorScheme.surfaceContainerLow),
        AppCachedNetworkImage(
          imageUrl: url,
          httpHeaders: kGetchuImageHeaders,
          fit: BoxFit.cover,
          placeholder: (context, url) => const SizedBox.expand(),
          errorWidget: (context, url, error) {
            // 失败了也得把文字放出来，否则这张卡永远是一片空白。
            _markCoverReady();
            return const Center(
              child: Icon(Symbols.image_not_supported_rounded),
            );
          },
          // 这里**不开** faceFocus。
          //
          // 列表卡用的 package.jpg 多是 500×715 的竖版海报，卡片的 0.7 比例
          // 跟它几乎一致，本来就裁不到什么；而开了以后要走「检测完再造一个
          // Image」的路径，同一张图被解析两次，实测有相当一部分封面会永远停在
          // 占位态，只剩一块白板。详情页的 GetchuCover 仍然开着。
          imageBuilder: (context, provider) {
            // 只有图真的解码出帧，imageBuilder 才会被调起 —— 这是「图到齐了」
            // 唯一可靠的信号，用它把阴影和文字一起放出来。
            _markCoverReady();
            return Image(image: provider, fit: BoxFit.cover);
          },
        ),
      ],
    );
  }
}

/// 站方还没给这张商品出封面时的占位：中性底 + 一行说明。
class _NoCover extends StatelessWidget {
  const _NoCover({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ColoredBox(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Center(
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}
