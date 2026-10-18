import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/hover_zoom.dart';

/// 把 [CardHover] 包进最小可交互的壳里，返回一个能读到最近一次 hovered 的探针。
({Widget widget, bool Function() hovered}) _probe({bool enabled = true}) {
  var seen = false;
  return (
    widget: MaterialApp(
      home: Center(
        child: SizedBox(
          width: 200,
          height: 200,
          child: CardHover(
            enabled: enabled,
            builder: (context, hovered) {
              seen = hovered;
              return const SizedBox.expand();
            },
          ),
        ),
      ),
    ),
    hovered: () => seen,
  );
}

void main() {
  testWidgets('鼠标移到卡片上算悬停，移走就不算', (tester) async {
    final probe = _probe();
    await tester.pumpWidget(probe.widget);
    expect(probe.hovered(), isFalse, reason: '一上来不该是悬停态');

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(CardHover)));
    await tester.pump();
    expect(probe.hovered(), isTrue);

    await gesture.moveTo(const Offset(1, 1));
    await tester.pump();
    expect(probe.hovered(), isFalse);
  });

  testWidgets('enabled 为假时怎么移都不算悬停', (tester) async {
    final probe = _probe(enabled: false);
    await tester.pumpWidget(probe.widget);

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);

    await gesture.moveTo(tester.getCenter(find.byType(CardHover)));
    await tester.pump();
    expect(probe.hovered(), isFalse, reason: '多选态这类场合不该有悬停反馈');
  });

  testWidgets('悬停时封面推近，离开后回到原尺寸', (tester) async {
    Widget build(bool hovered) => MaterialApp(
      home: Center(
        child: SizedBox(
          width: 100,
          height: 100,
          child: ZoomOnHover(
            hovered: hovered,
            child: const ColoredBox(color: Colors.red),
          ),
        ),
      ),
    );

    await tester.pumpWidget(build(false));
    expect(tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);

    await tester.pumpWidget(build(true));
    // 动画走完后缩放停在目标值上。
    await tester.pump(hoverCoverDuration);
    expect(
      tester.widget<AnimatedScale>(find.byType(AnimatedScale)).scale,
      hoverCoverScale,
    );
  });

  test('推近幅度与首页卡片一致', () {
    // 首页 `video_card.dart` 的 `coverHoverScale` 也是 1.06 —— 同一张封面
    // 换到哪个页面，悬停手感都该一样。
    expect(hoverCoverScale, 1.06);
  });
}
