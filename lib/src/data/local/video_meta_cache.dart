import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../domain/models/video.dart';
import 'json_store.dart';

/// 列表卡片元数据缓存。
///
/// 站点有些分类（里番、泡麵番）的列表页只给封面和标题，卡片会去视频详情页补一次
/// 时长/播放量/作者/评分/封面；补到的结果写进这里（内存 + 磁盘），之后刷新、滚动
/// 来回、重启应用都直接用缓存，不再重复请求。
class VideoMetaCache {
  VideoMetaCache(this._store) {
    unawaited(_load());
  }

  static const _fileName = 'video_meta.json';
  static const _limit = 800;

  final JsonStore _store;
  final _memory = <String, VideoCard>{};
  var _writing = false;
  var _pending = false;

  /// 同步读内存（命中时卡片可以立刻渲染补全后的内容，不会闪一下）。
  VideoCard? read(String id) => _memory[id];

  Future<void> put(VideoCard meta) async {
    _memory[meta.id] = meta;
    // 多张卡片几乎同时回来，合并成一次写盘；但仍然等它真的写完。
    if (_writing) {
      _pending = true;
      return;
    }
    _writing = true;
    try {
      do {
        _pending = false;
        await _store.write(_fileName, {for (final entry in _memory.entries) entry.key: entry.value.toJson()});
      } while (_pending);
    } catch (_) {
      // 写盘失败不影响卡片已经补全的内容
    } finally {
      _writing = false;
    }
  }

  Future<void> _load() async {
    final json = await _store.read(_fileName);
    for (final entry in json.entries) {
      final value = entry.value;
      if (value is Map) _memory[entry.key] = VideoCard.fromJson(Map<String, dynamic>.from(value));
    }
    if (_memory.length > _limit) {
      for (final key in _memory.keys.take(_memory.length - _limit).toList()) {
        _memory.remove(key);
      }
      await put(_memory.values.first);
    }
  }
}

final videoMetaCacheProvider = Provider((ref) => VideoMetaCache(JsonStore()));
