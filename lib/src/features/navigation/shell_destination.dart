import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// 打开侧栏 / 抽屉里的一个目的地。
///
/// 分支根走 [StatefulNavigationShell.goBranch]，分支内的子路由走 [GoRouter.go]。
///
/// 两条路都不能换成 `push`：`push` 会把这条路径写进「当前分支」的 matchList，
/// 却不切换 `currentIndex`。之后 `goBranch` 恢复的就是那个被污染的 matchList，
/// 于是点了「首页」显示的却是上次 push 进去的子页 —— 而且侧栏高亮还停在首页，
/// 看上去就像点了没反应。用 `go` 则会让 go_router 重建 matchList 并把
/// `currentIndex` 切到该路径所属的分支。
void openShellDestination(
  BuildContext context,
  StatefulNavigationShell navigationShell,
  String location,
) {
  switch (location) {
    case '/':
      // 恒回分支根：侧栏的「首页」就该是首页，不是首页分支上次停留的子页。
      navigationShell.goBranch(0, initialLocation: true);
    case '/settings':
      navigationShell.goBranch(3, initialLocation: true);
    case '/cache':
      navigationShell.goBranch(2, initialLocation: true);
    default:
      context.go(location);
  }
}
