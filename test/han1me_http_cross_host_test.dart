import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';

/// 端到端复现「我的」页空列表的**真正形状**：登录态存在 `hanime1.com` 上，
/// 但请求被 301 跳到镜像站 `hanime1.me`。
///
/// 这里用 `HttpOverrides` 把两个镜像主机都指到本地测试服务器，从而在离线环境下
/// 走完「跨主机跳转」全程。修复前第二跳是匿名的，服务端随即下发新的匿名会话，
/// 覆盖掉真正的登录态 —— 表现就是「我的」页收藏/稍后观看全空，但页面不报错。
void main() {
  late HttpServer server;
  late int port;
  late List<String> hopCookies;
  late List<String> hopHosts;

  setUp(() async {
    hopCookies = [];
    hopHosts = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    port = server.port;
    server.listen((request) async {
      hopHosts.add(request.headers.host ?? '');
      hopCookies.add(request.headers.value(HttpHeaders.cookieHeader) ?? '');
      switch (request.uri.path) {
        case '/likes':
          final loggedIn = hopCookies.last.contains('hanime1_session=real');
          request.response
            ..statusCode = HttpStatus.ok
            ..write(loggedIn ? 'LOGGED_IN' : 'ANONYMOUS');
        case '/entry-me':
          // 镜像站互跳：.com → .me，跨主机。
          request.response
            ..statusCode = HttpStatus.movedPermanently
            ..headers.set(HttpHeaders.locationHeader, 'http://hanime1.me:$port/likes');
        case '/entry-com':
          request.response
            ..statusCode = HttpStatus.movedPermanently
            ..headers.set(HttpHeaders.locationHeader, 'http://hanime1.com:$port/likes');
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });

    HttpOverrides.global = _LoopbackOverride(port);
  });

  tearDown(() async {
    HttpOverrides.global = null;
    await server.close(force: true);
  });

  test('登录态存在 .com 时，跳到 .me 的第二跳仍然带着它', () async {
    final client = Han1meHttpClient();
    // 模拟 App 启动时按 resolvedBaseUrl（hanime1.com）写入登录 cookie。
    await client.saveCookies(
      'hanime1_session=real; remember_web_abc=xyz',
      url: 'http://hanime1.com:$port',
    );

    final response = await client.get('http://hanime1.com:$port/entry-me');

    // 旧实现下这里会是 ANONYMOUS：Dart 跨源重定向丢弃 Cookie，
    // 且 _cookiesFor('hanime1.me') 查不到 .com 桶里的值。
    expect(response.body, 'LOGGED_IN');
    expect(response.url, 'http://hanime1.me:$port/likes');
    expect(hopHosts, hasLength(2));
    expect(hopHosts[0], contains('hanime1.com'));
    expect(hopHosts[1], contains('hanime1.me'));
    expect(hopCookies[1], contains('hanime1_session=real'));
    expect(hopCookies[1], contains('remember_web_abc=xyz'));
  });

  test('反向跳转 .me → .com 同样保住登录态', () async {
    final client = Han1meHttpClient();
    await client.saveCookies('hanime1_session=real', url: 'http://hanime1.me:$port');

    // 同一个处理器：第一跳 301 到 .com
    final direct = await client.get('http://hanime1.me:$port/entry-com');
    expect(direct.body, 'LOGGED_IN');
  });

  test('镜像桶之外的站点不会拿到 hanime 登录态', () async {
    final client = Han1meHttpClient();
    await client.saveCookies('hanime1_session=real', url: 'http://hanime1.com:$port');

    expect(await client.hasCookie('http://example.com:$port/likes', 'hanime1_session'), isFalse);
    expect(await client.hasCookie('http://hanime1.me:$port/likes', 'hanime1_session'), isTrue);
    expect(await client.hasCookie('http://hanimeone.me:$port/likes', 'hanime1_session'), isTrue);
  });
}

/// 把 hanime 镜像主机的连接都指向本地测试服务器。
class _LoopbackOverride extends HttpOverrides {
  _LoopbackOverride(this.port);

  final int port;

  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.connectionFactory = (uri, proxyHost, proxyPort) =>
        Socket.startConnect(InternetAddress.loopbackIPv4, port);
    return client;
  }
}
