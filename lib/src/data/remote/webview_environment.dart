import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;

import '../../core/platform_paths.dart';
import '../../core/settings.dart';
import '../local/json_store.dart';
import 'address_ranker.dart';
import 'windows_http_overrides.dart';
import 'windows_connection_factory.dart';

/// 给 WebView2 下发「域名解析覆盖 / 代理」用的进程级环境变量名。
///
/// **为什么不能只靠 `WebViewEnvironmentSettings.additionalBrowserArguments`**：
/// 那条路要求自定义环境创建成功；而实测本机上 `WebViewEnvironment.create` 是**失败**的
/// （抛 `PlatformException(0, Cannot create WebViewEnvironment: ...)`，HRESULT 为
/// `E_FAIL` 且没有消息文本），插件于是让 WebView 回退到**默认环境** —— 默认环境不读
/// 我们构造的 options，DNS 覆盖与代理参数全部落空。
///
/// 而 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS` 是 WebView2 **运行时自己读**的进程级
/// 变量，对默认环境同样生效（微软文档与 WebView2Feedback#5571 都确认它优先于
/// options 里的 `AdditionalBrowserArguments`）。所以两条路一起下发：环境建成走 options，
/// 建不成也有环境变量兜底。
const webViewArgsEnvironmentVariable = 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS';

typedef _SetEnvironmentVariableNative = Int32 Function(Pointer<Utf16> name, Pointer<Utf16> value);
typedef _SetEnvironmentVariableDart = int Function(Pointer<Utf16> name, Pointer<Utf16> value);

/// 把 [webViewArgsEnvironmentVariable] 设成 [arguments]。
///
/// 必须**在任何 WebView2 环境创建之前**调用：WebView2 只在创建环境那一刻读它。
/// Dart 的 `Platform.environment` 是只读快照，改不了进程环境，所以这里直接调
/// kernel32 的 `SetEnvironmentVariableW`。
void applyWebViewArgumentsToProcess(String arguments) {
  if (!Platform.isWindows) return;
  try {
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final setVariable = kernel32.lookupFunction<_SetEnvironmentVariableNative, _SetEnvironmentVariableDart>('SetEnvironmentVariableW');
    final name = webViewArgsEnvironmentVariable.toNativeUtf16();
    final value = arguments.toNativeUtf16();
    try {
      setVariable(name, value);
    } finally {
      malloc.free(name);
      malloc.free(value);
    }
  } catch (error) {
    // 设不上不该让启动失败：自定义环境那条路仍然是主路径。
    debugPrint('[webview] set $webViewArgsEnvironmentVariable failed: $error');
  }
}

/// WebView / 网络相关的诊断日志落盘文件。
///
/// **为什么必须落盘**：`han1me_win_plus.exe` 是 `IMAGE_SUBSYSTEM_WINDOWS_GUI` 的
/// Windows 程序（PE Subsystem = 2），从 PowerShell/CMD 启动时**不会 attach 到父控制台** ——
/// `.\han1me_win_plus.exe 2>&1 | Tee-Object` 那种写法一个字节都读不到（实测确认）。
/// 而 WebView2 环境创建失败的现场只有启动那几十毫秒，不落盘就永远查不到原因。
const diagnosticLogFileName = 'webview_diagnostics.log';

/// 诊断日志文件位置（数据目录下）。排查登录页白屏时先看这个文件。
Future<File> webViewDiagnosticsLogFile() async =>
    File(path.join((await appStorageDirectory()).path, diagnosticLogFileName));

/// 追加一行诊断日志。**失败静默**：日志本身不该影响启动，也不该让调用方崩。
Future<void> appendWebViewDiagnostic(String message) async {
  debugPrint(message);
  try {
    final file = await webViewDiagnosticsLogFile();
    await file.writeAsString('${DateTime.now().toIso8601String()} $message\n', mode: FileMode.append, flush: true);
  } catch (_) {}
}

/// 启动最早期写的标记：证明「这一次进程确实跑到了 Dart 入口」。
///
/// 这一步**同步**做（`writeAsStringSync`），不依赖设置、不依赖任何 provider。
/// 排查时的用处：如果连这条都看不到，说明进程没跑到入口（或跑的是别的包）；
/// 如果只看到这条、看不到后面的 `bootstrap args=`，故障就发生在这两者之间 ——
/// 而不是像之前那样只能笼统地说"日志没变化"。
Future<void> writeStartupMarker(List<String> args) async {
  if (!Platform.isWindows) return;
  try {
    final file = await webViewDiagnosticsLogFile();
    file.writeAsStringSync(
      '${DateTime.now().toIso8601String()} [startup] pid=$pid exe=$_executablePath args=${args.join(' ')}\n',
      mode: FileMode.append,
      flush: true,
    );
  } catch (_) {}
}

