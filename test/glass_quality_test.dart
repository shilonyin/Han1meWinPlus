import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/liquid_glass.dart';

/// 三档玻璃质感必须是**三种不同的渲染**，不能只是换个名字。
void main() {
  GlassMaterial build(GlassQuality quality) => GlassMaterial.quality(
    quality: quality,
    tint: const Color(0xff888888),
    dark: false,
    readable: false,
    borderRadius: BorderRadius.circular(8),
    opacity: 1,
  );

  group('玻璃质感三档', () {
    test('模糊强度互不相同：磨砂最糊、超透最清', () {
      final frosted = build(GlassQuality.frosted);
      final clear = build(GlassQuality.clear);
      final liquid = build(GlassQuality.liquid);

      expect(frosted.blur, greaterThan(liquid.blur));
      expect(liquid.blur, greaterThan(clear.blur));
      // 三档不能退化成同一个值
      expect({frosted.blur, clear.blur, liquid.blur}.length, 3);
    });

    test('折射强度：液体玻璃最强、磨砂为 0、超透只留一点亮边', () {
      expect(build(GlassQuality.liquid).liquid, 1.0);
      expect(build(GlassQuality.frosted).liquid, 0);
      // 超透需要一点点折射来产生边缘高光（morrow 的 clear 靠亮边表达通透），
      // 但不能强到把画面糊掉。
      expect(build(GlassQuality.clear).liquid, greaterThan(0));
      expect(build(GlassQuality.clear).liquid, lessThan(.5));
    });

    test('底色浓度：磨砂最实、超透最轻', () {
      // 取渐变首个 stop 的 alpha 作为"实心程度"的代理。
      double density(GlassQuality q) {
        final gradient =
            (build(q).decoration.gradient! as LinearGradient);
        return gradient.colors.first.a;
      }

      expect(density(GlassQuality.frosted), greaterThan(density(GlassQuality.liquid)));
      expect(density(GlassQuality.clear), lessThan(density(GlassQuality.liquid)));
    });

    test('不透明度滑条只对磨砂档生效，另外两档透明度固定', () {
      GlassMaterial at(GlassQuality q, double opacity) => GlassMaterial.quality(
        quality: q,
        tint: const Color(0xff888888),
        dark: false,
        readable: false,
        borderRadius: BorderRadius.circular(8),
        opacity: opacity,
      );
      double first(GlassQuality q, double opacity) =>
          ((at(q, opacity).decoration.gradient! as LinearGradient).colors.first.a);

      // 磨砂：滑条直接改变底色浓度。
      expect(first(GlassQuality.frosted, .3), lessThan(first(GlassQuality.frosted, 1)));
      // 超透 / 液体玻璃：透明度是固定的（morrow 里也只有磨砂能调）。
      expect(first(GlassQuality.clear, .3), first(GlassQuality.clear, 1));
      expect(first(GlassQuality.liquid, .3), first(GlassQuality.liquid, 1));
    });

    test('磨砂档：滑条 100% 确实接近实色，20% 很透', () {
      double alphaAt(double opacity) => ((build(GlassQuality.frosted))
              .decoration
              .gradient! as LinearGradient)
          .colors
          .first
          .a;
      double at(double opacity) => ((GlassMaterial.quality(
                quality: GlassQuality.frosted,
                tint: const Color(0xff888888),
                dark: false,
                readable: false,
                borderRadius: BorderRadius.circular(8),
                opacity: opacity,
              ).decoration.gradient! as LinearGradient)
              .colors
              .first
              .a);

      // 曾经这里沿用了很淡的基数，滑条拉满也只有 0.25，用户反馈"调到 100% 也不明显"。
      expect(at(1), greaterThan(.9));
      expect(at(.2), lessThan(.25));
      expect(alphaAt(1), greaterThan(.9));
    });

    test('新装默认：磨砂 + 50% 不透明度', () {
      expect(const AppSettings().glassQuality, GlassQuality.frosted);
      expect(const AppSettings().glassSurfaceOpacity, .5);
    });

    test('全新配置（无玻璃字段）也落到「磨砂」而不是关闭', () {
      final settings = AppSettings.fromJson(const <String, dynamic>{});
      expect(settings.glassQuality, GlassQuality.frosted);
    });
  });
}
