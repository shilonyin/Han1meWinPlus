// 守卫：深色主题迁移后，UI 层不应再直接拿 AppDesignTokens 的固定色当颜色用。
//
// 背景：v6 设计稿只做了浅色基准面，整个界面曾经用写死的 AppDesignTokens.ink /
// surface / pageBackground …，切深色主题时页面纹丝不动（只有弹窗用 Theme.of 会变）。
// 迁移的做法是给每个固定色加一个按 Brightness 推导的 xxxOf(context) 版本，
// 调用点改用 xxxOf。这里用「只减不增」钉住：存量额度不再增加，新代码不许回退到固定色。
//
// 允许的例外：xxxxOf 定义处（app_design_tokens.dart），以及明确按亮度三元但浅色分支
// 仍取固定值的少数点（如 video_card 的 metaInk）。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // 只匹配「直接以固定色结尾/被使用」的形态：AppDesignTokens.ink 后面不能紧跟字母，
  // 且不能是 xxxOf 访问器本身。
  final fixedColor = RegExp(
    r'AppDesignTokens\.(pageBackground|accountCardFill|switchTrackOff|inkSubtle|inkMuted|fieldFill|surface|stroke|divider|ink)(?![A-Za-z])',
  );

  List<String> collect() {
    final hits = <String>[];
    for (final e in Directory('lib/src').listSync(recursive: true).whereType<File>()) {
      if (!e.path.endsWith('.dart')) continue;
      final name = e.path.split(RegExp(r'[\\/]')).last;
      if (name == 'app_design_tokens.dart') continue; // 定义处
      final lines = e.readAsLinesSync();
      for (final (i, line) in lines.indexed) {
        if (!fixedColor.hasMatch(line)) continue;
        hits.add('${e.path}:${i + 1}: ${line.trim()}');
      }
    }
    return hits;
  }

  test('UI 层不再直接用固定色 token（对照 baseline 只减不增）', () {
    final hits = collect();
    // ignore: avoid_print
    print('直接用固定色 token：${hits.length} 条');
    // baseline = 迁移完成那一刻的存量（video_card 的 metaInk 浅色分支 1 处）。
    // 降低它的方式是继续把这些点改成 Of(context)；不要为变绿而调大。
    const baseline = 1;
    expect(
      hits.length,
      lessThanOrEqualTo(baseline),
      reason: '深色主题要用 AppDesignTokens.xxxOf(context)，不要直接用固定色。'
          '当前 ${hits.length} 条：\n${hits.take(20).join('\n')}',
    );
  });
}
