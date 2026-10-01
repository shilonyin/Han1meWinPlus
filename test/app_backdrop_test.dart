import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_backdrop.dart';
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
