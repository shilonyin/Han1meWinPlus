import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/app_surface_tokens.dart';
import '../../../core/color_contrast.dart';
import '../../../core/glass_tier.dart';
import '../../../core/settings.dart';
import '../../settings/settings_controller.dart';
import 'liquid_glass.dart';

/// 把"这块面板实际呈现的不透明底色"告知子树。
///
/// 为什么需要它：玻璃面板是半透明的，它到底呈现什么颜色取决于底下的页面画布
/// 与当前质感档位。子树里的文字要保证可读，就得知道自己压在多亮的底上 ——
/// 而这个值只有 [GlassPanel] 算得出来（它才知道 tint / 档位 / 不透明度）。
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

/// 在玻璃面板上解析一个**保证可读**的文字/图标色。
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

/// 按「玻璃质感」设置渲染的面板：关闭档走纯色底，其余档走对应的玻璃材质。
///
/// 抽出来是为了让质感**全局统一** —— 设置页左栏的分组卡片、右栏的条目卡片、
/// 以及其他地方的卡片都用它，改档位时整个界面一起变，
/// 而不是只有用了 `LiquidGlassSurface` 的那一处变。
class GlassPanel extends ConsumerWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint,
    this.solidColor,
    this.margin,
    this.padding,
    this.glassEnabled = true,
    this.border,
    this.pageBackground,
    this.reduceTransparency = false,
    this.tierCeiling,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 玻璃底色。省略时用 `surfaceContainerLow`。
  final Color? tint;

  /// 关闭档（`GlassQuality.off`）用的纯色底。省略时用半透明的 `surface`
  /// —— 各页原来的卡片底色不尽相同，传进来可以让"关闭"档保持各页原本的观感。
  final Color? solidColor;

  /// 外边距 / 内边距。各页原来的卡片是 `Container(margin:, padding:)` 画的，
  /// 这里接住这两个，替换时布局才不会变。
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 为 `false` 时即使开着玻璃也走纯色底。
  /// 用于列表里的选中项这类**需要突出显示**的场合（玻璃会把选中态的色块冲淡）。
  final bool glassEnabled;

  /// 额外描边（例如选中项的主色边框）。
  final BorderSide? border;

  /// 面板下方页面画布的底色，仅用于**推算可读性**（见 [GlassPanelScope]）。
  ///
  /// 不传时用 `scaffoldBackgroundColor` 兜底。它不参与任何绘制，
  /// 所以给得不精确也只会让兜底判定偏保守，不会影响观感。
  final Color? pageBackground;

  /// 系统的「减少透明度」开关，由应用读好后传进来。
  ///
  /// **Flutter 不暴露这个设置**（`MediaQuery` 里没有对应字段），所以只能外部传。
  /// 这里特意不接受 `highContrast`：那个开关要的是**边界清晰**，不是**别透**，
  /// 拿它去关掉玻璃是答错了题。高对比度该由描边处理，不该改材质层级。
  final bool reduceTransparency;

  /// 这台机器能承受的最高玻璃层级。`null` 表示不设上限。
  ///
  /// 低端机上给 [GlassTier.cheap]，玻璃仍在但不再捕获背景。见 [resolveGlassTier]。
  final GlassTier? tierCeiling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final quality = glassEnabled
        ? (settings?.glassQuality ?? GlassQuality.off)
        : GlassQuality.off;
    final opacity = settings?.glassSurfaceOpacity ?? .72;
    final scheme = Theme.of(context).colorScheme;
    // 明暗**只读一次**：下面的关闭档底色与 LiquidGlassSurface 都由它推导，
    // 两处不可能分叉（原先关闭档那个表达式在"判定可读性"和"实际绘制"
    // 各写了一遍，改一处忘一处就会让两者不一致）。
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final glassTint = tint ?? AppSurfaceTokens.glassTint(scheme);
    // 关闭档的卡片底色。判定可读性与实际绘制都取它 —— 以前同一个表达式写在
    // 两个地方，改一处忘一处就会让"判定用的底色"和"画出来的底色"从此不同。
    final closedSurface = solidColor ??
        AppSurfaceTokens.closedSurface(scheme, brightness);

    // 面板实际呈现的不透明底色：关闭档是"实色底（或半透明 surface）"，
    // 玻璃档是"tint 按该档浓度合成"。
    //
    // 磨砂档的浓度直接取 `glassSurfaceOpacity` 滑条值 —— 与
    // `GlassMaterial.densityFor` 同源，两边不会漂移。
    final canvas = pageBackground ??
        (Theme.of(context).scaffoldBackgroundColor.a > 0
            ? Theme.of(context).scaffoldBackgroundColor
            : scheme.surface);
    final panelSurface = quality == GlassQuality.off
        ? opaqueCompositeOver(closedSurface, canvas)
        : glassSurfaceColor(
            tint: glassTint,
            opacity: GlassMaterial.densityFor(quality, opacity),
            background: canvas,
          );

    // 降级层级：与材质档正交。`full` 时材质档原样生效；降级只**绕过背景捕获**，
    // 材质档本身不动 —— 条件恢复后立刻回到用户的选择。
    //
    // 三级各自的画法（照 g1455 的 tiers）：
    // - `full`   ：真玻璃，捕获背景、模糊、折射。
    // - `cheap`  ：**同形状 + 同边框**，把该档的等效底色直接铺上，不模糊不折射。
    //              它填的是「关闭」与「磨砂」之间的空档：用户想要形状与底色，
    //              但不想要背景采样。g1455 给它的用法之一正是「全玻璃 bar 底下
    //              一长串卡片」—— 设置页右栏就是那个结构。
    // - `opaque` ：铺一个不透明实色。系统「减少透明度」要的就是这个。
    //
    // 「减少透明度」只能外部传入：Flutter 的 MediaQuery 没有这个字段。
    // 刻意不用 `highContrastOf` 代替 —— 那个开关要的是边界清晰（该用描边解决），
    // 不是别透，拿它关玻璃是答错了题。
    final tierChoice = resolveGlassTier(
      reduceTransparency: reduceTransparency,
      ceiling: tierCeiling,
    );

    // 关闭档与非 full 层级都**不需要捕获背景**。三条分支共用一个绘制骨架，
    // 差别只在铺什么颜色 —— 这样「降级的是成本，不是形状」在代码里就是显然的。
    if (quality == GlassQuality.off || !tierChoice.readsBackdrop) {
      final Color fill;
      if (quality == GlassQuality.off) {
        // 关闭档维持原样：半透明底，让卡片透出画布的渐变。
        fill = closedSurface;
      } else if (tierChoice.tier == GlassTier.opaque) {
        // 不透明档：铺该档玻璃叠在画布上的**等效实色**，一点都不透。
        fill = panelSurface;
      } else {
        // 省捕获档：**保留该档玻璃的底色浓度**（所以仍会透出一点背景），
        // 只是不再模糊、不再折射 —— 省掉的是背景捕获，不是材质的浓淡。
        fill = glassTint.withValues(
          alpha: GlassMaterial.densityFor(quality, opacity),
        );
      }
      return GlassPanelScope(
        surfaceColor: opaqueCompositeOver(fill, canvas),
        child: Container(
          margin: margin,
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: fill,
            borderRadius: borderRadius,
            border: border == null ? null : Border.fromBorderSide(border!),
          ),
          child: child,
        ),
      );
    }
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border == null ? null : Border.fromBorderSide(border!),
      ),
      child: LiquidGlassSurface(
        tint: glassTint,
        dark: dark,
        borderRadius: borderRadius,
        material: GlassMaterial.quality(
          quality: quality,
          tint: glassTint,
          dark: dark,
          readable: false,
          borderRadius: borderRadius,
          opacity: opacity,
        ),
        // padding 在玻璃**内部**（内容距边缘），margin 在外。
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
    return GlassPanelScope(
      surfaceColor: panelSurface,
      child: margin == null ? panel : Padding(padding: margin!, child: panel),
    );
  }
}
