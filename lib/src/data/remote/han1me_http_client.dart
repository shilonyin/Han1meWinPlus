import 'dart:convert';
import 'dart:io';

import 'package:charset/charset.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart' as webview;

import '../../core/desktop_platform.dart';
import 'address_ranker.dart';
import 'browser_user_agent.dart';
import 'windows_connection_factory.dart';
import 'windows_http_overrides.dart';

class Han1meHttpResponse {
  const Han1meHttpResponse({required this.statusCode, required this.body, required this.headers, required this.url});

  final int statusCode;
  final String body;
  final Map<String, List<String>> headers;
  final String url;
}

/// 按域名清理 WebView cookie 时要覆盖的主机：站点自身 + `www.` 变体。
///
/// 站点把会话同时写在 `hanime1.me` 与 `www.hanime1.me` 两处，只清叶子域会留下
/// 另一半，下次进登录页仍然是被登录态。范围必须**锁死在站点自身**：一旦放大到
/// 「全清」，Cloudflare 的 `cf_clearance` 会被一起抹掉，登录页立刻被 CF 挡住
/// （回归 issue #18）。
List<String> webViewCookieHostsFor(Uri uri) =>
    [uri.host, if (!uri.host.startsWith('www.')) 'www.${uri.host}'];

/// 把 [webViewCookieHostsFor] 的主机名拼成交给 [CookieManager.deleteCookies] 的 URL。
///
/// **必须是绝对 URL**：`WebUri('hanime1.me/')` 解出来的 `scheme` 与 `host` 都是空串，
/// 而 Windows 端 `deleteCookies` 是拿这个串去调 `Network.getCookies` 的 —— 无效 URL
/// 取回空列表，删除循环一次都不跑，**什么都没删还回调 `true`**（静默失败）。
/// 拼 url 的这一步单独抽出来，就是为了让回归测试能直接钉住「host 不能为空」。
///
/// 还兜住另一种坏输入：`Uri.parse('hanime1.me')` 没有 scheme 时，**host 也是空的**
/// （整串被当成 path）。这种输入不能原样透传，否则又会拼出 `https:///` 这种空 host
/// 的地址，把同一个静默失败原样带回来。
List<webview.WebUri> webViewCookieUrlsFor(Uri uri, {String fallbackScheme = 'https'}) {
  final scheme = uri.scheme.isEmpty ? fallbackScheme : uri.scheme;
  final hosts = uri.host.isEmpty
      ? webViewCookieHostsFor(Uri.parse('$scheme://${uri.path}'))
      : webViewCookieHostsFor(uri);
  return [for (final host in hosts) webview.WebUri('$scheme://$host/')];
}

class Han1meHttpClient {
  static const _channel = MethodChannel('com.liar.han1meplus/http');
  static final _desktopCookies = <String, String>{};
  static bool get _isDesktop => isDesktopHttpPlatform;

  /// 取「WebView 正在用的那个 WebView2 环境」。
  ///
  /// **必须和登录页/验证页共用一个环境，否则读写的是另一份 cookie 库。**
  /// `CookieManager.instance()` 不带参数时绑定的是 WebView2 的**默认环境**
  /// （数据目录在 exe 同目录），而登录页用的是带 `userDataFolder` 的自定义环境
  /// （数据目录在 `%APPDATA%\<产品名>\webview2`）。两者互不可见：
  /// 网页里登录成功后，应用按默认环境去读，读到的永远是空 —— 表现就是
  /// 「网页里明明登录成功、应用里永远是未登录」。
  final webview.WebViewEnvironment? Function()? _environment;

  webview.WebViewEnvironment? _cachedEnvironment;
  webview.CookieManager? _cachedCookieManager;

  Han1meHttpClient({webview.WebViewEnvironment? Function()? webViewEnvironment}) : _environment = webViewEnvironment;

