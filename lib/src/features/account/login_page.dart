import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/webview_environment.dart';
import '../../data/remote/windows_connection_factory.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';
import 'account_controller.dart';

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
  Future<bool> _capture({bool allowEmpty = false}) async {
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
    } catch (error) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _error = error;
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
    await _capture();
  }

  /// 当前页是否**已经离开登录页**（且不是挑战页）。
  Future<bool> _leftLoginPage() async {
    final controller = _controller;
    if (controller == null) return false;
    try {
      final url = await controller.getUrl();
      if (url == null || url.host.isEmpty) return false;
      final settings = await ref.read(settingsProvider.future);
      final login = Uri.parse('${settings.resolvedBaseUrl}/login');
      return url.host != login.host || url.path != login.path;
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
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
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
        body: Stack(
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
        ),
      ),
    );
  }
}
