import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as path;

import '../../core/platform_paths.dart';
import '../../domain/models/video.dart';

/// 播放窗口投给主窗口的意图种类。
enum DownloadRequestKind {
  /// 用户点了「下载(N)」：把选中的集加进下载队列。
  download,

  /// 用户点了「我的下载」：把主窗口唤到前台并切到缓存页。
  openDownloads,
}

/// 一条下载意图。
///
/// 只带**跨进程能传的东西**（id / 标题 / 封面这些 JSON 字段）：`VideoDetail`
/// 对象跨不了进程，主窗口收到后会自己按 id 去取详情页拿片源。
class DownloadRequest {
  const DownloadRequest({
    required this.kind,
    this.episodes = const [],
    this.quality = '',
    this.groupName = '',
    this.seriesIds = const [],
    this.createdAt = 0,
  });

  final DownloadRequestKind kind;

  /// 用户勾选的集（当前集也在里面）。
  final List<VideoCard> episodes;

  /// 选中的画质名（主窗口按同名清晰度取源）。
  final String quality;

  /// 目标分组名；空表示不分组。
  final String groupName;

  /// 同系列的全部 id：用于把仍留在默认分组的旧任务一并归入新组。
  final List<String> seriesIds;

  final int createdAt;

  Map<String, dynamic> toJson() => {
        'kind': kind.name,
        'episodes': episodes.map((episode) => episode.toJson()).toList(),
        'quality': quality,
        'groupName': groupName,
        'seriesIds': seriesIds,
        'createdAt': createdAt,
      };

  factory DownloadRequest.fromJson(Map<String, dynamic> json) => DownloadRequest(
        kind: DownloadRequestKind.values
                .where((value) => value.name == json['kind'])
                .firstOrNull ??
            DownloadRequestKind.download,
        episodes: ((json['episodes'] as List?) ?? const [])
            .whereType<Map>()
            .map((item) => VideoCard.fromJson(Map<String, dynamic>.from(item)))
            .where((episode) => episode.id.isNotEmpty)
            .toList(),
        quality: json['quality'] as String? ?? '',
        groupName: json['groupName'] as String? ?? '',
        seriesIds: ((json['seriesIds'] as List?) ?? const [])
            .whereType<String>()
            .toList(),
        createdAt: json['createdAt'] as int? ?? 0,
      );
}

/// 信箱目录：与应用设置同处 `%APPDATA%\han1me_win_plus`，不在下载目录里。
///
/// 放设置目录而不是下载目录：下载目录是用户可以随时改的，改完之后两个进程未必
/// 同时重新读到新值；信箱的位置必须固定，否则意图会落在没人看的目录里。
Future<Directory> _requestDirectory() async =>
    downloadRequestDirectoryOverride ??
    Directory(
      path.join((await appStorageDirectory()).path, 'download_requests'),
    );

/// 测试用：把信箱指到一个临时目录。
///
/// 生产路径要走 path_provider（测试进程里没有插件，直接调会抛
/// MissingPluginException），而这里要验的恰恰是「写进去、取出来、取走就没了」
/// 这套跨进程约定，所以只换目录、不换逻辑。
@visibleForTesting
Directory? downloadRequestDirectoryOverride;

/// 播放窗口侧：把一条意图投进信箱；主窗口下次轮询时取走。
///
/// 每条意图写**独立文件**（文件名 = 微秒时间戳 + pid），所以不需要读-改-写：
/// 多个播放窗口同时投递不会互相覆盖，也不需要跨进程锁。先写 `.tmp` 再 rename，
/// 主窗口就不会读到写了一半的文件。
Future<void> postDownloadRequest(DownloadRequest request) async {
  final directory = await _requestDirectory();
  await directory.create(recursive: true);
  final stamp = DateTime.now().microsecondsSinceEpoch;
  final target = File(path.join(directory.path, '${stamp}_$pid.json'));
  final temporary = File('${target.path}.tmp');
  await temporary.writeAsString(jsonEncode(request.toJson()), flush: true);
  await temporary.rename(target.path);
}

/// 主窗口侧：取出信箱里的全部意图，**取出即删除**（同一个文件不会被处理两次）。
///
/// 读坏的文件直接删掉并跳过：一封坏信不该把整个信箱卡死。文件名按时间戳升序，
/// 所以多条意图会按用户点击的先后顺序执行。
Future<List<DownloadRequest>> takeDownloadRequests() async {
  final directory = await _requestDirectory();
  if (!await directory.exists()) return const [];
  final entries = await directory.list().toList();
  entries.sort((a, b) => a.path.compareTo(b.path));
  final requests = <DownloadRequest>[];
  for (final entity in entries) {
    if (entity is! File || !entity.path.endsWith('.json')) continue;
    try {
      final raw = await entity.readAsString();
      if (raw.trim().isNotEmpty) {
        requests.add(
          DownloadRequest.fromJson(jsonDecode(raw) as Map<String, dynamic>),
        );
      }
    } catch (_) {
      // 坏文件：跳过即可，下面统一删掉。
    }
    try {
      await entity.delete();
    } catch (_) {}
  }
  return requests;
}
