import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/color_contrast.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/settings/settings_list.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_panel.dart';
import 'package:han1me_win_plus/src/features/shared/glass/liquid_glass.dart';

/// 固定返回一份设置的替身（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this.initial);
  final AppSettings initial;
  @override
  Future<AppSettings> build() async => initial;
}

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

  group('GlassMaterial.densityFor（渲染与可读性判定的唯一来源）', () {
    test('与三档实际渲染的底色浓度一致', () {
      // densityFor 存在的理由：GlassPanel 要按它把面板压成等效底色来判断可读性。
      // 若它和渲染用的浓度漂移，可读性判定就会基于错误的底色。
      for (final quality in [
        GlassQuality.frosted,
        GlassQuality.clear,
        GlassQuality.liquid,
      ]) {
        final rendered =
            ((GlassMaterial.quality(
                      quality: quality,
                      tint: const Color(0xff888888),
                      dark: false,
                      readable: false,
                      borderRadius: BorderRadius.circular(8),
                      opacity: .5,
                    ).decoration.gradient! as LinearGradient)
                  .colors
                  .first
                  .a)
            .clamp(0.0, 1.0);
        // 渲染的首个 stop 就是 density × 1.0（shade(1.0)）。
        expect(rendered, closeTo(GlassMaterial.densityFor(quality, .5), .001));
      }
    });

    test('磨砂档浓度跟滑条走，另外两档固定', () {
      expect(GlassMaterial.densityFor(GlassQuality.frosted, .3), .3);
      expect(GlassMaterial.densityFor(GlassQuality.frosted, 1), 1);
      expect(GlassMaterial.densityFor(GlassQuality.clear, .3),
          GlassMaterial.densityFor(GlassQuality.clear, 1));
      expect(GlassMaterial.densityFor(GlassQuality.liquid, .3),
          GlassMaterial.densityFor(GlassQuality.liquid, 1));
    });
  });

  group('GlassPanel 可读性接入', () {
    testWidgets('子树能拿到面板等效底色，且它是不透明的', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
            home: GlassPanel(
              borderRadius: BorderRadius.circular(18),
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox(width: 100, height: 40);
                },
              ),
            ),
          ),
        ),
      );
      final surface = GlassPanelScope.surfaceColorOf(ctx);
      expect(surface, isNotNull);
      expect(surface!.a, 1.0);
    });

    testWidgets('面板外的子树拿不到底色（不该硬套兜底）', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
            home: Builder(
              builder: (context) {
                ctx = context;
                return const SizedBox();
              },
            ),
          ),
        ),
      );
      expect(GlassPanelScope.surfaceColorOf(ctx), isNull);
      // 拿不到底色时原样返回候选色，不改动普通页面上的颜色。
      final scheme = Theme.of(ctx).colorScheme;
      expect(GlassPanelTextColor.resolve(ctx), scheme.onSurfaceVariant);
    });

    testWidgets('定位到真实短板：浅色磨砂面板上的次要文字被兜到达标', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
            home: GlassPanel(
              borderRadius: BorderRadius.circular(18),
              child: Builder(
                builder: (context) {
                  ctx = context;
                  return const SizedBox(width: 200, height: 40);
                },
              ),
            ),
          ),
        ),
      );
      final surface = GlassPanelScope.surfaceColorOf(ctx)!;
      final scheme = Theme.of(ctx).colorScheme;

      // 未兜底前这个值在浅色玻璃上只有 4.2 左右 —— 这条断言就是本改动的理由。
      final resolved = GlassPanelTextColor.resolve(ctx);
      expect(contrastRatio(resolved, surface), greaterThanOrEqualTo(4.5));
      // 但不能变成正文色：次要文字的层次要保住。
      expect(resolved, isNot(scheme.onSurface));
    });
  });

  group('端到端：真实设置列表里的次要文字确实被兜到', () {
    testWidgets('SettingsTile 描述文字在浅色玻璃上达标（证明接入不是死代码）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => _StubSettings(
                const AppSettings(glassQuality: GlassQuality.frosted),
              ),
            ),
          ],
          child: MaterialApp(
            theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
            home: Scaffold(
              body: SettingsList(
                sections: [
                  SettingsSection(
                    tiles: [
                      SettingsTile.navigation(
                        title: const Text('标题'),
                        description: const Text('描述'),
                        leading: const Icon(Icons.info_outline),
                        onPressed: (_) {},
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // 描述文字渲染出来了，且它的颜色在面板底色上达标。
      final description = tester.widget<Text>(
        find.text('描述'),
      );
      expect(description, isNotNull);

      // 取出真正用于渲染的颜色：由 DefaultTextStyle 合并而来。
      final richText = tester.widget<RichText>(
        find.descendant(
          of: find.text('描述'),
          matching: find.byType(RichText),
        ),
      );
      final painted = richText.text.style!.color!;

      // 面板等效底色从作用域取（与运行时同一来源）。
      final ctx = tester.element(find.text('描述'));
      final surface = GlassPanelScope.surfaceColorOf(ctx);
      expect(surface, isNotNull, reason: '设置条目应当位于 GlassPanel 子树内');

      // 自证式断言：同一个底色上，**未兜底**的 onSurfaceVariant 确实不达标。
      // 有这一条，下面的"达标"才说明兜底真的起了作用，而不是本来就好。
      final scheme = Theme.of(ctx).colorScheme;
      expect(
        contrastRatio(scheme.onSurfaceVariant, surface!),
        lessThan(4.5),
        reason: '若这里本就达标，本测试就测不出兜底是否生效（换主题色再跑）',
      );
      expect(
        contrastRatio(painted, surface),
        greaterThanOrEqualTo(4.5),
        reason: '兜底没生效 —— 说明 SettingsTile 没落在 GlassPanel 子树内，接入是死代码',
      );
      // 层次仍在：兜底不该把次要文字变成正文色。
      expect(painted, isNot(scheme.onSurface));
    });
  });
}
