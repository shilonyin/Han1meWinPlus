import 'dart:convert';

import '../../domain/models/video.dart';
import '../../domain/models/comic.dart';
import 'preferences_store.dart';

class HomeCache {
  static const _prefix = 'home_feed_v2:';
  final _preferences = PreferencesStore.instance;

  Future<HomeFeed?> read(String baseUrl, String? accountId) async {
    final value = await _preferences.getString(_key(baseUrl, accountId));
    if (value == null) return null;
    try {
      return HomeFeed.fromJson(Map<String, dynamic>.from(jsonDecode(value) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(String baseUrl, String? accountId, HomeFeed feed) => _write(_key(baseUrl, accountId), feed.toJson());

  String _key(String baseUrl, String? accountId) => '$_prefix$baseUrl:${accountId ?? 'anonymous'}';

  Future<ComicHome?> readComics() async {
    final value = await _preferences.getString('${_prefix}comics');
    if (value == null) return null;
    try {
      return ComicHome.fromJson(Map<String, dynamic>.from(jsonDecode(value) as Map));
    } catch (_) {
      return null;
    }
  }

  Future<void> writeComics(ComicHome feed) => _write('${_prefix}comics', feed.toJson());

  /// 缓存写盘失败不算错误。
  ///
  /// 首屏缓存只是「下次启动先拿旧内容顶一下」，写不进去最坏的后果是下次多打一次站点；
  /// 而刷新路径是 `unawaited(refresh())` 发出去的，异常一旦抛出去就没人接、直接冒到
  /// 界面变成一条红色错误条（Win 上 `preferences.json` 被瞬时占用就会这样）。
  /// 所以这里就地兜住，让调用方永远拿到一个成功的 future。
  Future<void> _write(String key, Map<String, dynamic> json) async {
    try {
      await _preferences.setString(key, jsonEncode(json));
    } catch (_) {
      // 缓存没写进去就算了，数据本身已经返回给界面。
    }
  }
}
