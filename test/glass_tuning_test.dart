import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_tuning.dart';

/// 设置里那三个玻璃维度 → g1455 参数的对照表。
///
/// 之所以专门测它：真正把值装进 `GlassHost` 的地方在 widget 树最深处
/// （`MaterialApp.builder` 里那个 host），要断言它得把整个应用起起来；
/// 这里全是纯函数，输入输出直接钉死，改错一眼就能看见。
void main() {
  group('波纹档位', () {
    test('关闭 → null（不是「给个不动的波纹」，而是根本不起波纹）', () {
      expect(glassRippleFor(GlassRippleKind.off), isNull);
    });

    test('水 / 蜂蜜 → 只改 viscosity，正是 g1455 文档给的两个示范值', () {
      expect(glassRippleFor(GlassRippleKind.water)!.viscosity, 0.15);
      expect(glassRippleFor(GlassRippleKind.honey)!.viscosity, 0.95);
    });

    test('果冻 → 用包的默认 0.6（包里没有这一档，它就是默认手感）', () {
      expect(glassRippleFor(GlassRippleKind.jelly)!.viscosity, const GlassRipple().viscosity);
    });

    test('四档之外没动别的旋钮：其余参数与包默认一致', () {
      // 这几个数是作者按眼睛定的，我们没有更好的依据去改，所以只动 viscosity。
      for (final kind in [GlassRippleKind.water, GlassRippleKind.jelly, GlassRippleKind.honey]) {
        final ripple = glassRippleFor(kind)!;
        const fallback = GlassRipple();
        expect(ripple.amplitude, fallback.amplitude, reason: '$kind');
        expect(ripple.speed, fallback.speed, reason: '$kind');
        expect(ripple.width, fallback.width, reason: '$kind');
        expect(ripple.press, fallback.press, reason: '$kind');
        expect(ripple.pressRadius, fallback.pressRadius, reason: '$kind');
        expect(ripple.light, fallback.light, reason: '$kind');
      }
    });

    test('viscosity 递增：水 < 果冻 < 蜂蜜（越大越黏）', () {
      final water = glassRippleFor(GlassRippleKind.water)!.viscosity;
      final jelly = glassRippleFor(GlassRippleKind.jelly)!.viscosity;
      final honey = glassRippleFor(GlassRippleKind.honey)!.viscosity;
      expect(water, lessThan(jelly));
      expect(jelly, lessThan(honey));
    });
  });

  group('渲染层级', () {
    test('自动 → 不下钉子，交给 g1455 自己定（默认 full）', () {
      expect(glassPinnedTier(GlassTierMode.auto), isNull);
      final choice = glassTierChoice(mode: GlassTierMode.auto, reduceTransparency: false);
      expect(choice.tier, GlassTier.full);
      expect(choice.reason, GlassTierReason.byDefault);
    });

    test('玻璃 / 半透 / 不透明 → 三个 tier 一一对上', () {
      expect(glassPinnedTier(GlassTierMode.full), GlassTier.full);
      expect(glassPinnedTier(GlassTierMode.cheap), GlassTier.cheap);
      expect(glassPinnedTier(GlassTierMode.opaque), GlassTier.opaque);
    });

    test('用户选的档位会被钉住，理由记成 pinnedByHost（方便诊断）', () {
      final choice = glassTierChoice(mode: GlassTierMode.cheap, reduceTransparency: false);
      expect(choice.tier, GlassTier.cheap);
      expect(choice.reason, GlassTierReason.pinnedByHost);
    });

    test('系统说「减少透明度」时，系统压过用户选的档位', () {
      // 这是刻意的：那个可访问性开关是用户对**整个系统**的要求，
      // 不该被应用里一个玻璃偏好盖掉。钉住的 pitfall 见 GlassTierPolicy.choose()：
      // pinned 排在 reduceTransparency 前面，所以这里必须主动不给 pinned。
      final choice = glassTierChoice(mode: GlassTierMode.full, reduceTransparency: true);
      expect(choice.tier, GlassTier.opaque);
      expect(choice.reason, GlassTierReason.reduceTransparency);
    });

    test('每一档的 readsBackdrop 与 g1455 一致：只有 full 读背景', () {
      for (final mode in GlassTierMode.values) {
        final tier = glassPinnedTier(mode);
        if (tier == null) continue;
        expect(tier.readsBackdrop, tier == GlassTier.full, reason: '$mode');
      }
    });
  });

  group('对比度', () {
    test('增强 → 永远 true，不管系统怎么说', () {
      expect(glassHighContrastFor(GlassContrast.increased, systemHighContrast: false), isTrue);
      expect(glassHighContrastFor(GlassContrast.increased, systemHighContrast: true), isTrue);
    });

    test('跟随系统 → 直接透传我们自己读到的值', () {
      // 传 false 而不是 null：Windows 上引擎从不设置 MediaQuery 的 highContrast，
      // 交给 host 去读等于永远读到 false，还会把「系统确实开着」这种情况吞掉。
      expect(glassHighContrastFor(GlassContrast.auto, systemHighContrast: false), isFalse);
      expect(glassHighContrastFor(GlassContrast.auto, systemHighContrast: true), isTrue);
    });
  });

  group('设置读写', () {
    test('三个新维度默认值：波纹关、层级自动、对比度跟随系统', () {
      const settings = AppSettings();
      expect(settings.glassRipple, GlassRippleKind.off);
      expect(settings.glassTier, GlassTierMode.auto);
      expect(settings.glassContrast, GlassContrast.auto);
    });

    test('存了再读回来还是同一档（枚举按 name 存）', () {
      final saved = const AppSettings().copyWith(
        glassRipple: GlassRippleKind.honey,
        glassTier: GlassTierMode.cheap,
        glassContrast: GlassContrast.increased,
      );
      final loaded = AppSettings.fromJson(saved.toJson());
      expect(loaded.glassRipple, GlassRippleKind.honey);
      expect(loaded.glassTier, GlassTierMode.cheap);
      expect(loaded.glassContrast, GlassContrast.increased);
    });

    test('存的是 name 字符串，不是 index（换顺序不会串档）', () {
      final json = const AppSettings().copyWith(glassRipple: GlassRippleKind.water).toJson();
      expect(json['glassRipple'], 'water');
      expect(json['glassTier'], 'auto');
      expect(json['glassContrast'], 'auto');
    });

    test('老配置没有这三个键 → 走默认，不报错', () {
      final loaded = AppSettings.fromJson(const {});
      expect(loaded.glassRipple, GlassRippleKind.off);
      expect(loaded.glassTier, GlassTierMode.auto);
      expect(loaded.glassContrast, GlassContrast.auto);
    });

    test('键值认不出来（手改坏了 / 降级）→ 回默认而不是崩', () {
      final loaded = AppSettings.fromJson(const {
        'glassRipple': 'molasses',
        'glassTier': 'ultra',
        'glassContrast': 'maximum',
      });
      expect(loaded.glassRipple, GlassRippleKind.off);
      expect(loaded.glassTier, GlassTierMode.auto);
      expect(loaded.glassContrast, GlassContrast.auto);
    });
  });
}
