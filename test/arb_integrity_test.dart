import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// ARB 文件里同一个 key 出现两次时，`jsonDecode` 会静默保留后一个，
/// 编辑器也只会在满天飞的其他警告里顺带提一句，很容易一直没人发现。
/// 这个测试直接扫原文的键行，把重复键挡在提交之前。
void main() {
  const files = [
    'lib/l10n/app_zh.arb',
    'lib/l10n/app_en.arb',
    'lib/l10n/app_zh_TW.arb',
  ];
  final baseCount = _messageKeys(files.first).length;

  for (final path in files) {
    test('$path 没有重复的 key', () {
      // 顶层键行形如 `  "key": ...`；`@key` 是元数据，单独计。
      final keyLine = RegExp(r'^  "([^"@][^"]*)"\s*:', multiLine: true);
      final seen = <String>{};
      final duplicated = <String>[];
      for (final match in keyLine.allMatches(File(path).readAsStringSync())) {
        final key = match.group(1)!;
        if (!seen.add(key) && !duplicated.contains(key)) duplicated.add(key);
      }
      expect(duplicated, isEmpty, reason: '$path 存在重复的 key：$duplicated');
    });

    test('$path 的键数量与中文一致（${files.first}）', () {
      // 三份译文的键必须完全对应，少一条就会出现「切语言后仍是中文」。
      expect(_messageKeys(path).length, baseCount);
    });
  }
}

/// 取出一个 arb 里的全部消息键，跳过 `@@locale` 与 `@key` 元数据。
Set<String> _messageKeys(String path) {
  final decoded =
      jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
  return decoded.keys.where((key) => !key.startsWith('@')).toSet();
}
