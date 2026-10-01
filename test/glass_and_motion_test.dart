import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/app_motion.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/shared/glass/liquid_glass.dart';

void main() {
  group('动效规范层 AppMotion', () {
    test('时长与曲线引用 Material 3 官方 token', () {
      expect(AppMotion.instant, Durations.short1);
      expect(AppMotion.quick, Durations.short2);
      expect(AppMotion.brief, Durations.short3);
      expect(AppMotion.standard, Durations.short4);
      expect(AppMotion.emphasis, Durations.medium1);
      expect(AppMotion.dialog, Durations.medium2);
      expect(AppMotion.page, Durations.medium4);
      expect(AppMotion.enter, Easing.emphasizedDecelerate);
      expect(AppMotion.exit, Easing.emphasizedAccelerate);
    });

    testWidgets('减少动画时 motionDuration 归零', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Builder(
            builder: (context) {
              ctx = context;
              return const SizedBox();
            },
          ),
        ),
      );
      expect(motionEnabledOf(ctx), isFalse);
      expect(motionDuration(ctx, AppMotion.emphasis), Duration.zero);
    });
  });

  group('毛玻璃设置项', () {
    test('默认关闭', () {
      expect(const AppSettings().glassSurfaceEnabled, isFalse);
    });

    test('copyWith 可开启且不改动其它字段', () {
      const base = AppSettings();
      final on = base.copyWith(glassSurfaceEnabled: true);
      expect(on.glassSurfaceEnabled, isTrue);
      expect(on.themeMode, base.themeMode);
      expect(on.preferredQuality, base.preferredQuality);
    });

    test('序列化往返保留开关状态', () {
      final on = const AppSettings().copyWith(glassSurfaceEnabled: true);
      final restored = AppSettings.fromJson(on.toJson());
      expect(restored.glassSurfaceEnabled, isTrue);

      final off = AppSettings.fromJson(const AppSettings().toJson());
      expect(off.glassSurfaceEnabled, isFalse);
    });

    test('旧配置文件缺少该字段时回落到关闭', () {
      final json = const AppSettings().toJson()..remove('glassSurfaceEnabled');
      expect(AppSettings.fromJson(json).glassSurfaceEnabled, isFalse);
    });
  });

  group('毛玻璃组件', () {
    testWidgets('LiquidGlassSurface 可在本项目构建并渲染', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 240,
                height: 120,
                child: LiquidGlassSurface(
                  tint: Colors.indigo,
                  dark: false,
                  borderRadius: BorderRadius.circular(18),
                  child: const Center(child: Text('glass')),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(LiquidGlassSurface), findsOneWidget);
      expect(find.text('glass'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    test('GlassMaterial.liquid 按可读性调整透明度', () {
      final clear = GlassMaterial.liquid(
        tint: Colors.black,
        dark: false,
        readable: false,
        borderRadius: BorderRadius.circular(8),
      );
      final readable = GlassMaterial.liquid(
        tint: Colors.black,
        dark: false,
        readable: true,
        borderRadius: BorderRadius.circular(8),
      );
      expect(clear.blur, 5);
      expect(clear.liquid, 1);
      expect(clear, isNot(equals(readable)));
    });
  });
}
