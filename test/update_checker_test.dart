import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/json_store.dart';
import 'package:han1me_win_plus/src/data/remote/update_checker.dart';

/// 内存版存储，避免测试写真实的应用数据目录。
class _MemoryStore extends JsonStore {
  final Map<String, Map<String, dynamic>> files = {};

  @override
  Future<Map<String, dynamic>> read(String fileName) async => files[fileName] ?? {};

  @override
  Future<void> write(String fileName, Map<String, dynamic> value) async => files[fileName] = value;
}

/// 用本地假 GitHub API 验证「ETag 条件请求 + 缓存兜底 + Atom 源兜底」：
/// 200 时缓存结果并记下 ETag；带 If-None-Match 时返回 304（304 不消耗真实额度）；
/// 请求失败（这里用 403 模拟额度用尽）时先试不计额度的 releases.atom，
/// 再退到缓存，都拿不到时把 [UpdateChecker.lastCallFailed] 置真。
void main() {
  late HttpServer server;
  late Dio dio;
  late _MemoryStore store;
  late UpdateChecker checker;

  var mode = 'ok';
  var feedOk = true;
  var requests = 0;
  var conditionalRequests = 0;

  const atom =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<feed xmlns="http://www.w3.org/2005/Atom">'
      '<entry>'
      '<updated>2026-09-13T17:53:51Z</updated>'
      '<link rel="alternate" type="text/html" href="https://example.com/releases/tag/v9.9.9"/>'
      '<title>Demo v9.9.9</title>'
      '<content type="html">&lt;h2&gt;更新内容&lt;/h2&gt;\n&lt;ul&gt;\n&lt;li&gt;修复某个问题 (&lt;code&gt;abc1234&lt;/code&gt;)&lt;/li&gt;\n&lt;/ul&gt;</content>'
      '</entry>'
      '</feed>';

  setUp(() async {
    mode = 'ok';
    feedOk = true;
    requests = 0;
    conditionalRequests = 0;
    server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((request) {
      if (request.uri.path.contains('releases.atom')) {
        if (!feedOk) {
          request.response.statusCode = 404;
          request.response.close();
          return;
        }
        request.response.statusCode = 200;
        request.response.write(atom);
        request.response.close();
        return;
      }
      requests++;
      final etag = request.headers.value('if-none-match');
      if (mode != 'ok') {
        request.response.statusCode = 403;
        request.response.write('{"message":"API rate limit exceeded"}');
        request.response.close();
        return;
      }
      if (etag == '"v1"') {
        conditionalRequests++;
        request.response.statusCode = 304;
        request.response.headers.set('etag', '"v1"');
        request.response.close();
        return;
      }
      request.response.statusCode = 200;
      request.response.headers.set('etag', '"v1"');
      request.response.headers.contentType = ContentType.json;
      request.response.write(
        jsonEncode({
          'tag_name': 'v9.9.9',
          'html_url': 'https://example.com/releases/v9.9.9',
          'body': 'release notes',
          'created_at': '2026-09-14T00:00:00Z',
          'assets': [
            {'name': 'Han1meWinPlus-Setup.exe', 'browser_download_url': 'https://example.com/Han1meWinPlus-Setup.exe'},
          ],
        }),
      );
      request.response.close();
    });

    store = _MemoryStore();
    dio = Dio()
      ..interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            final feed = options.path.contains('releases.atom');
            options.path = feed ? 'http://127.0.0.1:${server.port}/releases.atom' : 'http://127.0.0.1:${server.port}/releases/latest';
            handler.next(options);
          },
        ),
      );
    checker = UpdateChecker(dio, cache: ReleaseCache(store));
  });

  tearDown(() => server.close(force: true));

  test('成功获取时写入缓存，重复请求走 304 且不算失败', () async {
    final first = await checker.latestRelease();
    expect(first, isNotNull);
    expect(first!.tagName, 'v9.9.9');
    expect(first.body, 'release notes');
    expect(first.downloadUrl, isNotEmpty);
    expect(checker.lastCallFailed, isFalse);
    expect(store.files['release_cache.json']?['etag'], '"v1"');
    expect(requests, 1);

    final second = await checker.latestRelease();
    expect(second?.tagName, 'v9.9.9');
    expect(checker.lastCallFailed, isFalse);
    expect(requests, 2);
    expect(conditionalRequests, 1, reason: '第二次应该带上 If-None-Match 并收到 304');
  });

  test('check() 只在远端版本更新时返回结果', () async {
    expect((await checker.check(currentVersion: '1.0.0'))?.tagName, 'v9.9.9');
    expect(await checker.check(currentVersion: '9.9.9'), isNull);
    expect(checker.lastCallFailed, isFalse);
  });

  test('额度用尽时回退到缓存并标记失败', () async {
    await checker.latestRelease();
    mode = 'limited';
    feedOk = false;

    final fallback = await checker.latestRelease();
    expect(fallback?.tagName, 'v9.9.9', reason: '应回退到缓存里的发布信息');
    expect(checker.lastCallFailed, isTrue);
  });

  test('额度用尽时用 Releases Atom 源兜底（不计额度）', () async {
    mode = 'limited';

    final feed = await checker.latestRelease();
    expect(feed?.tagName, 'v9.9.9', reason: '版本号来自 Atom 条目里的 release 链接');
    expect(feed?.body, contains('更新内容'));
    expect(feed?.body, contains('abc1234'), reason: 'HTML 正文应被转成纯文本');
    expect(checker.lastCallFailed, isFalse, reason: '拿到了数据就不算失败');
  }, skip: Platform.isWindows ? false : '仅 Windows 走 Atom 兜底');

  test('没有缓存且两端都失败时返回空并标记失败', () async {
    mode = 'limited';
    feedOk = false;
    expect(await checker.latestRelease(), isNull);
    expect(checker.lastCallFailed, isTrue);
  });
}
