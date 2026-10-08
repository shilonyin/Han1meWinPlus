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
/// 目前只收录一块：关闭玻璃档时卡片该铺什么底。
/// 另外两块（玻璃默认底色、质感卡片底色）随「主题模式」面板重做一起删掉了 ——
/// 前者是 `surfaceContainerLow` 的直接转发（本模块开篇就说了不收转发），
/// 后者只服务那几张已经不在的图标卡片。
abstract final class AppSurfaceTokens {
  /// 滑块在**深色底**上的轨道配色。
  ///
  /// 播放器控制条、投屏接收页这类界面自己铺了深色底，滑块却由全局主题给出底色：
  /// 浅色主题下 `inactiveTrackColor` 落在白底附近，压到深色控制条上几乎看不见。
  /// 所以这几处必须显式盖一套白色轨道，不能只在全局 `sliderTheme` 里改 ——
  /// 那样会把设置页、漫画页这些浅底界面一起拖黑。
  ///
  /// 进度条只画已播轨（不画 `inactiveTrackColor`），音量条两条轨都要看得见。
  static const SliderThemeData darkTrackTheme = SliderThemeData(
    activeTrackColor: Colors.white,
    inactiveTrackColor: Colors.white24,
    thumbColor: Colors.white,
  );

  /// 深色底上**带档位**的滑块：除了白轨道，还要把档位气泡自己补一套。
  ///
  /// 气泡的底色本来由滑块外观版本决定，而全局外观版本已经不再钉（见 `app_theme`），
  /// 这里显式给成反色，换个全局默认也不会看不清。
  static SliderThemeData darkDiscreteTrackTheme(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return darkTrackTheme.copyWith(
      valueIndicatorColor: theme.colorScheme.inverseSurface,
      valueIndicatorTextStyle:
          theme.textTheme.labelLarge!.copyWith(color: theme.colorScheme.onInverseSurface),
    );
  }

  /// 关闭玻璃档时，卡片浮在背景画布上的半透明底色。
  ///
  /// 玻璃档的卡片由材质档位自己画底；关闭档没有那套材质，
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

  /// 各档玻璃的浓度**不在这里**。
  ///
  /// 原来这里有一张 `densityFor(quality, opacity)` 表，把三档各记一个浓度，
  /// 用来把面板压成等效底色好判断文字可读性。换成 g1455 之后那张表成了**平行的
  /// 第二份真相**：它把「液体玻璃」记成 .55，而材质真实的 tint alpha 是
  /// .693（深）/ .718（浅），于是"判定用的底色"和真的画出来的玻璃并不一致。
  ///
  /// 现在浓度只有一个来源 —— 材质自己的 tint；后来玻璃材质整层退役（改用
  /// Material 3 自己的面），这一层连"哪种料什么浓度"都不必再判断了。
  /// 删除这张表是那次合并的一部分。
}
