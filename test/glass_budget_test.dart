import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/glass_budget.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/liquid_glass.dart';

void main() {
  group('GlassBudget 折射路径', () {
    test('静止且可见时走 realtime（默认路径，与改动前一致）', () {
      expect(
        resolveGlassRefractionPath(isScrolling: false, tickerActive: true),
        GlassRefractionPath.realtime,
      );
    });

    test('滚动中降到 fallback', () {
      expect(
        resolveGlassRefractionPath(isScrolling: true, tickerActive: true),
        GlassRefractionPath.fallback,
      );
    });

    test('面板不可见（TickerMode 关闭）时降到 fallback', () {
      expect(
        resolveGlassRefractionPath(isScrolling: false, tickerActive: false),
        GlassRefractionPath.fallback,
      );
      expect(
        resolveGlassRefractionPath(isScrolling: true, tickerActive: false),
        GlassRefractionPath.fallback,
      );
    });

    test('预算里不含模糊强度与透明度 —— 降级不可能改动观感参数', () {
      // 这条是本设计与上游 BiliPai 的关键差异，也是它的立身之本：
      // BiliPai 的 BlurBudget 带 maxBlurLevel，滚动时压到 0，会造成明暗跳跃。
      // 这里用"枚举成员只有两个、且都不携带任何数值"把这条约束固化下来 ——
      // 将来有人想往路径里塞强度，就必须先改这个测试，也就必须先面对这个问题。
      for (final path in GlassRefractionPath.values) {
        expect(
          path,
          anyOf(GlassRefractionPath.realtime, GlassRefractionPath.fallback),
        );
      }
      // 两条路径之间没有"程度"，只有"哪一条"：不存在第三档。
      expect(GlassRefractionPath.values.length, 2);
    });

    test('静态方法与自由函数结果一致', () {
      for (final scrolling in [true, false]) {
        for (final ticker in [true, false]) {
          expect(
            resolveGlassRefractionPath(isScrolling: scrolling, tickerActive: ticker),
            GlassBudget.resolveRefractionPath(
              isScrolling: scrolling,
              tickerActive: ticker,
            ),
          );
        }
      }
    });
  });

  group('生效范围（实测事实，防止误以为默认档也受益）', () {
    test('只对走折射的档位有意义：磨砂档的折射强度为 0', () {
      // _filter 在 liquid <= .001 时直接返回纯模糊，与传入路径无关。
      // 也就是说新装默认档（磨砂）下，本预算不带来性能变化。
      // 把这条写进测试，是为了让"默认档受益"这个错误前提不会悄悄传播。
      GlassMaterial at(GlassQuality quality) => GlassMaterial.quality(
        quality: quality,
        tint: const Color(0xff888888),
        dark: false,
        readable: false,
        borderRadius: BorderRadius.circular(8),
        opacity: .5,
      );

      expect(at(GlassQuality.frosted).liquid, 0, reason: '磨砂是纯模糊档');
      expect(at(GlassQuality.clear).liquid, greaterThan(0), reason: '超透走折射');
      expect(at(GlassQuality.liquid).liquid, greaterThan(0), reason: '液体玻璃走折射');
    });

    test('新装默认档是磨砂（即默认配置下本预算不改善性能）', () {
      expect(const AppSettings().glassQuality, GlassQuality.frosted);
    });
  });
}
