import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/shared/underline_tab_strip.dart';

/// 可切的页签条：把选中项放在 ValueNotifier 里，测试自己切。
Widget _strip(ValueNotifier<int> index) => MaterialApp(
  home: Scaffold(
    body: ValueListenableBuilder<int>(
      valueListenable: index,
      builder: (context, value, _) => UnderlineTabStrip(
        labels: const ['推荐', '热门', '排行榜'],
        index: value,
        onSelected: (i) => index.value = i,
      ),
    ),
  ),
);

void main() {
  testWidgets('整排只有一根下划线，切页签时滑到新的那一项', (tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(_strip(index));
    await tester.pumpAndSettle();

    // 一根，不是每项各一根。
    expect(find.byKey(UnderlineTabStrip.underlineKey), findsOneWidget);

    final size = tester.getSize(find.byKey(UnderlineTabStrip.underlineKey));
    expect(size.width, UnderlineTabStrip.underlineWidth);
    expect(size.height, UnderlineTabStrip.underlineHeight);

    // 下划线对准选中那一项的中心。
    expect(
      tester.getCenter(find.byKey(UnderlineTabStrip.underlineKey)).dx,
      closeTo(tester.getCenter(find.text('推荐')).dx, 0.5),
    );

    // 切到第三项：滑过去，宽度不变（宽度变了就是「忽胖忽瘦」）。
    index.value = 2;
    await tester.pumpAndSettle();
    expect(
      tester.getCenter(find.byKey(UnderlineTabStrip.underlineKey)).dx,
      closeTo(tester.getCenter(find.text('排行榜')).dx, 0.5),
    );
    expect(
      tester.getSize(find.byKey(UnderlineTabStrip.underlineKey)).width,
      UnderlineTabStrip.underlineWidth,
    );
  });

  testWidgets('插槽按粗体预留宽度：选中与悬停都不挤动邻居', (tester) async {
    final index = ValueNotifier<int>(0);
    addTearDown(index.dispose);
    await tester.pumpWidget(_strip(index));
    await tester.pumpAndSettle();

    final firstBefore = tester.getCenter(find.text('推荐')).dx;
    final lastBefore = tester.getCenter(find.text('排行榜')).dx;

    // 换个选中项：标题字重变了（w600 → w400），但插槽宽度是按粗体预留的，位置不该动。
    index.value = 1;
    await tester.pumpAndSettle();

    expect(tester.getCenter(find.text('推荐')).dx, closeTo(firstBefore, 0.01));
    expect(tester.getCenter(find.text('排行榜')).dx, closeTo(lastBefore, 0.01));
  });
}
