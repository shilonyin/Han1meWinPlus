import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as path;
import '../../core/settings.dart';
import '../../core/platform_paths.dart';
import '../../core/platform_service.dart';
import '../../data/han1me_repository.dart';
import '../../domain/models/download.dart';
import '../../domain/models/video.dart';
import '../../features/settings/settings_controller.dart';

class DownloadState {
  const DownloadState({this.groups = const [DownloadGroup(id: 'default', name: 'Cached', createdAt: 0)], this.tasks = const []});

  final List<DownloadGroup> groups;
  final List<DownloadTask> tasks;

  Map<String, dynamic> toJson() => {'groups': groups.map((item) => item.toJson()).toList(), 'tasks': tasks.map((item) => item.toJson()).toList()};

  factory DownloadState.fromJson(Map<String, dynamic> json) {
    final groups = ((json['groups'] as List?) ?? const []).whereType<Map>().map((item) => DownloadGroup.fromJson(Map<String, dynamic>.from(item))).where((group) => group.id.isNotEmpty).toList();
    final normalizedGroups = groups.any((group) => group.id == 'default') ? groups : [const DownloadGroup(id: 'default', name: 'Cached', createdAt: 0), ...groups];
    final groupIds = normalizedGroups.map((group) => group.id).toSet();
    final tasks = ((json['tasks'] as List?) ?? const [])
        .whereType<Map>()
        .map((item) => DownloadTask.fromJson(Map<String, dynamic>.from(item)))
        .map((task) => task.copyWith(groupIds: task.groupIds.where(groupIds.contains).toSet(), updatedAt: task.updatedAt))
        .toList();
    return DownloadState(groups: normalizedGroups, tasks: tasks);
  }
}

final downloadProvider = AsyncNotifierProvider<DownloadController, DownloadState>(DownloadController.new);

class DownloadController extends AsyncNotifier<DownloadState> {
  late Directory _root;
  final _running = <String>{};
  final _jobs = <String, ({VideoDetail detail, VideoSource source})>{};

  /// 被用户暂停的任务。
  ///
  /// 单放一份集合而不是只看 `DownloadStatus.paused`：正在跑的那条流要能**立刻**收到
  /// 信号停下来，而它每写一个分片都会覆盖一次状态，光靠状态字段判断会来不及。
  final _paused = <String>{};
  Future<void> _writeQueue = Future<void>.value();

