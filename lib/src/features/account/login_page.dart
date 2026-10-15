import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_logger.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/webview_environment.dart';
import '../../data/remote/windows_connection_factory.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';
import 'account_controller.dart';
import 'login_url_scope.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  /// 轮询间隔：CF 挑战过掉之后页面会自己跳转，只靠等 `onLoadStop` 有漏掉的风险，
  /// 所以定时主动看一眼当前状态（照上游 Han1mePlus 最新版的做法）。
  static const _pollInterval = Duration(milliseconds: 700);

  /// 两次采集之间的冷却，避免页面连续跳转时反复写盘。
  static const _captureCooldown = Duration(seconds: 2);

  /// 判定「这个页面已经是登录态」的标记，照上游 Han1mePlus 最新版与 Han1meViewer：
  /// 站点登录后右上角会出现指向 `/user/<id>` 的入口（`#user-modal-trigger`），
  /// 个人页则有 `.profile-sub-stats-id`。**用页面真实内容判断，而不是猜 URL** ——
  /// 被 Cloudflare 拦在中间时 URL 根本不会变成「已离开登录页」，URL 判断必然失效。
  static const _loginMarkerScript = r"""
(function () {
  var trigger = document.querySelector('#user-modal-trigger');
  if (trigger) {
    if (/\/user\/\d+/.test(trigger.getAttribute('href') || '')) return true;
    if (trigger.querySelector('a[href*="/user/"]')) return true;
  }
  return document.querySelector('.profile-sub-stats-id') !== null;
})()
""";

  /// 判定当前页**仍是 Cloudflare 挑战页**。挑战页过掉之前取 cookie 只能拿到
  /// `cf_clearance`，那时保存会把「还没真正登录」误判成登录完成。
  static const _challengeMarkerScript = r"""
(function () {
  return document.querySelector('#challenge-form') !== null
      || document.querySelector('#challenge-success-text') !== null
      || document.querySelector('#challenge-error-text') !== null;
})()
""";

  InAppWebViewController? _controller;
  Timer? _timer;
  DateTime? _lastAttempt;
  var _saving = false;
  var _saved = false;
  Object? _error;

  /// 网页自己的加载失败（连不上站点、DNS 挂了等）。
  ///
  /// 登录页会**永久白屏**的情形里，最常见的一种就是「站点根本没连上」—— 设置里选
  /// 「不使用代理」时我们会给 WebView 传 `--no-proxy-server`，而该站点在直连下
  /// 往往打不开（实测：开代理后登录页立刻正常）。以前这种情况界面上什么都没有，
  /// 用户只能看到一片白，也不知道该去开代理。这里把失败原因摆出来。
  String? _loadError;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  /// 这次登录要查 cookie 的候选地址。
  ///
  /// 登录完成后 WebView 可能停在镜像域或 `www.` 子域上，而
  /// `CookieManager.getCookies(url)` 只返回该 URL 作用域内的 cookie；只查设置里的
  /// 那一个地址，一旦登录后停在别处就什么都取不到（「网页里登录成功、应用里仍是
  /// 未登录」就是这么来的）。这里把当前页域名、设置域名、全部镜像域都列上。
  Future<Iterable<String>> _candidateUrls() async {
    final settings = await ref.read(settingsProvider.future);
    final urls = <String>{};
    final current = await _controller?.getUrl();
    if (current != null && current.host.isNotEmpty) urls.add('${current.scheme}://${current.authority}/');
    final base = Uri.tryParse(settings.resolvedBaseUrl);
    if (base != null && base.host.isNotEmpty) urls.add('${base.scheme}://${base.authority}/');
    for (final host in WindowsConnectionFactory.hanimeHosts) {
      urls.add('https://$host/');
    }
    return urls;
  }

  Future<bool> _isChallengePage() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final result = await controller.evaluateJavascript(source: _challengeMarkerScript);
      return result == true || result == 'true';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _hasLoginMarker() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final result = await controller.evaluateJavascript(source: _loginMarkerScript);
      return result == true || result == 'true';
    } catch (_) {
      return false;
    }
  }

  /// 保存这次登录拿到的 cookie。返回是否走通（调用方据此决定放不放行）。
  ///
  /// [quiet] 用于轮询触发的自动采集：那时失败**不该弹给用户**。
  ///
  /// 原因是用户能直接看到的那个症状：密码输错时站点在登录页上显示
  /// `auth.failed`（「账号或密码错误」），而轮询同时也会尝试采集 cookie —— 拿到的是
  /// 未登录的 cookie，`saveCookie` 抓不到账号资料就抛
  /// `Account profile is unavailable`。那条内部错误一旦弹成横幅，就**盖住了站点自己
  /// 那条用户真正需要看的提示**；而且轮询每 2 秒一次，横幅会反复出现。
  ///
  /// 所以自动采集失败时只记日志、不设 [_error]；用户点「确定」或关闭页面时走的是
  /// 非 quiet 路径，那时才把失败摆出来（用户主动操作了，需要知道结果）。
  Future<bool> _capture({bool allowEmpty = false, bool quiet = false}) async {
    if (_saving || _saved || !mounted) return _saved;
    setState(() => _saving = true);
    try {
      final cookie = await ref.read(han1meHttpClientProvider).webViewCookiesFor(await _candidateUrls());
      if (_withoutCloudflare(cookie).isEmpty) {
        if (!mounted) return false;
        setState(() {
          _saving = false;
          _saved = allowEmpty;
        });
        return _saved;
      }
      await ref.read(accountProvider.notifier).saveCookie(cookie);
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _saved = true;
      });
      _timer?.cancel();
      _timer = null;
      Navigator.pop(context);
      return true;
    } catch (error, stack) {
      AppLogger.instance.warning('登录采集失败 quiet=$quiet: $error', tag: 'login');
      AppLogger.instance.debug('$stack', tag: 'login');
      if (!mounted) return false;
      setState(() {
        _saving = false;
        if (!quiet) _error = error;
      });
      return false;
    }
  }

  void _startPolling() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
  }

  /// 定时检查：要么页面自己报了登录标记，要么已经离开登录页。
  ///
  /// 两条都**排除挑战页**：停在 CF 挑战页时既不是登录页也不算登录成功，
  /// 此刻采集只会拿到 `cf_clearance`，把 `_saved` 置位反而会让用户之后真正
  /// 登录成功时不再保存。
  Future<void> _poll() async {
    if (!mounted || _saving || _saved) return;
    final last = _lastAttempt;
    if (last != null && DateTime.now().difference(last) < _captureCooldown) return;
    if (await _isChallengePage()) return;
    if (!await _hasLoginMarker() && !await _leftLoginPage()) return;
    if (!mounted) return;
    _lastAttempt = DateTime.now();
    await _capture(quiet: true);
  }

  /// 当前页是否**已经离开登录页**（且不是挑战页）。
  ///
  /// 判据见 [isStillOnLoginPage]：**不能按精确 host 比** —— 站点已把 `hanime1.com`
  /// 301 到 `hanime1.me`，而用户设置里存的仍是 `.com`，精确比较会恒为「已离开」，
  /// 导致轮询每 2 秒强制采集一次、把站点的「账号或密码错误」提示盖掉。
  Future<bool> _leftLoginPage() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final url = await controller.getUrl();
      if (url == null || url.host.isEmpty) return false;
      final settings = await ref.read(settingsProvider.future);
      return !isStillOnLoginPage(current: Uri.parse(url.toString()), base: settings.resolvedBaseUrl);
    } catch (_) {
      return false;
    }
  }

  /// 去掉 `cf_clearance` 之后还剩不剩东西 —— 只拿到 CF 凭证说明还没登录。
  static String _withoutCloudflare(String cookies) => cookies
      .split(';')
      .where((cookie) => cookie.trim().toLowerCase().split('=').first != 'cf_clearance')
      .join(';')
      .trim();

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final loginUrl = Uri.parse('$baseUrl/login');
    // WebView2 环境是**异步**创建的（要读设置、取目录、建环境）。必须等这个 Future
    // 结束再建 `InAppWebView`：以前直接取 `valueOrNull`，首帧必然是 null，
    // `InAppWebView(webViewEnvironment: null)` 于是让 WebView2 回退到**默认环境**
    // —— 数据目录落到 exe 同目录、系统 DNS、系统代理，`additionalBrowserArguments`
    // 里配的 `--host-resolver-rules`（绕过被污染的 DNS）和代理参数**全部不生效**，
    // 表现出来就是登录页先白屏、几秒后报「网页打不开」。
    //
    // 注意这里**不能**因为环境建不成就不给页面：`webViewEnvironmentProvider` 在创建
    // 失败时会降级成 `null`（默认环境），本页照常渲染。曾经写成拿 error 分支显示错误页，
    // 结果本机上 `WebViewEnvironment.create` 本来就失败，登录页被彻底堵死在错误页上 ——
    // 比原来的白屏还糟。DNS 覆盖改由进程级环境变量兜底，降级后同样生效。
    final environment = ref.watch(webViewEnvironmentProvider);
    return PopScope(
      // 用户在 WebView 里登录完成后，多半直接按返回/关闭退出这个页面，而站点是否
      // 「跳转回首页」并不确定（跳转又可能被 CF 拦下）。关页面时再兜底保存一次 ——
      // 这是最后一道防线，漏掉它，用户看见的就是「网页里登录成功、应用里仍是未登录」。
      canPop: _saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final navigator = Navigator.of(context);
        if (await _capture(allowEmpty: true)) return;
        navigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.login),
          actions: [
            // 手动兜底：轮询万一没赶上（站点停留位置太刁钻），用户点一下就能强制采集。
            PressScale(child: TextButton(
              onPressed: _saving ? null : () => unawaited(_capture(allowEmpty: true)),
              child: Text(AppLocalizations.of(context)!.confirm),
            )),
          ],
        ),
        floatingActionButton: FloatingActionButton(
          tooltip: AppLocalizations.of(context)!.manualCookieLogin,
          onPressed: () => context.push('/login/cookies'),
          child: const Icon(Symbols.cookie_rounded),
        ),
        body: environment.when(
          // 环境还在建：给个明确的加载态，而不是拿 null 环境先把 WebView 建起来。
          loading: () => const Center(child: CircularProgressIndicator()),
          // provider 内部已把失败降级成 data(null)，这里只是兜底：即使真的漏出异常，
          // 也要照常给页面，别把用户挡在错误页上。
          error: (_, __) => _webView(context, loginUrl, null),
          data: (webViewEnvironment) => _webView(context, loginUrl, webViewEnvironment),
        ),
      ),
    );
  }

  Widget _webView(BuildContext context, Uri loginUrl, WebViewEnvironment? webViewEnvironment) {
    return Stack(
      fit: StackFit.expand,
      children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            thirdPartyCookiesEnabled: true,
            userAgent: Han1meApi.userAgent,
          ),
          onWebViewCreated: (controller) async {
            _controller = controller;
            // 只清**本站**的登录 cookie，让登录页显示表单而不是直接跳回已登录页。
            // 这里以前是整个 WebView 一把清（`clearWebViewCookies`），把
            // `cf_clearance` 也抹了，于是登录页本身就被 Cloudflare 挡住 —— 见
            // `Han1meHttpClient.clearWebViewCookiesFor` 的注释。
            await ref.read(han1meHttpClientProvider).clearWebViewCookiesFor(loginUrl.toString());
            if (!mounted) return;
            await controller.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl.toString())));
            if (!mounted) return;
            _startPolling();
          },
          // 页面加载失败（连不上站点）必须让用户看见原因，否则就是一块无解的白板。
          onReceivedError: (_, request, error) {
            if (request.isForMainFrame != true || !mounted) return;
            setState(() => _loadError = error.description);
          },
          // 收到首个响应后清掉上一次的错误提示（比如用户刚去开了代理再回来重试）。
          onLoadStart: (_, url) {
            if (url == null || !mounted || _loadError == null) return;
            setState(() => _loadError = null);
          },
        ),
        if (_loadError != null)
          Positioned(
            left: 24,
            right: 24,
            top: 24,
            child: Card(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Icon(Symbols.wifi_off_rounded, size: 20, color: Theme.of(context).colorScheme.onErrorContainer),
                      const SizedBox(width: 8),
                      Text(
                        AppLocalizations.of(context)!.networkErrorTitle,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    // 登录页连不上站点时，最常见的原因就是「代理模式选了不使用代理，
                    // 而该站点直连打不开」。直接把这句话说出来，比只丢一个技术错误码有用。
                    Text(
                      AppLocalizations.of(context)!.loginLoadFailedHint,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer),
                    ),
                    const SizedBox(height: 4),
                    Text(_loadError!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.onErrorContainer)),
                    const SizedBox(height: 8),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 站点被拦时，手动贴 Cookie 是唯一能走通的后备路线 —— 就在这把入口
                          // 摆出来，别让用户自己去找设置页里的那一项。
                          PressScale(child: TextButton(
                            onPressed: () => context.push('/login/cookies'),
                            child: Text(AppLocalizations.of(context)!.manualCookieLogin),
                          )),
                          PressScale(child: TextButton(
                            onPressed: () async {
                              setState(() => _loadError = null);
                              await _controller?.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl.toString())));
                            },
                            child: Text(AppLocalizations.of(context)!.retry),
                          )),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (_error != null)
          Positioned(
            left: 16,
            right: 16,
            bottom: 16,
            child: MaterialBanner(
              content: Text('$_error'),
              actions: [
                PressScale(child: TextButton(
                  onPressed: () => setState(() => _error = null),
                  child: Text(AppLocalizations.of(context)!.close),
                )),
              ],
            ),
          ),
        if (_saving) const Align(alignment: Alignment.topCenter, child: LinearProgressIndicator()),
      ],
    );
  }
}
