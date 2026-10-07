// 回归测试：按下缩放（PressScale）的行为 + 「全应用按钮统一」的覆盖面。
//
// 背景（用户要求）：「全应用按钮统一」——按下要有统一的缩放反馈。
//
// 为什么是包一层而不是挂在主题上：`ButtonStyle.backgroundBuilder` /
// `foregroundBuilder` 拿到的只是按钮的**内容层**（flutter/lib/src/material/
// button_style_button.dart:535-548 里 result 先包内容，再交给 backgroundBuilder），
// 底色与边框在更外层的 Material 上；在那里缩放会变成「只有文字缩小、底色不动」。
// `ButtonStyle` 也没有任何 transform/scale 字段。所以只能在按钮外面包。
//
// 本文件同时做两件事：
//  A. 行为：按下缩到 0.96、抬起回到 1；
//  B. **直接读生产源码**断言每个按钮形态的调用点都被包住 —— 只测 A 的话，
//     以后新加的按钮忘了包，测试照样绿。B 就是这份「统一」的守门人
//     （与 .dsh_shots/press_mask.py 是同一套判定）。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/press_scale.dart';

/// 需要被 PressScale 包住的按钮形态调用。
const _buttonCalls = <String>[
  'IconButton.filledTonal(',
  'IconButton.filled(',
  'IconButton.outlined(',
  'IconButton(',
  'TextButton.icon(',
  'TextButton(',
  'FilledButton.tonalIcon(',
  'FilledButton.tonal(',
  'FilledButton.icon(',
  'FilledButton(',
  'OutlinedButton.icon(',
  'OutlinedButton(',
  'ElevatedButton.icon(',
  'ElevatedButton(',
  'MenuButton(',
  'InkWell(',
  'InkResponse(',
];

const _ident = r'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$.';

/// 把字符串与注释里的字符标成「不是代码」，免得文档里提到 `IconButton(` 就被当成命中。
List<bool> _codeMask(String text) {
  final mask = List<bool>.filled(text.length, true);
  var i = 0;
  while (i < text.length) {
    final c = text[i];
    if (c == '/' && i + 1 < text.length && text[i + 1] == '/') {
      var j = text.indexOf('\n', i);
      if (j < 0) j = text.length;
      for (var k = i; k < j; k++) {
        mask[k] = false;
      }
      i = j;
    } else if (c == '/' && i + 1 < text.length && text[i + 1] == '*') {
      final j = text.indexOf('*/', i + 2);
      final stop = j < 0 ? text.length : j + 2;
      for (var k = i; k < stop; k++) {
        mask[k] = false;
      }
      i = stop;
    } else if (c == "'" || c == '"') {
      final raw = i > 0 && text[i - 1] == 'r' && (i < 2 || !_ident.contains(text[i - 2]));
      final triple = text.startsWith(c * 3, i);
      final quote = triple ? c * 3 : c;
      var j = i + quote.length;
      while (j < text.length) {
        if (!raw && text[j] == r'\') {
          j += 2;
          continue;
        }
        if (text.startsWith(quote, j)) {
          j += quote.length;
          break;
        }
        if (!triple && text[j] == '\n') break;
        j++;
      }
      for (var k = i; k < j && k < text.length; k++) {
        mask[k] = false;
      }
      i = j;
    } else {
      i++;
    }
  }
  return mask;
}

int _matchingParen(String text, List<bool> mask, int open) {
  var depth = 0;
  for (var j = open; j < text.length; j++) {
    if (!mask[j]) continue;
    if (text[j] == '(') {
      depth++;
    } else if (text[j] == ')') {
      depth--;
      if (depth == 0) return j;
    }
  }
  throw StateError('括号不配对：$open');
}

int _lineOf(String text, int index) => '\n'.allMatches(text.substring(0, index)).length + 1;

/// 按钮调用点所在行的前缀里，紧挨着它的就是 `PressScale(` + `child:`。
final _pressScaleHead = RegExp(r'PressScale\(\s*child:\s*$');

/// 往前 300 字符内能找到 `PressScale(` + `child:`（中间隔着 `SizedBox(` 之类也算，
/// 那种情况下按外层同样会缩）。
final _pressScaleBefore = RegExp(r'PressScale\(\s*child:');

void main() {
  testWidgets('按下缩到 0.96，抬起回到 1', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: PressScale(
              child: ElevatedButton(onPressed: () {}, child: const Text('按我')),
            ),
          ),
        ),
      ),
    );
    double scaleOf() => tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale;
    expect(scaleOf(), 1);

    final gesture = await tester.startGesture(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pumpAndSettle();
    expect(scaleOf(), 0.96);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(), 1);
  });

  test('lib/ 里每个按钮调用点都被 PressScale 包住（嵌套的由外层负责）', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '这个测试要从仓库根目录跑');

    final missing = <String>[];
    var covered = 0;
    for (final entity in lib.listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart') || entity.path.endsWith('press_scale.dart')) {
        continue;
      }
      final text = entity.readAsStringSync();
      final mask = _codeMask(text);
      final spans = <List<int>>[];
      for (final name in _buttonCalls) {
        var start = 0;
        while (true) {
          final i = text.indexOf(name, start);
          if (i < 0) break;
          start = i + 1;
          if (mask.sublist(i, i + name.length).contains(false)) continue;
          if (i > 0 && _ident.contains(text[i - 1])) continue;
          spans.add([i, _matchingParen(text, mask, i + name.length - 1) + 1]);
        }
      }
      for (final span in spans) {
        final i = span[0];
        final end = span[1];
        final head = text.substring(i == 0 ? 0 : text.lastIndexOf('\n', i - 1) + 1, i);
        // `PressScale(` 与 `child:` 之间允许换行与任意空白：手写的包裹经常分行写
        // （`PressScale(\n  child: TextButton.icon(`），判定不该反过来约束排版。
        if (_pressScaleHead.hasMatch(head)) {
          covered++;
          continue;
        }
        // 外层已经包住的嵌套调用点（InkWell 里套 TextButton）不算漏：
        // 按外层的时候里面同样会缩，且避免 0.96² 的双重缩放。
        if (spans.any((s) => s[0] < i && s[1] >= end)) continue;
        final back = text.substring(i < 300 ? 0 : i - 300, i);
        if (_pressScaleBefore.hasMatch(back)) {
          covered++;
          continue;
        }
        missing.add('${entity.path}:${_lineOf(text, i)}  ${head.trim()}');
      }
    }

    expect(
      covered,
      greaterThan(200),
      reason: '扫描到的已包住调用点太少，八成是工作目录或匹配规则失效了（vacuous pass）',
    );
    expect(missing, isEmpty, reason: '这些按钮没有按下缩放：\n${missing.join('\n')}');
  });
}
