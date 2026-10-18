import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_page_colors.dart';
import '../../core/app_radius.dart';
import '../../domain/models/getchu_preview.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';

/// 宽窄屏分界，与 AniBaka 详情页一致。
const double kGetchuWideBreakpoint = 800;

/// 详情页内容区最大宽度。比 AniBaka 的 1200 再宽一档 —— 卡片太窄时正文行宽
/// 撑不开，一屏能读到的字太少。
const double kGetchuContentMaxWidth = 1400;

/// 内容卡片顶部圆角。背景图与页签栏共用，两处对上才像一个容器。
const BorderRadius kGetchuContentTopRadius = BorderRadius.vertical(top: Radius.circular(AppRadius.xl));

/// Getchu 的图片有防盗链，取图时必须带上这两个头。
const Map<String, String> kGetchuImageHeaders = {
  'Referer': 'https://www.getchu.com/',
  'Cookie': 'getchu_adalt_flag=getchu.com; gc=gc',
};

/// 顶部背景图 + 渐变遮罩。
///
/// 这一层要留在滚动视图外面（页面根 Stack 里），滚动时大图才不动。
/// 顶部两角与下方内容卡片共用 [kGetchuContentTopRadius]，
/// 图与内容拼起来才像同一个容器。
class GetchuBackdrop extends StatelessWidget {
  const GetchuBackdrop({super.key, required this.imageUrl, required this.height, this.surfaceColor});

  final String? imageUrl;
  final double height;

  /// 遮罩渐变的收尾颜色。详情页传内容卡片的底色，图的末端与卡片无缝接上；
  /// 不传则用页面画布色，背景图自己就是一块独立底板。
  final Color? surfaceColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 必须用页面底色，不能用 theme.scaffoldBackgroundColor：
    // 后者在本应用里是 Colors.transparent（底色交给 AppBackdrop 画），
    // 拿它做遮罩等于没有遮罩，背景图会直接压在正文下面。
    final surface = surfaceColor ?? AppPageColors.of(theme.brightness);
    final source = imageUrl;
    final fallback = ColoredBox(color: theme.colorScheme.surfaceContainerHighest);
    return ClipRRect(
      borderRadius: kGetchuContentTopRadius,
      child: SizedBox(
        height: height,
        width: double.infinity,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (source == null || source.isEmpty)
              fallback
            else
              AppCachedNetworkImage(
                imageUrl: source,
                httpHeaders: kGetchuImageHeaders,
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                memCacheWidth: 1280,
                fadeInDuration: Duration.zero,
                placeholder: (context, url) => fallback,
                errorWidget: (context, url, error) => fallback,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  // 遮罩往页面底色走，而不是往黑走：浅色模式下底色是近白，
                  // 顶部 55% 底色的图就够淡，黑字压得住；深色模式下反过来把图压深，
                  // 白字又压得住。早先顶部只有 20% 底色，图像素直接顶到文字上，
                  // 粉紫背景配黑标题、稀灰厂商名，两行都读不清。
                  colors: [surface.withValues(alpha: .55), surface.withValues(alpha: .88), surface],
                  stops: const [0, .55, 1],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 竖版封面卡片。阴影挂在最外层 Container 上、图片在 ClipRRect 里，阴影才不会被裁掉。
class GetchuCover extends StatelessWidget {
  const GetchuCover({super.key, required this.imageUrl, required this.width, required this.height});

  final String? imageUrl;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final source = imageUrl;
    final fallback = ColoredBox(
      color: dark ? Colors.white.withValues(alpha: .06) : const Color(0xFFF2F2F7),
      child: Center(
        child: Icon(Symbols.image_not_supported_rounded, size: width * .24, color: dark ? Colors.white24 : Colors.black26),
      ),
    );
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: dark ? Colors.white.withValues(alpha: .08) : Colors.black.withValues(alpha: .04), width: .5),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: dark ? .28 : .16), blurRadius: 18, offset: const Offset(0, 8))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.md - .5),
        child: source == null || source.isEmpty
            ? fallback
            : AppCachedNetworkImage(
                imageUrl: source,
                httpHeaders: kGetchuImageHeaders,
                fit: BoxFit.cover,
                memCacheWidth: (width * 2).round(),
                fadeInDuration: Duration.zero,
                placeholder: (context, url) => fallback,
                errorWidget: (context, url, error) => fallback,
              ),
      ),
    );
  }
}

/// 背景上那一整块：封面 + 标题 + 标签 + 两个按钮。
///
/// 宽屏封面与文字横排，文字列撑满封面高度、按钮压到底；
/// 窄屏封面与标题并排，标签与按钮另起两行。
class GetchuHeader extends StatelessWidget {
  const GetchuHeader({super.key, required this.detail, required this.onPlayTrailer, required this.onOpenProduct});

