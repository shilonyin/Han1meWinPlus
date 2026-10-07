/// 设置里的几个玻璃维度 → g1455 参数。
///
/// 单独成一个文件是为了让这张对照表**能被测到**：`GlassHost` 那一处调用点在
/// widget 树最深处，拿它做断言要起整个应用；这里都是纯函数，直接断言输入输出。
///
/// 对照表本身照抄 g1455 演示站的控制面板
/// （`g1455-0.1.4/example/lib/src/style.dart`）—— 那一页就是作者自己摆出来的
/// 权威档位表，连枚举名和色值都是他定的，我们没有理由另编一套。
library;

import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

import '../../../core/settings.dart';

/// 一组玻璃设置。预设就是「给某组取值起个名字」，所以两者用同一个类型。
typedef GlassRecipe = ({
  GlassMaterial material,
  GlassTintKind tint,
  GlassRendering rendering,
  GlassRippleKind ripple,
  GlassContrast contrast,
});

/// 四档预设各自是什么，顺序与演示站一致（从最费到最省）。
///
/// `ultra` 多出来的只有波纹 —— 演示站对它的说明就是「手指底下有波纹的液体玻璃」；
/// 另外三档的说明分别是「iOS 画出来的那种液体玻璃」「叠在背景上的 tint，什么都不捕获」
/// 「一块不透明填充，背后什么都看不见」，正好对应 `rendering` 那三档。
const Map<GlassPresetKind, GlassRecipe> glassPresetRecipes = {
  GlassPresetKind.ultra: (
    material: GlassMaterial.regular,
    tint: GlassTintKind.neutral,
    rendering: GlassRendering.glass,
    ripple: GlassRippleKind.jelly,
    contrast: GlassContrast.auto,
  ),
  GlassPresetKind.high: (
    material: GlassMaterial.regular,
    tint: GlassTintKind.neutral,
    rendering: GlassRendering.glass,
    ripple: GlassRippleKind.off,
    contrast: GlassContrast.auto,
  ),
  GlassPresetKind.medium: (
    material: GlassMaterial.regular,
    tint: GlassTintKind.neutral,
    rendering: GlassRendering.translucent,
    ripple: GlassRippleKind.off,
    contrast: GlassContrast.auto,
  ),
  GlassPresetKind.low: (
    material: GlassMaterial.regular,
    tint: GlassTintKind.neutral,
    rendering: GlassRendering.opaque,
    ripple: GlassRippleKind.off,
    contrast: GlassContrast.auto,
  ),
};

/// 把设置里的那几项收成一份配方，便于和预设比。**不含外观** ——
/// 演示站算预设时也是先把外观归一掉再比的（外观不属于玻璃本身）。
GlassRecipe glassRecipeOf(AppSettings settings) => (
  material: settings.glassMaterial,
  tint: settings.glassTint,
  rendering: settings.glassRendering,
  ripple: settings.glassRipple,
  contrast: settings.glassContrast,
);

/// 这份配方正好等于哪一档预设；都不等就是自定义（null）。
///
/// 预设不落盘，每次都由实际设置反推 —— 手改了任意一项就变成自定义，
/// 改回去预设又回来。演示站就是这么做的。
GlassPresetKind? glassPresetFor(GlassRecipe recipe) {
  for (final entry in glassPresetRecipes.entries) {
    if (entry.value == recipe) return entry.key;
  }
  return null;
}

/// 把设置里的波纹档位翻成 g1455 的参数；关闭档给 null（= 不起波纹）。
///
/// 三档**只改 viscosity**，取值直接照抄演示站：`water` 0、`jelly` .5、`honey` 1。
/// 其余参数（amplitude / speed / width / press / pressRadius / light）保持包的默认值，
/// 因为那是作者"按眼睛定的、没有参照可量"的一组数，我们没有更好的依据去动它。
///
/// g1455 的文档说 viscosity 是"多数应用唯一需要的旋钮：**0 是水**，会一圈圈荡开；
/// **1 是蜂蜜**，只有一坨慢慢鼓起来"。
GlassRipple? glassRippleFor(GlassRippleKind kind) => switch (kind) {
  GlassRippleKind.off => null,
  GlassRippleKind.water => const GlassRipple(viscosity: 0),
  GlassRippleKind.jelly => const GlassRipple(viscosity: .5),
  GlassRippleKind.honey => const GlassRipple(viscosity: 1),
};

