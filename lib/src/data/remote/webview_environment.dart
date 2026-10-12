import 'dart:io';

import 'package:flutter/foundation.dart';
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
  final userDataFolder = path.join(supportDirectory.path, 'webview2');
  final arguments = _browserProxyArgument(rule);
  try {
    final environment = await _createEnvironment(userDataFolder, arguments);
    debugPrint('[webview] environment ready: $userDataFolder args=$arguments');
    ref.onDispose(() => environment.dispose());
    return environment;
  } catch (error, stack) {
    // 这里以前是裸 await：创建失败时 FutureProvider 进入 error 态，而所有调用方都读
    // `valueOrNull`，于是**失败被静默吞掉**，WebView 一直是 null、登录页永久白屏，
    // 却看不到任何线索。留下日志，让下次白屏时能直接看到原因。
    debugPrint('[webview] WebViewEnvironment.create failed: $error\n$stack');
    rethrow;
  }
});

/// 创建 WebView2 环境。
///
/// 注意 `additionalBrowserArguments` 的选择**直接决定 WebView 能不能打开站点**：
/// `direct`（不使用代理）时这里传 `--no-proxy-server`，WebView 就真的直连；
/// 而登录页/挑战页所在的站点在直连下是打不开的（实测：开代理后登录页立刻正常
/// 加载出来，关代理就是一片白）。所以代理模式为 `direct` 时登录页白屏是
/// 「网络确实连不上」的正常表现，不是环境创建失败。
Future<WebViewEnvironment> _createEnvironment(String userDataFolder, String arguments) =>
    WebViewEnvironment.create(
      settings: WebViewEnvironmentSettings(
        userDataFolder: userDataFolder,
        additionalBrowserArguments: arguments,
      ),
    );

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
