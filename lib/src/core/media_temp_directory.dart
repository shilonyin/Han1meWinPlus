import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as path;

import 'platform_paths.dart';

/// media_kit 在打开片源时会把播放地址写进一个临时文件（`TempFile.create()`），
/// 位置取自 `Directory.systemTemp`（Windows 上是 `%TEMP%`）。这一步一旦失败，
/// `player.open()` 就直接抛异常，而界面层拿不到任何可展示的错误 —— 播放页会永远
/// 停在转圈上（用户报的「点进去一直在加载」）。
///
/// 常见触发场景：
/// * `%TEMP%` 被组策略 / 安全软件改成不可写，或指向不存在的盘符；
/// * 应用被以受限身份运行（沙箱、受控文件夹访问），`%TEMP%` 只读；
/// * 临时目录里残留了同名只读文件。
///
/// 与其赌系统临时目录可用，不如自己准备一个**一定可写**的目录：系统临时目录探测
/// 通过就照旧用它，否则退到应用自己的存储目录（`%APPDATA%\han1me_win_plus\temp`，
/// 这个目录应用本来就在读写设置与下载，权限一定没问题）。
///
/// Dart 的 `Directory.systemTemp` 没有 setter，但会优先走当前 zone 的 [IOOverrides]，
/// 所以把 [IOOverrides.runZoned] 挂在应用根 zone 上，`getSystemTempDirectory()`
/// 就会被重定向 —— media_kit 无论在哪一层异步代码里取值都拿得到新目录。
///
/// 兜底目录准备失败时不做任何重定向、直接运行 [body]：这个助手是「锦上添花」，
/// 绝不能因为它自己出问题而拖垮启动。
Future<T> runWithWritableMediaTemp<T>(FutureOr<T> Function() body) async {
  Directory? fallback;
  try {
    if (await _writableSystemTemp() == null) {
      final directory = Directory(path.join((await appStorageDirectory()).path, 'temp'));
      await directory.create(recursive: true);
      fallback = directory;
    }
  } catch (_) {
    fallback = null;
  }
  if (fallback == null) return await body();
  final resolved = fallback;
  return await IOOverrides.runZoned(body, getSystemTempDirectory: () => resolved);
}

/// 系统临时目录可写时返回它，否则返回 `null`（真的建一个文件探测，而不只看路径存不存在）。
Future<Directory?> _writableSystemTemp() async {
  try {
    final directory = Directory.systemTemp;
    if (!await directory.exists()) return null;
    final probe = File(path.join(directory.path, 'han1me_win_plus_write_probe_${DateTime.now().microsecondsSinceEpoch}'));
    try {
      await probe.writeAsString('', flush: true);
    } finally {
      try {
        if (await probe.exists()) await probe.delete();
      } catch (_) {}
    }
    return directory;
  } catch (_) {
    return null;
  }
}
