import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：界面里不许再用 emoji 当图标或标签装饰。
///
/// ## 背景
///
/// 签到页的「类型」选择器与单日明细原来用 🤜💤👫👅❓ 当图标。全项目图标
/// 统一走 `material_symbols_icons`（一套线性笔画、一个尺寸、随文字色），
/// 混进 emoji 之后既不是同一套笔画粗细，也没法跟随 ink/inkSubtle/inkMuted
/// 三档文字色。2026-11 换成线性图标后加这条守卫，防止新页面又写回去。
///
/// 只扫 UI 层的**字符串字面量**：注释里讨论 emoji、以及 l10n 的译文都
/// 不在范围内（用户生成内容、评论正文里的 emoji 是数据，不是界面图标）。
/// 与 radius/motion 守卫同一套「扫源码 + 不增长」的思路。
void main() {
  /// 常见表情符号与装饰符号的 Unicode 区段（含变体选择符 / ZWJ 序列的
  /// 首个码点）。命中即认为这一行的字符串里带了 emoji。
  final emoji = RegExp(
    r'[\u{1F300}-\u{1FAFF}\u{2600}-\u{27BF}\u{FE0F}]',
    unicode: true,
  );

  List<File> uiFiles() => [
    ...Directory('lib/src/features').listSync(recursive: true),
    ...Directory('lib/src/app').listSync(recursive: true),
  ].whereType<File>().where((f) => f.path.endsWith('.dart')).toList();

  test('UI 层字符串里不再出现 emoji 图标', () {
    final offenders = <String>[];
    for (final file in uiFiles()) {
      final relative = file.path.replaceAll(r'\', '/');
      final lines = file.readAsLinesSync();
      for (final (index, line) in lines.indexed) {
        final trimmed = line.trimLeft();
        // 注释行跳过：注释里说明「原来用 emoji」不算违规。
        if (trimmed.startsWith('//')) continue;
        // 只关心字符串字面量里的 emoji，避免误伤标识符或数字。
        // 分别扫单引号与双引号串；写成两个正则，免得 raw string 里的
        // 转义引号把模式本身截断。
        final inSingle = RegExp(r"'([^'\\]|\\.)*'").allMatches(line);
        final inDouble = RegExp(r'"([^"\\]|\\.)*"').allMatches(line);
        final strings = [
          ...inSingle.map((m) => m.group(0) ?? ''),
          ...inDouble.map((m) => m.group(0) ?? ''),
        ];
        if (strings.any((s) => emoji.hasMatch(s))) {
          offenders.add('$relative:${index + 1}: ${line.trim()}');
        }
      }
    }
    expect(
      offenders,
      isEmpty,
      reason:
          '界面图标统一用 material_symbols_icons 的线性图标，别用 emoji 当图标'
          '（见 docs/design-tokens.md）：\n${offenders.join('\n')}',
    );
  });

  test('守卫能拦住 emoji，且不误伤普通文本', () {
    expect(emoji.hasMatch("'💤'"), isTrue);
    expect(emoji.hasMatch("'🚀 New'"), isTrue);
    expect(emoji.hasMatch("'Symbols.check_rounded'"), isFalse);
    expect(emoji.hasMatch("'12 集'"), isFalse);
  });
}
