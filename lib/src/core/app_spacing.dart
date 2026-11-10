import 'package:flutter/material.dart';

/// 全应用统一的间距规范层，与 [AppRadius] 的分档思路一致。
///
/// 之前设置页 6 种行距（2.5/3/4/5/10/20）各自散在页面里。
/// 同一个「行」在主题页 40、播放页 44、布局页 56，疏密不一。
/// 间距和圆角一样，应该按语义收在一处，页面只引用令牌。
///
/// 分档按**用途**而不是数值：同一用途在任何页面都用同一档。
abstract final class AppSpacing {
  /// 微间距（4）：图标与文字、标题与副标题、chip 内边距。
  static const double xs = 4;

  /// 小间距（8）：相邻控件、分隔线两侧、紧凑列表行内。
  static const double sm = 8;

  /// 中间距（12）：卡片标题与内容、按钮组之间。
  static const double md = 12;

  /// 标准间距（16）：卡片内边距、行左右留白。
  static const double lg = 16;

  /// 大间距（24）：卡片与卡片之间、分区之间。
  static const double xl = 24;

  /// 特大间距（40）：页首大卡、整块分区的上下留白。
  static const double xxl = 40;

  /// 便捷形式，省得每处写 `EdgeInsets.all(...)`。
  static EdgeInsets all(double value) => EdgeInsets.all(value);
  static Widget height(double value) => SizedBox(height: value);
  static Widget width(double value) => SizedBox(width: value);
}

/// 把 num 变成间距 widget / EdgeInsets，写法收敛到一处。
///
/// 与 flutter_beautiful_ui 的 `SizeExtension on num` 同思路：
/// `12.heightBox`、`16.allPadding` 这种写法在页面里出现时，语义仍然来自
/// [AppSpacing] 的分档（调用点写 `AppSpacing.md.heightBox`），不引入新的裸数值。
extension AppSpacingNum on num {
  Widget get heightBox => SizedBox(height: toDouble());
  Widget get widthBox => SizedBox(width: toDouble());
  EdgeInsets get allPadding => EdgeInsets.all(toDouble());
  EdgeInsets get horizontalPadding =>
      EdgeInsets.symmetric(horizontal: toDouble());
  EdgeInsets get verticalPadding => EdgeInsets.symmetric(vertical: toDouble());
}
