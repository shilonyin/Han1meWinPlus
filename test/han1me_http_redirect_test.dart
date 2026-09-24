import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';

/// 端到端回归：桌面端必须自己走重定向，并在**每一跳**重算 cookie。
///
/// 交给 Dart 的 `HttpClient` 跟随时，`Cookie` 作为敏感头在跨主机 301 上被丢弃
/// （`http_impl.dart` 的 `shouldCopyHeaderOnRedirect`），镜像站之间正好是这种
/// 跨主机跳转：第二跳匿名 → 服务端下发**新的匿名会话** → 覆盖掉真正的登录态。
/// 这里用一个真实的本地 HTTP 服务复现「跳转 + Set-Cookie」两个环节。
///
/// 另外 `HttpClientResponse.isRedirect` 是**按请求方法**分流的（POST 只认 303），
/// 所以客户端不能依赖它来判断是否重定向。
void main() {
  late HttpServer server;
  late String base;
  late List<_Hop> hops;

  setUp(() async {
    hops = [];
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    base = 'http://127.0.0.1:${server.port}';
    server.listen((request) async {
      final body = await utf8.decodeStream(request);
      hops.add(_Hop(request.method, request.uri.path, request.headers.value(HttpHeaders.cookieHeader) ?? '', body));
      switch (request.uri.path) {
        case '/login':
          // 第一跳：下发会话 cookie 并 301 跳到目标页。
          request.response
            ..statusCode = HttpStatus.movedPermanently
            ..headers.set(HttpHeaders.locationHeader, '$base/likes')
            ..headers.add(HttpHeaders.setCookieHeader, 'hanime1_session=real; Path=/');
          break;
        case '/likes':
          request.response
            ..statusCode = HttpStatus.ok
            ..write(hops.last.cookie.contains('hanime1_session=real') ? 'LOGGED_IN' : 'ANONYMOUS');
          break;
        default:
          request.response.statusCode = HttpStatus.notFound;
      }
      await request.response.close();
    });
  });

  tearDown(() => server.close(force: true));

  test('跨跳转的 Set-Cookie 会在下一跳带上去，登录态不丢', () async {
    final client = Han1meHttpClient();
    final response = await client.get('$base/login');

    expect(response.statusCode, 200);
    expect(response.url, '$base/likes');
    // 第一跳拿到的会话必须出现在第二跳请求头里——这正是原实现的失败点。
    expect(response.body, 'LOGGED_IN');
    expect(hops, hasLength(2));
    expect(hops[1].cookie, contains('hanime1_session=real'));
  });

  test('followRedirects=false 时停在 301，且已保存该跳的 cookie', () async {
    final client = Han1meHttpClient();
    final response = await client.get('$base/login', followRedirects: false);

    expect(response.statusCode, 301);
    expect(hops, hasLength(1));
    expect(await client.hasCookie('$base/likes', 'hanime1_session'), isTrue);
  });

  test('301 上的 POST 按惯例降级为 GET 且不再重发 body', () async {
    final client = Han1meHttpClient();
    final response = await client.post('$base/login', {'a': '1'});

    // POST 收到 301 时必须照样跟进（旧实现依赖 isRedirect，会停在这里）。
    expect(response.statusCode, 200);
    expect(response.body, 'LOGGED_IN');
    expect(hops, hasLength(2));
    expect(hops[0].method, 'POST');
    expect(hops[0].body, 'a=1');
    expect(hops[1].method, 'GET');
    expect(hops[1].body, isEmpty);
  });
}

class _Hop {
  const _Hop(this.method, this.path, this.cookie, this.body);

  final String method;
  final String path;
  final String cookie;
  final String body;
}
