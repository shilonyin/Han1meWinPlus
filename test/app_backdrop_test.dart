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
      await tester.pumpWidget(
        MaterialApp(
          home: AppBackdrop(enabled: false, child: const Center(child: Text('仅内容'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('仅内容'), findsOneWidget);
      // 画布本身就是一层 ColoredBox，所以按「AppBackdrop 子树里有没有它」判，
      // 而不是数全局数量 —— MaterialApp 自己也会铺底色，数量比不出结论。
      expect(
        find.descendant(
          of: find.byType(AppBackdrop),
          matching: find.byType(ColoredBox),
        ),
        findsNothing,
      );
    });

    testWidgets('启用时确实多铺一层画布', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(null, const Color(0xff7662ba)),
          home: const AppBackdrop(child: Center(child: Text('内容'))),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(AppBackdrop),
          matching: find.byType(ColoredBox),
        ),
        findsOneWidget,
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

  group('画布是平的', () {
    /// 把画布真画出来再采样，量「页面离那个平色最多偏多少」。
    ///
    /// 光晕/渐变已经全部删掉（玻璃退役后它们存在的唯一理由消失了），
    /// 所以这里的期望值是 0 —— 留 1 是给取整的余量。这组测试现在的意义是
    /// **卡住"又把光晕加回来"的回归**：早先 0.06~0.08 那组实测暗色 28 / 亮色 13，
    /// 更早的 0.32~0.46 会到 90 上下。
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

    // 实测值（纯平底色）：暗色 0、亮色 0。
    testWidgets('暗色下就是一块平色', (tester) async {
      expect(
        await maxChannelDeviation(tester, Brightness.dark),
        lessThanOrEqualTo(1),
      );
    });

    testWidgets('亮色下就是一块平色', (tester) async {
      expect(
        await maxChannelDeviation(tester, Brightness.light),
        lessThanOrEqualTo(1),
      );
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
