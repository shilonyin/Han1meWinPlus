/// 设置里的三个玻璃维度 → g1455 参数。
///
/// 单独成一个文件是为了让这张对照表**能被测到**：`GlassHost` 那一处调用点在
/// widget 树最深处，拿它做断言要起整个应用；这里都是纯函数，直接断言输入输出。
///
/// 三个维度都落在同一个 `GlassHost` 上 —— g1455 把它们定义成**整屏级**的东西：
/// 层级决定"要不要为这一屏做那次全屏捕获"，捕获是共享的，所以只能整屏选；
/// 波纹与对比度则是 host 上的"这一屏的默认值"，每块玻璃仍可自己覆盖。
library;

import 'package:g1455/g1455.dart';

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
