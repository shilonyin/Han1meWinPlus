import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// 预告卡片网格的尺寸计算：窗口变窄时减少列数；窗口够高时把卡片压小，
/// 让一屏里至少露出 [minRows] 排。
class PreviewGridMetrics {
  const PreviewGridMetrics({required this.columns, required this.cardWidth, required this.itemHeight});

  final int columns;
  final double cardWidth;
  final double itemHeight;

  static const double horizontalPadding = 16;
  static const double spacing = 12;

  /// 按宽度算列数时的最小卡片宽度。
  static const double _minCardWidth = 190;

  /// 按高度反推列数时，卡片再小也不低于这个宽度 —— 否则窗口一矮，
  /// 列数会顶到 [maxColumns]，卡片小到看不清标题。
  static const double _minColumnWidthForRows = 120;

  /// [coverRatio] 是封面高度 / 封面宽度，[detailsHeight] 是封面下方信息区的固定高度。
  ///
  /// [minRows] 是一屏里希望至少放下的排数。只看宽度时，宽窗口下卡片会被撑得很高，
  /// 一排就占满一屏；这里再按视口高度反推列数，把卡片压小。
  /// [reservedHeight] 留给网格上方的标题、月份条等固定内容。
  factory PreviewGridMetrics.of(
    BoxConstraints constraints, {
    required double coverRatio,
    required double detailsHeight,
    int minRows = 1,
    int maxColumns = 4,
    double reservedHeight = 0,
  }) {
    final usable = math.max(constraints.maxWidth - horizontalPadding * 2, _minCardWidth);
    var columns = math.min(((usable + spacing) / (_minCardWidth + spacing)).floor(), maxColumns);

    final viewport = constraints.maxHeight - reservedHeight;
    if (minRows > 1 && viewport.isFinite && viewport > 0) {
      // 要让 minRows 排都露出来，每张卡片最多能有多高，再换算成对应的卡片宽度。
      final rowBudget = (viewport - spacing * (minRows - 1)) / minRows;
      final coverHeight = rowBudget - detailsHeight;
      if (coverHeight > 0) {
        final widthBudget = math.max(coverHeight / coverRatio, _minColumnWidthForRows);
        // 取上整，保证每列宽度不超过 widthBudget。
        final needed = ((usable + spacing) / (widthBudget + spacing)).ceil();
        columns = math.max(columns, math.min(needed, maxColumns));
      }
    }

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
