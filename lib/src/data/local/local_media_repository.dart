import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:watcher/watcher.dart';

import '../../core/local_media_scanner.dart';
import '../../features/settings/settings_controller.dart';
import 'json_store.dart';

/// 本地媒体库索引：存 JSON（与仓库其它本地数据一致），并监听目录变化自动更新。
///
/// 不做全量重扫——监听只处理「新增 / 删除 / 改名」，已有条目的元数据
/// （大小、修改时间）在这些事件里顺带刷新，省掉一次几千个文件的 stat。
class LocalMediaRepository {
  LocalMediaRepository(this._store, this._scanner);

  final JsonStore _store;
  final LocalMediaScanner _scanner;
  static const _fileName = 'local_media.json';

  StreamSubscription<WatchEvent>? _watch;
  String? _watchedDirectory;

  Future<List<LocalMediaEntry>> load() async {
    final raw = await _store.read(_fileName);
    final list = (raw['entries'] as List?) ?? const [];
    return list.whereType<Map>().map((item) => LocalMediaEntry.fromJson(Map<String, dynamic>.from(item))).toList();
  }

  Future<void> _save(List<LocalMediaEntry> entries) => _store.write(_fileName, {'entries': entries.map((entry) => entry.toJson()).toList()});

  /// 全量重扫并写回索引，返回新索引。
  Future<List<LocalMediaEntry>> rescan(String directory) async {
    final entries = await _scanner.scan(directory);
    await _save(entries);
    return entries;
  }

  /// 按当前设置开启目录监听；目录为空或没变则不重复订阅。
  Future<void> watchDirectory(String directory) async {
    if (directory.isEmpty) {
      await stopWatching();
      return;
    }
    if (_watchedDirectory == directory && _watch != null) return;
    await stopWatching();
    try {
      final watcher = DirectoryWatcher(directory);
      _watchedDirectory = directory;
      _watch = watcher.events.listen((event) => _handleEvent(event));
    } catch (error) {
      debugPrint('[local-media] watch failed: $error');
    }
  }

  Future<void> stopWatching() async {
    await _watch?.cancel();
    _watch = null;
    _watchedDirectory = null;
  }

  Future<void> _handleEvent(WatchEvent event) async {
    final path = event.path;
    if (!LocalMediaScanner.videoExtensions.contains(_extensionOf(path))) return;
    final current = await load();
    if (event.type == ChangeType.REMOVE) {
      await _save(current.where((entry) => entry.path != path).toList());
      return;
    }
    // ADD / MODIFY：文件可能还在写入，读不到就跳过这次事件。
    final file = File(path);
    if (!await file.exists()) return;
    final stat = await file.stat();
    final entry = LocalMediaEntry(id: path, path: path, title: LocalMediaScanner.titleFromPath(path), fileSize: stat.size, modifiedAt: stat.modified);
    final next = [...current.where((item) => item.path != path), entry];
    await _save(next);
  }

  static String _extensionOf(String path) {
    final name = path.split(RegExp(r'[\\/]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? '' : name.substring(dot + 1).toLowerCase();
  }
}

final localMediaRepositoryProvider = Provider((ref) => LocalMediaRepository(JsonStore(), LocalMediaScanner()));

/// 当前本地媒体目录（取自设置）下的索引；切换目录或手动刷新时重建。
final localMediaProvider = FutureProvider<List<LocalMediaEntry>>((ref) async {
  final settings = await ref.watch(settingsProvider.future);
  final directory = settings.localMediaDirectory;
  if (directory.isEmpty) return const [];
  return ref.read(localMediaRepositoryProvider).load();
});
