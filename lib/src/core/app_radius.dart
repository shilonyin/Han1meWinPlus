import 'package:flutter/material.dart';

/// 全应用统一的圆角规范层。
///
/// 收拢之前散在 34 个文件里的 15 种圆角值（2/4/6/8/10/12/14/15/16/18/22/24/28/40/999）。
/// 那些值大多不是设计选择，而是各页面各自随手写的：设置卡片用 8、库页用 12、
/// 作者页用 22/28、账号页用 40 —— 同一个「卡片」在三处是三个数。
///
/// ## 分档依据
///
/// 按**元素尺寸**分档，而不是按页面分：圆形半径在视觉上不是绝对值，是相对元素高度的
/// 比例。8 的圆角放在 40px 高的 chip 上是「药丸」，放在 300px 宽的卡片上几乎看不出。
/// 所以这里按元素从大到小给五档，同尺寸的元素在应用任何地方都该用同一档。
///
/// 不做「把所有圆角都改成同一个值」——那会让大卡片显得方正、小控件显得臃肿，
/// 反而更乱。这里只保证**同尺寸即同值**。
abstract final class AppRadius {
  /// 微元素（2~6px 级）：进度条、色块、小角标、封面内的细节描边。
  static const double xs = 6;

  /// 小元素（8~10px 级）：封面切口、缩略图、紧凑卡片、菜单项。
  ///
  /// [videoCardRadius] 也归在这一档（封面是 8）。
  static const double sm = 10;

  /// 中元素（12~14px 级）：列表行、设置卡片、下拉、浮层提示。
  static const double md = 12;

  /// 大元素（16~18px 级）：内容卡片、对话框里的分组、面板。
  static const double lg = 16;

  /// 特大元素（20~24px 级）：对话框、底部弹层、整块面板。
  static const double xl = 24;

  /// 全圆（药丸）：chip、标签、开关滑块。
  static const double pill = 999;

  /// 给 [BorderRadius] 用的便捷形式，省得每处都写 `BorderRadius.circular(...)`。
  static BorderRadius all(double value) => BorderRadius.circular(value);
}
