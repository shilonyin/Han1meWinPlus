import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;

import '../../core/settings.dart';
import '../../domain/models/download.dart';
import '../../domain/models/video.dart';
import 'download_repository.dart' show DownloadState;
import 'json_store.dart';

/// 从已解析的缓存索引里挑出可用于播放的本地文件路径；挑不到返回 null。
///
/// 抽成纯函数以便单测（见 test/cached_video_lookup_test.dart）：命中条件有几条
/// 容易写错的边界（没下完的、文件被删的、路径为空的），单靠手测覆盖不到。
///
/// [fileExists] 用来判断本地文件是否还在；省略时不做这层检查。
String? pickCachedVideoPath(
  DownloadState state,
  String videoCode, {
  bool Function(String path)? fileExists,
}) {
  final task = state.tasks
      .where(
        (item) =>
            item.videoCode == videoCode &&
            item.status == DownloadStatus.completed,
      )
      .firstOrNull;
  final localPath = task?.localVideoPath;
  // 没下完的任务也带 localVideoPath（写到一半的目标文件），绝不能拿它去播；
  // 上面已用 status == completed 挡掉，这里再挡住空路径。
  if (localPath == null || localPath.isEmpty) return null;
  if (fileExists != null && !fileExists(localPath)) return null;
  return localPath;
}

/// 按视频 id 查本地缓存，供**独立播放窗口**用。
///
/// 为什么是「只读」而不能复用 [downloadProvider]：
/// `DownloadController.build()` 结尾有个 `Timer.run(_schedule)`，它会自动续传未完成
/// 的下载，并周期性把 `download_store.json` 写回磁盘。播放窗口是**另一个进程**，
/// 在里面初始化那个 provider 就会让两个进程同时下同一批分片、同时写同一个索引文件
/// —— 那是直接的数据损坏风险。所以这里只读文件、不碰任何 provider、不写盘。
///
/// 读不出来（设置读失败 / 文件不存在 / 解析失败 / 视频文件已删）一律返回 null，
/// 让调用方回退到网络播放：缓存只是"能更快打开"的优化，绝不能因为它出问题就让
/// 视频打不开。
Future<VideoDetail?> loadCachedVideoDetail(String videoCode) async {
  try {
    // SettingsStore.load() 内部已做 normalizeDownloadPath。
    final settings = await SettingsStore(JsonStore()).load();
    final store = File(path.join(settings.downloadPath, 'download_store.json'));
    if (!await store.exists()) return null;
    final raw = await store.readAsString();
    if (raw.trim().isEmpty) return null; // 截断写入的产物，当作没有缓存
    final state = DownloadState.fromJson(
      jsonDecode(raw) as Map<String, dynamic>,
    );
    final localPath = pickCachedVideoPath(
      state,
      videoCode,
      fileExists: (value) => File(value).existsSync(),
    );
    if (localPath == null) return null;
    // 命中后从同一条任务上取展示信息（title / 封面 / 画质）。
    final task = state.tasks.firstWhere(
      (item) =>
          item.videoCode == videoCode &&
          item.status == DownloadStatus.completed &&
          item.localVideoPath == localPath,
    );
    return VideoDetail(
      id: task.videoCode,
      title: task.title,
      coverUrl: task.coverUrl,
      sources: [VideoSource(quality: task.quality, url: localPath)],
      tags: const [],
      playlist: const [],
      related: const [],
    );
  } catch (_) {
    // 缓存读取的任何异常都不该阻断播放：交给调用方走网络。
    return null;
  }
}
