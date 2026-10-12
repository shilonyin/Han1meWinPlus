import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;
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
///
/// **另外**：第一版修复只改了「清哪些域名」，却把交给原生层的 URL 拼成了裸主机加
/// 斜杠（`hanime1.me/`），那是个 scheme/host 双空的相对地址 —— Windows 端
/// `deleteCookies` 拿它去调 `Network.getCookies` 取回空列表，**什么都没删还回调
/// `true`**。清理整个是空转的，所以 bug 依旧。下面那组
/// 「交给原生层的 URL」用例钉的就是这个二次缺陷。
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

  group('交给原生层的 URL 必须是绝对地址（issue #18 二次修复）', () {
    test('裸主机拼出来的 WebUri 是坏的 —— 这正是必须带 scheme 的原因', () {
      // 把这个反例留在测试里，免得以后有人又把 '$host/' 当捷径写回去。
      final broken = webview.WebUri('hanime1.me/');
      expect(broken.scheme, isEmpty);
      expect(broken.host, isEmpty,
          reason: 'host 为空时原生 Network.getCookies 取不到任何 cookie，删除会静默空转');
    });

    test('webViewCookieUrlsFor 产出的每个 URL 都带 scheme 与 host', () {
      for (final uri in [
        Uri.parse('https://hanime1.me/login'),
        Uri.parse('https://hanime1.com'),
        Uri.parse('https://www.hanime1.me/login'),
      ]) {
        final urls = webViewCookieUrlsFor(uri);
        expect(urls, hasLength(webViewCookieHostsFor(uri).length));
        for (final url in urls) {
          expect(url.scheme, 'https');
          expect(url.host, isNotEmpty,
              reason: '发给 CookieManager.deleteCookies 的 URL 没有 host，清理会静默失效');
          expect(url.path, '/');
        }
      }
    });

    test('传进来的地址没带 scheme 时兜底成 https，host 仍然是好的', () {
      // logout() 走的是 settings.resolvedBaseUrl，这里防的是它哪天变成裸主机。
      final urls = webViewCookieUrlsFor(Uri.parse('hanime1.me'));
      expect(urls.map((webview.WebUri url) => url.host),
          containsAll(['hanime1.me', 'www.hanime1.me']));
      for (final url in urls) {
        expect(url.scheme, 'https');
      }
    });
  });
}

