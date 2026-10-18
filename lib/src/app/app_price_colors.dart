import 'package:flutter/material.dart';

/// 价格的文字色。
///
/// 取 Getchu 站方自己的价格色：`master_soft20160107.css` 里 `.redb` 与
/// `.redb2` 都是 `color:#C00; font-weight:700`。列表卡片、详情页标签行、
/// 基本信息卡片三处价格统一走这里 —— 价格是整套界面里唯一用红色的东西，
/// 扫一眼就能定位，也跟站点自己的观感对得上。
///
/// 暗色下不能直接沿用 `#C00`：它压在 `#141A26` 的卡片上对比度只有 2.9:1，
/// 低于正文要求的 4.5:1。同色相提亮到 `#FF6B6B` 后是 6.2:1，仍是同一个红。
abstract final class AppPriceColors {
  /// 亮色：站点原色。
  static const Color light = Color(0xFFCC0000);

  /// 暗色：同色相提亮，保证在深色卡片上仍读得清。
  static const Color dark = Color(0xFFFF6B6B);

  /// 按明暗取价格色。收 [Brightness] 而不是 `bool dark`，与
  /// `AppPageColors.of` 保持同一个取法。
  static Color of(Brightness brightness) =>
      brightness == Brightness.dark ? dark : light;
}
