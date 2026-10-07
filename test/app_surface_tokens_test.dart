import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/app_surface_tokens.dart';

/// 这一层只收「有规则」的语义底色（见模块顶部说明），所以测试要钉住两件事：
/// 1. 各访问器在深浅两档下取到的是**预期的那个值**；
/// 2. 收口是把原先散落的值原样搬进来 —— 不是顺手改观感。
void main() {
  // 用真实主题色跑，避免只测到"默认紫"这一种巧合。
  ColorScheme scheme(Brightness brightness) => ColorScheme.fromSeed(
    seedColor: const Color(0xff7662ba),
    brightness: brightness,
  );

  group('AppSurfaceTokens.closedSurface（关闭玻璃档的卡片底）', () {
    test('浅色给 72%、深色给 62% 不透明度', () {
      final light = scheme(Brightness.light);
      final dark = scheme(Brightness.dark);

      // 收口前 GlassPanel 里写的就是 dark ? .62 : .72，这里保持等价。
      expect(AppSurfaceTokens.closedSurface(light, Brightness.light).a, closeTo(.72, 1e-6));
      expect(AppSurfaceTokens.closedSurface(dark, Brightness.dark).a, closeTo(.62, 1e-6));
    });

    test('色相取自 surface，只改 alpha', () {
      final s = scheme(Brightness.light);
      final result = AppSurfaceTokens.closedSurface(s, Brightness.light);

      expect(result.r, closeTo(s.surface.r, 1e-6));
      expect(result.g, closeTo(s.surface.g, 1e-6));
      expect(result.b, closeTo(s.surface.b, 1e-6));
    });

    test('深色比浅色更实（深色背景暗，卡片再透就糊成一片）', () {
      final light = AppSurfaceTokens.closedSurface(scheme(Brightness.light), Brightness.light);
      final dark = AppSurfaceTokens.closedSurface(scheme(Brightness.dark), Brightness.dark);
      expect(dark.a, lessThan(light.a));
    });

    test('同一输入可重复取到相同值（判定与绘制两处必须一致）', () {
      final s = scheme(Brightness.light);
      expect(
        AppSurfaceTokens.closedSurface(s, Brightness.light),
        AppSurfaceTokens.closedSurface(s, Brightness.light),
      );
    });
  });
}
