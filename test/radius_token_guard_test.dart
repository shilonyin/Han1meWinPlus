import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：圆角不许再写成裸数字。
///
/// ## 背景
///
/// `AppRadius` 出现之前，34 个文件里散着 15 种圆角值（2/4/6/8/10/12/14/15/16/18/
/// 22/24/28/40/999）——「同一个卡片在三处是三个数」。2026-11 按**元素尺寸**把
/// 全部值收成五档（xs/sm/md/lg/xl）+ 药丸，残留 0 处字面量。
///
/// 收拢的价值不在「代码短了」，而在**同一个尺寸在任何页面都是同一个数**：
/// 只修一半、留几个字面量，规则就又变成了各写各的。
///
/// 所以这里直接扫源码：`BorderRadius.circular(<数字>)` 一律违规。
void main() {
  /// `BorderRadius.circular(12)` / `BorderRadius.circular(12.0)`。
  ///
  /// 不匹配 `BorderRadius.circular(AppRadius.md)`，也不匹配 `.vertical(...)`
  /// 这类别的构造器 —— 它们本来就该由调用点自己决定方向。
  final literalRadius = RegExp(r'BorderRadius\.circular\(\s*\d+(?:\.0)?\s*\)');

  List<File> uiFiles() => [
    ...Directory('lib/src/features').listSync(recursive: true),
    ...Directory('lib/src/app').listSync(recursive: true),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  test('UI 层不再出现 BorderRadius.circular 的数字字面量', () {
    final offenders = <String>[];
    for (final file in uiFiles()) {
      final relative = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        if (line.trimLeft().startsWith('//')) continue;
        if (!literalRadius.hasMatch(line)) continue;
        offenders.add('$relative:${index + 1}: ${line.trim()}');
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '圆角按元素尺寸取令牌（AppRadius.xs 6 / sm 10 / md 12 / lg 16 / '
          'xl 24 / pill 999），见 docs/design-tokens.md：\n${offenders.join('\n')}',
    );
  });

  test('守卫能拦住字面量，且不误伤令牌写法', () {
    expect(literalRadius.hasMatch('BorderRadius.circular(12)'), isTrue);
    expect(literalRadius.hasMatch('BorderRadius.circular( 8.0 )'), isTrue);
    expect(
      literalRadius.hasMatch('BorderRadius.circular(AppRadius.md)'),
      isFalse,
    );
    expect(literalRadius.hasMatch('BorderRadius.circular(radius)'), isFalse);
    // 分方向的构造器不归这条守卫管。
    expect(
      literalRadius.hasMatch('BorderRadius.vertical(top: Radius.circular(12))'),
      isFalse,
    );
  });
}
