import 'package:flutter/material.dart';

/// 页面底色：**照 g1455 演示站的两个主题来**。
///
/// 这两个值不是我调出来的，是从官方产物里取的：
///
/// - 暗色 `#070A12` 是演示站自己的 `manifest.json` 里 `background_color` 与
///   `theme_color`（PWA 的启动底色通常就等于应用底色，两个字段一致）；
/// - 亮色 `#F2F2F7` 是官方文档 `foundations/legibility.md` 里 `LightPanel.page`
///   的取值，配的注释是 "A light settings panel inside a dark app" ——
///   也就是 Apple 的 iOS light `systemGroupedBackground`。
///
/// **两个都是中性色**（一个蓝黑、一个中性浅灰），这是关键：g1455 的材质 tint
/// 本身是中性灰 `rgba(29,29,32,.693)`，底色一旦自带彩度，玻璃抽出来的每一块
/// 都会跟着偏色，而且和材质自己的灰打架。演示站的颜色来自内容（封面图、
/// 彩色卡片），不来自底色。
///
/// 亮暗两档分别对应 `AppBackdrop` 的画布基色与 `GlassHost.backdrop`
/// （给玻璃上的文字选黑/白、以及给不透明档填色用）。三处必须同源，
/// 否则会出现「文字按 A 色挑、实际画在 B 色上」这类判定与实际不符的问题。
abstract final class AppPageColors {
  /// 暗色底：近黑的蓝黑。
  static const Color dark = Color(0xFF070A12);

  /// 亮色底：中性浅灰。
  static const Color light = Color(0xFFF2F2F7);

  /// 按明暗取底色。参数收 [Brightness] 而不是 `bool dark`：调用方传
  /// `Theme.of(context).brightness` 即可，不必自己先比一次 ——
  /// 多一次"自己判断"就多一处可能和别处判断不一致的地方。
  static Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