  final GetchuPreviewDetail detail;
  final VoidCallback? onPlayTrailer;
  final VoidCallback onOpenProduct;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final textColor = dark ? Colors.white : Colors.black;
    // 厂商名压在背景图上，用了一档比常规次级文字更实的灰：
    // 早先是 #8E8E93，在浅色模式的浅粉背景上只有 3:1，读不出来。
    final subtitleColor = dark ? Colors.white70 : const Color(0xFF5C5C63);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > kGetchuWideBreakpoint;
        final coverWidth = isWide ? 270.0 : 130.0;
        final coverHeight = isWide ? 378.0 : 182.0;

        final cover = GetchuCover(imageUrl: detail.coverUrl, width: coverWidth, height: coverHeight);
        final tags = GetchuTags(detail: detail, isDark: dark);

        final actionsRow = Row(
          children: [
            isWide
                ? SizedBox(width: 160, child: _HeaderActionButton(isPrimary: true, icon: Symbols.play_arrow_rounded, label: l10n.playTrailer, onTap: onPlayTrailer))
                : Expanded(child: _HeaderActionButton(isPrimary: true, icon: Symbols.play_arrow_rounded, label: l10n.playTrailer, onTap: onPlayTrailer)),
            SizedBox(width: isWide ? 16 : 12),
            isWide
                ? SizedBox(width: 160, child: _HeaderActionButton(isPrimary: false, icon: Symbols.open_in_new_rounded, label: l10n.openGetchu, onTap: onOpenProduct))
                : Expanded(child: _HeaderActionButton(isPrimary: false, icon: Symbols.open_in_new_rounded, label: l10n.openGetchu, onTap: onOpenProduct)),
          ],
        );

        final title = Text(
          detail.title,
          style: TextStyle(
            fontSize: isWide ? 38 : 22,
            fontWeight: FontWeight.w800,
            letterSpacing: isWide ? -.8 : -.6,
            height: 1.2,
            color: textColor,
          ),
          maxLines: isWide ? 2 : 3,
          overflow: TextOverflow.ellipsis,
        );
        final brand = detail.brand;
        final hasBrand = brand != null && brand.trim().isNotEmpty;

        if (isWide) {
          // 文字列与封面等高：标题在上、标签区限高可滚、按钮贴底
          return SizedBox(
            height: coverHeight,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                cover,
                const SizedBox(width: 48),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      title,
                      if (hasBrand) ...[
                        const SizedBox(height: 12),
                        Text(brand, style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500, height: 1.3, color: subtitleColor), maxLines: 1, overflow: TextOverflow.ellipsis),
                      ],
                      const SizedBox(height: 16),
                      ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 36, maxHeight: 96),
                        child: SingleChildScrollView(physics: const BouncingScrollPhysics(), child: tags),
                      ),
                      const Spacer(),
                      const SizedBox(height: 12),
                      actionsRow,
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                cover,
                const SizedBox(width: 20),
                Expanded(
                  child: SizedBox(
                    height: coverHeight,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [title, const Spacer()],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            tags,
            const SizedBox(height: 24),
            actionsRow,
          ],
        );
      },
    );
  }
}

/// 标签行：厂商、发售日、价格，空的自动跳过。
class GetchuTags extends StatelessWidget {
  const GetchuTags({super.key, required this.detail, required this.isDark});

  final GetchuPreviewDetail detail;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final pills = [detail.brand, detail.releaseDate, detail.price].whereType<String>().where((value) => value.trim().isNotEmpty).toList();
    if (pills.isEmpty) return const SizedBox.shrink();
    final decoration = BoxDecoration(
      color: isDark ? Colors.white.withValues(alpha: .08) : const Color(0xFFF2F2F7),
      borderRadius: BorderRadius.circular(AppRadius.xs),
    );
    final style = TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: .2, color: isDark ? Colors.white70 : const Color(0xFF3A3A3C));
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final pill in pills)
          Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5), decoration: decoration, child: Text(pill, style: style)),
      ],
    );
  }
}

/// 顶部按钮：主按钮实底、次按钮浅底；高 44、圆角 12。
class _HeaderActionButton extends StatelessWidget {
  const _HeaderActionButton({required this.isPrimary, required this.icon, required this.label, required this.onTap});

  final bool isPrimary;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final background = isPrimary ? (dark ? Colors.white : Colors.black) : (dark ? const Color(0xFF2C2C2E) : const Color(0xFFF2F2F7));
    final foreground = isPrimary ? (dark ? Colors.black : Colors.white) : (dark ? Colors.white : Colors.black);
    final enabled = onTap != null;
    final tint = enabled ? foreground : foreground.withValues(alpha: .5);
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          height: 44,
          decoration: BoxDecoration(
            color: enabled ? background : background.withValues(alpha: .4),
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 20, color: tint),
              const SizedBox(width: 6),
              Text(label, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: .5, color: tint)),
            ],
          ),
        ),
      ),
    );
  }
}
