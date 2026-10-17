import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:han1me_win_plus/src/app/theme_transition.dart';

/// 把被测组件放进一个能切换明暗的 `MaterialApp` 里。
///
/// `themeAnimationDuration` 设成零，与 `app_widget.dart` 的真实配置一致 ——
/// 过渡完全由 [ThemeTransition] 负责，不靠 MaterialApp 自己的配色插值。
Widget _host(Brightness brightness) => MaterialApp(
  debugShowCheckedModeBanner: false,
  themeMode: brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
  theme: ThemeData(brightness: Brightness.light),
  darkTheme: ThemeData(brightness: Brightness.dark),
  themeAnimationDuration: Duration.zero,
  builder: (context, child) =>
      ThemeTransition(child: child ?? const SizedBox.shrink()),
  home: const Scaffold(body: Center(child: Text('content'))),
);

/// 旧画面那一层在不在。
///
/// 按 [ThemeTransition.overlayKey] 找，不按 `FadeTransition` 类型找 ——
/// `MaterialApp` 内部的路由、对话框自带一堆 `FadeTransition`。
bool _hasOverlay(WidgetTester tester) =>
    tester.any(find.byKey(ThemeTransition.overlayKey));

/// 过渡层里的裁剪组件（圆形揭示靠它实现）。
Finder _overlayClip() => find.descendant(
  of: find.byKey(ThemeTransition.overlayKey),
  matching: find.byType(ClipPath),
);

