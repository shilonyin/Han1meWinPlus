import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Windows 卷容量（`GetDiskFreeSpaceExW`）。
///
/// `dart:io` 的 `FileStat` 只有单个文件的信息，拿不到「整块盘多大、还剩多少」。
/// 设计稿的「共 128 GB · 可用 115.6 GB」必须读真实卷信息，不能写死一个假数字。
class DiskSpace {
  const DiskSpace({required this.total, required this.free});

  /// 卷总字节数。
  final int total;

  /// 当前用户可用的字节数。
  final int free;

  /// 已用字节数。
  int get used => total - free;

  /// 查 [directory] 所在卷的容量；非 Windows 或调用失败时返回 null。
  static DiskSpace? of(Directory directory) {
    if (!Platform.isWindows) return null;
    try {
      final kernel32 = DynamicLibrary.open('kernel32.dll');
      final getDiskFreeSpaceEx = kernel32
          .lookupFunction<
            Int32 Function(
              Pointer<Utf16>,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
            ),
            int Function(
              Pointer<Utf16>,
              Pointer<Uint64>,
              Pointer<Uint64>,
              Pointer<Uint64>,
            )
          >('GetDiskFreeSpaceExW');
      final path = directory.path.toNativeUtf16();
      final freeBytes = calloc<Uint64>();
      final totalBytes = calloc<Uint64>();
      final totalFreeBytes = calloc<Uint64>();
      try {
        final ok = getDiskFreeSpaceEx(
          path,
          freeBytes,
          totalBytes,
          totalFreeBytes,
        );
        if (ok == 0) return null;
        return DiskSpace(total: totalBytes.value, free: freeBytes.value);
      } finally {
        calloc.free(path);
        calloc.free(freeBytes);
        calloc.free(totalBytes);
        calloc.free(totalFreeBytes);
      }
    } catch (_) {
      return null;
    }
  }
}
