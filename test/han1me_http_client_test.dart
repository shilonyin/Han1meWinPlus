import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';

/// 镜像站（`hanime1.com` / `hanime1.me` / `hanimeone.me`）之间必须共享 cookie。
///
/// 回归的是「我的」页收藏/稍后观看全空、账号卡片显示「0 部影片」这个 bug：
/// 登录态存在 `.com` 桶里，而请求会 301 跳到 `.me`，若按精确 host 分桶，
/// 跳到 `.me` 后就查不到登录 cookie，服务端只能返回匿名页面。
void main() {
  late Han1meHttpClient client;

  setUp(() async {
    client = Han1meHttpClient();
    await client.clearCookies();
  });

  test('cookie 在镜像主机之间共享', () async {
    await client.saveCookies('hanime1_session=token', url: 'https://hanime1.com');

    expect(await client.hasCookie('https://hanime1.com/', 'hanime1_session'), isTrue);
    // 301 之后落到的主机必须也能看到同一个登录态。
    expect(await client.hasCookie('https://hanime1.me/', 'hanime1_session'), isTrue);
    expect(await client.hasCookie('https://hanimeone.me/', 'hanime1_session'), isTrue);
  });

  test('www 子域沿用所属镜像桶', () async {
    await client.saveCookies('hanime1_session=token', url: 'https://hanime1.me');
    expect(await client.hasCookie('https://www.hanime1.me/', 'hanime1_session'), isTrue);
  });

  test('clearCookies 清掉整个镜像桶', () async {
    await client.saveCookies('hanime1_session=token', url: 'https://hanime1.com');
    await client.clearCookies(url: 'https://hanime1.me');

    expect(await client.hasCookie('https://hanime1.com/', 'hanime1_session'), isFalse);
    expect(await client.hasCookie('https://hanime1.me/', 'hanime1_session'), isFalse);
  });

  test('不相关的主机不共享 cookie', () async {
    await client.saveCookies('session=token', url: 'https://example.com');
    expect(await client.hasCookie('https://example.com/', 'session'), isTrue);
    expect(await client.hasCookie('https://hanime1.me/', 'session'), isFalse);
  });

  test('同一份 cookie 字符串按最后出现的值合并', () async {
    await client.saveCookies('a=1; b=2', url: 'https://hanime1.com');
    await client.saveCookies('b=3', url: 'https://hanime1.me');
    expect(await client.hasCookie('https://hanime1.com/', 'a'), isTrue);
    expect(await client.hasCookie('https://hanime1.com/', 'b'), isTrue);
  });

  // Cloudflare 会把 UA 和 TLS/HTTP 指纹对账：Dart 的 HttpClient 只讲 HTTP/1.1，
  // 一旦 UA 声称是浏览器就判为伪装、回 403 you have been blocked（实测移动版和
  // 桌面版 Chrome UA 都被拦），自报家门的 UA 才是 200。所以「我的」页要能加载，
  // UA 必须不能冒充浏览器。
  test('hanime 站群用自报家门的 UA，不冒充浏览器', () {
    for (final host in ['hanime1.me', 'hanime1.com', 'hanimeone.me', 'www.hanime1.me']) {
      expect(Han1meHttpClient.userAgentFor(host), Han1meHttpClient.selfIdentifiedUserAgent, reason: host);
    }
    expect(Han1meHttpClient.userAgentFor('hanime1.me'), isNot(contains('Mozilla')));
    expect(Han1meHttpClient.userAgentFor('hanime1.me'), startsWith('Han1meWinPlus/'));
  });

  test('非 hanime 主机继续用浏览器 UA，行为不变', () {
    for (final host in ['vdownload.hembed.com', 'www.getchu.com', 'example.com']) {
      expect(Han1meHttpClient.userAgentFor(host), Han1meHttpClient.browserUserAgent, reason: host);
    }
  });
}
