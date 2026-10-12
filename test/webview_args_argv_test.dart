import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/remote/webview_environment.dart';

// CommandLineToArgvW —— Windows（以及 Chromium）解析命令行用的就是这套规则。
// 直接调它，就能证明「我们拼出来的参数串被切开以后长什么样」，
// 而不是只对着字符串做主观断言。
typedef _ArgvNative = Pointer<Pointer<Utf16>> Function(Pointer<Utf16> commandLine, Pointer<Int32> numArgs);
typedef _ArgvDart = Pointer<Pointer<Utf16>> Function(Pointer<Utf16> commandLine, Pointer<Int32> numArgs);
typedef _LocalFreeNative = Pointer<Void> Function(Pointer<Void> handle);
typedef _LocalFreeDart = Pointer<Void> Function(Pointer<Void> handle);

List<String> _splitLikeChromium(String commandLine) {
  final shell32 = DynamicLibrary.open('shell32.dll');
  final kernel32 = DynamicLibrary.open('kernel32.dll');
  final argv = shell32.lookupFunction<_ArgvNative, _ArgvDart>('CommandLineToArgvW');
  final localFree = kernel32.lookupFunction<_LocalFreeNative, _LocalFreeDart>('LocalFree');

  final line = commandLine.toNativeUtf16();
  final count = malloc<Int32>();
  try {
    final result = argv(line, count);
    if (result == nullptr) return const [];
    try {
      return [
        for (var i = 0; i < count.value; i++) result[i].toDartString(),
      ];
    } finally {
      localFree(result.cast());
    }
  } finally {
    malloc.free(line);
    malloc.free(count);
  }
}

/// 回归 `ERR_CONNECTION_TIMED OUT`：登录页连不上站点。
///
/// 这是**真正的端到端证明**：把应用拼出来的参数串交给 `CommandLineToArgvW`，
/// 看 Chromium 会把它切成几个参数、`--host-resolver-rules` 的值还剩什么。
///
/// 修复前的实测结果（这就是故障原因）：
///   `app.exe --host-resolver-rules=MAP hanime1.me 172.64.229.154,...`
///   → 7 段，flag 的值只剩 `MAP`
///   → 规则完全没生效 → WebView 仍走被污染的系统 DNS → 连接超时
///
/// 修复后：值被双引号包住，切成 1 段，完整规则原样送达。
void main() {
  test('CommandLineToArgvW 会把不带引号的规则按空格切碎（故障复现）', () {
    if (!Platform.isWindows) return;

    // 先复现旧写法（不加引号）造成的破坏，把这个反例留在测试里。
    final broken = _splitLikeChromium(
      'app.exe --host-resolver-rules=MAP hanime1.me 172.64.229.154,MAP www.hanime1.me 172.64.229.154 --other',
    );
    expect(broken.length, greaterThan(2), reason: '旧写法确实会被切碎');
    expect(broken[1], '--host-resolver-rules=MAP', reason: 'flag 的值只剩 MAP —— 规则等于没注入');

    // 再验证新写法：整体加引号后，值完整送达。
    final fixed = _splitLikeChromium(
      'app.exe --host-resolver-rules="MAP hanime1.me 172.64.229.154,MAP www.hanime1.me 172.64.229.154" --other',
    );
    expect(fixed.length, 3);
    expect(
      fixed[1],
      '--host-resolver-rules=MAP hanime1.me 172.64.229.154,MAP www.hanime1.me 172.64.229.154',
      reason: '规则必须完整送达，否则 WebView 会继续走被污染的 DNS',
    );
  });

  test('应用真实拼出来的参数串，经 Chromium 解析后规则仍然完整', () {
    if (!Platform.isWindows) return;

    final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
    final argv = _splitLikeChromium('han1me_win_plus.exe $arguments');

    // 找出解析后的规则参数，它必须是完整一段、且含有全部 MAP 项。
    final rules = argv.where((arg) => arg.startsWith('--host-resolver-rules=')).toList();
    expect(rules, hasLength(1), reason: '规则被切成了多段 —— 这就是 ERR_CONNECTION_TIMED OUT 的原因');

    final value = rules.single.substring('--host-resolver-rules='.length);
    expect(value, startsWith('MAP '), reason: '值不是完整规则，说明被空格截断了');
    expect(value, contains(',MAP '), reason: '多个主机映射应当都在同一个值里');
    // 内置表里每个 host 一条 MAP，按逗号分隔；完整送达时至少要有 hanime1.me 与 hanime1.com。
    expect(value, contains('MAP hanime1.me '));
    expect(value, contains('MAP hanime1.com '));
    // 不允许出现「值被截断后剩下的零散参数」。
    expect(argv.where((arg) => arg.startsWith('MAP ')), isEmpty, reason: '规则碎片不应成为独立参数');
  });

  test('--no-proxy-server 也原样送达', () {
    if (!Platform.isWindows) return;
    final arguments = webViewBrowserArguments('DIRECT', settings: const AppSettings(useBuiltInHosts: true));
    final argv = _splitLikeChromium('han1me_win_plus.exe $arguments');
    expect(argv, contains('--no-proxy-server'));
  });

  test('走代理时参数串里只有代理一条（不注入规则）', () {
    if (!Platform.isWindows) return;
    final arguments = webViewBrowserArguments('PROXY 127.0.0.1:7897', settings: const AppSettings(useBuiltInHosts: true));
    final argv = _splitLikeChromium('han1me_win_plus.exe $arguments');
    expect(argv, contains('--proxy-server=http://127.0.0.1:7897'));
    expect(argv.where((arg) => arg.startsWith('--host-resolver-rules')), isEmpty);
  });
}
