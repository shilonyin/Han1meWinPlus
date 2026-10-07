import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_tuning.dart';

/// 设置里那几个玻璃维度 → g1455 参数的对照表。
///
/// 之所以专门测它：真正把值装进 `GlassHost` 的地方在 widget 树最深处
/// （`MaterialApp.builder` 里那个 host），要断言它得把整个应用起起来；
/// 这里全是纯函数，输入输出直接钉死，改错一眼就能看见。
void main() {
  group('波纹档位', () {
    test('关闭 → null（不是「给个不动的波纹」，而是根本不起波纹）', () {
      expect(glassRippleFor(GlassRippleKind.off), isNull);
    });

    test('水 / 果冻 / 蜂蜜 → viscosity 就是演示站那三个数 0 / .5 / 1', () {
      // 演示站 style.dart 的 `RippleChoice` 写死了这三个值，照抄。
      expect(glassRippleFor(GlassRippleKind.water)!.viscosity, 0);
      expect(glassRippleFor(GlassRippleKind.jelly)!.viscosity, 0.5);
      expect(glassRippleFor(GlassRippleKind.honey)!.viscosity, 1);
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
    test('玻璃 / 半透 / 不透明 → 三个 tier 一一对上', () {
      expect(glassPinnedTier(GlassRendering.glass), GlassTier.full);
      expect(glassPinnedTier(GlassRendering.translucent), GlassTier.cheap);
      expect(glassPinnedTier(GlassRendering.opaque), GlassTier.opaque);
    });

    test('用户选的档位会被钉住，理由记成 pinnedByHost（方便诊断）', () {
      final choice = glassTierChoice(rendering: GlassRendering.translucent, reduceTransparency: false);
      expect(choice.tier, GlassTier.cheap);
      expect(choice.reason, GlassTierReason.pinnedByHost);
    });

    test('系统说「减少透明度」时，系统压过用户选的档位', () {
      // 这是刻意的：那个可访问性开关是用户对**整个系统**的要求，
      // 不该被应用里一个玻璃偏好盖掉。钉住的 pitfall 见 GlassTierPolicy.choose()：
      // pinned 排在 reduceTransparency 前面，所以这里必须主动不给 pinned。
      final choice = glassTierChoice(rendering: GlassRendering.glass, reduceTransparency: true);
      expect(choice.tier, GlassTier.opaque);
      expect(choice.reason, GlassTierReason.reduceTransparency);
    });

    test('注意这里和演示站的做法不同：演示站一律 pinned，我们让系统开关赢', () {
      // 演示站是 `GlassTierPolicy(pinned: rendering.tier).choose()`，会盖掉系统开关。
      // 我们保留这一格地板，所以同样的输入在两边结果不同 —— 这条测试就是钉住这个差异。
      final ours = glassTierChoice(rendering: GlassRendering.glass, reduceTransparency: true);
      final demo = GlassTierPolicy(pinned: GlassTier.full).choose();
      expect(ours.tier, GlassTier.opaque);
      expect(demo.tier, GlassTier.full);
    });

    test('每一档的 readsBackdrop 与 g1455 一致：只有 full 读背景', () {
      for (final rendering in GlassRendering.values) {
        final tier = glassPinnedTier(rendering);
        expect(tier.readsBackdrop, tier == GlassTier.full, reason: '$rendering');
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

  group('染色', () {
    test('中性 → 不指定颜色（交给材质自己的色调）', () {
      expect(glassTintColorFor(GlassTintKind.neutral), isNull);
    });

    test('靛蓝 / 玫瑰 → 演示站 style.dart 里那两个确切色值', () {
      expect(glassTintColorFor(GlassTintKind.indigo), const Color(0xFF28348C));
      expect(glassTintColorFor(GlassTintKind.rose), const Color(0xFF962850));
    });
  });

  group('材质 → g1455 材质', () {
    test('标准档按明暗挑包自己的 regular 分支', () {
      expect(
        glassFinishFor(
          material: GlassMaterial.regular,
          tint: GlassTintKind.neutral,
          brightness: Brightness.dark,
        ),
        GlassFinish.regularDark,
      );
      expect(
        glassFinishFor(
          material: GlassMaterial.regular,
          tint: GlassTintKind.neutral,
          brightness: Brightness.light,
        ),
        GlassFinish.regularLight,
      );
    });

    test('深色 / 浅色两档与明暗无关，选谁就是谁', () {
      for (final brightness in Brightness.values) {
        expect(
          glassFinishFor(
            material: GlassMaterial.dark,
            tint: GlassTintKind.neutral,
            brightness: brightness,
          ),
          GlassFinish.regularDark,
          reason: '$brightness',
        );
        expect(
          glassFinishFor(
            material: GlassMaterial.light,
            tint: GlassTintKind.neutral,
            brightness: brightness,
          ),
          GlassFinish.regularLight,
          reason: '$brightness',
        );
      }
    });

    test('超透 / 磨砂是包校准过的另外两块料，没有被映射成 regular', () {
      final clear = glassFinishFor(
        material: GlassMaterial.clear,
        tint: GlassTintKind.neutral,
        brightness: Brightness.dark,
      );
      final frosted = glassFinishFor(
        material: GlassMaterial.frosted,
        tint: GlassTintKind.neutral,
        brightness: Brightness.dark,
      );
      expect(clear, GlassFinish.clear);
      expect(frosted, GlassFinish.frosted);
      expect(clear.blurSigmaLogical, isNot(frosted.blurSigmaLogical));
    });

    test('中性染色不动材质原本的 tint', () {
      final finish = glassFinishFor(
        material: GlassMaterial.dark,
        tint: GlassTintKind.neutral,
        brightness: Brightness.dark,
      );
      expect(finish.tint, GlassFinish.regularDark.tint);
    });

    test('带色时只换 RGB，保留材质自己的 alpha', () {
      final base = GlassFinish.regularDark;
      final finish = glassFinishFor(
        material: GlassMaterial.dark,
        tint: GlassTintKind.indigo,
        brightness: Brightness.dark,
      );
      expect(finish.tint.a, base.tint.a);
      expect(finish.tint.r, isNot(base.tint.r));
      expect(finish.tint.b, isNot(base.tint.b));
      expect(finish.blurSigmaLogical, base.blurSigmaLogical, reason: '染色不该换料');
    });
  });

  group('预设', () {
    test('默认设置落在「高」这一档（就是包默认那组取值）', () {
      const settings = AppSettings();
      expect(glassPresetFor(glassRecipeOf(settings)), GlassPresetKind.high);
    });

    test('四档各自对应一组取值，且组与组之间不重复', () {
      final seen = <GlassRecipe>{};
      for (final preset in GlassPresetKind.values) {
        final recipe = glassPresetRecipes[preset]!;
        expect(seen.add(recipe), isTrue, reason: '$preset 与前面某一档取值完全相同');
        expect(glassPresetFor(recipe), preset, reason: '$preset 反推不回来');
      }
      expect(seen.length, GlassPresetKind.values.length);
    });

    test('极致 = 高 + 果冻波纹（演示站唯一在「高」之上多给的就是那道波纹）', () {
      final high = glassPresetRecipes[GlassPresetKind.high]!;
      final ultra = glassPresetRecipes[GlassPresetKind.ultra]!;
      expect(ultra.ripple, GlassRippleKind.jelly);
      expect(high.ripple, GlassRippleKind.off);
      expect(ultra.material, high.material);
      expect(ultra.rendering, high.rendering);
      expect(ultra.tint, high.tint);
    });

    test('中 / 低 = 高 的渲染层级分别降到半透 / 不透明', () {
      final high = glassPresetRecipes[GlassPresetKind.high]!;
      expect(high.rendering, GlassRendering.glass);
      expect(glassPresetRecipes[GlassPresetKind.medium]!.rendering, GlassRendering.translucent);
      expect(glassPresetRecipes[GlassPresetKind.low]!.rendering, GlassRendering.opaque);
    });

    test('改到不落在四档上的取值就反推不出预设（面板上显示「自定义」）', () {
      final base = glassRecipeOf(const AppSettings());
      GlassRecipe tweak({
        GlassMaterial? material,
        GlassTintKind? tint,
        GlassRendering? rendering,
        GlassRippleKind? ripple,
        GlassContrast? contrast,
      }) => (
        material: material ?? base.material,
        tint: tint ?? base.tint,
        rendering: rendering ?? base.rendering,
        ripple: ripple ?? base.ripple,
        contrast: contrast ?? base.contrast,
      );

      expect(glassPresetFor(tweak(tint: GlassTintKind.rose)), isNull);
      expect(glassPresetFor(tweak(material: GlassMaterial.dark)), isNull);
      expect(glassPresetFor(tweak(material: GlassMaterial.frosted)), isNull);
      expect(glassPresetFor(tweak(ripple: GlassRippleKind.honey)), isNull);
      expect(glassPresetFor(tweak(contrast: GlassContrast.increased)), isNull);
      // 换色 + 换料一起改当然也不是任何一档。
      expect(
        glassPresetFor(tweak(tint: GlassTintKind.indigo, material: GlassMaterial.light)),
        isNull,
      );

      // 反过来说：**只**动渲染层级是落在四档网格上的 —— 演示站的
      // 中/低两档本来就只跟「高」差这一项，所以这里会反推出预设而不是「自定义」。
      // 这不是 bug，是那张网格的形状；写出来免得以后有人以为反推坏了。
      expect(glassPresetFor(tweak(rendering: GlassRendering.opaque)), GlassPresetKind.low);
      expect(glassPresetFor(tweak(rendering: GlassRendering.translucent)), GlassPresetKind.medium);
    });

    test('应用一整档预设后，反推出来还是那一档', () {
      for (final preset in GlassPresetKind.values) {
        final recipe = glassPresetRecipes[preset]!;
        final applied = const AppSettings().copyWith(
          glassMaterial: recipe.material,
          glassTint: recipe.tint,
          glassRendering: recipe.rendering,
          glassRipple: recipe.ripple,
          glassContrast: recipe.contrast,
        );
        expect(glassPresetFor(glassRecipeOf(applied)), preset, reason: '$preset');
      }
    });
  });

  group('设置读写', () {
    test('新默认值：材质标准、染色中性、渲染玻璃、波纹关、对比度跟随系统', () {
      const settings = AppSettings();
      expect(settings.glassMaterial, GlassMaterial.regular);
      expect(settings.glassTint, GlassTintKind.neutral);
      expect(settings.glassRendering, GlassRendering.glass);
      expect(settings.glassRipple, GlassRippleKind.off);
      expect(settings.glassContrast, GlassContrast.auto);
    });

    test('存了再读回来还是同一档（枚举按 name 存）', () {
      final saved = const AppSettings().copyWith(
        glassMaterial: GlassMaterial.frosted,
        glassTint: GlassTintKind.rose,
        glassRendering: GlassRendering.translucent,
        glassRipple: GlassRippleKind.honey,
        glassContrast: GlassContrast.increased,
      );
      final loaded = AppSettings.fromJson(saved.toJson());
      expect(loaded.glassMaterial, GlassMaterial.frosted);
      expect(loaded.glassTint, GlassTintKind.rose);
      expect(loaded.glassRendering, GlassRendering.translucent);
      expect(loaded.glassRipple, GlassRippleKind.honey);
      expect(loaded.glassContrast, GlassContrast.increased);
    });

    test('存的是 name 字符串，不是 index（换顺序不会串档）', () {
      final json = const AppSettings().copyWith(glassRipple: GlassRippleKind.water).toJson();
      expect(json['glassRipple'], 'water');
      expect(json['glassMaterial'], 'regular');
      expect(json['glassRendering'], 'glass');
      expect(json['glassTint'], 'neutral');
      expect(json['glassContrast'], 'auto');
    });

    test('不再写已经删掉的那个不透明度键', () {
      // 滑条连同这个字段一起删了：它只对磨砂档有效，而磨砂档已经不在面板上。
      final json = const AppSettings().toJson();
      expect(json.containsKey('glassSurfaceOpacity'), isFalse);
    });

    test('老配置没有这些键 → 走默认，不报错', () {
      final loaded = AppSettings.fromJson(const {});
      expect(loaded.glassMaterial, GlassMaterial.regular);
      expect(loaded.glassRendering, GlassRendering.glass);
      expect(loaded.glassRipple, GlassRippleKind.off);
      expect(loaded.glassContrast, GlassContrast.auto);
    });

    test('键值认不出来（手改坏了 / 降级）→ 回默认而不是崩', () {
      final loaded = AppSettings.fromJson(const {
        'glassMaterial': 'obsidian',
        'glassRendering': 'ultra',
        'glassRipple': 'molasses',
        'glassContrast': 'maximum',
      });
      expect(loaded.glassMaterial, GlassMaterial.regular);
      expect(loaded.glassRendering, GlassRendering.glass);
      expect(loaded.glassRipple, GlassRippleKind.off);
      expect(loaded.glassContrast, GlassContrast.auto);
    });

    test('老版本存下的 glassQuality / glassTier 照样能读回来', () {
      // 改名的迁移路径：老键还在，值也还认得。
      expect(
        AppSettings.fromJson(const {'glassQuality': 'liquid'}).glassMaterial,
        GlassMaterial.regular,
        reason: 'liquid 就是标准材质的旧名字',
      );
      expect(
        AppSettings.fromJson(const {'glassQuality': 'frosted'}).glassMaterial,
        GlassMaterial.frosted,
      );
      expect(
        AppSettings.fromJson(const {'glassQuality': 'clear'}).glassMaterial,
        GlassMaterial.clear,
      );
      expect(
        AppSettings.fromJson(const {'glassQuality': 'off'}).glassMaterial,
        GlassMaterial.regular,
        reason: '材质档里没有"关闭"，关不关由调用点自己说',
      );

      expect(
        AppSettings.fromJson(const {'glassTier': 'auto'}).glassRendering,
        GlassRendering.glass,
        reason: 'auto 判出来就是 full，所以并到玻璃档',
      );
      expect(
        AppSettings.fromJson(const {'glassTier': 'cheap'}).glassRendering,
        GlassRendering.translucent,
      );
      expect(
        AppSettings.fromJson(const {'glassTier': 'opaque'}).glassRendering,
        GlassRendering.opaque,
      );
    });

    test('新键优先于老键（同存时以新键为准）', () {
      final loaded = AppSettings.fromJson(const {
        'glassQuality': 'frosted',
        'glassMaterial': 'dark',
        'glassTier': 'opaque',
        'glassRendering': 'glass',
      });
      expect(loaded.glassMaterial, GlassMaterial.dark);
      expect(loaded.glassRendering, GlassRendering.glass);
    });
  });
}
