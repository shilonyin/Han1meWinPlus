import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_api.dart';
import 'package:han1me_win_plus/src/data/remote/han1me_http_client.dart';

/// 回归「单个分区超时不该让整页『我的』报错」。
///
/// 站点把 `hanime1.com` 301 到 `hanime1.me`，每个请求都多一跳；叠加代理后首字节在
/// 500ms 量级。`Han1meApi.library` 会并发拉四个页面（稍后观看 / 收藏 / 播放列表 /
/// 历史），原来用 `Future.wait` 一起抛 —— 实测日志里出现过
/// `HttpException: 信号灯超时时间已到, uri = .../user/605056/likes`，
/// 而那三个页面明明都拿到了，用户却看到整页失败。
///
/// 现在改成每个分区独立容错：哪个取不到就那个分区空着。这里用一个必定失败的
/// HttpClient 来钉住这个行为。
void main() {
  test('单个分区请求失败时，其余分区照常返回，不整页抛错', () async {
    final http = _FailingClient(failPath: '/user/123/likes');
    final api = Han1meApi(http);

    final library = await api.library('https://hanime1.me', '123');

    // 失败的那个分区为空。
    expect(library.favorites, isEmpty, reason: 'likes 对应 favorites，取不到就该空着');
    // 其余分区照常有内容 —— 这正是容错要保住的东西。
    expect(library.watchLater, isNotEmpty, reason: 'saves 拿到了，不该被 likes 拖累');
    expect(library.history, isNotEmpty, reason: 'histories 拿到了，不该被 likes 拖累');
  });

  test('全部请求都失败时也不抛错，返回空库', () async {
    final http = _FailingClient(failPath: null);
    final api = Han1meApi(http);

    final library = await api.library('https://hanime1.me', '123');

    expect(library.watchLater, isEmpty);
    expect(library.favorites, isEmpty);
    expect(library.playlists, isEmpty);
    expect(library.history, isEmpty);
    expect(library.subscriptions, isEmpty);
  });
}

/// 指定路径返回 500，其余返回一个含最小可解析结构的页面。
class _FailingClient implements Han1meHttpClient {
  _FailingClient({required this.failPath});

  /// 命中这个路径子串就失败；`null` 表示全部失败。
  final String? failPath;

  @override
  Future<Han1meHttpResponse> get(String url, {String? responseCharset, Map<String, String>? headers, bool followRedirects = true}) async {
    final shouldFail = failPath == null || url.contains(failPath!);
    if (shouldFail) {
      return Han1meHttpResponse(statusCode: 503, body: '', headers: const {}, url: url);
    }
    return Han1meHttpResponse(
      statusCode: 200,
      body: _stubBody,
      headers: const {},
      url: url,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  /// 一个能过解析、且 `_libraryVideos` 能取到一条记录的最小页面。
  static const _stubBody = '''
<html><head><title>stub</title></head><body>
<div class="user-tab-item-wrapper">
  <a href="/watch?v=406505"></a>
  <img src="https://vdownload.hembed.com/image/thumbnail/406505h.jpg" alt="stub video">
  <div class="title">stub video</div>
</div>
<div class="user-tab-item-wrapper">
  <a href="/watch?v=166761"></a>
  <img src="https://vdownload.hembed.com/image/thumbnail/166761h.jpg" alt="stub two">
  <div class="title">stub two</div>
</div>
</body></html>
''';
}
