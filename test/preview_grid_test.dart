import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/previews/preview_grid.dart';

/// 一屏能放下几排卡片：按网格实际占用的高度算，别用估算。
int rowsThatFit(PreviewGridMetrics metrics, double viewportHeight) {
  final usable = viewportHeight + PreviewGridMetrics.spacing;
  return (usable / (metrics.itemHeight + PreviewGridMetrics.spacing)).floor();
}

void main() {
  group('窗口够高时压小卡片，保证露出两排', () {
    test('1920x1080 窗口下 Getchu 页至少露出两排', () {
      // 逻辑尺寸：1280 宽去掉侧栏 64、左右内边距；高度去掉标题栏与月份条。
      const constraints = BoxConstraints.tightFor(width: 1216, height: 600);
      final metrics = PreviewGridMetrics.of(
        constraints,
        coverRatio: 4 / 3,
        detailsHeight: 60,
        minRows: 2,
        maxColumns: 8,
        reservedHeight: 44,
      );

      expect(rowsThatFit(metrics, 556), greaterThanOrEqualTo(2), reason: '一屏只露一排就还是老问题');
      expect(metrics.columns, greaterThan(4), reason: '不增加列数就压不小卡片');
    });

    test('窗口更矮时列数跟着增加，卡片继续变小', () {
      const tall = BoxConstraints.tightFor(width: 1216, height: 900);
      const short = BoxConstraints.tightFor(width: 1216, height: 480);
      final a = PreviewGridMetrics.of(tall, coverRatio: 4 / 3, detailsHeight: 60, minRows: 2, maxColumns: 8);
      final b = PreviewGridMetrics.of(short, coverRatio: 4 / 3, detailsHeight: 60, minRows: 2, maxColumns: 8);

      expect(b.columns, greaterThanOrEqualTo(a.columns));
      expect(b.itemHeight, lessThanOrEqualTo(a.itemHeight));
    });
  });

  group('不会把卡片压到看不清', () {
    test('极矮窗口下列数封顶在 maxColumns', () {
      const constraints = BoxConstraints.tightFor(width: 1600, height: 200);
      final metrics = PreviewGridMetrics.of(constraints, coverRatio: 4 / 3, detailsHeight: 60, minRows: 2, maxColumns: 8);

      expect(metrics.columns, lessThanOrEqualTo(8));
      expect(metrics.cardWidth, greaterThan(0));
    });

    test('高度无界时不按高度反推，退回按宽度算', () {
      const constraints = BoxConstraints(maxWidth: 1600);
      final metrics = PreviewGridMetrics.of(constraints, coverRatio: 4 / 3, detailsHeight: 60, minRows: 2, maxColumns: 8);

      // 纯按宽度：(1600 - 32 + 12) / (190 + 12) = 7.82 → 7 列。
      expect(metrics.columns, 7);
      expect(metrics.itemHeight, closeTo(metrics.cardWidth * 4 / 3 + 60, 0.01));
    });
  });

  group('minRows 为 1 时行为不变', () {
    test('宽窗口下仍是按最小卡片宽度算出来的列数', () {
      const constraints = BoxConstraints.tightFor(width: 1216, height: 600);
      final metrics = PreviewGridMetrics.of(constraints, coverRatio: 16 / 9, detailsHeight: 40);

      expect(metrics.columns, 4);
      expect(metrics.itemHeight, closeTo(metrics.cardWidth * 16 / 9 + 40, 0.01));
    });
  });

  group('窄窗口', () {
    test('宽度不足时列数降到 1，卡片不出现负宽', () {
      const constraints = BoxConstraints.tightFor(width: 150, height: 600);
      final metrics = PreviewGridMetrics.of(constraints, coverRatio: 4 / 3, detailsHeight: 60, minRows: 2, maxColumns: 8);

      expect(metrics.columns, greaterThanOrEqualTo(1));
      expect(metrics.cardWidth, greaterThan(0));
    });
  });
}
