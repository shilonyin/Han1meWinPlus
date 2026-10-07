// 回归测试：漫画卡片必须是**可聚焦的按钮**，而不是裸 GestureDetector。
//
// 背景（better-accessibility 清单）：
// 漫画网格里的整块卡片原本是 `GestureDetector(onTap: ...)` —— 键盘 Tab 到不了、
// Enter/Space 无反应，读屏也读不出「这是能点开的」。现在改成
// `Material(transparency) → PressScale → InkWell`：InkWell 自带 ActivateIntent
// （Enter/Space 激活）与 onTap 语义，焦点高亮单独给（水波纹被关掉了，否则键盘
// 用户看不出焦点停在哪儿）。
//
// 这个测试只断言「结构上确实可聚焦、确实能激活、点完真的跳转」——不去等封面图，
// 所以用单帧 pump 而不是 pumpAndSettle（后者会一直等网络图片）。
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han1me_win_plus/src/domain/models/comic.dart';
import 'package:han1me_win_plus/src/features/comics/comic_pages.dart';

const _comic = ComicCard(id: '42', title: '测试漫画标题', coverUrl: 'https://example.invalid/c.jpg');

/// 卡片点开后落到 `/comics/42`，用一个能读出路径的替身页代替真实详情页
/// （真实页会去抓网络）。
Widget _app() => MaterialApp.router(
  routerConfig: GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const Scaffold(
          body: SizedBox(width: 220, height: 320, child: ComicTile(comic: _comic)),
        ),
      ),
      GoRoute(
        path: '/comics/:id',
        builder: (context, state) => Scaffold(
          body: Text('详情 ${state.pathParameters['id']}'),
        ),
      ),
    ],
  ),
);

void main() {
  testWidgets('漫画卡片是 InkWell（可聚焦、有 onTap 语义），不是裸 GestureDetector', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _app()));
    await tester.pump();

    expect(find.byType(InkWell), findsOneWidget);
    final inkWell = tester.widget<InkWell>(find.byType(InkWell));
    expect(inkWell.onTap, isNotNull, reason: '卡片必须能点开');
    // 焦点高亮：水波纹关掉之后，焦点圈是键盘用户唯一能看到的落点提示。
    expect(inkWell.focusColor, isNotNull, reason: '水波纹关掉了，必须给焦点底色');
  });

  testWidgets('键盘 Enter 能激活卡片并跳转到详情', (tester) async {
    await tester.pumpWidget(ProviderScope(child: _app()));
    await tester.pump();

    // 模拟 Tab 把焦点送到卡片上（InkWell 的 canRequestFocus 默认为真）。
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('详情 42'), findsOneWidget, reason: 'Enter 应当触发 onTap 并跳转');
  });
}
