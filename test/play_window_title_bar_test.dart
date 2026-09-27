// 播放窗口顶部栏的组件测试：结构、标题联动、上下集置灰、以及**悬停形状统一**。
//
// 参考实现（PixPin 截图）里这条栏从左到右是：
//   [🏠 回到主界面] [‹] [›]      居中标题      [置顶] [画中画] | [─] [□] [✕]
// 实测尺寸：72 物理 px @150% DPI = 48 逻辑 px，底色 #1E2022。
//
// 这里锁住两件事：
//  1. 「标题与可用性来自 PlayWindowTitleTarget，会跟着变」——本组件与播放页之间
//     唯一的数据通道。
//  2. 「栏里所有可点项的悬停高亮是同一个圆角矩形」——用户报过「左边圆角、右边
//     不是，不统一」，根因是四处各写各的（胶囊 / IconButton 圆形水波 / 直角方块）。
//     现在全部走 _BarButton，用同一组常量。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/core/play_window_title_target.dart';
import 'package:han1me_win_plus/src/features/window/play_window_title_bar.dart';

Widget _host({VoidCallback? onHome}) => MaterialApp(
  locale: const Locale('zh'),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  home: Scaffold(
    body: Column(
      children: [
        PlayWindowTitleBar(onHome: onHome ?? () {}),
        const Expanded(child: ColoredBox(color: Colors.black)),
      ],
    ),
  ),
);

