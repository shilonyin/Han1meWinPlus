import 'package:flutter/material.dart';

import '../../../core/app_surface_tokens.dart';
import '../../../core/color_contrast.dart';

/// 把"这块面板实际呈现的不透明底色"告知子树。
///
/// 为什么需要它：面板的底色不一定等于主题的 surface（调用点会传自己的
/// [GlassPanel.solidColor]），子树里的文字要保证可读，就得知道自己压在多亮的底上 ——
/// 而这个值只有 [GlassPanel] 算得出来。
///
/// 刻意**只提供数据、不强行改颜色**：`GlassPanel` 若用 `DefaultTextStyle`
/// 兜底，会把调用处已经显式给好的颜色（例如悬停变主题色、选中态用
/// `onSecondaryContainer`）一并冲掉，反而破坏交互反馈。所以这里只把底色传下去，
/// 由真正在意的调用方显式索取 —— 见 [GlassPanelTextColor]。
class GlassPanelScope extends InheritedWidget {
  const GlassPanelScope({
    super.key,
    required this.surfaceColor,
    required super.child,
  });

  /// 面板压在页面底色之上后的**不透明**等效色。
  final Color surfaceColor;

  /// 取当前面板的等效底色；不在 [GlassPanel] 子树里时返回 `null`。
  static Color? surfaceColorOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<GlassPanelScope>()
      ?.surfaceColor;

  @override
  bool updateShouldNotify(GlassPanelScope oldWidget) =>
      oldWidget.surfaceColor != surfaceColor;
}

/// 在面板上解析一个**保证可读**的文字/图标色。
///
/// 用法：把候选色交给它，它在面板等效底色上做对比度兜底：
///
/// ```dart
/// color: GlassPanelTextColor.resolve(context, fallback: scheme.onSurfaceVariant)
/// ```
///
/// 不在 [GlassPanel] 子树里（拿不到面板底色）时原样返回候选色 —— 此时没有
/// "面板底色"这个概念，硬套一个只会把普通页面上的颜色改错。
abstract final class GlassPanelTextColor {
  /// 解析 [candidate]（省略时用主题的 `onSurfaceVariant`），保证它在这块面板上可读。
  ///
  /// [fallbacks] 是读不清时的候选回退色，默认给一组语义色。
  /// [minimumContrast] 默认按正文阈值；图标/边框传 [accessibleUiMinContrast]。
  static Color resolve(
    BuildContext context, {
    Color? candidate,
    List<Color>? fallbacks,
    double minimumContrast = accessibleTextMinContrast,
  }) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final surface = GlassPanelScope.surfaceColorOf(context);
    final wanted = candidate ?? scheme.onSurfaceVariant;
    if (surface == null) return wanted;
    return resolveTextColorOnSurface(
      candidate: wanted,
      surface: surface,
      fallbacks: fallbacks ??
          // 回退序列：先是正文色（同底色下一定最可读），再用极端色兜底。
          // 不用 `onBackground`：它自 v3.18 起已废弃、并入 `onSurface`。
          <Color>[scheme.onSurface, scheme.inverseSurface, scheme.scrim],
      minimumContrast: minimumContrast,
    );
  }
}

/// 卡片面板：统一的圆角、底色与可选描边，外加一个"这块面板有多亮"的作用域。
///
/// **这里已经不画玻璃了。** 为什么收掉：g1455 那套实时采样在我们这种
/// "桌面窗口 + 接近纯色的页面背景"下，三种做法各有各的坏处 ——
/// ① 真采背景（`GlassSurface`）：它一屏只录**一张**共享降采样图、且录在
/// post-frame 回调里，天生比内容晚一帧，滚动时上一帧的标题/图标会硬边地浮进卡片
/// （tint alpha 只有 .22 的磨砂/超透尤其明显）；② 把材质色合成成不透明色：
/// 卡片就是一块死纯色，页面背景完全透不过来；③ 留半透明 tint + 高光：只有
/// 衬在满屏彩色背景上才好看，而本仓库的页面背景是刻意压平的。
///
/// 所以卡片底色回到主题自己的面：调用点给 [solidColor] 就用它（各页原本的观感），
/// 否则用 [AppSurfaceTokens.closedSurface]。设置里的材质/染色/渲染随之停用，
/// 决策与验收标准记在 `docs/ui-polish.md`。
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.borderRadius,
    this.solidColor,
    this.margin,
    this.padding,
    this.border,
    this.pageBackground,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 卡片底色。省略时用 [AppSurfaceTokens.closedSurface]。
  /// 各页原来的卡片底色不尽相同，传进来可以保持各页原本的观感。
  final Color? solidColor;

  /// 外边距 / 内边距。各页原来的卡片是 `Container(margin:, padding:)` 画的，
  /// 这里接住这两个，替换时布局才不会变。
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 额外描边（例如选中项的主色边框）。
  ///
  /// **不传时给一圈极淡的 [ColorScheme.outlineVariant]**：参考图的卡片是靠
  /// 「1px 极浅边 + 一丝投影」和页面底分开的，而不是靠明度差硬拉。原来的
  /// 「零海拔、零描边」在纯白卡片压在近白页面上时，边界几乎读不出来。
  final BorderSide? border;

  /// 面板下方页面画布的底色，仅用于**推算可读性**（见 [GlassPanelScope]）。
  ///
  /// 不传时用 `scaffoldBackgroundColor` 兜底。它不参与任何绘制，
  /// 所以给得不精确也只会让兜底判定偏保守，不会影响观感。
  final Color? pageBackground;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final brightness = Theme.of(context).brightness;
    // 面板下面的那层底色：只用来推算可读性，不参与绘制。
    final pageCanvas = pageBackground ??
        (Theme.of(context).scaffoldBackgroundColor.a > 0
            ? Theme.of(context).scaffoldBackgroundColor
            : scheme.surface);
    final panelSurface =
        solidColor ?? AppSurfaceTokens.closedSurface(scheme, brightness);
    // 判定文字可读性要用**不透明**的等效色。
    final textSurface = opaqueCompositeOver(panelSurface, pageCanvas);
    return GlassPanelScope(
      surfaceColor: textSurface,
      child: Container(
        margin: margin,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: panelSurface,
          borderRadius: borderRadius,
          border: Border.fromBorderSide(
            border ?? BorderSide(color: scheme.outlineVariant),
          ),
          // 一丝投影：参考图的卡片是"浮"在页面上的，不是画上去的。
          // 亮色用 4% 黑（再重就会在纯白卡片周围糊出一圈灰），深色下底色本来就黑，
          // 用高一点的不透明度才有同样的"离地"感。
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: brightness == Brightness.dark ? .22 : .04,
              ),
              blurRadius: 2,
              offset: const Offset(0, 1),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}
