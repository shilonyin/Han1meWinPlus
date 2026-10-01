// 回归测试：控制栏底部按钮行的对齐。
//
// 背景（用户报的现象）：底部按钮行「对齐不对」——右侧按钮不贴右缘。
//
// 演进过程（每一步都实测过，别凭直觉改回去）：
//  1. 原始写法：时间文本固定宽 + Spacer。按钮贴右，但**窄窗口下溢出**
//     （画中画 380px 窗里按钮 + 时间文本要 440px，必然 RenderFlex overflow）。
//  2. 9/28 改动：时间文本包进 Flexible(flex:1)。窄窗口能收缩了，但它与
//     Spacer(flex:1) 会**平分**剩余空间，于是宽窗口下整行铺不满、按钮离开右缘
//     —— 实测 1000 逻辑像素时偏 130.8px，就是用户看到的「对齐不对」。
//  3. 现在：时间文本固定宽度（不参与 flex）+「Expanded + Align 右对齐 +
//     横向可滚动」，宽窗口贴右、极窄窗口按钮组自己滚动。
//
// 本文件同时做两件事：
//  A. 用复刻骨架量化三种写法的差异（Flexible 写法偏 130.8px 的证据）；
//  B. **直接读生产源码**断言 VideoPlayerControls 里时间文本没有被 Flexible 包住
//     —— 复刻骨架只能证明「理论上如此」，改坏了生产代码它照样绿，
//     所以必须有 B 这类直接盯着生产文件的断言（变异验证过：把生产代码改回
//     Flexible 时 B 会红）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 时间文本（固定宽度，不参与 flex）。
Widget _time(String tag) => Padding(
  key: ValueKey('time-$tag'),
  padding: const EdgeInsets.symmetric(horizontal: 6),
  child: const Text('00:08 / 25:19', maxLines: 1, overflow: TextOverflow.ellipsis),
);

Widget _rightButtons(String tag) => Row(
  mainAxisSize: MainAxisSize.min,
  children: [
    SizedBox(width: 48, key: ValueKey('a-$tag')),
    SizedBox(width: 48, key: ValueKey('b-$tag')),
    SizedBox(width: 48, key: ValueKey('last-$tag')),
  ],
);

Widget _row({required String tag, required double width, required bool flexibleTime, required bool expandedRight}) {
  return SizedBox(
    width: width,
    child: Row(
      key: ValueKey('row-$tag'),
      children: [
        const SizedBox(width: 48),
        const SizedBox(width: 48),
        if (flexibleTime) Flexible(child: _time(tag)) else _time(tag),
        if (expandedRight)
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                reverse: true,
                child: _rightButtons(tag),
              ),
            ),
          )
        else ...[
          const Spacer(),
          _rightButtons(tag),
        ],
      ],
    ),
  );
}

Widget _host(double width) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        _row(tag: 'legacy', width: width, flexibleTime: false, expandedRight: false),
        _row(tag: 'flex', width: width, flexibleTime: true, expandedRight: false),
        _row(tag: 'expanded', width: width, flexibleTime: false, expandedRight: true),
      ],
    ),
  ),
);

double _gap(WidgetTester tester, String tag) =>
    tester.getRect(find.byKey(ValueKey('row-$tag'))).right - tester.getRect(find.byKey(ValueKey('last-$tag'))).right;

void main() {
  group('A. 布局量化（复刻骨架）', () {
    testWidgets('宽窗口：按钮贴右缘（legacy 与 expanded 都该贴右）', (tester) async {
      await tester.pumpWidget(_host(1000));
      expect(_gap(tester, 'legacy'), lessThan(1.0), reason: '原始写法：Spacer 把按钮推到右缘');
      expect(_gap(tester, 'expanded'), lessThan(1.0), reason: '现有写法：Expanded + Align 右对齐');
    });

    testWidgets('宽窗口：Flexible 写法让按钮离开右缘（回归防护）', (tester) async {
      await tester.pumpWidget(_host(1000));
      expect(
        _gap(tester, 'flex'),
        greaterThan(50),
        reason: 'Flexible 与 Spacer 平分剩余空间 → 整行铺不满 → 按钮离开右缘（实测 130.8px）',
      );
    });

    testWidgets('极窄窗口：legacy 会溢出，expanded 不溢出', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Column(children: [_row(tag: 'legacy', width: 380, flexibleTime: false, expandedRight: false)]))),
      );
      expect(tester.takeException(), isNotNull, reason: '原始写法在 380px 下应溢出（这正是 9/28 改动要解决的问题）');

      await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Column(children: [_row(tag: 'expanded', width: 380, flexibleTime: false, expandedRight: true)]))),
      );
      expect(tester.takeException(), isNull, reason: '现有写法：按钮组自己横向滚动，不撑破这一行');
    });
  });

  group('B. 生产代码结构（直接读 VideoPlayerControls 源码）', () {
    late String source;

    setUpAll(() {
      source = File('lib/src/features/video/video_player_controls.dart').readAsStringSync();
    });

    /// 取底部按钮行那一段源码（从 row 变量定义到处）。
    String controlsRowSource() {
      final start = source.indexOf('final row = Row(children: [');
      expect(start, greaterThanOrEqualTo(0), reason: '找不到底部按钮行的定义，测试需要跟着结构更新');
      final end = source.indexOf(']);', start);
      expect(end, greaterThan(start));
      return source.substring(start, end);
    }

    test('时间文本没有被 Flexible 包住（宽窗口右对齐的前提）', () {
      final rowSource = controlsRowSource();
      // 逐行看：Flexible 后面紧跟的那段不能是时间文本的 Padding。
      final lines = rowSource.split('\n');
      for (var i = 0; i < lines.length; i++) {
        if (!lines[i].contains('Flexible(')) continue;
        final window = lines.skip(i).take(4).join('\n');
        expect(
          window.contains('_formatDuration'),
          isFalse,
          reason: '时间文本被 Flexible 包住了：它会与 Spacer 平分剩余空间，导致宽窗口下右侧按钮离开右缘 130.8px（实测）',
        );
      }
    });

    test('不再使用 Spacer 推右（改用 Expanded + Align 右对齐）', () {
      final rowSource = controlsRowSource();
      expect(
        rowSource.contains('Spacer()'),
        isFalse,
        reason: 'Spacer 会与 Flexible 抢空间；现在用 Expanded + Align 右对齐',
      );
      expect(rowSource.contains('Alignment.centerRight'), isTrue, reason: '右侧按钮组应显式右对齐');
    });

    test('右侧按钮组横向可滚动（极窄窗口不溢出）', () {
      final rowSource = controlsRowSource();
      expect(
        rowSource.contains('SingleChildScrollView') && rowSource.contains('Axis.horizontal'),
        isTrue,
        reason: '极窄窗口（画中画 380px）下按钮组要能自己滚动，否则会 RenderFlex overflow',
      );
    });
  });
}
