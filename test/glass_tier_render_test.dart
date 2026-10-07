import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/glass_tier.dart';
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

/// 层级降级必须**真的改变渲染** —— 接了参数但不生效的话，纯函数测试照样全绿。
///
/// 判据不是"看起来不同"，而是 **`LiquidGlassSurface` 有没有被建出来**：
/// 那块 widget 就是背景捕获的来源（它内部是 `BackdropFilter`）。
/// 降级的全部意义就是让一屏少建几块它。
void main() {
  Widget host(
    Widget child, {
    GlassQuality quality = GlassQuality.frosted,
  }) => ProviderScope(
    overrides: [
      settingsProvider.overrideWith(
        () => _StubSettings(AppSettings(glassQuality: quality)),
      ),
    ],
    child: MaterialApp(
      theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
      home: Scaffold(body: Center(child: child)),
    ),
  );

  Widget panel({GlassTier? ceiling, bool reduceTransparency = false}) =>
      GlassPanel(
        borderRadius: BorderRadius.circular(12),
        tierCeiling: ceiling,
        reduceTransparency: reduceTransparency,
        child: const SizedBox(width: 120, height: 60, child: Text('内容')),
      );

  group('tier 降级真的生效（自证式）', () {
    testWidgets('默认（无上限、无减少透明度）→ 建 LiquidGlassSurface', (tester) async {
      await tester.pumpWidget(host(panel()));
      await tester.pumpAndSettle();
      expect(
        find.byType(LiquidGlassSurface),
        findsOneWidget,
        reason: '完整层级必须走真玻璃，否则整个层级体系把默认行为改坏了',
      );
    });

    testWidgets('tierCeiling: cheap → 不建 LiquidGlassSurface（这就是省下的捕获）', (tester) async {
      await tester.pumpWidget(host(panel(ceiling: GlassTier.cheap)));
      await tester.pumpAndSettle();
      expect(
        find.byType(LiquidGlassSurface),
        findsNothing,
        reason: '省捕获档若仍然建了玻璃表面，等于一行代码都没省',
      );
      // 形状与内容还在：降级的是成本，不是身份。
      expect(find.text('内容'), findsOneWidget);
    });

    testWidgets('reduceTransparency → 不建 LiquidGlassSurface', (tester) async {
      await tester.pumpWidget(host(panel(reduceTransparency: true)));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassSurface), findsNothing);
    });

    testWidgets('cheap 与默认的差别只在捕获，不在形状', (tester) async {
      // 两次渲染都用同样的圆角与内容；把容器尺寸取出来比。
      await tester.pumpWidget(host(panel()));
      await tester.pumpAndSettle();
      final full = tester.getSize(find.text('内容'));

      await tester.pumpWidget(host(panel(ceiling: GlassTier.cheap)));
      await tester.pumpAndSettle();
      final cheap = tester.getSize(find.text('内容'));

      expect(cheap, full, reason: '降级不该动布局尺寸');
    });

    testWidgets('tierCeiling: full 等于没设上限 → 仍是真玻璃', (tester) async {
      await tester.pumpWidget(host(panel(ceiling: GlassTier.full)));
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
    });

    testWidgets('关闭档本来就不建玻璃（pre-existing 行为没被破坏）', (tester) async {
      await tester.pumpWidget(
        host(panel(), quality: GlassQuality.off),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassSurface), findsNothing);
    });
  });

  group('端到端：设置列表的长卡片确实封顶在 cheap', () {
    testWidgets('SettingsList 里的行不建 LiquidGlassSurface，但内容正常', (tester) async {
      await tester.pumpWidget(
        host(
          SettingsList(
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
      );
      await tester.pumpAndSettle();

      // 这就是接线是否生效的判据：设置列表是「一长串卡片」，
      // 照 g1455 的用法封顶在省捕获层级。
      expect(
        find.byType(LiquidGlassSurface),
        findsNothing,
        reason: '设置列表若仍在建玻璃表面，tierCeiling 那行就是死代码',
      );
      expect(find.text('标题'), findsOneWidget);
      expect(find.text('描述'), findsOneWidget);
    });
  });
}