  @override
  Future<DownloadState> build() async {
    ref.listen<AsyncValue<AppSettings>>(settingsProvider, (previous, next) {
      if (previous?.valueOrNull?.downloadPath != next.valueOrNull?.downloadPath) {
        ref.invalidateSelf();
      } else {
        _schedule();
      }
    });
    final settings = await ref.read(settingsProvider.future);
    _root = Directory(await normalizeDownloadPath(settings.downloadPath));
    await _root.create(recursive: true);
    final file = File(path.join(_root.path, 'download_store.json'));
    try {
      // 空文件（或只剩空白的文件）**不能**当成"没有缓存"。
      //
      // 它几乎总是"上次写到一半被打断"的产物：`writeAsString` 不是原子的，会先把
      // 文件截断到 0 再写内容，进程在此时被杀（强杀、断电、卸载）就留下一个 0 字节
      // 文件。旧代码把它当空状态返回，随后任何一次保存都会把空状态覆盖回磁盘 ——
      // 用户所有已下载的索引就此静默消失（视频文件其实还在磁盘上）。
      // 这里直接抛错走 catch 分支，让调用方知道"读坏了"，而不是"没有数据"。
      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        throw const FormatException('download_store.json is empty (truncated write?)');
      }
      final loaded = DownloadState.fromJson(jsonDecode(raw) as Map<String, dynamic>);
      final tasks = loaded.tasks.map((task) {
        if (task.status == DownloadStatus.completed) return task;
        // 上次退出前手动暂停的，重启后保持暂停，不要擅自开始。
        if (task.status == DownloadStatus.paused) {
          _paused.add(task.id);
          return task;
        }
        if (task.sourceUrl?.isEmpty != false) return task.copyWith(status: DownloadStatus.failed, errorMessage: 'Download interrupted');
        _jobs[task.id] = (
          detail: VideoDetail(id: task.videoCode, title: task.title, coverUrl: task.coverUrl, sources: const [], tags: const [], playlist: const [], related: const []),
          source: VideoSource(quality: task.quality, url: task.sourceUrl!),
        );
        return task.copyWith(status: DownloadStatus.queued, clearError: true);
      }).toList();
      final restored = DownloadState(groups: loaded.groups, tasks: tasks);
      Timer.run(_schedule);
      return restored;
    } catch (_) {
      // 读失败时**先**把坏文件挪走留证，再返回空状态。
      // 这样万一还是走到了"用空状态覆盖"的路径，至少原文件还在，能人工恢复。
      // 只对"非空但解析失败/空文件"这么做；文件本就不存在（首次启动）不必留证。
      try {
        if (await file.exists() && await file.length() > 0) {
          final salvage = File('${file.path}.corrupt');
          if (await salvage.exists()) await salvage.delete();
          await file.rename(salvage.path);
        }
      } catch (_) {}
      return const DownloadState();
    }
  }

  /// 原子保存。
  ///
  /// **必须**写临时文件再 `rename` 替换：直接 `writeAsString` 会先把目标文件截断到
  /// 0 再写内容，如果进程正好在写入过程中被杀（用户强杀 / 安装程序 /CLOSEAPPLICATIONS
  /// /断电），磁盘上就只剩一个 0 字节文件 —— 下次启动读不出内容，用户的下载索引
  /// 会被静默清空。同一目录内的 rename 是原子的，替换要么完整成功要么完全不动。
  Future<void> _save(DownloadState value) async {
    final file = File(path.join(_root.path, 'download_store.json'));
    _writeQueue = _writeQueue.then((_) async {
      final temporary = File('${file.path}.tmp');
      await temporary.writeAsString(jsonEncode(value.toJson()), flush: true);
      await temporary.rename(file.path);
      state = AsyncData(value);
    });
    await _writeQueue;
  }

  Future<String?> addGroup(String name, DownloadGroupSort sort) async {
    final text = name.trim();
    final current = state.value ?? const DownloadState();
    if (text.isEmpty || current.groups.any((group) => group.name == text)) return null;
    final id = DateTime.now().microsecondsSinceEpoch.toString();
    await _save(DownloadState(groups: [...current.groups, DownloadGroup(id: id, name: text, createdAt: DateTime.now().millisecondsSinceEpoch, sort: sort)], tasks: current.tasks));
    return id;
  }

  Future<void> updateGroup(String id, String name, DownloadGroupSort sort) async {
    final text = name.trim();
    final current = state.value ?? const DownloadState();
    if (text.isEmpty || current.groups.any((group) => group.id != id && group.name == text)) return;
    await _save(DownloadState(groups: current.groups.map((group) => group.id == id ? group.copyWith(name: text, sort: sort) : group).toList(), tasks: current.tasks));
  }

  Future<void> deleteGroup(String id) async {
    if (id == 'default') return;
    final current = state.value ?? const DownloadState();
    final tasks = current.tasks.map((task) => task.groupIds.contains(id) ? task.copyWith(groupIds: {...task.groupIds}..remove(id)) : task).toList();
    await _save(DownloadState(groups: current.groups.where((group) => group.id != id).toList(), tasks: tasks));
  }

  Future<void> deleteTasks(Set<String> ids) async {
    final current = state.value ?? const DownloadState();
    for (final task in current.tasks.where((task) => ids.contains(task.id))) {
      final directory = Directory(path.join(_root.path, task.videoCode));
      if (await directory.exists()) await directory.delete(recursive: true);
      _jobs.remove(task.id);
    }
    // 暂停标记也要一起清掉，否则同 id 重新下载时会被当成"仍在暂停"而卡住。
    _paused.removeAll(ids);
    await _save(DownloadState(groups: current.groups, tasks: current.tasks.where((task) => !ids.contains(task.id)).toList()));
  }

  Future<void> togglePinned(Set<String> ids) async {
    final current = state.value ?? const DownloadState();
    final selected = current.tasks.where((task) => ids.contains(task.id)).toList();
    if (selected.isEmpty) return;
    final pinned = !selected.every((task) => task.pinned);
    await _save(DownloadState(groups: current.groups, tasks: current.tasks.map((task) => ids.contains(task.id) ? task.copyWith(pinned: pinned) : task).toList()));
  }

  Future<void> setTaskGroups(Set<String> ids, Set<String> groupIds) async {
    final current = state.value ?? const DownloadState();
    final valid = groupIds.where((id) => id != 'default' && current.groups.any((group) => group.id == id)).toSet();
    await _save(DownloadState(groups: current.groups, tasks: current.tasks.map((task) => ids.contains(task.id) ? task.copyWith(groupIds: valid) : task).toList()));
  }

  Future<void> replace(DownloadState value) => _save(value);

  /// 自动分组：同名组直接复用，否则新建，返回可传给 [create] 的 groupId。
  /// 名称为空或建组失败时回退到默认分组。
  Future<String> resolveAutoGroup(String name, DownloadGroupSort sort) async {
    final text = name.trim();
    if (text.isEmpty) return 'default';
    final current = state.value ?? const DownloadState();
    final existing = current.groups.where((group) => group.name == text).firstOrNull;
    if (existing != null) return existing.id;
    return await addGroup(text, sort) ?? 'default';
  }

  /// 把同系列中**仍留在默认分组**的已下载影片归入目标组。
  /// 用户手动分过组（groupIds 非空）的一律不动，避免覆盖用户意图。
  Future<int> adoptSeriesTasks(Iterable<String> videoCodes, String groupId) async {
    if (groupId == 'default') return 0;
    final codes = videoCodes.toSet();
    final current = state.value ?? const DownloadState();
    final pending = current.tasks.where((task) => codes.contains(task.videoCode) && task.groupIds.isEmpty).toList();
    if (pending.isEmpty) return 0;
    final ids = pending.map((task) => task.id).toSet();
    await _save(DownloadState(groups: current.groups, tasks: current.tasks.map((task) => ids.contains(task.id) ? task.copyWith(groupIds: {groupId}) : task).toList()));
    return ids.length;
  }

  Future<void> create(VideoDetail detail, VideoSource source, String groupId) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final task = DownloadTask(id: detail.id, videoCode: detail.id, title: detail.title, coverUrl: detail.coverUrl, duration: detail.duration, views: detail.views, rating: detail.rating, uploadTime: detail.uploadDate, sourceUrl: source.url, groupIds: groupId == 'default' ? const {} : {groupId}, quality: source.quality, status: DownloadStatus.queued, progress: 0, downloadedBytes: 0, totalBytes: 0, createdAt: now, updatedAt: now);
    final current = state.value ?? const DownloadState();
    _jobs[task.id] = (detail: detail, source: source);
    await _save(DownloadState(groups: current.groups, tasks: [...current.tasks.where((item) => item.videoCode != detail.id), task]));
    _schedule();
  }

  Future<void> _replace(String id, DownloadTask Function(DownloadTask) update) async {
    final current = state.value ?? const DownloadState();
    await _save(DownloadState(groups: current.groups, tasks: current.tasks.map((task) => task.id == id ? update(task) : task).toList()));
  }

  Future<void> retry(String id) async {
    final current = state.value ?? const DownloadState();
    final task = current.tasks.where((item) => item.id == id).firstOrNull;
    if (task == null || task.status != DownloadStatus.failed) return;
    final settings = await ref.read(settingsProvider.future);
    VideoDetail detail;
    VideoSource? source;
    try {
      detail = await ref.read(han1meRepositoryProvider).video(settings.resolvedBaseUrl, task.videoCode);
      source = detail.sources.where((item) => item.quality == task.quality).firstOrNull ?? detail.sources.firstOrNull;
    } catch (_) {
      if (task.sourceUrl?.isEmpty != false) return;
      detail = VideoDetail(id: task.videoCode, title: task.title, coverUrl: task.coverUrl, sources: const [], tags: const [], playlist: const [], related: const []);
      source = VideoSource(quality: task.quality, url: task.sourceUrl!);
    }
    if (source == null) return;
    _jobs[id] = (detail: detail, source: source);
    await _replace(id, (value) => value.copyWith(status: DownloadStatus.queued, progress: 0, downloadedBytes: 0, totalBytes: 0, sourceUrl: source!.url, clearError: true));
    _schedule();
  }

  /// 暂停一批任务。
  ///
  /// 正在下载的那条流会被 [_paused] 打断，已写入的 `.part` 分片保留 —— 下次开始
  /// 时靠 `Range` 头续传，不用从头再来。
  Future<void> pauseTasks(Set<String> ids) async {
    final current = state.value ?? const DownloadState();
    final targets = current.tasks.where((task) => ids.contains(task.id) && (task.status == DownloadStatus.downloading || task.status == DownloadStatus.queued)).map((task) => task.id).toSet();
    if (targets.isEmpty) return;
    _paused.addAll(targets);
    await _save(DownloadState(
      groups: current.groups,
      tasks: current.tasks.map((task) => targets.contains(task.id) ? task.copyWith(status: DownloadStatus.paused) : task).toList(),
    ));
  }

  /// 开始（或继续）一批任务：失败的按重试处理，其余排队等调度。
  Future<void> resumeTasks(Set<String> ids) async {
    final current = state.value ?? const DownloadState();
    final targets = current.tasks.where((task) => ids.contains(task.id) && (task.status == DownloadStatus.paused || task.status == DownloadStatus.failed)).toList();
    if (targets.isEmpty) return;
    for (final task in targets) {
      _paused.remove(task.id);
      if (task.status == DownloadStatus.failed) {
        await retry(task.id);
        continue;
      }
      // 暂停过的任务可能已经不在本次会话的调度表里（例如重启后想继续），
      // 重新取一次详情页把片源补回来再排队。
      if (!_jobs.containsKey(task.id)) {
        final settings = await ref.read(settingsProvider.future);
        try {
          final detail = await ref.read(han1meRepositoryProvider).video(settings.resolvedBaseUrl, task.videoCode);
          final source = detail.sources.where((item) => item.quality == task.quality).firstOrNull ?? detail.sources.where((item) => !item.url.contains('.m3u8')).firstOrNull;
          if (source == null) continue;
          _jobs[task.id] = (detail: detail, source: source);
          await _replace(task.id, (value) => value.copyWith(sourceUrl: source.url, clearError: true));
        } catch (_) {
          if (task.sourceUrl?.isEmpty != false) continue;
          _jobs[task.id] = (
            detail: VideoDetail(id: task.videoCode, title: task.title, coverUrl: task.coverUrl, sources: const [], tags: const [], playlist: const [], related: const []),
            source: VideoSource(quality: task.quality, url: task.sourceUrl!),
          );
        }
      }
      await _replace(task.id, (value) => value.copyWith(status: DownloadStatus.queued, clearError: true));
    }
    _schedule();
  }

  /// 删除一批任务，顺带清掉本地文件（暂停中的也要能删）。
  Future<void> removeTasks(Set<String> ids) => deleteTasks(ids);

  Future<void> exportCompleted(String destinationPath) async {
    final destination = Directory(destinationPath);
    await destination.create(recursive: true);
    final tasks = (state.value ?? const DownloadState()).tasks.where((task) => task.status == DownloadStatus.completed);
    for (final task in tasks) {
      final source = Directory(path.join(_root.path, task.videoCode));
      if (!await source.exists()) continue;
      await for (final entity in source.list(recursive: true)) {
        if (entity is! File) continue;
        final relativePath = entity.path.substring(source.path.length + 1);
        final target = File(path.join(destination.path, task.videoCode, relativePath));
        await target.parent.create(recursive: true);
        await entity.copy(target.path);
      }
    }
  }

  Future<bool> exportCompletedWithPicker() async {
    if (!Platform.isAndroid) return false;
    final destination = await PlatformService.selectDirectory();
    if (destination == null) return false;
    final temporary = await Directory.systemTemp.createTemp('han1me_win_plus_export_');
    try {
      await exportCompleted(temporary.path);
      await PlatformService.exportDirectory(temporary.path, destination);
      return true;
    } finally {
      if (await temporary.exists()) await temporary.delete(recursive: true);
    }
  }

  void _schedule() {
    final limit = ref.read(settingsProvider).value?.concurrentDownloads ?? 2;
    while (_running.length < limit) {
      final queued = (state.value?.tasks ?? const <DownloadTask>[]).where((item) => item.status == DownloadStatus.queued && !_paused.contains(item.id) && _jobs.containsKey(item.id) && !_running.contains(item.id));
      final task = queued.isEmpty ? null : queued.first;
      if (task == null) return;
      final job = _jobs[task.id]!;
      _running.add(task.id);
      _run(task, job.detail, job.source).whenComplete(() {
        _running.remove(task.id);
        _schedule();
      });
    }
  }

  Future<void> _run(DownloadTask task, VideoDetail detail, VideoSource source) async {
    try {
      final directory = Directory(path.join(_root.path, task.videoCode));
      await directory.create(recursive: true);
      final meta = File(path.join(directory.path, 'detail.json'));
      await meta.writeAsString(jsonEncode({'videoCode': detail.id, 'title': detail.title, 'coverUrl': detail.coverUrl, 'artistName': detail.artist, 'genre': detail.genre, 'viewsText': detail.views, 'uploadDate': detail.uploadDate, 'introduction': detail.description, 'tags': detail.tags.map((tag) => tag.name).toList(), 'sourceQuality': source.quality, 'sourceUrl': source.url}));
      await _replace(task.id, (value) => value.copyWith(status: DownloadStatus.downloading));
      final localCoverPath = await _downloadCover(detail.coverUrl, directory);
      if (localCoverPath != null) await _replace(task.id, (value) => value.copyWith(localCoverPath: localCoverPath));
      final quality = source.quality.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_');
      final video = File(path.join(directory.path, 'video_$quality.mp4'));
      await _downloadVideo(source.url, video, task.id);
      // 下载途中被暂停：`.part` 已经写好了，别再往下标记成完成。
      if (_paused.contains(task.id)) return;
      await _replace(task.id, (value) => value.copyWith(status: DownloadStatus.completed, progress: 1, localVideoPath: video.path, localMetaPath: meta.path, clearError: true));
    } catch (error) {
      if (_paused.contains(task.id)) return;
      await _replace(task.id, (value) => value.copyWith(status: DownloadStatus.failed, errorMessage: '$error'));
    } finally {
      _jobs.remove(task.id);
    }
  }

  Future<void> _downloadVideo(String url, File destination, String taskId) async {
    final partial = File('${destination.path}.part');
    final received = await partial.exists() ? await partial.length() : 0;
    final response = await Dio().get<ResponseBody>(url, options: Options(responseType: ResponseType.stream, headers: received > 0 ? {'Range': 'bytes=$received-'} : null));
    final rangeAccepted = response.statusCode == 206;
    if (!rangeAccepted && received > 0) {
      await partial.delete();
      return _downloadVideo(url, destination, taskId);
    }
    final total = (response.data?.contentLength ?? -1) < 0 ? -1 : (rangeAccepted ? received : 0) + response.data!.contentLength;
    var downloaded = received;
    var windowStart = DateTime.now();
    var windowBytes = 0;
    var speedStart = DateTime.now();
    var speedBytes = 0;
    var speed = 0;
    final sink = partial.openWrite(mode: received > 0 && rangeAccepted ? FileMode.append : FileMode.write);
    try {
      await for (final chunk in response.data!.stream) {
        // 每收到一个分片都检查一次暂停：这样点「暂停」后最多再多写一个分片就停住，
        // 已下载的部分留在 `.part` 里等着续传。
        if (_paused.contains(taskId)) break;
        sink.add(chunk);
        downloaded += chunk.length;
        windowBytes += chunk.length;
        speedBytes += chunk.length;
        final elapsed = DateTime.now().difference(speedStart);
        if (elapsed >= const Duration(milliseconds: 800)) {
          speed = (speedBytes / elapsed.inMilliseconds * 1000).round();
          speedStart = DateTime.now();
          speedBytes = 0;
        }
        await _replace(taskId, (value) => value.copyWith(progress: total <= 0 ? 0 : downloaded / total, downloadedBytes: downloaded, totalBytes: total, speedBytesPerSecond: speed));
        final limit = ref.read(settingsProvider).value?.downloadSpeedLimitMbps ?? 0;
        if (limit > 0) {
          final elapsed = DateTime.now().difference(windowStart);
          final target = Duration(microseconds: (windowBytes * Duration.microsecondsPerSecond / (limit * 1024 * 1024)).round());
          if (target > elapsed) await Future<void>.delayed(target - elapsed);
          if (DateTime.now().difference(windowStart) >= const Duration(seconds: 1)) {
            windowStart = DateTime.now();
            windowBytes = 0;
          }
        }
      }
    } finally {
      await sink.close();
    }
    // 暂停时保留 `.part`，留给下次续传；只有真正下完才改名成正式文件。
    if (_paused.contains(taskId)) return;
    if (await destination.exists()) await destination.delete();
    await partial.rename(destination.path);
  }

  Future<String?> _downloadCover(String? url, Directory directory) async {
    if (url == null || url.isEmpty) return null;
    final cover = File(path.join(directory.path, 'cover.jpg'));
    try {
      await Dio().download(url, cover.path);
      return cover.path;
    } catch (_) {
      return null;
    }
  }
}
