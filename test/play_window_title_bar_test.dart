// 播放窗口顶部栏的组件测试：结构、标题联动、上下集置灰。
//
// 参考实现（PixPin 截图）里这条栏从左到右是：
//   [🏠 回到主界面] [‹] [›]      居中标题      [置顶] [画中画] | [─] [□] [✕]
// 实测尺寸：72 物理 px @150% DPI = 48 逻辑 px，底色 #1E2022。
//
// 这里锁住「标题与可用性来自 PlayWindowTitleTarget，会跟着变」这条联动——
// 那是本组件与播放页之间唯一的数据通道。
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

    final left = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_left),
        matching: find.byType(IconButton),
      ),
    );
    final right = tester.widget<IconButton>(
      find.ancestor(
        of: find.byIcon(Icons.chevron_right),
        matching: find.byType(IconButton),
      ),
    );
    expect(left.onPressed, isNull, reason: '第一集不该能点「上一集」');
    expect(right.onPressed, isNotNull);
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