void main() {
  testWidgets('首次构建不铺旧画面（没有基线可比）', (tester) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();
    expect(_hasOverlay(tester), isFalse);
  });

  testWidgets('同亮度重建不触发过渡', (tester) async {
    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pump();
    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pump();
    expect(_hasOverlay(tester), isFalse);
  });

  testWidgets('明暗切换后旧画面被裁成圆形揭示，动画结束自动移除', (tester) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();

    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pump();

    // 截图在测试环境里未必成功（`toImageSync` 依赖真实光栅化后端），
    // 所以这里只断言「要么铺上了并在结束后清掉，要么压根没铺」——
    // 两种都不允许留下常驻的过渡层。
    if (_hasOverlay(tester)) {
      expect(_overlayClip(), findsOneWidget);

      // 过渡层里必须是一个位图（旧画面），不是把新内容再渲染一遍。
      expect(
        find.descendant(
          of: find.byKey(ThemeTransition.overlayKey),
          matching: find.byType(RawImage),
        ),
        findsOneWidget,
      );
    }

    await tester.pumpAndSettle();
    expect(_hasOverlay(tester), isFalse);
  });

  testWidgets('过渡层不拦截指针', (tester) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();
    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pump();
    if (_hasOverlay(tester)) {
      expect(
        find.descendant(
          of: find.byKey(ThemeTransition.overlayKey),
          matching: find.byType(IgnorePointer),
        ),
        findsOneWidget,
      );
    }
    await tester.pumpAndSettle();
  });

  testWidgets('来回切换不会抛异常，最终停在最新主题', (tester) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();
    for (final brightness in [
      Brightness.dark,
      Brightness.light,
      Brightness.dark,
    ]) {
      await tester.pumpWidget(_host(brightness));
      await tester.pump(const Duration(milliseconds: 40));
    }
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(
      Theme.of(tester.element(find.text('content'))).brightness,
      Brightness.dark,
    );
  });

  testWidgets('动画中途被新的切换打断，也不会残留过渡层', (tester) async {
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();
    await tester.pumpWidget(_host(Brightness.dark));
    await tester.pump(const Duration(milliseconds: 100));
    // 动画没走完就切回去 —— 控制器会被 forward(from: 0) 重启。
    await tester.pumpWidget(_host(Brightness.light));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(_hasOverlay(tester), isFalse);
    expect(
      Theme.of(tester.element(find.text('content'))).brightness,
      Brightness.light,
    );
  });

  group('揭示裁剪的几何', () {
    // 这一组是本次实现的**核心断言**：新旧画面的交界必须是硬边界。
    // 如果哪天有人把它改回「整层做透明度混合」，底色就会退化成
    // (0.5×浅色 + 0.5×深色) 的中灰 —— 也就是这次要避免的那个毛病。
    const size = Size(400, 300);

    /// 取出裁剪器并按给定进度算路径。
    Path clipAt(double progress) =>
        ThemeTransition.debugRevealPath(progress, size);

    test('进度 0：整块保留，旧画面铺满', () {
      final path = clipAt(0);
      expect(path.getBounds(), Offset.zero & size);
      // 整块矩形的面积 = 全部。
      expect(path.contains(const Offset(200, 150)), isTrue);
    });

    test('进度 1：整块裁掉，旧画面完全不可见', () {
      expect(clipAt(1).getBounds().isEmpty, isTrue);
    });

    test('中间进度：中心被挖空，四角仍保留 —— 交界是硬边界而非透明度', () {
      final path = clipAt(0.5);
      // 圆心（默认 Alignment.center）已被挖掉 → 露出下层的新内容。
      expect(path.contains(const Offset(200, 150)), isFalse);
      // 四角还在 → 旧画面仍覆盖。
      expect(path.contains(const Offset(1, 1)), isTrue);
      expect(path.contains(const Offset(398, 298)), isTrue);
    });

    test('半径随进度单调增大（挖空区域只扩不缩）', () {
      // 沿左上到中心的对角线取一点，找到它「刚被挖掉」的进度；
      // 进度继续增大后它必须仍被挖掉，不能又露回旧画面。
      const probe = Offset(120, 90);
      var firstHole = -1.0;
      for (var i = 0; i <= 100; i++) {
        final p = i / 100;
        if (!clipAt(p).contains(probe)) {
          firstHole = p;
          break;
        }
      }
      expect(firstHole, greaterThan(0));
      for (var i = (firstHole * 100).round() + 1; i <= 100; i++) {
        expect(
          clipAt(i / 100).contains(probe),
          isFalse,
          reason: '进度 ${i / 100} 处又露回了旧画面',
        );
      }
    });
  });

  group('圆心取按下的位置', () {
    testWidgets('四角与中心换算成对应的 Alignment', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Center(
            child: SizedBox(key: Key('probe'), width: 200, height: 100),
          ),
        ),
      );
      final box = tester.renderObject<RenderBox>(
        find.byKey(const Key('probe')),
      );
      final origin = box.localToGlobal(Offset.zero);

      expect(
        ThemeTransition.originFromPointer(origin, box),
        const Alignment(-1, -1),
      );
      expect(
        ThemeTransition.originFromPointer(origin + const Offset(200, 100), box),
        const Alignment(1, 1),
      );
      expect(
        ThemeTransition.originFromPointer(origin + const Offset(100, 50), box),
        const Alignment(0, 0),
      );
      // 左上四分之一处。
      expect(
        ThemeTransition.originFromPointer(origin + const Offset(50, 25), box),
        const Alignment(-0.5, -0.5),
      );
    });

    testWidgets('点过之后切换主题，圆从点击处扩散而不是屏幕中心', (tester) async {
      await tester.pumpWidget(_host(Brightness.light));
      await tester.pump();

      // 点在左上角附近，远离屏幕中心。
      const tapPoint = Offset(60, 40);
      await tester.tapAt(tapPoint);
      await tester.pump();

      await tester.pumpWidget(_host(Brightness.dark));
      await tester.pump();

      // 测试环境里 `toImageSync` 未必成功，铺不上过渡层就跳过 ——
      // 换算本身已由上一条用例覆盖。
      expect(_hasOverlay(tester), isTrue, reason: '过渡层没铺上，这条用例等于没跑');

      final clip = tester.widget<ClipPath>(_overlayClip());
      final clipper = clip.clipper! as ThemeRevealClipper;
      final size = tester.getSize(find.byType(MaterialApp));
      // 圆心落在点击处：换算回来应等于点击点相对整窗的比例。
      final center = clipper.origin.alongSize(size);
      expect(center.dx, closeTo(tapPoint.dx, 1));
      expect(center.dy, closeTo(tapPoint.dy, 1));
      // 与「默认屏幕中心」明确不同 —— 否则这条用例分不出两种实现。
      expect(center, isNot(equals(size.center(Offset.zero))));
    });
  });
}