  /// 作用在 WebView 那个环境上的 CookieManager（环境没就绪时退回默认实例）。
  webview.CookieManager _cookieManager() {
    final environment = _environment?.call();
    if (identical(environment, _cachedEnvironment) && _cachedCookieManager != null) return _cachedCookieManager!;
    _cachedEnvironment = environment;
    return _cachedCookieManager = environment == null
        ? webview.CookieManager.instance()
        : webview.CookieManager.instance(webViewEnvironment: environment);
  }

  /// hanime 站群专用的 UA：**故意不冒充浏览器**。
  ///
  /// Cloudflare 会拿 UA 和 TLS/HTTP 指纹对账：Dart 的 `HttpClient` 只会 HTTP/1.1、
  /// ClientHello 也跟 Chrome 完全不像，一旦 UA 声称是 Chrome（实测移动版和桌面版
  /// 都中招，`curl/8.4.0` 这类已知工具 UA 同样被拦），就判为伪装并回
  /// `403 you have been blocked`；反过来用自报家门的 UA（或不带 UA）则是 200。
  /// 2026-09-25 用同一 cookie、同一秒对 `https://hanime1.me/user/605056/likes` 实测：
  /// 移动 Chrome UA / 桌面 Chrome UA / `curl/8.4.0` 全部 403（len=5484），
  /// `Han1meWinPlus/1.1.24` 与不带 UA 都是 200 且拿到完整的 60 条收藏。
  static const selfIdentifiedUserAgent = 'Han1meWinPlus/1.1.24';

  /// 浏览器 UA —— 需要「像浏览器」的场景用：登录 / Cloudflare 校验的 WebView、
  /// 无头代取、播放器请求头，以及会校验 `navigator.userAgent` 的 AV 站点。
  ///
  /// 版本号**动态取自本机 WebView2 内核**（见 [BrowserUserAgent]），不写死：
  /// 写死的版本一旦与真实内核不符（内核 154、代码写 149），请求头与页面自报的
  /// 信息自相矛盾，会被判定成伪造浏览器，验证永远过不去。
  static String get browserUserAgent => BrowserUserAgent.value;

  /// 按目标主机挑 UA。
  ///
  /// 两套 UA 服务的是**两类不同的站点**，不能合并：
  /// - hanime 站群（`hanime1.*` 等）：靠 [selfIdentifiedUserAgent] 绕过「冒充浏览器」
  ///   判定 —— Dart 客户端的 TLS 指纹装不成 Chrome，用浏览器 UA 反而会被 403。
  /// - 其它主机（AV 源、图片 CDN、getchu…）：站点会校验页面内 `navigator.userAgent`，
  ///   必须用与 WebView 内核一致的 [browserUserAgent]。
  static String userAgentFor(String host) {
    for (final mirror in WindowsConnectionFactory.hanimeHosts) {
      if (host == mirror || host.endsWith('.$mirror')) return selfIdentifiedUserAgent;
    }
    return browserUserAgent;
  }

  /// 镜像主机（`hanime1.com` / `hanime1.me` / `hanimeone.me`）共用的 cookie 桶名。
  ///
  /// 三者是同一站点、登录态互通，必须共用一个桶：`hanime1.com` 会 301 到
  /// `hanime1.me`，而 Dart 的 `HttpClient` 把 `Cookie` 当敏感头、跨主机重定向时
  /// 直接丢弃（见 [_maxRedirects] 处注释）。若 jar 仍按精确 host 分桶，跳到 `.me`
  /// 后重算 cookie 就查不到 `.com` 存下的登录态，服务端返回匿名页面 ——
  /// 表现为「我的」页收藏/稍后观看全空、账号卡片显示「0 部影片」。
  static const _mirrorCookieKey = 'hanime1-mirrors';

  static String _cookieKey(String host) {
    for (final mirror in WindowsConnectionFactory.hanimeHosts) {
      if (host == mirror || host.endsWith('.$mirror')) return _mirrorCookieKey;
    }
    return host;
  }

