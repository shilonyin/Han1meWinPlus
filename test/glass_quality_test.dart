import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/app_surface_tokens.dart';
import 'package:han1me_win_plus/src/core/color_contrast.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/settings/settings_list.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_panel.dart';


/// 固定返回一份设置的替身（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this.initial);
  final AppSettings initial;
  @override
  Future<AppSettings> build() async => initial;
}

void main() {
  group('AppSurfaceTokens.densityFor（可读性判定的底色来源）', () {
    // 原来这里还有一条「与三档实际渲染的底色浓度一致」——玻璃渲染换成 g1455
    // 之后它失去了对照物（渲染不再由 `densityFor` 驱动），所以删掉。
    // `densityFor` 现在只服务一件事：把面板压成等效底色，好判断文字读不读得清。
    test('磨砂档浓度跟滑条走，另外两档固定', () {
      expect(AppSurfaceTokens.densityFor(GlassQuality.frosted, .3), .3);
      expect(AppSurfaceTokens.densityFor(GlassQuality.frosted, 1), 1);
      expect(AppSurfaceTokens.densityFor(GlassQuality.clear, .3),
          AppSurfaceTokens.densityFor(GlassQuality.clear, 1));
      expect(AppSurfaceTokens.densityFor(GlassQuality.liquid, .3),
          AppSurfaceTokens.densityFor(GlassQuality.liquid, 1));
    });

    test('关闭档为 0（不走玻璃渲染）', () {
      expect(AppSurfaceTokens.densityFor(GlassQuality.off, .8), 0);
    });

    test('三档浓度互不相同，不是换个名字', () {
      final values = {
        AppSurfaceTokens.densityFor(GlassQuality.frosted, .5),
        AppSurfaceTokens.densityFor(GlassQuality.clear, .5),
        AppSurfaceTokens.densityFor(GlassQuality.liquid, .5),
      };
      expect(values.length, 3);
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
