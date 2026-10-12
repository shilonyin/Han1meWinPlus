import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/webview_environment.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';
import 'account_controller.dart';

class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  var _saving = false;
  var _saved = false;
  Object? _error;

  /// 登录页自身的地址，用来判断 WebView 什么时候「已经离开登录页」。
  ///
  /// 必须存成字段：`build` 里那份是从设置同步算出来的，而 `onLoadStop` 的回调
  /// 拿不到它，早期版本靠比较 path 判断，遇到被 CF 拦截后停在挑战页的情况就判断不出来。
  Uri? _loginUrl;

  /// 保存这次登录拿到的 cookie。
  ///
  /// [allowEmpty] 为 true 时即使 cookie 为空也算「处理完了」（不再重试）。
  /// 返回这次保存有没有走通，调用方（返回拦截）据此决定放不放行。
  Future<bool> _saveCookies({bool allowEmpty = false}) async {
    if (_saving || _saved || !mounted) return _saved;
    setState(() => _saving = true);
    try {
      final settings = await ref.read(settingsProvider.future);
      final cookie = await ref.read(han1meHttpClientProvider).webViewCookies(settings.resolvedBaseUrl);
      if (cookie.isEmpty) {
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

  /// 这次导航是不是「已经离开登录页，并且页面已经真正渲染出来」。
  ///
  /// 两个条件缺一不可：
  /// - **离开登录页**：停留在 `/login` 时用户可能正在输密码，取 cookie 只会拿到
  ///   未认证的空会话。
  /// - **不是 Cloudflare 挑战页**：验证过不去时 WebView 会被挡在
  ///   `challenges.cloudflare.com` 上，那既不是登录页也不算登录成功；此时取 cookie
  ///   同样只有 `cf_clearance`，把 `_saved` 置位反而会让用户后续真正登录成功时不再保存。
  bool _leftLoginPage(Uri? url) {
    if (url == null || url.host.isEmpty) return false;
    if (url.host.endsWith('cloudflare.com')) return false;
    final login = _loginUrl;
    if (login == null) return false;
    return url.host != login.host || url.path != login.path;
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final loginUrl = Uri.parse('$baseUrl/login');
    _loginUrl = loginUrl;
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
    return PopScope(
      // 用户在 WebView 里登录完成后，多半是直接按返回/关闭退出这个页面，而站点
      // 是否「跳转回首页」并不确定（跳转又可能被 CF 拦下）。所以在页面被关掉时
      // 再兜底保存一次 —— 这是最后一道防线，漏掉它，用户看见的就是「网页里登录
      // 成功、应用里仍是未登录」。
      canPop: _saved,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        // 保存成功时 `_saveCookies` 已经弹过页面了；只有没弹出去（取不到 cookie
        // 或保存失败）才需要这里补一次，避免用户被卡在登录页出不去。
        final navigator = Navigator.of(context);
        if (await _saveCookies(allowEmpty: true)) return;
        navigator.pop();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        appBar: AppBar(title: Text(AppLocalizations.of(context)!.login)),
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
                // 只清**本站**的登录 cookie，让登录页显示表单而不是直接跳回已登录页。
                // 这里以前是整个 WebView 一把清（`clearWebViewCookies`），把
                // `cf_clearance` 也抹了，于是登录页本身就被 Cloudflare 挡住 —— 见
                // `Han1meHttpClient.clearWebViewCookiesFor` 的注释。
                await ref.read(han1meHttpClientProvider).clearWebViewCookiesFor(loginUrl.toString());
                if (!mounted) return;
                await controller.loadUrl(urlRequest: URLRequest(url: WebUri(loginUrl.toString())));
              },
              onLoadStop: (_, url) {
                final target = url == null ? null : Uri.tryParse(url.toString());
                if (_leftLoginPage(target)) _saveCookies();
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