  Future<void> saveCookies(String cookies, {String? url}) async {
    if (!_isDesktop) {
      await _channel.invokeMethod<void>('saveCookies', {'cookies': cookies, if (url != null) 'url': url});
      return;
    }
    final host = Uri.tryParse(url ?? '')?.host;
    if (host != null && host.isNotEmpty) {
      final key = _cookieKey(host);
      _desktopCookies[key] = _mergeCookies(_desktopCookies[key], cookies);
    }
  }

  Future<void> clearCookies({String? url}) async {
    if (!_isDesktop) {
      await _channel.invokeMethod<void>('clearCookies', {if (url != null) 'url': url});
      return;
    }
    final host = Uri.tryParse(url ?? '')?.host;
    if (host == null || host.isEmpty) {
      _desktopCookies.clear();
    } else {
      _desktopCookies.remove(_cookieKey(host));
    }
  }

  Future<String> webViewCookies(String url) async {
    if (!_isDesktop) return await _channel.invokeMethod<String>('webViewCookies', {'url': url}) ?? '';
    final cookies = await _cookieManager().getCookies(url: webview.WebUri(url));
    final value = cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; ');
    if (value.isNotEmpty) await saveCookies(value, url: url);
    return value;
  }

  /// 从**多个候选地址**汇总 WebView 里的 cookie（后出现的覆盖先出现的同名项）。
  ///
  /// 为什么不能只查一个地址：WebView 登录完成后停在哪一跳并不确定 —— 站点可能落到
  /// `hanime1.me`、`www.hanime1.me` 或某个镜像域；而 `CookieManager.getCookies(url)`
  /// **只返回该 URL 作用域内的 cookie**。只查 `settings.resolvedBaseUrl` 时，一旦登录
  /// 后停留在别的域名上就什么都取不到，「网页里登录成功、应用里仍是未登录」。
  /// Han1meViewer 用 `getCookie(url.host)` 取当前页域名，上游 Han1mePlus 则是把
  /// 当前页域名、设置域名、全部镜像域一起查 —— 这里采用后者，覆盖面最大。
  Future<String> webViewCookiesFor(Iterable<String> urls) async {
    final merged = <String, String>{};
    for (final url in urls) {
      final value = await webViewCookies(url);
      if (value.isEmpty) continue;
      for (final entry in _splitCookies(value).entries) {
        merged[entry.key] = entry.value;
      }
    }
    return merged.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }

  static Map<String, String> _splitCookies(String cookies) => {
        for (final part in cookies.split(';'))
          if (part.trim().isNotEmpty && part.contains('='))
            part.trim().split('=').first.trim(): part.trim().substring(part.trim().indexOf('=') + 1),
      };

  Future<void> clearWebViewCookies() async {
    if (!_isDesktop) {
      await _channel.invokeMethod<void>('clearWebViewCookies');
      return;
    }
    await _cookieManager().deleteAllCookies();
    await clearCookies();  }

