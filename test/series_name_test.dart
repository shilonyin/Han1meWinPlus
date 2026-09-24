import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/domain/series_name.dart';

void main() {
  group('inferSeriesName', () {
    test('剥掉常见集数标记', () {
      expect(inferSeriesName('某系列 第1話'), '某系列');
      expect(inferSeriesName('某系列 第12话'), '某系列');
      expect(inferSeriesName('某系列 #3'), '某系列');
      expect(inferSeriesName('某系列 Vol.4'), '某系列');
      expect(inferSeriesName('某系列 Part 5'), '某系列');
      expect(inferSeriesName('某系列 (6)'), '某系列');
      expect(inferSeriesName('某系列【7】'), '某系列');
      expect(inferSeriesName('某系列_2'), '某系列');
      expect(inferSeriesName('某系列 Ⅳ'), '某系列');
    });

    test('没有集数标记时判定为非系列', () {
      expect(inferSeriesName('独立标题'), isNull);
      expect(inferSeriesName(''), isNull);
      expect(inferSeriesName(null), isNull);
    });

    test('不会把标题削到只剩一两个字', () {
      // 剥完只剩 1 个字符，视为不可靠，保留原样判定为非系列。
      expect(inferSeriesName('A 1'), isNull);
    });

    test('标题本身就是系列名时不误判', () {
      expect(inferSeriesName('系列名'), isNull);
    });
  });

  group('suggestGroupName', () {
    test('关闭系列名来源时用影片标题', () {
      expect(suggestGroupName(title: '影片A 第1話', seriesName: '影片A', useSeriesName: false), '影片A 第1話');
    });

    test('开启系列名来源时优先系列名', () {
      expect(suggestGroupName(title: '影片A 第1話', seriesName: '影片A', useSeriesName: true), '影片A');
    });

    test('推断不出系列名时回退到影片标题', () {
      expect(suggestGroupName(title: '独立标题', seriesName: null, useSeriesName: true), '独立标题');
    });
  });

  group('toTraditionalForGroupName', () {
    test('转换高频简体字', () {
      expect(toTraditionalForGroupName('动画'), '動畫');
      expect(toTraditionalForGroupName('网络'), '網絡');
    });

    test('保留未收录字、英文数字与标点', () {
      expect(toTraditionalForGroupName('ABC 123 - テスト'), 'ABC 123 - テスト');
    });
  });
}
