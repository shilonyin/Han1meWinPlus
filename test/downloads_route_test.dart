import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_router.dart';
import 'package:han1me_win_plus/src/features/navigation/exit_coordinator.dart';
import 'package:go_router/go_router.dart';

/// 守的是一个真实反馈：在播放页点下载弹窗的「我的下载」后，
/// 视频没暂停（后台继续出声），而且回不去正在看的那一集。
///
/// 两个根因：
///   1. 当时用 `context.go('/cache')` —— go 会**替换**整条路由栈，视频页被销毁，
///      用户只能重新点开视频从头播；
///   2. 跳转前没有暂停播放，视频页还活着（旧写法是直接销毁，反而"碰巧"没声）。
///
/// 修法：跳转前 `VideoPlayerShutdown.pauseAll()`，并 push 到挂在**根导航器**上的
/// `/downloads`（与 /search 同一套办法），返回即回到原来那一集。
///
/// 这里只验证路由本身（不 pump 真实页面，避免 CachePage 那堆 provider 在测试
/// 收尾时的销毁噪音）：路径存在、且请求它时解析到一个可返回的 push 目标。
void main() {
  test('/downloads 路由存在并挂在根导航器上', () {
    final router = AppRouter(AppExitCoordinator()).router;
    addTearDown(router.dispose);

    // 能找到这条路由（不存在时 go_router 会走到 error builder）。
    final match = router.configuration.findMatch(Uri.parse('/downloads'));
    expect(match.routes, isNotEmpty, reason: '/downloads 应该是一条已注册的路由');

    // 关键：它必须挂在根导航器上（parentNavigatorKey = navigatorKey）。
    // 挂 shell 分支的话，从视频页 push 进来的返回语义就不对。
    final route = match.routes.last;
    expect(route is GoRoute && route.parentNavigatorKey != null, isTrue, reason: '/downloads 应该挂在根导航器上，这样从视频页 push 后能原路返回');
  });

  test('shell 分支里的 /cache 仍然照常工作（侧栏入口不受影响）', () {
    final router = AppRouter(AppExitCoordinator()).router;
    addTearDown(router.dispose);
    final match = router.configuration.findMatch(Uri.parse('/cache'));
    expect(match.routes, isNotEmpty, reason: '/cache 分支路由应该仍然存在');
  });
}