  /// 清掉 WebView 里**某一个站点**的 cookie，其它站点原样保留。
  ///
  /// 登录页要的是「换一个账号登录」，所以必须先丢掉上一位用户的 `hanime1_session`，
  /// 否则站点直接回已登录页、根本不显示登录表单。但**不能**顺手清掉
  /// `cf_clearance`：它是 Cloudflare 给这台机器的通行证，与登录哪个账号无关。
  /// 用 [clearWebViewCookies] 或 `deleteAllCookies()` 会把 CF 凭证一并抹掉，
  /// 于是登录页一打开就撞上 CF 拦截，用户登录成功后跳转又被拦在首页前，
  /// 登录页根本收不到「已离开登录页」的信号（见 [LoginPage] 的保存时机），
  /// 结果就是「网页里明明登录成功、应用里永远是未登录」。
  ///
  /// 传给原生的**必须是绝对 URL**：`WebUri('hanime1.me/')`（裸主机加斜杠）解出来的
  /// `scheme` 与 `host` 都是空的，而 Windows 端的 `deleteCookies` 会拿这个串去调
  /// `Network.getCookies` —— 无效 URL 取回空列表，循环一次都不执行，**什么都没删，
  /// 却照样回调 `true`**。于是老会话一直在、登录页直接跳回已登录页，用户根本拿不到
  /// 表单；应用侧还继续拿旧会话请求，`saveCookie` 在检出 `id == null` 时抛错，
  /// 账号从不落盘 —— 这就是 issue #18 修复后仍然「登不进去」的原因。
  Future<void> clearWebViewCookiesFor(String url) async {
    if (!_isDesktop) {
      await _channel.invokeMethod<void>('clearWebViewCookies');
      return;
    }
    final parsed = Uri.parse(url);
    final urls = webViewCookieUrlsFor(parsed);
    for (final target in urls) {
      await _cookieManager().deleteCookies(url: target);
    }
    // 内存镜像也一起清（`deleteCookies` 不会同步到 [_desktopCookies]）。
    // 键必须走 [_cookieKey]：镜像域在镜像里统一存在 `hanime1-mirrors` 这一个桶下，
    // 拿裸主机名去 remove 永远删不到东西，旧会话会被一直重放。
    for (final target in urls) {
      _desktopCookies.remove(_cookieKey(target.host));
    }
  }

  Future<void> setNetworkSettings({required bool useBuiltInHosts, required bool useDoh, required String dohPreset, required String dohCustomUrl, required String dohBootstrapIps, required int dohTimeoutSeconds, String proxyMode = 'direct', String customProxy = '', bool useAddressRanking = true}) async {
    // 地址优选器是全局单例（连接工厂在同步路径上要用它排序），设置在这里统一下发。
    AddressRanker.instance.enabled = useAddressRanking;
    if (_isDesktop) {
      HttpOverrides.global = WindowsHttpOverrides(
        proxy: await WindowsHttpOverrides.resolveRule(mode: proxyMode, custom: customProxy),
        useBuiltInHosts: useBuiltInHosts,
        useDoh: useDoh,
        dohPreset: dohPreset,
        dohCustomUrl: dohCustomUrl,
        dohBootstrapIps: dohBootstrapIps,
        dohTimeoutSeconds: dohTimeoutSeconds,
      );
      return;
    }
    await _channel.invokeMethod<void>('setNetworkSettings', {'useBuiltInHosts': useBuiltInHosts, 'useDoh': useDoh, 'dohPreset': dohPreset, 'dohCustomUrl': dohCustomUrl, 'dohBootstrapIps': dohBootstrapIps, 'dohTimeoutSeconds': dohTimeoutSeconds});
  }

  Future<bool> hasCookie(String url, String name) async => _isDesktop ? _cookiesFor(Uri.parse(url)).split(';').any((cookie) => cookie.trim().split('=').first.toLowerCase() == name.toLowerCase()) : await _channel.invokeMethod<bool>('hasCookie', {'url': url, 'name': name}) ?? false;

  /// [followRedirects] 为 false 时不自动跟随重定向（只对桌面端生效：移动端走原生实现，
  /// 仍是自动跟随）。给 KVS 系站点用：它们会把非 ASCII 的 slug 以原始 UTF-8
  /// 字节写进 `Location`，而 HTTP 头按规范是 Latin-1，Dart 解出来是乱码，
  /// 自动跟随会一直拿到同一个 301（最后报 Redirect loop detected）。
  Future<Han1meHttpResponse> get(String url, {String? responseCharset, Map<String, String>? headers, bool followRedirects = true}) =>
      _request(url, responseCharset: responseCharset, headers: headers, followRedirects: followRedirects);

