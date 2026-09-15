import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 预告卡片网格的尺寸计算：一排最多 4 个，窗口变窄时自动减少列数。
class PreviewGridMetrics {
  const PreviewGridMetrics({required this.columns, required this.cardWidth, required this.itemHeight});

  final int columns;
  final double cardWidth;
  final double itemHeight;

  static const double horizontalPadding = 16;
  static const double spacing = 12;
  static const int maxColumns = 4;
  static const double _minCardWidth = 190;

  /// [coverRatio] 是封面高度 / 封面宽度，[detailsHeight] 是封面下方信息区的固定高度。
  factory PreviewGridMetrics.of(BoxConstraints constraints, {required double coverRatio, required double detailsHeight}) {
    final usable = math.max(constraints.maxWidth - horizontalPadding * 2, _minCardWidth);
    final columns = math.min(((usable + spacing) / (_minCardWidth + spacing)).floor(), maxColumns);
    final cardWidth = (usable - spacing * (columns - 1)) / columns;
    return PreviewGridMetrics(columns: columns, cardWidth: cardWidth, itemHeight: cardWidth * coverRatio + detailsHeight);
  }

  SliverGridDelegate get delegate => SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisSpacing: spacing,
        crossAxisSpacing: spacing,
        mainAxisExtent: itemHeight,
      );
}
