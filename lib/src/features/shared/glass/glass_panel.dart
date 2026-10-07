import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';

import '../../../core/app_surface_tokens.dart';
import '../../../core/color_contrast.dart';
import '../../../core/settings.dart';
import '../../settings/settings_controller.dart';
import 'glass_tuning.dart';

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
    this.ripple,
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

  /// 触摸时表面起的波纹（g1455 的 `GlassRipple`）。`null` = 不起波纹。
  ///
  /// **什么时候真的能看到它** —— 这条比"要不要开"更容易搞错：
  /// 波纹要求玻璃**自己收到 pointer**，而 `GlassSurface.hitTest` 只在
  /// **没命中子节点**时才把自己加进命中结果。于是：
  ///
  /// - 玻璃下铺满整块可点区域（`InkWell` 包住整行）→ 永远命中子节点
  ///   → **波纹永远不触发**。主应用的设置项卡片正是这种。
  /// - 玻璃下是纯展示内容（顶部只有一两个按钮、其余是文字/图形）
  ///   → 点在非按钮处都能触发。
  ///
  /// 反过来它**不会**抢走内容的点击：只有 `!hit` 时才接管，而且它只监听
  /// pointer、不参与手势竞技场。
  ///
  /// g1455 另外建议只用在**无文字**的大块玻璃上：有文字时它要按
  /// `minLabelContrast` 把玻璃压暗，波纹会跟着变淡。
  final GlassRipple? ripple;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final quality = glassEnabled
        ? (settings?.glassQuality ?? GlassQuality.off)
        : GlassQuality.off;
    final opacity = settings?.glassSurfaceOpacity ?? .72;
    final scheme = Theme.of(context).colorScheme;
    // 明暗**只读一次**：下面的关闭档底色与档位映射都由它推导，
    // 两处不可能分叉（原先关闭档那个表达式在"判定可读性"和"实际绘制"
    // 各写了一遍，改一处忘一处就会让两者不一致）。
    final brightness = Theme.of(context).brightness;
    // 关闭档的卡片底色。判定可读性与实际绘制都取它 —— 以前同一个表达式写在
    // 两个地方，改一处忘一处就会让"判定用的底色"和"画出来的底色"从此不同。
    final closedSurface = solidColor ??
        AppSurfaceTokens.closedSurface(scheme, brightness);

    // 这一档玻璃究竟长什么样：**只在这里定一次**。
    //
    // 换成 g1455 渲染之后，"面板呈现什么颜色"由材质自己的 `tint` 决定（着色器按
    // `mix(背景, tint, tint.a)` 叠），不再由我们算一个浓度出来。所以等效底色也改成
    // 直接读 `finish.tint` —— 原来那张平行的 `densityFor` 表会漂移（它把「液体玻璃」
    // 记成 .55，而材质真实的 alpha 是 .693/.718），现在它已经不在了。
    final panelTint = tint;
    final material = glassFinishFor(
      quality: quality,
      brightness: brightness,
      scheme: scheme,
      opacity: opacity,
      tint: settings?.glassTint ?? GlassTintKind.neutral,
    );
    // 面板自己指定底色时**只换 RGB**：调用处给的是"什么颜色"，不是"多浓"，
    // 浓度属于档位（磨砂由滑条定、液体玻璃由材质定）。
    final finish = panelTint == null
        ? material
        : material.copyWith(tint: panelTint.withValues(alpha: material.tint.a));

    // 面板实际呈现的不透明底色：关闭档是"实色底（或半透明 surface）"，
    // 玻璃档是"材质 tint 按它自己的 alpha 合成"。
    final canvas = pageBackground ??
        (Theme.of(context).scaffoldBackgroundColor.a > 0
            ? Theme.of(context).scaffoldBackgroundColor
            : scheme.surface);
    final panelSurface = quality == GlassQuality.off
        ? opaqueCompositeOver(closedSurface, canvas)
        : glassSurfaceColor(tint: finish.tint, opacity: 1, background: canvas);

    // 降级层级：与材质档正交。`full` 时材质档原样生效；降级只**绕过背景捕获**，
    // 只剩「关闭档」需要在这里特殊处理：g1455 的两个维度里**没有"关闭"**
    // （它只有材质 finish 与层级 tier）。用户明确选了关闭，就老老实实走纯色底，
    // 不去建一块没有内容的玻璃。
    if (quality == GlassQuality.off) {
      return GlassPanelScope(
        surfaceColor: panelSurface,
        child: Container(
          margin: margin,
          padding: padding,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            // 半透明卡片浮在背景画布上：透出一点底下的渐变，卡片才有"材质感"。
            color: closedSurface,
            borderRadius: borderRadius,
            border: border == null ? null : Border.fromBorderSide(border!),
          ),
          child: child,
        ),
      );
    }
    // 换成 g1455 的 `GlassSurface`：整个包共用一个 `GlassHost` 录制全屏一次，
    // 这块面板取自己那一格 —— 真折射、真模糊、真亮边，且静止时不重新录制。
    //
    // 它是**原始图元**：不像 `GlassCard` 那样自带默认内边距与标签着色，
    // 所以这里自己决定内边距（padding 在玻璃内部、margin 在外，与原来一致）。
    //
    // `BorderSide` 它没有对应参数（它只有自带的 rim）。用外层 `DecoratedBox`
    // 画边框，而不是丢掉 —— 选中态的主色描边靠它表达。
    final glass = GlassSurface(
      borderRadius: borderRadius,
      finish: finish,
      // 有文字落在上面，允许它为了 `minLabelContrast` 压暗。
      labelled: true,
      ripple: ripple,
      child: padding == null ? child : Padding(padding: padding!, child: child),
    );
    final panel = border == null
        ? glass
        : DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: borderRadius,
              border: Border.fromBorderSide(border!),
            ),
            child: glass,
          );
    return GlassPanelScope(
      surfaceColor: panelSurface,
      child: margin == null ? panel : Padding(padding: margin!, child: panel),
    );
  }
}