  Future<void> download(String url, String path) async {
    if (!_isDesktop) {
      await _channel.invokeMethod<void>('download', {'url': url, 'path': path});
      return;
    }
    final client = _desktopClient();
    try {
      final request = await client.getUrl(Uri.parse(url));
      request.headers.set(HttpHeaders.userAgentHeader, userAgentFor(request.uri.host));
      final cookie = _cookiesFor(request.uri);
      if (cookie.isNotEmpty) request.headers.set(HttpHeaders.cookieHeader, cookie);
      final response = await request.close();
      if (response.statusCode < 200 || response.statusCode >= 300) throw HttpException('Download failed: HTTP ${response.statusCode}', uri: request.uri);
      final output = File(path);
      await output.parent.create(recursive: true);
      await response.pipe(output.openWrite());
      _saveResponseCookies(request.uri, response.cookies);
    } finally {
      client.close(force: true);
    }
  }

  Future<Han1meHttpResponse> post(String url, Map<String, String> data, {Map<String, String>? headers, String? responseCharset}) =>
      _request(url, method: 'POST', data: data, headers: headers, responseCharset: responseCharset);

  Future<Han1meHttpResponse> delete(String url, Map<String, String> data, {Map<String, String>? headers, bool json = false}) =>
      _request(url, method: 'DELETE', data: data, headers: headers, json: json);

  Future<Han1meHttpResponse> _request(String url, {String methodName = 'request', String method = 'GET', Map<String, String>? data, Map<String, String>? headers, String? responseCharset, bool json = false, bool followRedirects = true}) async {
    if (_isDesktop) return _desktopRequest(url, method: method, data: data, headers: headers, responseCharset: responseCharset, json: json, followRedirects: followRedirects);
    final response = await _channel.invokeMethod<dynamic>(methodName, {
      'url': url,
      'method': method,
      if (data != null) 'data': data,
        if (headers != null) 'headers': headers,
        if (responseCharset != null) 'responseCharset': responseCharset,
      if (json) 'json': true,
    });
    final result = Map<Object?, Object?>.from(response as Map);
    return Han1meHttpResponse(
      statusCode: result['statusCode']! as int,
      body: result['body']! as String,
      url: result['url']! as String,
      headers: Map<String, List<String>>.fromEntries(
        Map<Object?, Object?>.from(result['headers']! as Map).entries.map(
          (entry) => MapEntry(entry.key! as String, List<String>.from(entry.value! as List)),
        ),
      ),
    );
  }

  /// Dart 的 `HttpClient` 把 `Cookie` 当敏感头，跨主机重定向时**直接丢弃**
  /// （`_http/http_impl.dart` 的 `shouldCopyHeaderOnRedirect` 只允许同源复制 cookie），
  /// 而镜像站正是靠 `hanime1.com` → `hanime1.me` 这类跨主机 301 互相跳转：
  /// 第二跳变成匿名请求，服务端于是回一个**新的匿名会话**（`Set-Cookie`），
  /// 覆盖掉真正的登录态 —— 表现为「我的」页收藏/稍后观看全空、账号卡片「0 部影片」。
  /// 所以这里自己走重定向：每一跳都按目标 host 重新算 cookie，与浏览器行为一致。
  static const _maxRedirects = 5;

  /// 自己判断是否重定向，不用 `HttpClientResponse.isRedirect`：后者是**按请求方法**
  /// 分流的（`http_impl.dart` 里 GET/HEAD 认 301/302/303/307/308，而 POST 只认 303），
  /// 于是 POST 收到 301/302 时它返回 false，重定向不会被跟进、cookie 也不会重算。
  static bool _isRedirectStatus(int statusCode) =>
      statusCode == HttpStatus.movedPermanently ||
      statusCode == HttpStatus.found ||
      statusCode == HttpStatus.seeOther ||
      statusCode == HttpStatus.temporaryRedirect ||
      statusCode == HttpStatus.permanentRedirect;

