import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/media_temp_directory.dart';
import 'package:path/path.dart' as path;

/// media_kit 打开片源时会把播放地址写进 `Directory.systemTemp` 下的临时文件；
/// 该目录不可用/不可写时 `player.open()` 直接抛异常、播放页永远转圈（用户报的
/// 「AV 站无法播放，一直转圈不报错」）。这里锁住 `runWithWritableMediaTemp` 的行为：
/// * 系统临时目录可写时**不做任何改动**（保持既有行为）；
/// * 不可用时在运行期把它换到一个一定可写的目录，且该目录真的能写。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('系统临时目录可写时不安装覆盖层', () async {
    final before = Directory.systemTemp.path;
    final result = await runWithWritableMediaTemp(() => Directory.systemTemp.path);
    expect(result, before, reason: '临时目录可用时不该改变 systemTemp');
  });

  test('系统临时目录不可用时，运行期被换到一个可写目录', () async {
    // 指向一个**不存在**的目录：等价于 `%TEMP%` 指向已删除的盘符 / 被清理掉。
    final missing = Directory(path.join(Directory.systemTemp.path, 'han1me_missing_${DateTime.now().microsecondsSinceEpoch}', 'nested'));
    await IOOverrides.runZoned(
      () async {
        String? seen;
        await runWithWritableMediaTemp(() async {
          final current = Directory.systemTemp.path;
          seen = current;
          final probe = File(path.join(current, 'probe_${DateTime.now().microsecondsSinceEpoch}'));
          await probe.writeAsString('ok', flush: true);
          expect(await probe.exists(), isTrue, reason: '重定向后的临时目录必须真的能写');
          await probe.delete();
        });
        expect(seen, isNot(missing.path));
      },
      getSystemTempDirectory: () => missing,
    );
  });
}
