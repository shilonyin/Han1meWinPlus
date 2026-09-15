import 'dart:io';

import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import '../features/shared/app_image_cache.dart';
import 'platform_paths.dart';

/// 清理应用自己产生的缓存：封面图片（磁盘 + 内存）与列表卡片元数据。
///
/// 下载的视频、观看记录、追番与收藏都不是缓存，不会被清掉。
class CacheCleaner {
  const CacheCleaner._();

  static const _imageQueries = ['han1me_images', 'libCachedImageData'];
  static const _metaFile = 'video_meta.json';

  /// 缓存当前占用的字节数（图片目录 + 卡片元数据文件）。
  static Future<int> size() async {
    var total = 0;
    for (final directory in await _imageDirectories()) {
      total += await _directorySize(directory);
    }
    final metadata = File(path.join((await appStorageDirectory()).path, _metaFile));
    if (await metadata.exists()) {
      try {
        total += await metadata.length();
      } catch (_) {}
    }
    return total;
  }

  /// 清掉图片的磁盘缓存（新 key 与旧版本遗留的 key 一起）。
  static Future<void> clearImages() async {
    await appImageCacheManager.emptyCache();
    await DefaultCacheManager().emptyCache();
    // emptyCache 只删它索引里记录的文件：旧版本留下的一千多个文件（100+ MB）删不掉，
    // 所以再把目录内容直接清一遍。
    for (final directory in await _imageDirectories()) {
      if (!await directory.exists()) continue;
      try {
        await for (final entity in directory.list()) {
          try {
            await entity.delete(recursive: true);
          } catch (_) {}
        }
      } catch (_) {}
    }
  }

  static String formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  static Future<List<Directory>> _imageDirectories() async {
    final temporary = await getTemporaryDirectory();
    return [for (final key in _imageQueries) Directory(path.join(temporary.path, key))];
  }

  static Future<int> _directorySize(Directory directory) async {
    if (!await directory.exists()) return 0;
    var total = 0;
    try {
      await for (final entity in directory.list(recursive: true, followLinks: false)) {
        if (entity is! File) continue;
        try {
          total += await entity.length();
        } catch (_) {}
      }
    } catch (_) {}
    return total;
  }
}