/// 把设置里的渲染层级翻成 `GlassTierPolicy` 的 `pinned`。
GlassTier glassPinnedTier(GlassRendering rendering) => switch (rendering) {
  GlassRendering.glass => GlassTier.full,
  GlassRendering.translucent => GlassTier.cheap,
  GlassRendering.opaque => GlassTier.opaque,
};

/// 这一屏实际该用哪一档。
///
/// **系统说「减少透明度」时不给 pinned** —— g1455 的 `choose()` 是
/// `pinned → reduceTransparency → ceiling` 的顺序，也就是说 pinned 会盖掉那条
/// 可访问性请求。那是用户为了**能看清东西**才开的开关，不该被应用里的一个
/// 下拉框默默推翻（Apple 自己的 Reduce Transparency 也是应用盖不掉的）。
/// 所以设置里的档位只在系统没提这个要求时生效。
///
/// 演示站的 `tierChoice` 没做这件事（它直接 `pinned: rendering.tier`），
/// 这一处我们**故意不照抄**。
GlassTierChoice glassTierChoice({
  required GlassRendering rendering,
  required bool reduceTransparency,
}) => GlassTierPolicy(
  pinned: reduceTransparency ? null : glassPinnedTier(rendering),
  reduceTransparency: reduceTransparency,
).choose();

/// 设置里的对比度档位 → `GlassHost.highContrast`。
///
/// `system` 传的是**我们自己读到的**系统值，而不是 null：g1455 的 null 表示
/// "去读 `MediaQuery.highContrastOf`"，而引擎只在 iOS 与 Android 34+ 上设置它，
/// **Windows 上永远是 false** —— 照原样交给它，等于"跟随系统"这一档在 Windows 上
/// 永远跟不出来。所以由调用方读注册表，读不到就当没开。
bool? glassHighContrastFor(
  GlassContrast contrast, {
  required bool systemHighContrast,
}) => switch (contrast) {
  GlassContrast.auto => systemHighContrast,
  GlassContrast.increased => true,
};

/// 设置里的玻璃染色 → 玻璃 tint 要用的**颜色**；`neutral` 返回 null。
///
/// null 的意思是「别动材质自己的 tint」：g1455 那两个 `.regular` 的 tint 是按真机材质
/// 校准过的（`regularDark` 是 `rgba(29,29,32,0.693)`，`glass_finish.dart:368`），拿我们的
/// 表面色去替掉它只会让玻璃偏离作者量过的工作点。只有选了带色的两档才换掉 RGB。
///
/// 两个色值直接取演示站的 `TintChoice`（`style.dart`）：靛蓝 `0xFF28348C`、
/// 玫瑰 `0xFF962850`。
Color? glassTintColorFor(GlassTintKind kind) => switch (kind) {
  GlassTintKind.neutral => null,
  GlassTintKind.indigo => const Color(0xFF28348C),
  GlassTintKind.rose => const Color(0xFF962850),
};

/// 设置里的材质 / 染色 → g1455 的 `GlassFinish`。
///
/// 材质那五档是包按真机**校准过**的常数，所以这里只做"挑一块"，从不自己拼：
/// `regular` 交给 `GlassFinish.regular(appearance:)` 按明暗挑（深色下即 `regularDark`），
/// 其余四档按名字取。换料**不碰** tint。
///
/// 只有选了带色的两档才覆盖 tint，而且只换 RGB、保留材质自己的 alpha ——
/// 那个 alpha 是它校准过的浓度（`.regular` 是 .693/.718，`.frosted` 是 .22）。
GlassFinish glassFinishFor({
  required GlassMaterial material,
  required GlassTintKind tint,
  required Brightness brightness,
}) {
  final chosen = glassTintColorFor(tint);
  final base = switch (material) {
    GlassMaterial.regular => GlassFinish.regular(appearance: brightness),
    GlassMaterial.dark => GlassFinish.regularDark,
    GlassMaterial.light => GlassFinish.regularLight,
    GlassMaterial.clear => GlassFinish.clear,
    GlassMaterial.frosted => GlassFinish.frosted,
  };
  return chosen == null
      ? base
      : base.copyWith(tint: chosen.withValues(alpha: base.tint.a));
}
