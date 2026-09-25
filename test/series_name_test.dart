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

    // 真实标题里的集数标记几乎不在末尾：后面还跟着副标题和 `[中文字幕]` 之类的标签。
    // 旧实现把集数锚定在字符串结尾，这批标题一律识别失败，弹窗只能显示
    // 「未能从标题中识别系列名称」，分组名退回整个标题。
    test('集数标记后面还有副标题和字幕标签时也能识别', () {
      expect(inferSeriesName('Tentacle and Witches ～第2話 プールの水で濡れてるんだから！～ [中文字幕]'), 'Tentacle and Witches');
      expect(inferSeriesName('人付き合いが苦手な亡人少女さんと呪いの指輪 【第01話】[中文字幕]'), '人付き合いが苦手な亡人少女さんと呪いの指輪');
    });

    test('卷标（上巻/下巻/前編/後編）也算集数标记', () {
      // 成人动画常用分卷写法，标题里没有「第N話」，只有末尾的「上巻」。
      // 用户真实下载里就有这条：分组原本退回整个标题，系列名该是去掉上巻的前缀。
      expect(
        inferSeriesName('ピュアホリック ～純潔乙女と婚姻カンケイ!?～THE ANIMATION 上巻 [中文字幕]'),
        'ピュアホリック ～純潔乙女と婚姻カンケイ!?～THE ANIMATION',
      );
      expect(inferSeriesName('某系列 上巻'), '某系列');
      expect(inferSeriesName('某系列 後編'), '某系列');
    });

    test('只有字幕标签、没有集数标记时不算系列', () {
      // 剥掉 [中文字幕] 不等于剥掉了集数：这类单片不该被硬凑成一个系列。
      expect(inferSeriesName('ビュアホリック ～純潔乙女と婚姻カンケイ!?～ [中文字幕]'), isNull);
      expect(inferSeriesName('単発タイトル [中文字幕]'), isNull);
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
