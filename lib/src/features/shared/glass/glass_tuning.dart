/// 设置里的三个玻璃维度 → g1455 参数。
///
/// 单独成一个文件是为了让这张对照表**能被测到**：`GlassHost` 那一处调用点在
/// widget 树最深处，拿它做断言要起整个应用；这里都是纯函数，直接断言输入输出。
///
/// 三个维度都落在同一个 `GlassHost` 上 —— g1455 把它们定义成**整屏级**的东西：
/// 层级决定"要不要为这一屏做那次全屏捕获"，捕获是共享的，所以只能整屏选；
/// 波纹与对比度则是 host 上的"这一屏的默认值"，每块玻璃仍可自己覆盖。
library;

import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

import '../../../core/app_surface_tokens.dart';
import '../../../core/settings.dart';

/// 把设置里的波纹档位翻成 g1455 的参数；关闭档给 null（= 不起波纹）。
///
/// 四档**只改 viscosity**：g1455 的文档说它是"多数应用唯一需要的旋钮 ——
/// 0 是水，会一圈圈荡开；1 是蜂蜜，只有一坨慢慢鼓起来"。其余参数
/// （amplitude / speed / width / press / pressRadius / light）保持包的默认值，
/// 因为那是作者"按眼睛定的、没有参照可量"的一组数，我们没有更好的依据去动它。
///
/// - `water` → 0.15（水，会荡开）
/// - `jelly` → 包自己的默认 0.6（果冻，也正是 g1455 演示页默认选中的那档）
/// - `honey` → 0.95（蜂蜜，一坨慢鼓）
///
/// 两个端点的数值直接取包自己的文档示例（`references/foundations/ripple.md` 里
/// 水的例子是 0.15、蜂蜜是 0.95），不是我们编的；中间那档就用包的默认值。
GlassRipple? glassRippleFor(GlassRippleKind kind) => switch (kind) {
  GlassRippleKind.off => null,
  GlassRippleKind.water => const GlassRipple(viscosity: .15),
  GlassRippleKind.jelly => const GlassRipple(),
  GlassRippleKind.honey => const GlassRipple(viscosity: .95),
};

/// 把设置里的层级档位翻成 `GlassTierPolicy` 的 `pinned`；`auto` 给 null。
///
/// null 的意思是"不钉任何档"：g1455 会按 `GlassTierChoice.byDefault` 走完整档，
/// 系统开了「减少透明度」时它自己会落到 opaque。
GlassTier? glassPinnedTier(GlassTierMode mode) => switch (mode) {
  GlassTierMode.auto => null,
  GlassTierMode.full => GlassTier.full,
  GlassTierMode.cheap => GlassTier.cheap,
  GlassTierMode.opaque => GlassTier.opaque,
};

/// 这一屏实际该用哪一档。
///
/// **系统说「减少透明度」时不给 pinned** —— g1455 的 `choose()` 是
/// `pinned → reduceTransparency → ceiling` 的顺序，也就是说 pinned 会盖掉那条
/// 可访问性请求。那是用户为了**能看清东西**才开的开关，不该被应用里的一个
/// 下拉框默默推翻（Apple 自己的 Reduce Transparency 也是应用盖不掉的）。
/// 所以设置里的档位只在系统没提这个要求时生效。
GlassTierChoice glassTierChoice({required GlassTierMode mode, required bool reduceTransparency}) =>
    GlassTierPolicy(
      pinned: reduceTransparency ? null : glassPinnedTier(mode),
      reduceTransparency: reduceTransparency,
    ).choose();

/// 设置里的对比度档位 → `GlassHost.highContrast`。
///
/// `system` 传的是**我们自己读到的**系统值，而不是 null：g1455 的 null 表示
/// "去读 `MediaQuery.highContrastOf`"，而引擎只在 iOS 与 Android 34+ 上设置它，
/// **Windows 上永远是 false** —— 照原样交给它，等于"跟随系统"这一档在 Windows 上
/// 永远跟不出来。所以由调用方读注册表，读不到就当没开。
bool? glassHighContrastFor(GlassContrast contrast, {required bool systemHighContrast}) =>
    switch (contrast) {
      GlassContrast.auto => systemHighContrast,
      GlassContrast.increased => true,
    };

