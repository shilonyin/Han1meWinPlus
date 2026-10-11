import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';

import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/jav/jav_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../data/remote/webview_environment.dart';
import '../account/account_controller.dart';
import 'settings_controller.dart';

class CloudflarePage extends ConsumerStatefulWidget {
  const CloudflarePage({super.key, this.initialUrl});

  final String? initialUrl;

  @override
  ConsumerState<CloudflarePage> createState() => _CloudflarePageState();
}

class _CloudflarePageState extends ConsumerState<CloudflarePage> {
  Timer? _verificationTimer;
  String? _initialClearance;
  var _saving = false;

  Future<void> _completeVerification(String requestUrl) async {
    if (_saving) return;
    _saving = true;
    try {
      final cookies = await ref.read(han1meHttpClientProvider).webViewCookies(requestUrl);
      final clearance = _clearanceCookie(cookies);
      if (clearance == null || clearance == _initialClearance || !mounted) return;
      await ref.read(accountProvider.notifier).saveCloudflareCookie(cookies);
      if (!mounted) return;
      _verificationTimer?.cancel();
      Navigator.pop(context, true);
    } catch (_) {
    } finally {
      _saving = false;
    }
  }

  void _startVerification(String requestUrl) {
    if (_verificationTimer != null) return;
    _verificationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_saving) _completeVerification(requestUrl);
    });
  }

  String? _clearanceCookie(String cookies) {
    for (final cookie in cookies.split(';')) {
      if (cookie.trim().toLowerCase().startsWith('cf_clearance=')) return cookie.trim();
    }
    return null;
  }

  @override
  void dispose() {
    _verificationTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final baseUrl = ref.watch(settingsProvider).valueOrNull?.resolvedBaseUrl ?? 'https://hanime1.com';
    final initialUrl = widget.initialUrl ?? baseUrl;
    // 验证用的 UA 必须和随后「像浏览器」的那批请求逐字一致（`cf_clearance` 与 UA
    // 绑定）：hanime1 走 `Han1meApi.userAgent`（= 动态取本机内核的浏览器 UA），
    // AV 源走 `JavApi.userAgent`。
    // 不能用 `Han1meHttpClient.userAgentFor(host)` —— 它对 hanime 站群返回的是
    // 自报家门的 UA（桌面 Dart 请求靠它绕过「冒充浏览器」判定），WebView 用它去过
    // 挑战必然失败。
    final userAgent = javSiteFor(initialUrl) == null ? Han1meApi.userAgent : JavApi.userAgent;
    final webViewEnvironment = ref.watch(webViewEnvironmentProvider).valueOrNull;
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context)!.cloudflareVerification)),
      body: Stack(children: [
        InAppWebView(
          webViewEnvironment: webViewEnvironment,
          initialSettings: InAppWebViewSettings(
            javaScriptEnabled: true,
            domStorageEnabled: true,
            thirdPartyCookiesEnabled: true,
            userAgent: userAgent,
          ),
          onWebViewCreated: (controller) async {
            _initialClearance = _clearanceCookie(await ref.read(han1meHttpClientProvider).webViewCookies(initialUrl));
            final url = WebUri(initialUrl);
            await controller.loadUrl(urlRequest: URLRequest(url: url));
            _startVerification(initialUrl);
          },
        ),
      ]),
    );
  }
}
