import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/webview_environment.dart';

/// 回归「诊断日志看不到现场」。
///
/// 排查登录页连不上时，最难过的不是修不好，而是**看不到现场**：应用是
/// `IMAGE_SUBSYSTEM_WINDOWS_GUI`（PE Subsystem = 2）的程序，从终端启动时不会
/// attach 到父控制台，`debugPrint` 一个字节都读不到；而曾经让用户
/// `.\exe 2>&1 | Tee-Object` 去抓日志，那条命令注定是空的。
///
/// 所以诊断必须**落盘**，而且必须在启动最早期就写一条：只看到这条、看不到后续，
/// 就说明故障发生在两者之间 —— 这比"日志没变化"有用得多。
void main() {
  test('启动标记同步落盘，且含 pid / exe / args', () async {
    if (!Platform.isWindows) return;
    final file = await webViewDiagnosticsLogFile();
    if (await file.exists()) await file.delete();

    await writeStartupMarker(const ['--probe-flag=1']);

    expect(await file.exists(), isTrue, reason: '启动标记必须同步写出来，不能等异步链');
    final content = await file.readAsString();
    expect(content, contains('[startup] pid='));
    expect(content, contains('--probe-flag=1'));
    expect(content, contains('exe='));
  });

  test('启动标记是追加，不会覆盖之前的内容', () async {
    if (!Platform.isWindows) return;
    final file = await webViewDiagnosticsLogFile();
    if (await file.exists()) await file.delete();

    await appendWebViewDiagnostic('EARLIER-LINE');
    await writeStartupMarker(const []);
    await writeStartupMarker(const []);

    final content = await file.readAsString();
    expect(content, contains('EARLIER-LINE'));
    expect('[startup] pid='.allMatches(content).length, 2, reason: 'run 两次应当有两行');
  });

  test('appendWebViewDiagnostic 真的写出内容，且是追加而不是覆盖', () async {
    if (!Platform.isWindows) return;
    final file = await webViewDiagnosticsLogFile();
    final existed = await file.exists();
    final before = existed ? await file.readAsString() : '';

    await appendWebViewDiagnostic('PROBE-MARKER-1');
    await appendWebViewDiagnostic('PROBE-MARKER-2');

    expect(await file.exists(), isTrue, reason: '日志文件没被创建 —— 诊断等于白做');
    final after = await file.readAsString();
    expect(after, contains('PROBE-MARKER-1'));
    expect(after, contains('PROBE-MARKER-2'));
    if (existed) {
      expect(after.startsWith(before), isTrue, reason: '应当是追加，不能把旧日志覆盖掉');
    }
  });

  test('日志路径在数据目录下（排查时知道去哪找）', () async {
    if (!Platform.isWindows) return;
    final file = await webViewDiagnosticsLogFile();
    expect(file.path, endsWith('webview_diagnostics.log'));
    expect(file.parent.path, contains('han1me_win_plus'));
  });
}
