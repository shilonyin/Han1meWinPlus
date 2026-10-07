import 'package:flutter/material.dart';

/// 玻璃材质的**语义底色**规范层。
///
/// ## 这个模块收什么、不收什么
///
/// 只收**有规则**的语义：一个值要按明暗、档位或调用场景推导出来，
/// 且散落在多处、彼此必须一致时才值得收在这里。
///
/// 它**不是** `ColorScheme` 的转发层。像 `surfaceContainerLow` 这样
/// 「取某一档就是某一档」的读取，直读 `colorScheme` 已经足够清楚，
/// 再包一层同名访问器不产生任何信息，只会让"改语义"看起来集中了、
/// 实际只是改了个名字。本仓库只有一套 Material 3 主题，没有第二套
/// 风格需要桥接，所以不存在上游 `AppSurfaceTokens` 那种桥接理由。
///
/// 目前收录的三块，共同点是**玻璃体系的既定规则**：
/// [closedSurface]、[glassTint]、[glassModeCardBase]。
abstract final class AppSurfaceTokens {
  /// 关闭玻璃档时，卡片浮在背景画布上的半透明底色。
  ///
  /// 玻璃档的卡片由 `GlassMaterial` 按档位浓度自己画底；关闭档没有那套材质，
  /// 就用一层半透明的 `surface` 顶替 —— 透出一点底下的渐变，卡片才有"材质感"，
  /// 否则整屏会退化成一片没有色调的灰白（这正是本仓库当初引入背景画布的原因）。
  ///
  /// 深浅两档不同：深色下背景本身很暗，卡片再透就会糊成一片，所以给得实一些。
  ///
  /// 这个值原先在 `GlassPanel` 里**写了两遍**（一处判定可读性、一处实际绘制），
  /// 两处必须一致才不会出现"判定用的底色和画出来的底色不同"。
  ///
  /// 参数收 [Brightness] 而不是 `bool dark`：取 62% 还是 72% 完全由明暗决定，
  /// 调用方传 `Theme.of(context).brightness` 即可，不必自己先比一次
  /// —— 多一次"自己判断"就多一处可能和别处判断不一致的地方。
  static Color closedSurface(ColorScheme scheme, Brightness brightness) =>
      scheme.surface.withValues(
        alpha: brightness == Brightness.dark ? .62 : .72,
      );

  /// 玻璃面板的默认底色。
  ///
  /// 调用方没传 `GlassPanel.tint` 时用它。选 `surfaceContainerLow` 而不是 `surface`：
  /// 玻璃内部还有一层按档位浓度叠上的 tint，底色再取最亮的 surface，
  /// 亮色主题下会糊成一片没有层次的浅色。
  static Color glassTint(ColorScheme scheme) => scheme.surfaceContainerLow;

  /// 质感选择卡片（设置页那几张 关闭 / 磨砂 / 液体玻璃）的底色。
  ///
  /// 未选中时用半透明的 `surface`：它自己就是"预览材质"的卡片，
  /// 底色比周围淡一档才不会把上面的图标与文字压住。
  ///
  /// 注意它和 [closedSurface] **取值不同**（.5 对 .72），这不是笔误：
  /// 质感卡片是紧挨着的几个小方块，比大块卡片更需要透出背景，
  /// 所以刻意比关闭档的卡片更淡。
  static Color glassModeCardBase(ColorScheme scheme) =>
      scheme.surface.withValues(alpha: .5);

  /// 各档玻璃的浓度**不在这里**。
  ///
  /// 原来这里有一张 `densityFor(quality, opacity)` 表，把三档各记一个浓度，
  /// 用来把面板压成等效底色好判断文字可读性。换成 g1455 之后那张表成了**平行的
  /// 第二份真相**：它把「液体玻璃」记成 .55，而材质真实的 tint alpha 是
  /// .693（深）/ .718（浅），于是"判定用的底色"和真的画出来的玻璃并不一致。
  ///
  /// 现在浓度只有一个来源 —— 材质自己的 `finish.tint`：档位怎么定浓度写在
  /// `glassFinishFor`（`features/shared/glass/glass_tuning.dart`）里，
  /// 需要等效底色的地方直接读 `finish.tint`。删除这张表是那次合并的一部分。
}