/// 当前进程的可执行文件路径（拿不到就返回占位符）。
String get _executablePath {
  try {
    return Platform.resolvedExecutable;
  } catch (_) {
    return '(unknown)';
  }
}

final webViewEnvironmentProvider = FutureProvider<WebViewEnvironment?>((ref) async {
  if (!Platform.isWindows) return null;
  final settings = await SettingsStore(JsonStore()).load();
  final rule = await webViewProxyRule(settings);
  // 用 appStorageDirectory 而不是 getApplicationSupportDirectory：后者在 Windows
  // 上按 exe 的版本资源拼路径，指向 %APPDATA%\Han1meWinPlus\Han1meWinPlus\ 那个
  // 历史目录，与应用真正在用的 %APPDATA%\han1me_win_plus\ 分家。它的后果不是
  // 「路径不好看」，而是 **WebView2 环境建不出来**（实测报
  // PlatformException(0, Cannot create WebViewEnvironment: 请求的资源在使用中) ），
  // 于是登录页加载不出、点登录一直卡着，最后报 Account profile is unavailable。
  // 详见 platform_paths.dart 的说明。
  final userDataFolder = path.join((await appStorageDirectory()).path, 'webview2');
  final arguments = webViewBrowserArguments(rule, settings: settings);
  // 兜底再设一次：`bootstrapWebViewArguments()` 已在启动早期设过，但环境可能在设置
  // 变更后被 invalidate 重建，那时参数（代理/内置 IP 排序）已经变了。
  applyWebViewArgumentsToProcess(arguments);
  try {
    final environment = await _createEnvironment(userDataFolder, arguments);
    await appendWebViewDiagnostic('[webview] environment ready userDataFolder=$userDataFolder args=$arguments');
    ref.onDispose(() => environment.dispose());
    return environment;
  } catch (error, stack) {
    // 创建失败**必须降级而不是抛错**：以前这里是裸 await，FutureProvider 进入 error 态，
    // 而调用方读 `valueOrNull`，失败被静默吞掉（WebView 一直是 null、登录页永久白屏）。
    // 而如果改成往上抛、由调用方显示错误页，本机「create 必然失败」就会把登录页
    // **硬堵死**在错误页上 —— 比白屏还糟。降级到默认环境（WebView2 自带、本来就能用）
    // 才是正确行为；代理与 DNS 覆盖已写进进程环境变量，降级后依然生效。
    await appendWebViewDiagnostic('[webview] WebViewEnvironment.create FAILED, fall back to default environment: $error\n$stack');
    return null;
  }
});

/// 决定 WebView 用哪个代理。
///
/// **这里刻意不跟随设置里的 `proxyMode`，而是照上游 Han1mePlus 的做法用系统代理**
/// （上游 `webview_environment.dart` 就是 `WindowsHttpOverrides.systemProxy()`）。
///
/// 原因是实测出来的：设置里选「不使用代理」会让我们注入 `--no-proxy-server`，
/// 把 WebView 的代理彻底关掉、逼它走系统 DNS —— 而本机对 hanime 站群的解析被污染
/// （`hanime1.me` → `65.49.26.99`，直连 10s 超时），页面必然是白的。
/// 用真实 Chromium 对照实测同一个 URL：
///
/// | WebView 参数 | 加载结果 |
/// | --- | --- |
/// | `--no-proxy-server` | **0 字节（白屏）** |
/// | `--proxy-server=http://127.0.0.1:7897` | **28737 字节（页面出来了）** |
///
/// WebView 只是个浏览器，让它跟随系统代理是最自然、也是上游验证过的行为；
/// Dart 侧的请求仍按用户设置的 `proxyMode` 走，两者互不影响。
///
/// 优先级：用户手填的代理 > 系统代理。都没配时返回 `DIRECT`，
/// 由 [webViewBrowserArguments] 用内置 IP 兜底。
Future<String> webViewProxyRule(AppSettings settings) async {
  if (settings.proxyMode == 'custom') {
    final custom = WindowsHttpOverrides.ruleForCustom(settings.customProxy);
    if (custom != null) return custom;
  }
  return WindowsHttpOverrides.systemProxy();
}

/// 启动早期调用：把 WebView2 需要的命令行参数写进进程环境。
///
/// **必须在任何 WebView2 创建之前**跑，所以不能让 provider 惰性触发 ——
/// `webViewPageFetcher`（无头代取 AV 源页面）可能比登录页更早建好默认环境，
/// 那时再设环境变量已经晚了：WebView2 只在创建环境那一刻读它，不会读第二遍。
///
/// [preloaded] 传 main 里已经读好的设置，避免为了这一件事再解析一次 setting.json
/// （系统代理模式下 `systemProxy` 还会起一次 `reg.exe`）。
Future<void> bootstrapWebViewArguments([AppSettings? preloaded]) async {
  if (!Platform.isWindows) return;
  try {
    final settings = preloaded ?? await SettingsStore(JsonStore()).load();
    final rule = await webViewProxyRule(settings);
    final arguments = webViewBrowserArguments(rule, settings: settings);
    applyWebViewArgumentsToProcess(arguments);
    await appendWebViewDiagnostic('[webview] bootstrap proxyRule=$rule args=$arguments');
  } catch (error) {
    await appendWebViewDiagnostic('[webview] bootstrap failed: $error');
  }
}

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

