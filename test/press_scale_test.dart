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

const _ident =
    r'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_$.';

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
      final raw =
          i > 0 &&
          text[i - 1] == 'r' &&
          (i < 2 || !_ident.contains(text[i - 2]));
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

int _lineOf(String text, int index) =>
    '\n'.allMatches(text.substring(0, index)).length + 1;

/// 按钮调用点所在行的前缀里，紧挨着它的就是 `PressScale(` + `child:`。
final _pressScaleHead = RegExp(r'PressScale\(\s*child:\s*$');

/// 往前 300 字符内能找到 `PressScale(...child:`（中间隔着 `SizedBox(` 之类也算，
/// 那种情况下按外层同样会缩）。
///
/// 括号内允许任意不带括号的内容：`PressScale` 除了 `child:` 还有 `scale:` /
/// `enabled:` 这些具名参数（禁用按钮要传 `enabled: false`），把它们的出现
/// 判成「没包住」是误报。
final _pressScaleBefore = RegExp(r'PressScale\([^()]*child:');

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
    // 读缩放值：`PressScale` 用 `TweenAnimationBuilder` + `Transform.scale`
    // 而不是 `AnimatedScale`，因为后者把 `transformHitTests` 写死为 true ——
    // 按下时命中区跟着缩 .96，鼠标停在边缘会「离开 → 进入」反复触发，
    // 旁边靠悬停着色的文字就会跟着闪。
    //
    // 直接读矩阵的 (0,0) 元素：`getMaxScaleOnAxis()` 会把 perspective 分量
    // 也算进去，对这里的矩阵恒返回 1（实测），读不出真实缩放。
    //
    // 按 `transformHitTests == false` 精确挑出 PressScale 自己那层：
    // `ElevatedButton` 内部也有 Transform，用 `.first` 会抓错。
    double scaleOf() {
      final transform = tester
          .widgetList<Transform>(
            find.descendant(
              of: find.byType(PressScale),
              matching: find.byType(Transform),
            ),
          )
          .firstWhere((t) => t.transformHitTests == false);
      return transform.transform.entry(0, 0);
    }

    expect(scaleOf(), 1);

    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(ElevatedButton)),
    );
    await tester.pumpAndSettle();
    expect(scaleOf(), 0.96);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scaleOf(), 1);
  });

  // 回归：按在**按钮之外**（但仍在父级给的那条横向带里）时，绝对不能缩。
  //
  // 之前的实现把 `Listener` 放在 `Transform` 外面，并且为了拿到 pointerDown
  // 用了 `HitTestBehavior.translucent` —— 那会让命中区扩张到父级约束的整个宽度。
  // `PressScale` 常被塞进 `Row` 而撑满一行，于是点同一横带上的任何位置都会
  // 触发它的缩放，表现成「点一个按钮，左边那些字跟着一起缩」。
  testWidgets('按在按钮外面不会触发缩放', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 400,
              child: PressScale(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () {},
                    child: const Text('按我'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    double scaleOf() => tester
        .widgetList<Transform>(
          find.descendant(
            of: find.byType(PressScale),
            matching: find.byType(Transform),
          ),
        )
        .firstWhere((t) => t.transformHitTests == false)
        .transform
        .entry(0, 0);

    // 在同一个 400 宽的槽里、但离按钮很远的位置按下。
    final farAway =
        tester.getCenter(find.byType(PressScale)) - const Offset(150, 0);
    final gesture = await tester.startGesture(farAway);
    await tester.pumpAndSettle();
    expect(scaleOf(), 1, reason: '按在按钮范围外时不该缩放');

    await gesture.up();
    await tester.pumpAndSettle();
  });

  test('lib/ 里每个按钮调用点都被 PressScale 包住（嵌套的由外层负责）', () {
    final lib = Directory('lib');
    expect(lib.existsSync(), isTrue, reason: '这个测试要从仓库根目录跑');

    final missing = <String>[];
    var covered = 0;
    for (final entity in lib.listSync(recursive: true).whereType<File>()) {
      if (!entity.path.endsWith('.dart') ||
          entity.path.endsWith('press_scale.dart')) {
        continue;
      }
      // `settings_list.dart` 是这条规则的**例外**：设置页的每一行都是整行可点的
      // `InkWell`，而这一行能宽到 1200+px。把整行包进 `PressScale` 时，缩放会以
      // 行中心为锚点把内容往里收 —— 左边文字右移十几像素、右侧开关左移十几像素，
      // 看起来就是「点一下整行跳了一下」。实测（1400 宽）标题左边缘 256 → 274。
      //
      // 所以那一页的行不用 `PressScale`，缩放下沉到右侧开关那个 56×30 的小控件上；
      // 行的按下反馈本来就是「标题与图标染成主题色」（`_TileLabel` 的 hovered）。
      if (entity.path
          .replaceAll('\\', '/')
          .endsWith('settings/settings_list.dart')) {
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
        final head = text.substring(
          i == 0 ? 0 : text.lastIndexOf('\n', i - 1) + 1,
          i,
        );
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
