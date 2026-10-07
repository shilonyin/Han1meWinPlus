import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_backdrop.dart';
import 'package:han1me_win_plus/src/app/app_page_colors.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';

void main() {
  group('背景画布 AppBackdrop', () {
    testWidgets('启用时渲染画布且不抛异常，child 正常显示', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(null, const Color(0xff7662ba)),
          home: const AppBackdrop(child: Center(child: Text('内容'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('内容'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('关闭时直接透传，不额外插一层画布', (tester) async {
      // 先取一个没有 AppBackdrop 的基线：MaterialApp 自身也会有 CustomPaint，
      // 所以要跟基线比数量，而不是断言"一个都没有"。
      await tester.pumpWidget(
        MaterialApp(home: const Center(child: Text('仅内容'))),
      );
      await tester.pumpAndSettle();
      final baseline = tester.widgetList(find.byType(CustomPaint)).length;

      await tester.pumpWidget(
        MaterialApp(
          home: AppBackdrop(enabled: false, child: const Center(child: Text('仅内容'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('仅内容'), findsOneWidget);
      expect(tester.widgetList(find.byType(CustomPaint)).length, baseline);
    });

    testWidgets('启用时确实多画一层画布', (tester) async {
      await tester.pumpWidget(
        MaterialApp(home: const Center(child: Text('内容'))),
      );
      await tester.pumpAndSettle();
      final baseline = tester.widgetList(find.byType(CustomPaint)).length;

      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(null, const Color(0xff7662ba)),
          home: const AppBackdrop(child: Center(child: Text('内容'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widgetList(find.byType(CustomPaint)).length,
        greaterThan(baseline),
      );
    });

    testWidgets('深色主题下同样能渲染（画布走深色配方）', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(null, const Color(0xff7662ba), brightness: Brightness.dark),
          home: const AppBackdrop(child: SizedBox.expand()),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('画布的光晕压得够淡', () {
    /// 把画布真画出来再采样，量「页面离演示站那个平色最多偏多少」。
    ///
    /// 光晕的半径是短边的 0.85~0.95 倍，也就是说整屏每个点都落在某个光晕里，
    /// 所以不能用「页面底色 == 常量」来断言 —— 只能约束最大偏移量。
    Future<int> maxChannelDeviation(
      WidgetTester tester,
      Brightness brightness,
    ) async {
      const key = ValueKey('canvas');
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(null, const Color(0xff7662ba), brightness: brightness),
          home: RepaintBoundary(
            key: key,
            child: const AppBackdrop(child: SizedBox.expand()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(key),
      );
      // toImage 要真的等一次位图回读，必须在 runAsync 里做：测试默认跑在假异步区，
      // 直接 await 会永久挂住（实测 5 分钟不返回）。
      final shot = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
        return (
          bytes: data!.buffer.asUint8List(),
          width: image.width,
          height: image.height,
        );
      });
      final bytes = shot!.bytes;

      final page = AppPageColors.of(brightness);
      final base = [
        (page.r * 255).round(),
        (page.g * 255).round(),
        (page.b * 255).round(),
      ];

      var worst = 0;
      for (var y = 0; y < shot.height; y += 4) {
        for (var x = 0; x < shot.width; x += 4) {
          final i = (y * shot.width + x) * 4;
          for (var c = 0; c < 3; c++) {
            worst = math.max(worst, (bytes[i + c] - base[c]).abs());
          }
        }
      }
      return worst;
    }

    // 实测值（0.06~0.08 这组光晕 + far 只混 5%）：暗色 28、亮色 13。
    // 阈值留一点余量，同时卡住「又把光晕开大」的回归 —— 早先那组 0.32~0.46 会到
    // 90 上下，中途只压到 0.12~0.18 时也还有 60 / 28。
    testWidgets('暗色下最多偏这么多', (tester) async {
      expect(await maxChannelDeviation(tester, Brightness.dark), lessThan(36));
    });

    testWidgets('亮色下最多偏这么多', (tester) async {
      expect(await maxChannelDeviation(tester, Brightness.light), lessThan(18));
    });
  });

  group('Scaffold 让出底色', () {
    test('非 AMOLED 时背景透明，画布才能透出来', () {
      final theme = appTheme(null, const Color(0xff7662ba));
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
    });

    test('AMOLED 时仍是纯黑（画布会被关掉）', () {
      final theme = appTheme(
        null,
        const Color(0xff7662ba),
        brightness: Brightness.dark,
        amoled: true,
      );
      expect(theme.scaffoldBackgroundColor, Colors.black);
    });
  });
}
