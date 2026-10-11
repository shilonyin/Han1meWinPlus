import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/platform_paths.dart';

class JsonStore {
  /// 每个目标文件一条写入队列。
  ///
  /// 同一个文件被并发写时，两个 `rename` 会撞在一起：后一个的目标路径正被前一个占用，
  /// Windows 直接回 `errno 5 拒绝访问`，而且重试也抢不过（对方还在写）。
  /// `AddressRanker` 多主机探测同时结束、以及偏好存储的整份快照写盘都会踩到，
  /// 所以在这里按文件名串行化 —— 这是唯一能覆盖所有调用方的位置。
  static final _writeTails = <String, Future<void>>{};

  Future<Map<String, dynamic>> read(String fileName) async {
    try {
      final file = await _file(fileName);
      if (!await file.exists()) return {};
      final value = jsonDecode(await file.readAsString());
      return value is Map<String, dynamic> ? value : {};
    } catch (_) {
      return {};
    }
  }

  /// 原子写盘，并且**同一文件的多次写入串行执行**。
  ///
  /// 先写临时文件再 `rename` 覆盖：直接往目标文件上写的话，写到一半进程被结束（或另一端
  /// 正在读）会留下半截 JSON，读回来就是「设置全部丢失」。改名在同一卷内是原子的，
  /// 读的人要么看到旧内容要么看到新内容，不会看到半截。
  ///
  /// 并发由 [_writeTails] 串行化，临时文件名再带上自增序号做双保险。两者缺一不可：
  /// 光靠唯一临时名解决不了「两个 rename 抢同一个目标文件」，光靠串行化也挡不住
  /// 非本类发起的并发。
  Future<void> write(String fileName, Map<String, dynamic> value) {
    final previous = _writeTails[fileName] ?? Future<void>.value();
    // 前一次写失败不能卡住后面的写，所以队列里存的是「忽略错误」的那份。
    final next = previous.then((_) => _writeAtomically(fileName, value));
    _writeTails[fileName] = next.then((_) {}, onError: (Object _) {});
    return next;
  }

  Future<void> _writeAtomically(String fileName, Map<String, dynamic> value) async {
    final target = await _file(fileName);
    final encoded = jsonEncode(value);
    Object? lastError;
    for (var attempt = 0; attempt < 5; attempt++) {
      // 每次尝试都用新的临时名，避免并发写之间、以及重试之间互相抢文件。
      final temp = File('${target.path}.${_tempSequence++}.tmp');
      try {
        await temp.writeAsString(encoded, flush: true);
        await temp.rename(target.path);
        return;
      } catch (error) {
        lastError = error;
        // 尽力清掉自己这次的临时文件，别在数据目录里留垃圾。
        try {
          if (await temp.exists()) await temp.delete();
        } catch (_) {}
        // 退避后再试：占用通常几十毫秒内就释放了。
        await Future<void>.delayed(Duration(milliseconds: 20 * (attempt + 1)));
      }
    }
    throw lastError!;
  }

  /// 临时文件名的自增序号，保证同一进程内不重名。
  static int _tempSequence = 0;

  Future<File> _file(String fileName) async {
    final directory = await appStorageDirectory();
    // 目录可能被用户/清理工具删掉，写之前补一次。
    if (!await directory.exists()) await directory.create(recursive: true);
    return File(path.join(directory.path, fileName));
  }
}