  Future<Han1meHttpResponse> _desktopRequest(String url, {required String method, Map<String, String>? data, Map<String, String>? headers, String? responseCharset, required bool json, bool followRedirects = true}) async {
    final client = _desktopClient();
    try {
      var currentMethod = method;
      var currentUri = Uri.parse(url);
      var sendBody = data != null;
      for (var hop = 0; ; hop++) {
        final request = await client.openUrl(currentMethod, currentUri);
        // 重定向由下面手动处理，原因见 [_maxRedirects] 的注释：交给 Dart 会丢 cookie。
        request.followRedirects = false;
        request.headers.set(HttpHeaders.userAgentHeader, userAgentFor(currentUri.host));
        final cookie = _cookiesFor(currentUri);
        if (cookie.isNotEmpty) request.headers.set(HttpHeaders.cookieHeader, cookie);
        headers?.forEach(request.headers.set);
        if (data != null && sendBody) {
          if (json) {
            request.headers.set(HttpHeaders.contentTypeHeader, 'application/json');
            request.write(jsonEncode(data));
          } else {
            request.headers.contentType = ContentType('application', 'x-www-form-urlencoded', charset: 'utf-8');
            request.write(data.entries.map((entry) => '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(entry.value)}').join('&'));
          }
        }
        final response = await request.close();
        _saveResponseCookies(currentUri, response.cookies);
        final location = response.headers.value(HttpHeaders.locationHeader);
        if (followRedirects && _isRedirectStatus(response.statusCode) && location != null && hop < _maxRedirects) {
          await response.drain<void>();
          // 303 一律转 GET；301/302 按惯例只把 POST 转 GET（保住 DELETE 等语义）；
          // 307/308 保持方法并重发 body。
          if (response.statusCode == HttpStatus.seeOther ||
              ((response.statusCode == HttpStatus.movedPermanently || response.statusCode == HttpStatus.found) && currentMethod == 'POST')) {
            currentMethod = 'GET';
            sendBody = false;
          }
          currentUri = currentUri.resolve(location);
          continue;
        }
        final bytes = await response.fold<List<int>>([], (value, chunk) => value..addAll(chunk));
        final responseHeaders = <String, List<String>>{};
        response.headers.forEach((name, values) => responseHeaders[name] = values);
        return Han1meHttpResponse(statusCode: response.statusCode, body: _decode(bytes, responseCharset), headers: responseHeaders, url: currentUri.toString());
      }
    } finally {
      client.close(force: true);
    }
  }

  String _decode(List<int> bytes, String? charset) {
    if (charset?.toLowerCase() case 'euc-jp' || 'euc_jp') return eucJp.decode(bytes);
    return Encoding.getByName(charset ?? 'utf-8')?.decode(bytes) ?? utf8.decode(bytes, allowMalformed: true);
  }

  HttpClient _desktopClient() => HttpClient();

  String _cookiesFor(Uri uri) {
    final key = _cookieKey(uri.host);
    final value = _desktopCookies[key];
    if (value != null) return value;
    // 非镜像主机（图片 CDN 等）仍按原样精确/后缀匹配。
    if (key != uri.host) return '';
    return _desktopCookies.entries.where((entry) => uri.host.endsWith('.${entry.key}')).map((entry) => entry.value).join('; ');
  }

  void _saveResponseCookies(Uri uri, List<Cookie> cookies) {
    if (cookies.isEmpty) return;
    saveCookies(cookies.map((cookie) => '${cookie.name}=${cookie.value}').join('; '), url: uri.toString());
  }

  String _mergeCookies(String? current, String next) {
    final cookies = <String, String>{};
    for (final cookie in [...(current ?? '').split(';'), ...next.split(';')]) {
      final separator = cookie.indexOf('=');
      if (separator > 0) cookies[cookie.substring(0, separator).trim()] = cookie.substring(separator + 1).trim();
    }
    return cookies.entries.map((entry) => '${entry.key}=${entry.value}').join('; ');
  }
}
