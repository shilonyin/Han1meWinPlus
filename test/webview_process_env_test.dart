import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/webview_environment.dart';

typedef _GetEnvNative = Int32 Function(Pointer<Utf16> name, Pointer<Utf16> buffer, Int32 size);
typedef _GetEnvDart = int Function(Pointer<Utf16> name, Pointer<Utf16> buffer, int size);

/// 回归「DNS 覆盖下发不到 WebView2」。
///
/// `WebViewEnvironment.create` 在本机实测是**失败**的（降级到默认环境），所以
/// `WebViewEnvironmentSettings.additionalBrowserArguments` 那条路走不通；
/// 兜底改成进程级 `WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS`（WebView2 运行时自己读）。
///
/// 这个兜底一旦失效，整个白屏修复就静默落空 —— 所以必须验证它**真的写进了进程环境**，
/// 而不是"调用了没报错"。
void main() {
  test('applyWebViewArgumentsToProcess 真的把变量写进了进程环境', () {
    if (!Platform.isWindows) return;

    const probe = '--host-resolver-rules=MAP probe.test 127.0.0.1';
    applyWebViewArgumentsToProcess(probe);

    // 用 FFI 读回来：Dart 的 Platform.environment 是启动时的只读快照，
    // 读不到本进程后来的修改，必须直接问系统。
    final kernel32 = DynamicLibrary.open('kernel32.dll');
    final getVariable = kernel32.lookupFunction<_GetEnvNative, _GetEnvDart>('GetEnvironmentVariableW');
    final name = webViewArgsEnvironmentVariable.toNativeUtf16();
    final buffer = malloc<Uint16>(2048).cast<Utf16>();
    try {
      final length = getVariable(name, buffer, 2048);
      expect(length, greaterThan(0), reason: '变量没写进去 —— 兜底完全失效');
      expect(buffer.toDartString(), probe);
    } finally {
      malloc.free(name);
      malloc.free(buffer);
    }
  });

  test('变量名必须是 WebView2 认的那一个', () {
    // 改错名字等于兜底不起作用（WebView2 读不到就静默用自己的默认值）。
    expect(webViewArgsEnvironmentVariable, 'WEBVIEW2_ADDITIONAL_BROWSER_ARGUMENTS');
  });

  test('设不上时不能抛异常（它在启动路径上，失败只该记日志）', () {
    expect(() => applyWebViewArgumentsToProcess('--no-proxy-server'), returnsNormally);
  });
}
