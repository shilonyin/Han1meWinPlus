/// 半透明面板上的颜色对比度兜底策略层。
///
/// 这个模块存在的理由：本应用大量使用半透明玻璃面板
/// （见 `features/shared/glass/glass_panel.dart` 与 `liquid_glass.dart`），
/// 文字直接躺在半透明底上。半透明意味着"文字实际压在多亮的底色上"取决于
/// 底下的页面画布，而主题种子色、明暗模式、玻璃质感档位、玻璃不透明度都会
/// 改动这个结果 —— 于是同一处文字换个主题或换档质感就可能忽然读不清。
///
/// 这里移植 BiliPai（Android/Compose 端）的 `ThemeContrastPolicy.kt`，
/// 只保留**纯函数策略**：给定底色与候选文字色，算出保证 WCAG 对比度的文字色。
/// 不碰 `BuildContext`、不碰任何 widget、不引入新依赖，所以可以直接单测，
/// 也可以在任何拿得到颜色的地方（含非 UI 代码）复用。
///
/// 为什么亮度用 [Color.computeLuminance] 而不是自己写 sRGB → 线性转换：
/// 它本身就是 WCAG 的相对亮度（含 gamma 展开与 0.2126/0.7152/0.0722 加权），
/// 与 Compose 的 `luminance()` 口径一致；重写一遍只会引入偏差。
library;

import 'package:flutter/material.dart';

/// 正文文字的最小对比度：WCAG AA 对正文的要求。
const double accessibleTextMinContrast = 4.5;

/// UI 元素（图标、边框、分割线、开关等非正文）的最小对比度：WCAG AA 对非文字的要求。
///
/// 比正文宽松是有意的：图形轮廓只要"看得见"即可，不需要像小字那样"读得准"。
const double accessibleUiMinContrast = 3.0;

/// 两个颜色的 WCAG 对比度，取值 1.0（亮度相同）～ 21.0（纯黑对纯白）。
///
/// 与 BiliPai 的 `calculateContrastRatio` 完全等价：只比亮度，**忽略 alpha**。
/// 想按"用户看到的颜色"比，先用 [opaqueCompositeOver] 把半透明色合成掉。
double contrastRatio(Color foreground, Color background) {
  final a = foreground.computeLuminance();
  final b = background.computeLuminance();
  final lighter = a > b ? a : b;
  final darker = a > b ? b : a;
  return (lighter + 0.05) / (darker + 0.05);
}

/// [foreground] 压在 [background] 上是否达到 [minimumContrast]。
///
/// 单独留一个判定函数，是为了让调用点读起来是"够不够"而不是"算出来比一下"；
/// 判定 UI 元素时传 [accessibleUiMinContrast]。
bool meetsContrast(
  Color foreground,
  Color background, {
  double minimumContrast = accessibleTextMinContrast,
}) => contrastRatio(foreground, background) >= minimumContrast;

/// 把半透明 [foreground] 合成到 [background] 上，返回用户真正看到的**不透明**色。
///
/// 对比度必须拿"眼睛看到的颜色"来算：`Colors.white70` 压在深色玻璃上，
/// 观感远低于把它的 RGB 直接当纯白算出来的结果。
///
/// 返回值的 alpha 恒为 1；当前景与背景都完全透明时不存在"看到的颜色"，
/// 返回 [Colors.transparent] 让调用方自己决定怎么处理（而不是凭空造一个黑）。
Color opaqueCompositeOver(Color foreground, Color background) {
  final fa = foreground.a;
  final ba = background.a;
  final outAlpha = fa + ba * (1 - fa);
  if (outAlpha <= 0) return Colors.transparent;
  return Color.from(
    alpha: 1,
    red: (foreground.r * fa + background.r * ba * (1 - fa)) / outAlpha,
    green: (foreground.g * fa + background.g * ba * (1 - fa)) / outAlpha,
    blue: (foreground.b * fa + background.b * ba * (1 - fa)) / outAlpha,
  );
}

/// 单一回退版：候选色达标就用它，否则用 [fallback]。
///
/// 对应 BiliPai 的 `resolveReadableTextColor`。只有一档回退时用这个，
/// 调用点不必为了一个元素包一层列表。
Color resolveReadableTextColor({
  required Color candidate,
  required Color background,
  required Color fallback,
  double minimumContrast = accessibleTextMinContrast,
}) => meetsContrast(candidate, background, minimumContrast: minimumContrast)
    ? candidate
    : fallback;

