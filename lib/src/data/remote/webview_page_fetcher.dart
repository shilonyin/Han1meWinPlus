import 'dart:async';
import 'dart:convert';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'webview_environment.dart';

final webViewPageFetcherProvider = Provider((ref) => WebViewPageFetcher(() => ref.read(webViewEnvironmentProvider.future)));

/// 用「无界面 WebView」（真实 Chromium 内核）代取页面。
///
/// 为什么需要它：Cloudflare 会按**客户端 TLS/HTTP2 指纹**（Ja3/Ja4）判定，
/// Dart 的 `HttpClient` 无论请求头怎么改都可能被拦 —— 实测过同一站点在同一代理
/// 出口下 curl 与真实浏览器都正常，Dart 恒定 403，把 `sec-ch-ua` / `sec-fetch-*`
/// / `Accept-Language` 补齐也没有用：拦的不是请求头而是 TLS 握手本身，Dart 侧
/// 无法绕过。
///
/// 解法不是换一个“更像浏览器”的请求，而是**真的用一个浏览器去取**：WebView2
/// 就是 Chromium，TLS 指纹、HTTP/2 特征、执行 JS 的能力都是真的，顺带还能把
/// 非交互式的 Cloudflare 挑战自动过掉（用户不用再手动点一次验证）。
///
/// 与 FlareSolverr / curl_cffi 是同一思路的两条实现路径：那两者要额外带一个
/// Python 服务或一个自编译的 curl 二进制，而 WebView 是应用本来就有的依赖。
class WebViewPageFetcher {
  WebViewPageFetcher(this._environment);

  /// 抓这些 AV 站点固定用桌面版 Chrome 的 UA（与 `JavApi.userAgent` 同一个值，
  /// 这样 WebView 拿到的 `cf_clearance` 与之后 Dart 请求的 UA 一致）。
  static const userAgent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/140.0.0.0 Safari/537.36';

  final Future<WebViewEnvironment?> Function() _environment;

  HeadlessInAppWebView? _webView;
  InAppWebViewController? _controller;
  Future<void>? _starting;
  Completer<void>? _loaded;
  /// 一个 WebView 同时只能加载一个页面，用队列把并发请求串起来。
  Future<void> _tail = Future<void>.value();
  bool _disposed = false;

  /// 已经「热身」过的源：WebView 正停在该源上，挑战已过、cookie 已就绪。
  ///
  /// 之后对同一个源的抓取就不必再导航了（见 [_fetchInPage]）。
  String? _warmedOrigin;
  /// 页面内 `fetch()` 的结果回传：每个请求带一个 token，靠 JS 桥回传。
  final _pending = <String, Completer<String>>{};
  int _fetchToken = 0;
  bool _bridgeReady = false;

  /// WebView 已经启动并拿到控制器。
  bool get started => _controller != null;

  /// 打开 [url] 并返回最终页面的 HTML。
  ///
  /// 仍停在人机验证页（需要用户交互的那种）或加载失败时返回 null，调用方据此
  /// 走「让用户手动完成验证」的路径。
  Future<String?> html(String url, {Duration timeout = const Duration(seconds: 30)}) {
    final task = _tail.then((_) => _load(url, timeout));
    _tail = task.then((_) {}, onError: (Object _) {});
    return task;
  }

  Future<void> dispose() async {
    _disposed = true;
    final webView = _webView;
    _webView = null;
    _controller = null;
    _starting = null;
    _warmedOrigin = null;
    for (final completer in _pending.values) {
      if (!completer.isCompleted) completer.complete('');
    }
    _pending.clear();
    if (webView != null) {
      try {
        await webView.dispose();
      } catch (_) {}
    }
  }