/// 设置里的玻璃染色 → 玻璃 tint 要用的**颜色**；`neutral` 返回 null。
///
/// null 的意思是「别动材质自己的 tint」：g1455 那两个 `.regular` 的 tint 是按真机材质
/// 校准过的（`regularDark` 是 `rgba(29,29,32,0.693)`，`glass_finish.dart:368`），拿我们的
/// 表面色去替掉它只会让玻璃偏离作者量过的工作点。只有选了带色的两档才换掉 RGB。
///
/// 靛蓝/玫瑰的色值是**我们的取舍**：演示站 Tint 那三档拿不到（站点是 Flutter web，
/// HTML 只是静态大纲、GitHub 又限流）。所以取 Material 两个基准色，向表面色靠一半 ——
/// 既看得出偏色，又不至于艳到盖过内容。
Color? glassTintColorFor(GlassTintKind kind, ColorScheme scheme) => switch (kind) {
  GlassTintKind.neutral => null,
  GlassTintKind.indigo =>
    Color.lerp(scheme.surfaceContainerLow, const Color(0xff3f51b5), .5),
  GlassTintKind.rose =>
    Color.lerp(scheme.surfaceContainerLow, const Color(0xffc2185b), .5),
};

/// 设置里的质感 / 染色 → g1455 的 `GlassFinish`。
///
/// | 本仓库 | g1455 | 依据 |
/// |---|---|---|
/// | `frosted` | `GlassFinish.frosted`，tint 换成本仓库的表面色、alpha 取滑条 | 两边同名同义（糊得最狠）；但包给的 tint 是近白 `rgba(249,249,249,.22)`，压在我们这个近黑页面上会变成一块浅灰面板。本仓库的磨砂一直是「表面色 + 可调浓度」，滑条调的就是那个浓度 |
/// | `liquid` | `GlassFinish.regular(appearance:)` | 我们要的「完整玻璃」就是 Apple 的 `.regular`：按明暗自己挑深浅，且带折射 |
/// | `off` | 不走到这里 | 关闭档在 `GlassPanel` 里已提前返回纯色分支，这里给中性值仅为穷尽 switch |
///
/// **为什么磨砂的 tint 必须在这里从滑条推**：g1455 的 tint 是玻璃唯一决定「呈现什么
/// 颜色」的入口（着色器按 `mix(背景, tint, tint.a)` 叠上去，`glass_finish.dart:566-573`）。
/// 换成 g1455 渲染之后，`glassSurfaceOpacity` 一度只喂给「文字可读性推算」，滑条就不再
/// 影响观感 —— 实测磨砂档在 20% 与 100% 下**画面逐像素完全相同**。现在它回到真正画
/// 玻璃的那条路上。
GlassFinish glassFinishFor({
  required GlassQuality quality,
  required Brightness brightness,
  required ColorScheme scheme,
  required double opacity,
  required GlassTintKind tint,
}) {
  final chosen = glassTintColorFor(tint, scheme);
  switch (quality) {
    case GlassQuality.frosted:
      return GlassFinish.frosted.copyWith(
        tint: (chosen ?? AppSurfaceTokens.glassTint(scheme)).withValues(
          alpha: opacity.clamp(0.0, 1.0),
        ),
      );
    case GlassQuality.liquid:
      final regular = GlassFinish.regular(
        appearance: brightness == Brightness.dark ? Brightness.dark : Brightness.light,
      );
      // 只换 RGB、保留材质自己的 alpha —— 那个 alpha 是它校准过的浓度。
      return chosen == null
          ? regular
          : regular.copyWith(tint: chosen.withValues(alpha: regular.tint.a));
    case GlassQuality.off:
      return GlassFinish.frosted;
  }
}
