// 回归测试：AppDesignTokens 的 Of(context) 访问器必须按 Brightness 返回两套值，
// 且浅色档与原有的 static const 完全一致（迁移页面时浅色观感不能变）。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/app_design_tokens.dart';

Widget _probe(Brightness b, void Function(BuildContext) onBuild) => MaterialApp(
  theme: ThemeData(brightness: b),
  home: Builder(builder: (c) { onBuild(c); return const SizedBox(); }),
);

void main() {
  testWidgets('浅色档 Of(context) 与原 constant 一致', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_probe(Brightness.light, (c) => ctx = c));
    expect(AppDesignTokens.pageBackgroundOf(ctx), AppDesignTokens.pageBackground);
    expect(AppDesignTokens.surfaceOf(ctx), AppDesignTokens.surface);
    expect(AppDesignTokens.inkOf(ctx), AppDesignTokens.ink);
    expect(AppDesignTokens.inkSubtleOf(ctx), AppDesignTokens.inkSubtle);
    expect(AppDesignTokens.strokeOf(ctx), AppDesignTokens.stroke);
  });

  testWidgets('深色档 pageBackground 比 surface 暗、ink 比 surface 亮', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_probe(Brightness.dark, (c) => ctx = c));
    final bg = AppDesignTokens.pageBackgroundOf(ctx);
    final surf = AppDesignTokens.surfaceOf(ctx);
    final ink = AppDesignTokens.inkOf(ctx);
    // 深色：页面底比卡片暗（亮度更低），正文比卡片亮
    expect(bg.computeLuminance(), lessThan(surf.computeLuminance()));
    expect(ink.computeLuminance(), greaterThan(surf.computeLuminance()));
    // 深浅两档必须真的不同
    expect(bg, isNot(AppDesignTokens.pageBackground));
    expect(ink, isNot(AppDesignTokens.ink));
  });

  testWidgets('文本对比度：深色正文 vs 深色卡底 >= 4.5', (tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(_probe(Brightness.dark, (c) => ctx = c));
    final fg = AppDesignTokens.inkOf(ctx).computeLuminance();
    final bg = AppDesignTokens.surfaceOf(ctx).computeLuminance();
    final hi = fg > bg ? fg : bg;
    final lo = fg > bg ? bg : fg;
    final ratio = (hi + 0.05) / (lo + 0.05);
    expect(ratio, greaterThanOrEqualTo(4.5), reason: '对比度 $ratio 不够');
  });
}