  Future<String?> _load(String url, Duration timeout) async {
    final controller = await _ensureController();
    if (controller == null || _disposed) return null;
    final uri = Uri.tryParse(url);
    final origin = uri == null ? null : '${uri.scheme}://${uri.authority}';
    // 同一个源已经待过时，直接用页面内的 fetch 取：不导航 = 不渲染页面、不等
    // load 事件、不跑广告脚本。首页好几分区抓下来能快上几倍。
    if (origin != null && origin == _warmedOrigin && uri!.hasScheme) {
      final text = await _fetchInPage(uri, timeout);
      if (text != null && text.isNotEmpty && !isChallengeBody(text)) return text;
    }
    final loaded = Completer<void>();
    _loaded = loaded;
    try {
      await controller.loadUrl(urlRequest: URLRequest(url: WebUri(url)));
    } catch (_) {
      return null;
    }
    await loaded.future.timeout(timeout, onTimeout: () {});
    if (_disposed) return null;
    var html = await _readHtml(controller);
    // 挑战页在验证通过后会自己 reload，这里轮询等它变成真正的页面。
    for (var attempt = 0; attempt < 12 && isChallengeBody(html); attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 1000));
      if (_disposed) return null;
      html = await _readHtml(controller);
    }
    // 页面真的出来了（且不再是挑战页）才算热身成功；是挑战页就下次仍走导航。
    if (!isChallengeBody(html)) _warmedOrigin = origin;
    return html;
  }

  /// 在当前页面里 `fetch()` 取同源 URL。
  ///
  /// 走的是 Chromium 自己的网络栈（TLS 指纹、cookie 与导航完全一致），只是不渲染
  /// 页面；结果用 JS 桥回传 —— WebView2 的 `ExecuteScript` 不会等 Promise，所以
  /// 不能直接把 fetch 的返回值取回来。
  Future<String?> _fetchInPage(Uri uri, Duration timeout) async {
    final controller = _controller;
    if (controller == null || _disposed || !_bridgeReady) return null;
    final token = 't${_fetchToken++}';
    final completer = Completer<String>();
    _pending[token] = completer;
    final script = '''
(function () {
  var send = function (text) {
    try { window.flutter_inappwebview.callHandler('pageText', '$token', text || ''); } catch (e) {}
  };
  fetch(${jsonEncode(uri.toString())}, { credentials: 'include' })
    .then(function (response) { return response.ok ? response.text() : ''; })
    .then(send)
    .catch(function () { send(''); });
})();
''';
    try {
      await controller.evaluateJavascript(source: script);
    } catch (_) {
      _pending.remove(token);
      return null;
    }
    try {
      final text = await completer.future.timeout(timeout);
      return text.isEmpty ? null : text;
    } catch (_) {
      _pending.remove(token);
      return null;
    }
  }

  Future<InAppWebViewController?> _ensureController() async {
    if (_controller != null) return _controller;
    _starting ??= _start();
    await _starting;
    return _controller;
  }

  Future<void> _start() async {
    final environment = await _environment();
    final webView = HeadlessInAppWebView(
      initialSize: const Size(1280, 900),
      webViewEnvironment: environment,
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        userAgent: userAgent,
        supportMultipleWindows: false,
        // 抓 HTML 不需要图片；挡掉能省不少带宽与时间。
        blockNetworkImage: true,
      ),
      onWebViewCreated: (controller) {
        _controller = controller;
        _registerBridge(controller);
      },
      onLoadStop: (_, __) => _completeLoad(),
      onReceivedError: (_, __, ___) => _completeLoad(),
      onReceivedHttpError: (_, __, ___) => _completeLoad(),
    );
    _webView = webView;
    try {
      await webView.run();
    } catch (_) {
      _webView = null;
      return;
    }
    // `run()` 只是把创建命令发下去，控制器是异步回来的。
    for (var attempt = 0; attempt < 60 && _controller == null; attempt++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    _controller ??= webView.webViewController;
  }

  void _completeLoad() {
    final loaded = _loaded;
    if (loaded != null && !loaded.isCompleted) loaded.complete();
  }

  /// 注册页面内 `fetch()` 的结果回传通道。
  void _registerBridge(InAppWebViewController controller) {
    if (_bridgeReady) return;
    try {
      controller.addJavaScriptHandler(
        handlerName: 'pageText',
        callback: (arguments) {
          final token = arguments.isNotEmpty ? '${arguments[0]}' : '';
          final text = arguments.length > 1 && arguments[1] is String ? arguments[1] as String : '';
          _pending.remove(token)?.complete(text);
          return null;
        },
      );
      _bridgeReady = true;
    } catch (_) {
      // 平台不支持 JS 桥（或注册失败）时保持 false，抓取一律走导航那条路。
      _bridgeReady = false;
    }
  }

  Future<String> _readHtml(InAppWebViewController controller) async {
    try {
      final html = await controller.evaluateJavascript(source: "window.document.getElementsByTagName('html')[0].outerHTML;");
      return html is String ? html : '';
    } catch (_) {
      return '';
    }
  }

  /// 是否还是「人机验证 / 已被拦截」页面。
  ///
  /// 只认强特征：`challenge-platform` 之类的脚本在**正常**的 Cloudflare 页面上
  /// 也会出现，拿它当判据会误判（这正是 [JavApi] 里那份判据要看状态码的原因）。
  static bool isChallengeBody(String? body) {
    if (body == null || body.isEmpty) return false;
    return RegExp(
      r'Just a moment|cf-chl-|Sorry, you have been blocked|Attention Required|Verifying you are human|Checking your browser|正在进行安全验证|請稍候|请稍候',
      caseSensitive: false,
    ).hasMatch(body);
  }
}