/// 把 [candidate] 的**明度**朝远离底色的一侧推，直到对比度达到 [minimumContrast]。
///
/// 这是兜底的**首选**手段，但**只针对"差一点"的情况**。
///
/// 为什么需要它：玻璃面板上的次要文字（`onSurfaceVariant`）在浅色玻璃上
/// 实测只有 4.2 左右，够不到 4.5。如果直接把它换成 `onSurface`，对比度确实
/// 达标了（11 左右），但**次要文字与正文变成了同一个颜色，主次层次被抹平**
/// —— 那不是修好了，是换了一种坏法。压明度只动"亮多少"，保留色相与饱和度，
/// 所以次要文字仍然是次要的样子，只是足够清楚了。
///
/// 为什么必须设 [closeEnoughRatio] 这道门槛：压明度是"微调"，不是"换色"。
/// 黑字压在深色玻璃上时，压明度会得到一块中灰（对比度刚好达标但观感发灰），
/// 而那里真正该做的是换成白色的语义回退色。实测这种场景的候选对比度只有
/// 1.4 左右，远低于门槛；而需要微调的次要文字有 4.2（门槛为 4.5×0.85≈3.83）。
/// 所以用"候选离达标线有多近"来区分"该微调"还是"该换色"。
///
/// 方向按底色亮度选：底子亮就往深里压，底子暗就往亮里提。沿途用二分逼近，
/// 停在刚好达标的附近，不做多余的加深（过度加深会显得比正文还重，同样破坏层次）。
///
/// 不满足前提（离达标线太远、或连明度极值都够不到）时返回 `null`，
/// 由调用方退回语义色。
Color? darkenOrLightenToContrast(
  Color candidate,
  Color background, {
  double minimumContrast = accessibleTextMinContrast,
  double closeEnoughRatio = .85,
  int steps = 24,
}) {
  final opaque = candidate.withValues(alpha: 1);
  final current = contrastRatio(opaque, background);
  if (current >= minimumContrast) return opaque;
  // 差得太远：候选色本身不适合这个底色，微调只会得到一个发灰的怪色，
  // 交给调用方换语义色更干净。
  if (current < minimumContrast * closeEnoughRatio) return null;

  final hsl = HSLColor.fromColor(opaque);
  final goDarker = background.computeLuminance() > 0.5;

  final extreme = goDarker ? 0.0 : 1.0;
  final far = hsl.withLightness(extreme).toColor();
  // 连极值都够不到（底色本身太极端），交给调用方回退。
  if (contrastRatio(far, background) < minimumContrast) return null;

  // 沿明度轴二分：先确认极值达标，再往"离极值更远"的方向收到刚好达标处。
  var best = far;
  var lo = 0.0;
  var hi = 1.0;
  for (var i = 0; i < steps; i++) {
    final mid = (lo + hi) / 2;
    final l = hsl.lightness + (extreme - hsl.lightness) * mid;
    final probe = hsl.withLightness(l.clamp(0.0, 1.0)).toColor();
    if (contrastRatio(probe, background) >= minimumContrast) {
      best = probe;
      hi = mid;
    } else {
      lo = mid;
    }
  }
  return best;
}

/// 多回退版：候选色达标就用它；否则**先尝试压明度**（保留色相与主次层次），
/// 再依序取 [fallbacks] 里第一个达标的；全都到不了时返回对比度最高的那个，
/// 并强制 `alpha = 1`。
///
/// 达标就原样返回，不做任何"顺手规整一下"的动作：已经可读的颜色被替换掉，
/// 主题里精心调过的色阶就被抹平了。只有走到兜底分支才强制不透明 ——
/// 半透明文字会透出底色，算出来的对比度并不等于观感，
/// 既然已经要兜底，就给出一个确定可见的结果。
///
/// 兜底顺序为什么是"先压明度、再换语义色"：换语义色（如把次要文字换成
/// `onSurface`）虽然一定达标，但会让次要文字与正文同色、丢掉层次；
/// 压明度只改"多亮"，保住色相与饱和度，是更小的一步改动。
///
/// 与 BiliPai 的一处差异：它在全不达标时直接退回候选色，这里改为在
/// "候选 + 回退"里挑对比度最高的。既然回退列表本来就是按"更该可读"排的，
/// 挑最高的那个至少不会比候选更差。
Color resolveReadableThemeTextColor({
  required Color candidate,
  required Color background,
  required List<Color> fallbacks,
  double minimumContrast = accessibleTextMinContrast,
}) {
  if (meetsContrast(candidate, background, minimumContrast: minimumContrast)) {
    return candidate;
  }
  // 首选：只推明度，保住色相与主次层次。
  final nudged = darkenOrLightenToContrast(
    candidate,
    background,
    minimumContrast: minimumContrast,
  );
  if (nudged != null) return nudged;
  for (final fallback in fallbacks) {
    if (meetsContrast(fallback, background, minimumContrast: minimumContrast)) {
      return fallback;
    }
  }

  var best = candidate;
  var bestRatio = contrastRatio(candidate, background);
  for (final fallback in fallbacks) {
    final ratio = contrastRatio(fallback, background);
    if (ratio > bestRatio) {
      best = fallback;
      bestRatio = ratio;
    }
  }
  return best.withValues(alpha: 1);
}

