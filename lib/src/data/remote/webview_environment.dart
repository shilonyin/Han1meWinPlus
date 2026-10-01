import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../../core/settings.dart';
import '../local/json_store.dart';
import 'windows_http_overrides.dart';

final webViewEnvironmentProvider = FutureProvider<WebViewEnvironment?>((ref) async {
  if (!Platform.isWindows) return null;
  final supportDirectory = await getApplicationSupportDirectory();
  // WebView 里的页面（登录、Cloudflare 挑战等）也必须跟随用户在设置里选的代理模式：
  // 之前这里只读系统代理，于是「手动指定代理」时网页仍走直连——用户看到的是
  // 主界面能打开、WebView 里却打不开。
  final settings = await SettingsStore(JsonStore()).load();
  final rule = await WindowsHttpOverrides.resolveRule(mode: settings.proxyMode, custom: settings.customProxy);
  final environment = await WebViewEnvironment.create(
    settings: WebViewEnvironmentSettings(
      userDataFolder: path.join(supportDirectory.path, 'webview2'),
      additionalBrowserArguments: _browserProxyArgument(rule),
    ),
  );
  ref.onDispose(() => environment.dispose());
  return environment;
});

/// Chromium 的 `--proxy-server` 只认 HTTP/SOCKS 代理的 `scheme://host:port` 写法，
/// 与 Dart 的 `PROXY host:port` 规则串不同，需要重新拼一次。
///
/// 取不到代理时用 `--no-proxy-server` 显式直连：不传参数会让 WebView2 回落到
/// 系统代理，那样「不使用代理」模式就形同虚设。
String _browserProxyArgument(String rule) {
  final proxy = RegExp(r'^PROXY\s+([^;]+)', caseSensitive: false).firstMatch(rule)?.group(1)?.trim();
  if (proxy == null || proxy.isEmpty) return '--no-proxy-server';
  return '--proxy-server=http://$proxy';
}