void main() {
  setUp(PlayWindowTitleTarget.reset);
  tearDown(PlayWindowTitleTarget.reset);

  testWidgets('高度与参考实现一致（48 逻辑 px）', (tester) async {
    await tester.pumpWidget(_host());
    final size = tester.getSize(find.byType(PlayWindowTitleBar));
    expect(size.height, playWindowTitleBarHeight);
    expect(size.height, 48);
  });

  testWidgets('画出了「回到主界面」与上一集 / 下一集', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.text('回到主界面'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_left), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsOneWidget);
  });

  testWidgets('画出了置顶 / 画中画 / 三个窗口按钮', (tester) async {
    await tester.pumpWidget(_host());
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.branding_watermark_outlined), findsOneWidget);
    expect(find.byIcon(Icons.remove), findsOneWidget); // 最小化
    expect(find.byIcon(Icons.crop_square), findsOneWidget); // 最大化
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('所有可点项的悬停高亮是同一个圆角矩形（用户报过形状不统一）', (tester) async {
    // 之前「回到主界面」是 8px 圆角胶囊、上一集/下一集是 IconButton 的**圆形**
    // 水波、置顶/画中画与窗口按钮是**直角**方块，鼠标扫过去形状一直在变。
    // 现在全部走 _BarButton，圆角半径一致。
    await tester.pumpWidget(_host());

    // 收集栏里所有「带圆角装饰的容器」，它们的半径必须完全一致。
    final radii = <double>{};
    var decorated = 0;
    for (final element in find
        .descendant(
          of: find.byType(PlayWindowTitleBar),
          matching: find.byType(Container),
        )
        .evaluate()) {
      final decoration = (element.widget as Container).decoration;
      if (decoration is! BoxDecoration) continue;
      final radius = decoration.borderRadius;
      if (radius is! BorderRadius) continue;
      radii.add(radius.topLeft.x);
      decorated++;
    }

    expect(
      decorated,
      greaterThanOrEqualTo(7),
      reason: '标题栏里应有 7 个可点项（回到主界面 / 上下集 / 置顶 / 画中画 / 三个窗口按钮）',
    );
    expect(
      radii,
      hasLength(1),
      reason: '所有可点项的圆角半径必须一致，不能一半圆角一半直角：$radii',
    );
  });

  testWidgets('可点项都是圆角矩形，没有圆形水波（IconButton 默认形态）', (tester) async {
    await tester.pumpWidget(_host());
    // IconButton 默认会画圆形 InkResponse；统一之后栏里不该再有 IconButton。
    expect(
      find.descendant(
        of: find.byType(PlayWindowTitleBar),
        matching: find.byType(IconButton),
      ),
      findsNothing,
      reason: '图标按钮统一成 _BarButton，不应再用 IconButton（圆形水波与圆角不一致）',
    );
  });

  testWidgets('所有可点项的高亮块尺寸一致（同一高度、按内容/固定宽）', (tester) async {
    // 形状统一不只是圆角半径一致，高亮块的高度也得一样——否则鼠标扫过去
    // 高亮块忽高忽低，同样割裂。
    await tester.pumpWidget(_host());

    final sizes = <String, Size>{};
    for (final entry in <String, IconData>{
      '回到主界面': Icons.home_outlined,
      '上一集': Icons.chevron_left,
      '下一集': Icons.chevron_right,
      '置顶': Icons.push_pin_outlined,
      '画中画': Icons.branding_watermark_outlined,
      '最小化': Icons.remove,
      '最大化': Icons.crop_square,
      '关闭': Icons.close,
    }.entries) {
      // 找到图标外层那个带圆角背景的 Container
      final container = find
          .ancestor(
            of: find.byIcon(entry.value),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is Container &&
                  w.decoration is BoxDecoration &&
                  (w.decoration! as BoxDecoration).borderRadius != null,
            ),
          )
          .first;
      sizes[entry.key] = tester.getSize(container);
    }

    final heights = sizes.values.map((s) => s.height).toSet();
    expect(
      heights,
      hasLength(1),
      reason: '所有高亮块高度必须一致，实测：$sizes',
    );
    // 高度 = 标题栏高 - 上下各 6px 留白
    expect(heights.single, playWindowTitleBarHeight - 12);

    // 窗口按钮三个宽度一致（46）
    expect(sizes['最小化']!.width, sizes['最大化']!.width);
    expect(sizes['最大化']!.width, sizes['关闭']!.width);
  });

  testWidgets('标题来自登记表，登记后立即显示', (tester) async {
    await tester.pumpWidget(_host());
    // 初始为空（播放页还没报）。
    expect(find.text('第1话 王令想要平静的生活'), findsNothing);

    PlayWindowTitleTarget.register(
      owner: Object(),
      title: '第1话 王令想要平静的生活',
      hasPrevious: false,
      hasNext: true,
    );
    await tester.pump();

    expect(find.text('第1话 王令想要平静的生活'), findsOneWidget);
  });

  testWidgets('没有上一集时左箭头不可点，有下一集时右箭头可点', (tester) async {
    await tester.pumpWidget(_host());
    PlayWindowTitleTarget.register(
      owner: Object(),
      title: '第1话',
      hasPrevious: false,
      hasNext: true,
      onNext: () {},
    );
    await tester.pump();

    // 可用性体现在 Semantics 的 enabled 上（图标按钮已统一成 _BarButton，
    // 不再是 IconButton）。禁用时 Semantics.enabled 为 false。
    final left = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byIcon(Icons.chevron_left),
            matching: find.byType(Semantics),
          )
          .first,
    );
    final right = tester.widget<Semantics>(
      find
          .ancestor(
            of: find.byIcon(Icons.chevron_right),
            matching: find.byType(Semantics),
          )
          .first,
    );
    expect(
      left.properties.enabled,
      isFalse,
      reason: '第一集不该能点「上一集」',
    );
    expect(right.properties.enabled, isTrue);
  });

  testWidgets('点「回到主界面」触发回调', (tester) async {
    var taps = 0;
    await tester.pumpWidget(_host(onHome: () => taps++));
    await tester.tap(find.text('回到主界面'));
    // 外层 GestureDetector 带 onDoubleTap，DoubleTapGestureRecognizer 会扣住手势
    // 约 300ms 等第二击（这是 Flutter 的既有行为），所以要等过那个窗口再断言。
    await tester.pump(const Duration(milliseconds: 400));
    expect(taps, 1);
  });

  testWidgets('标题变化后顶部栏跟着更新（换集场景）', (tester) async {
    await tester.pumpWidget(_host());
    final page = Object();
    PlayWindowTitleTarget.register(
      owner: page,
      title: '第1话',
      hasPrevious: false,
      hasNext: true,
    );
    await tester.pump();
    expect(find.text('第1话'), findsOneWidget);

    // 点下一集：新页面登记第2话。
    PlayWindowTitleTarget.register(
      owner: Object(),
      title: '第2话',
      hasPrevious: true,
      hasNext: false,
    );
    await tester.pump();
    expect(find.text('第2话'), findsOneWidget);
    expect(find.text('第1话'), findsNothing);
  });
}
