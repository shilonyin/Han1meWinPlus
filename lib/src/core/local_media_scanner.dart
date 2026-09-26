import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../domain/models/video.dart';

/// 本地视频的一条索引记录。
///
/// 只存能直接从文件读到的信息（路径、大小、标题），不落封面——
/// 封面走文件预览 / 播放器首帧，避免为一个本地库再存一份缩略图。
class LocalMediaEntry {
  const LocalMediaEntry({required this.id, required this.path, required this.title, required this.fileSize, required this.modifiedAt});

  /// 用路径做 id：同一台机器上路径唯一，且扫描时能天然去重。
  final String id;
  final String path;
  final String title;
  final int fileSize;
  final DateTime modifiedAt;

  Map<String, dynamic> toJson() => {'id': id, 'path': path, 'title': title, 'fileSize': fileSize, 'modifiedAt': modifiedAt.millisecondsSinceEpoch};

  factory LocalMediaEntry.fromJson(Map<String, dynamic> json) => LocalMediaEntry(
        id: json['id'] as String? ?? '',
        path: json['path'] as String? ?? '',
        title: json['title'] as String? ?? '',
        fileSize: json['fileSize'] as int? ?? 0,
        modifiedAt: DateTime.fromMillisecondsSinceEpoch(json['modifiedAt'] as int? ?? 0),
      );

  /// 转成播放页能直接吃的 [VideoDetail]：本地文件没有封面与作者信息，
  /// 用占位值补齐，播放源指向本地文件。
  VideoDetail toVideoDetail() => VideoDetail(
        id: id,
        title: title,
        tags: const [],
        playlist: const [],
        related: const [],
        sources: [VideoSource(quality: '本地文件', url: Uri.file(path).toString())],
      );
}

/// 本地媒体库扫描：给定目录，把里面的视频文件建成索引。
///
/// 索引本身复用仓库既有的 JSON 存储（见 `LocalMediaRepository`），
/// 不额外引入 sqlite —— 本机库规模是几百到几千条，JSON 读写足够，
/// 也免掉一个原生依赖（sqlite3 在 Windows 上还要带一份 DLL）。
class LocalMediaScanner {
  LocalMediaScanner();

  static const videoExtensions = {'mp4', 'mkv', 'webm', 'avi', 'mov', 'flv', 'wmv', 'm4v', 'ts'};

  /// 扫一遍目录，返回索引条目；目录不存在或读不了就返回空列表。
  Future<List<LocalMediaEntry>> scan(String directory, {bool recursive = true}) async {
    if (directory.isEmpty) return const [];
    final root = Directory(directory);
    if (!await root.exists()) return const [];
    final entries = <LocalMediaEntry>[];
    try {
      await for (final entity in root.list(recursive: recursive, followLinks: false)) {
        if (entity is! File) continue;
        if (!_isVideo(entity.path)) continue;
        final stat = await entity.stat();
        entries.add(LocalMediaEntry(
          id: entity.path,
          path: entity.path,
          title: _titleFromPath(entity.path),
          fileSize: stat.size,
          modifiedAt: stat.modifiedAt,
        ));
      }
    } catch (error) {
      debugPrint('[local-media] scan failed: $error');
    }
    return entries;
  }

  static bool _isVideo(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    if (dot <= 0) return false;
    return videoExtensions.contains(name.substring(dot + 1).toLowerCase());
  }

  /// 从文件名猜标题：去掉扩展名、`[]` 里压制组信息、把下划线点号换成空格。
  static String titleFromPath(String path) => _titleFromPath(path);

  static String _titleFromPath(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final withoutExtension = name.contains('.') ? name.substring(0, name.lastIndexOf('.')) : name;
    final cleaned = withoutExtension
        .replaceAll(RegExp(r'\[[^\]]*\]'), '')
        .replaceAll(RegExp(r'\([^)]*\)'), '')
        .replaceAll(RegExp(r'[._]+'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return cleaned.isEmpty ? name : cleaned;
  }
}
