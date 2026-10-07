import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/app_motion.dart';

/// 动效规范层。
///
/// 这个文件原先还测 `glassSurfaceEnabled` 字段与 `LiquidGlassSurface` 的构建，
/// 两者都已随玻璃实现换成 g1455 而退役：
/// - `glassSurfaceEnabled` 本就是个**渲染层不读**的失效字段（档位才是开关）；
/// - `LiquidGlassSurface` 已被 `GlassSurface` 取代。
/// 留着它们只会测一些没人调用的东西，所以一并删掉。
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
}