/// 拼出交给 WebView2 的完整命令行参数。
///
/// 由两部分组成，缺一不可：
///
/// 1. **代理**（见 [_browserProxyArgument]）—— 让「设置 → 网络」里的代理模式对网页生效。
/// 2. **域名解析覆盖**（见 [hostResolverRules]）—— 让 WebView 也走内置优选 IP。
///
/// 第 2 条是修复「登录页白屏」的关键：Dart 侧的请求走
/// [WindowsConnectionFactory] 的内置 CF 边缘 IP，绕过了被污染的系统 DNS；而 WebView
/// 原来只靠系统 DNS，于是在同样一个网络里**主界面能浏览、登录页却白屏**。
String webViewBrowserArguments(String proxyRule, {required AppSettings settings}) {
  final arguments = <String>[_browserProxyArgument(proxyRule)];
  // 与 Dart 侧同一套开关：只有「使用内置 Hosts」打开时才注入，走代理时也不必注入
  // （代理自己解析域名，注入反而让它绕开代理的分流规则）。
  if (settings.useBuiltInHosts && !_proxyActive(proxyRule)) {
    final rules = hostResolverRules();
    // **必须整体加双引号**：`MAP host ip` 语法本身带空格，而 Chromium 用
    // `CommandLineToArgvW` 解析命令行 —— 不加引号时值会在第一个空格处被截断，
    // 实际只生效 `MAP` 三个字符，规则等于完全没注入。
    //
    // 实测（CommandLineToArgvW）：
    //   不加引号 → 切成 7 段，`--host-resolver-rules=MAP` 后面全丢了
    //   加引号   → 切成 1 段，值与预期完全一致
    // 现场表现就是 WebView 仍走系统 DNS（被污染、连接超时）→ `ERR_CONNECTION_TIMED OUT`。
    if (rules.isNotEmpty) arguments.add('--host-resolver-rules="$rules"');
  }
  return arguments.join(' ');
}

/// [proxyRule] 是否真的会走代理。`_browserProxyArgument` 拿不到代理时会回退成
/// `--no-proxy-server`，那种情况属于直连、应当注入内置地址。
bool _proxyActive(String rule) => _browserProxyArgument(rule) != '--no-proxy-server';

/// 把内置优选地址拼成 Chromium 的 `--host-resolver-rules` 规则串。
///
/// 规则形如 `MAP hanime1.me 104.19.0.1,MAP www.hanime1.me 104.19.0.1`。
/// 每个主机取**当时排名最靠前的那个地址**（[AddressRanker.order] 已按实测延迟排过序），
/// 挑第一个即可，不必把整张表塞进去：Chromium 对同一主机只认最后一条 `MAP`，
/// 把整表都写上等于用最慢的那个覆盖最快的。
///
/// 裸域与 `www.` 变体都映射：站点会话常在两处各留一份，只映射一个的话另一半请求
/// 仍会撞上被污染的 DNS。
///
/// **分隔符只能用逗号，逗号后面不许有空格**：Chromium 按空格切分命令行，
/// 规则里一旦出现空格，这一条 flag 会被切成好几段而整条失效（Chromium 不认识某段时
/// 不报错、只忽略）。实测同一个 URL：带空格的写法 DOM 长度 0（等于没注入、还是白屏），
/// 不带空格是 5488。
///
/// [hosts] 与 [addressesFor] 只为可测性留出注入点，默认就是线上那份内置表与优选排序。
String hostResolverRules({Map<String, List<String>>? hosts, List<String> Function(String host, List<String> addresses)? addressesFor}) {
  final rules = <String>[];
  for (final entry in (hosts ?? WindowsConnectionFactory.builtInHosts).entries) {
    final ordered = addressesFor?.call(entry.key, entry.value) ?? AddressRanker.instance.order(entry.key, entry.value);
    final address = ordered.firstWhere(_isLiteralAddress, orElse: () => '');
    if (address.isEmpty) continue;
    rules.add('MAP ${entry.key} $address');
    if (!entry.key.startsWith('www.')) rules.add('MAP www.${entry.key} $address');
  }
  return rules.join(',');
}

/// 只认字面量 IP —— 主机名不能作为 `MAP` 的目标（那会形成解析回环）。
bool _isLiteralAddress(String value) => InternetAddress.tryParse(value) != null;

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