/// **已经拿到等效底色时的主入口**：给定"面板呈现的不透明底色"与候选文字色，
/// 返回保证对比度的文字色。
///
/// 与 [resolveGlassTextColor] 的分工：那个负责"把玻璃参数压成等效底色"，
/// 这个只管"在已知底色上挑文字色"。需要反复按同一底色解析多处文字时
/// （例如一块面板上的正文、次要文字、图标），先算一次底色再多次调用它，
/// 比每次重算一遍合成更省，也不会出现两处底色算得不一样的情况。
///
/// 候选与回退都会先合成到 [surface] 上再比对比度，所以半透明文字色
/// （例如 `Colors.white70`）按真实观感评估，返回的颜色必定不透明。
Color resolveTextColorOnSurface({
  required Color candidate,
  required Color surface,
  List<Color> fallbacks = const <Color>[],
  double minimumContrast = accessibleTextMinContrast,
}) => resolveReadableThemeTextColor(
  candidate: opaqueCompositeOver(candidate, surface),
  background: surface,
  fallbacks: <Color>[
    for (final fallback in fallbacks) opaqueCompositeOver(fallback, surface),
  ],
  minimumContrast: minimumContrast,
);

/// 玻璃面板的**不透明**等效色。
///
/// [tint] 是玻璃底色（`GlassPanel.tint`），[opacity] 是玻璃的不透明度
/// （设置里的 `glassSurfaceOpacity`），[background] 是玻璃下方的页面底色。
/// 玻璃本身是半透明的，它到底呈现什么颜色取决于底下画着什么；
/// 要判断"面板上的字读不读得清"，就得先把它压成一个不透明色。
Color glassSurfaceColor({
  required Color tint,
  required double opacity,
  required Color background,
}) {
  final effectiveAlpha = (tint.a * opacity).clamp(0.0, 1.0).toDouble();
  return opaqueCompositeOver(
    tint.withValues(alpha: effectiveAlpha),
    background,
  );
}

/// 玻璃面板颜色解析：把 [tint] + [opacity] 压成等效底色，再在它上面挑文字色。
///
/// 参数直接对应 `GlassPanel` 的构造方式：
/// - [tint]：玻璃底色（`GlassPanel.tint`，缺省是 `surfaceContainerLow`）；
/// - [opacity]：玻璃的不透明度（设置项 `glassSurfaceOpacity`）；
/// - [pageBackground]：玻璃**下方**的页面底色（背景画布）；
/// - [candidate]：原本想用的文字色；
/// - [fallbacks]：读不清时依序尝试的颜色，一般给主题语义色
///   （`onSurface` → `inverseSurface` → `scrim`）；
/// - [minimumContrast]：正文用默认的 [accessibleTextMinContrast]，
///   图标/边框这类非正文元素传 [accessibleUiMinContrast]。
///
/// 需要自己画面板底色、又要在面板上写字的地方，用
/// [resolveGlassPanelColors] 一次拿两个值，省得把同一套合成参数写两遍
/// （写两遍迟早会不一致，那正是对比度失守的开始）。
Color resolveGlassTextColor({
  required Color candidate,
  required Color tint,
  required double opacity,
  required Color pageBackground,
  List<Color> fallbacks = const <Color>[],
  double minimumContrast = accessibleTextMinContrast,
}) => resolveTextColorOnSurface(
  candidate: candidate,
  surface: glassSurfaceColor(
    tint: tint,
    opacity: opacity,
    background: pageBackground,
  ),
  fallbacks: fallbacks,
  minimumContrast: minimumContrast,
);

/// 玻璃面板一次解析出来的两个颜色：不透明等效底色 + 保证可读的文字色。
@immutable
class GlassPanelColors {
  const GlassPanelColors({required this.surfaceColor, required this.textColor});

  /// 面板压在页面底色上之后的不透明等效色。
  final Color surfaceColor;

  /// 面板上保证对比度的文字色（不透明）。
  final Color textColor;
}

/// [resolveGlassTextColor] 的"连底色一起给我"版本。
///
/// 需要自己画面板底色、又要在面板上写字的地方用它，省得调用方把同一套合成
/// 参数写两遍（写两遍迟早会不一致，那正是对比度失守的开始）。
GlassPanelColors resolveGlassPanelColors({
  required Color candidate,
  required Color tint,
  required double opacity,
  required Color pageBackground,
  List<Color> fallbacks = const <Color>[],
  double minimumContrast = accessibleTextMinContrast,
}) => GlassPanelColors(
  surfaceColor: glassSurfaceColor(
    tint: tint,
    opacity: opacity,
    background: pageBackground,
  ),
  textColor: resolveGlassTextColor(
    candidate: candidate,
    tint: tint,
    opacity: opacity,
    pageBackground: pageBackground,
    fallbacks: fallbacks,
    minimumContrast: minimumContrast,
  ),
);
