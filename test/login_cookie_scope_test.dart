import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';

/// 回归 issue #18「网页里登录成功，应用里依然是未登录」。
///
/// 这条链路上有两个独立的坑，都在「清理 cookie 的范围」上：
///
/// 1. 登录页在 WebView 创建时调 `clearWebViewCookies()`（内部 `deleteAllCookies()`），
///    把 Cloudflare 的 `cf_clearance` 一起抹了。登录页自己就被 CF 挡住，用户登录
///    成功后跳转又被拦在首页前，登录页收不到「已离开登录页」的信号，于是永远不保存。
/// 2. 退出登录同样调 `deleteAllCookies()`，把本机攒下的 CF 凭证丢掉，让下一次登录
///    必然重演坑 1。
///
/// 现在两处都改成「只清本站域名」，`cf_clearance` 保留。这个测试钉住的就是这条边界。
void main() {
  group('登录相关清理的域名范围', () {
    test('清站点 cookie 时同时覆盖裸域与 www，避免残留另一半会话', () {
      // CookieManager.deleteCookies 只作用于传入 URL 的域，登录态常同时在
      // `hanime1.me` 与 `www.hanime1.me` 上各留一份，只清一个仍会是被登录态。
      final targets = webViewCookieHostsFor(Uri.parse('https://hanime1.me/login'));
      expect(targets, containsAll(['hanime1.me', 'www.hanime1.me']));
    });

    test('已经是 www 的地址不再叠加前缀', () {
      final targets = webViewCookieHostsFor(Uri.parse('https://www.hanime1.me/login'));
      expect(targets, equals(['www.hanime1.me']));
    });

    test('清站点 cookie 的范围里不含任何第三方域，cf_clearance 因此不会被波及', () {
      final targets = webViewCookieHostsFor(Uri.parse('https://hanime1.com/login'));
      for (final host in targets) {
        expect(host, anyOf(equals('hanime1.com'), equals('www.hanime1.com')));
      }
      // Cloudflare 的凭证挂在挑战域上；只要清理范围锁在站点自身，它就活下来。
      expect(targets, isNot(contains('challenges.cloudflare.com')));
    });
  });
}
