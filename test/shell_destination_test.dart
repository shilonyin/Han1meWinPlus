// 侧栏 / 抽屉跳转的回归测试。
//
// 这里守的是 [openShellDestination] 的两条约束：
//   1. 分支根恒回根，不恢复该分支上次停留的子页
//   2. 分支内的子路由走 go，不把路径 push 进当前分支的 matchList
//
// 第 2 条是「点了首页却还显示新番」的根因：push 不切 currentIndex，
// 却污染了 matchList，之后 goBranch 恢复的就是那个被污染的位置。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han1me_win_plus/src/features/navigation/shell_destination.dart';

void main() {
  late StatefulNavigationShell shell;
  late BuildContext shellContext;

  /// 与 app_router.dart 同构的最小外壳：分支 0 带子路由，分支 1 带 :tab，分支 2 是根页。
  GoRouter buildRouter() => GoRouter(
        initialLocation: '/',
        routes: [
          StatefulShellRoute.indexedStack(
            builder: (context, state, s) {
              shell = s;
              shellContext = context;
              return Scaffold(body: s);
            },
            branches: [
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/',
                  builder: (c, s) => const Scaffold(body: Text('HOME')),
                  routes: [
                    GoRoute(
                      path: 'previews/:month',
                      builder: (c, s) => const Scaffold(body: Text('PREVIEWS')),
                    ),
                    GoRoute(
                      path: 'check-in',
                      builder: (c, s) => const Scaffold(body: Text('CHECKIN')),
                    ),
                  ],
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/library',
                  builder: (c, s) => const Scaffold(body: Text('LIBRARY')),
                  routes: [
                    GoRoute(
                      path: ':tab',
                      builder: (c, s) => const Scaffold(body: Text('LIBRARY_TAB')),
                    ),
                  ],
                ),
              ]),
              StatefulShellBranch(routes: [
                GoRoute(
                  path: '/cache',
                  builder: (c, s) => const Scaffold(body: Text('CACHE')),
                ),
              ]),
            ],
          ),
        ],
      );

  int count(String t) => find.text(t).evaluate().length;

  Future<void> open(WidgetTester tester, String location) async {
    openShellDestination(shellContext, shell, location);
    await tester.pumpAndSettle();
  }

  Future<void> pumpRouter(WidgetTester tester) async {
    final router = buildRouter();
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));
    await tester.pumpAndSettle();
  }

  group('分支根', () {
    testWidgets('点当前所在页面的按钮，再点别的页面，能切过去', (tester) async {
      await pumpRouter(tester);

      // 用户描述的动作：先点自己所在的页面，再点别的页面。
      await open(tester, '/');
      expect(count('HOME'), 1);

      await open(tester, '/cache');
      expect(count('CACHE'), 1);
      expect(shell.currentIndex, 2);
    });

    testWidgets('新番 → 下载 → 首页，点首页要真的回到首页', (tester) async {
      await pumpRouter(tester);

      await open(tester, '/previews/202610');
      expect(count('PREVIEWS'), 1);

      await open(tester, '/cache');
      expect(count('CACHE'), 1);

      // 修复前这里显示的还是 PREVIEWS：push 污染了分支 0 的 matchList。
      await open(tester, '/');
      expect(count('HOME'), 1);
      expect(count('PREVIEWS'), 0);
      expect(shell.currentIndex, 0);
    });

    testWidgets('在子页上点当前分支的根按钮，回到根而不是停在子页', (tester) async {
      await pumpRouter(tester);

      await open(tester, '/previews/202610');
      expect(count('PREVIEWS'), 1);

      await open(tester, '/');
      expect(count('HOME'), 1);
    });

    testWidgets('三个主页面来回点，每次都显示对应页面', (tester) async {
      await pumpRouter(tester);

      for (final step in [
        ('/', 'HOME'),
        ('/previews/202610', 'PREVIEWS'),
        ('/check-in', 'CHECKIN'),
        ('/previews/202610', 'PREVIEWS'),
        ('/', 'HOME'),
        ('/cache', 'CACHE'),
        ('/', 'HOME'),
      ]) {
        await open(tester, step.$1);
        expect(count(step.$2), 1, reason: '点了 ${step.$1} 应显示 ${step.$2}');
      }
    });
  });

  group('分支内的子路由', () {
    testWidgets('从我的清单子页点首页，能回首页', (tester) async {
      await pumpRouter(tester);

      await open(tester, '/library/favorites');
      expect(count('LIBRARY_TAB'), 1);
      expect(shell.currentIndex, 1);

      await open(tester, '/');
      expect(count('HOME'), 1);
      expect(count('LIBRARY_TAB'), 0);
      expect(shell.currentIndex, 0);
    });

    testWidgets('go 到别的分支的子路由，currentIndex 跟着切过去', (tester) async {
      await pumpRouter(tester);

      await open(tester, '/cache');
      expect(shell.currentIndex, 2);

      await open(tester, '/library/favorites');
      expect(count('LIBRARY_TAB'), 1);
      // push 时代这里会停在 2，页面却已经换成了别的分支的。
      expect(shell.currentIndex, 1);
    });

    testWidgets('子页与分支根之间来回，不会把子页留在栈里', (tester) async {
      await pumpRouter(tester);

      await open(tester, '/previews/202610');
      await open(tester, '/');
      expect(count('HOME'), 1);

      await open(tester, '/previews/202610');
      expect(count('PREVIEWS'), 1);

      // 栈没被污染时，pop 一次就回到首页。
      GoRouter.of(shellContext).pop();
      await tester.pumpAndSettle();
      expect(count('HOME'), 1);
      expect(count('PREVIEWS'), 0);
    });
  });
}
