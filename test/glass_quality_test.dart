import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
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

    testWidgets('定位到真实短板：浅色面板上的次要文字被兜到达标', (tester) async {
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
    testWidgets('SettingsTile 描述文字在设置卡片上达标（证明接入不是死代码）', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(
              () => _StubSettings(
                const AppSettings(),
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

      final scheme = Theme.of(ctx).colorScheme;

      // 这里原来还有一条「**未兜底**的 onSurfaceVariant 必须低于 4.5」的自证断言：
      // 那时中性面偏紫，次要文字在浅色玻璃上只有 3.7 左右，兜底是必需品。
      // 底色换成 g1455 演示站的中性面（`AppPageColors`）之后它自己就有 5.46，
      // 那条前置不再成立 —— 这是配色变好，不是兜底失效，所以删掉；
      // 兜底仍然会出手这件事改由下面那条合成用例证明。
      expect(
        contrastRatio(painted, surface!),
        greaterThanOrEqualTo(4.5),
        reason: '兜底没生效 —— 说明 SettingsTile 没落在 GlassPanel 子树内，接入是死代码',
      );
      // 层次仍在：兜底不该把次要文字变成正文色。
      expect(painted, isNot(scheme.onSurface));
    });

    test('底色压得候选色刚好不达标时，兜底必须把它推到 AA（证明兜底不是死代码）', () {
      // 造一组"差一点"的输入：浅色主题的次要文字是深灰（亮度约 .12），
      // 面板底色拿到中性灰（亮度约 .63）时对比度约 4.07 —— 不够 AA，但够得着，
      // 正是 `darkenOrLightenToContrast` 该出手的区间。
      //
      // 走纯函数而不是控件树：面板的等效底色是「tint 按浓度合成到页面上」，
      // 想用 `GlassPanel.tint` 把它精确压到某个亮度既别扭又不稳。
      final scheme = appTheme(
        null,
        AppThemeColor.purple.seedColor('62539F'),
      ).colorScheme;
      final candidate = scheme.onSurfaceVariant;
      const surface = Color(0xffcfcfd6);

      final before = contrastRatio(candidate, surface);
      expect(before, lessThan(4.5));
      // 也不能差到"只能换语义色"的地步（那个阈值是 4.5 * .85 = 3.825），
      // 否则测的是回退分支而不是本改动依赖的明度微调分支。
      expect(before, greaterThan(4.5 * .85));

      final resolved = resolveTextColorOnSurface(
        candidate: candidate,
        surface: surface,
        fallbacks: <Color>[scheme.onSurface, scheme.inverseSurface, scheme.scrim],
      );

      expect(contrastRatio(resolved, surface), greaterThanOrEqualTo(4.5));
      // 首选手段是"只推明度、保住色相"，所以不该跳到正文色上去。
      expect(resolved, isNot(scheme.onSurface));
    });
  });
}
