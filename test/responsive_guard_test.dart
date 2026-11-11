import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 守卫：UI 层不再新增写死的大尺寸宽高。
///
/// 基准值（侧栏 176、顶栏 112）在 `AppDesignTokens`，那些是设计稿实测、不随窗口变；
/// 但 `SizedBox(height: 520)`、`width: 360` 这类会同时破坏两类自适应：
/// 窗口拉宽时内容挤在中间，文字放大时固定高度把列表裁断。
/// 有推导规则的尺寸应走 `AppResponsive`，本守卫用「只减不增」挡住回退。
void main() {
  final literalSize = RegExp(r'\b(?:width|height):\s*(\d{3,})(?:\.0)?\s*[,)]');

  // 这两个文件里的常量是设计/基础设施本身的值，不按页面尺寸推导。
  const skipped = <String>{
    'app_design_tokens.dart',
    'app_responsive.dart',
  };

  List<String> offendersIn(File file) {
    final hits = <String>[];
    final lines = file.readAsLinesSync();
    for (final (index, line) in lines.indexed) {
      final match = literalSize.firstMatch(line);
      if (match == null) continue;
      final value = int.tryParse(match.group(1)!);
      if (value == null || value < 300) continue;
      hits.add('${file.path}:${index + 1}: ${line.trim()}');
    }
    return hits;
  }

  List<String> collect() => <String>[
    for (final entity
        in Directory('lib/src').listSync(recursive: true).whereType<File>())
      if (entity.path.endsWith('.dart') &&
          !skipped.any((name) => entity.path.endsWith(name)))
        ...offendersIn(entity),
  ];

  test('写死的大尺寸宽高（对照 baseline 只减不增）', () {
    final hits = collect();
    // ignore: avoid_print
    print('写死的大尺寸宽高：${hits.length} 条');
    // 改造收敛后只剩 4 处 height: 1000，都是 hover_preview / video_player_surface
    // 里的约束哨兵值，不是布局尺寸。baseline 钉死在这里，不许再新增写死的大宽高。
    const baseline = 4;
    expect(
      hits.length,
      lessThanOrEqualTo(baseline),
      reason: '有推导规则的宽高请走 AppResponsive（见 docs/design-tokens.md）。'
          '当前 ${hits.length} 条，上限 $baseline。\n'
          '${hits.take(20).join('\n')}',
    );
  });

  test('守卫规则本身有效（正例与反例）', () {
    expect(literalSize.hasMatch('SizedBox(height: 520,'), isTrue);
    expect(literalSize.hasMatch('width: 360,'), isTrue);
    expect(literalSize.hasMatch('width: double.infinity,'), isFalse);
    expect(literalSize.hasMatch('height: 40,'), isFalse);
  });
}
