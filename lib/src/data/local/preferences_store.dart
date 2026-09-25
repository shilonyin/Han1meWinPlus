import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'json_store.dart';

/// 应用自己的键值存储，取代 `SharedPreferencesAsync`。
///
/// 为什么不用 `shared_preferences`：Windows 上它通过 `path_provider` 决定落盘目录，而那条
/// 路径是由 exe 的 VERSIONINFO（`CompanyName\ProductName`）拼出来的 —— 1.1.11 第一次给
/// `Runner.rc` 加版本资源时，目录就从 `%APPDATA%\han1me_win_plus` 变成了
/// `%APPDATA%\Han1meWinPlus\Han1meWinPlus`，账号、首屏缓存与 CF cookie 一并「看起来被重置」。
/// 本应用其余数据都由 `platform_paths.dart` 钉在固定目录，这里也一样，并在首次启动时把
/// 老目录里的 [`_legacyFileName`] 一次性搬过来。
///
/// 键值语义与 `SharedPreferencesAsync` 保持一致（`getString` / `setString` / `remove` /
/// `getKeys`），调用方只需换掉字段类型。
class PreferencesStore {
  PreferencesStore({JsonStore? store, Future<File?> Function()? legacyFile})
      : _store = store ?? JsonStore(),
        _legacyFile = legacyFile ?? _systemLegacyFile;

  /// **全局共享实例**：账号、首屏缓存、HTTP 缓存三处使用方必须共用同一份内存镜像。
  ///
  /// 写盘是「写出整份快照」，若各自持有一份实例，后写的那份会把自己启动时读到的旧快照
  /// 盖回去 —— 实测表现为账号刷新刚写入的统计数据被随后的首屏缓存写盘抹掉（文件里始终是
  /// 刷新前的旧值）。
  static final PreferencesStore instance = PreferencesStore();

  static const _fileName = 'preferences.json';

  /// 旧的 `shared_preferences` 在 path_provider 目录下的文件名。
  static const _legacyFileName = 'shared_preferences.json';

  /// `shared_preferences`（走 path_provider）历史上写过的目录（相对 `%APPDATA%`）：
  /// 1. `han1me_win_plus\` —— 1.1.11 之前（exe 还没有版本资源，插件回退到 exe 名）；
  /// 2. `Han1meWinPlus\Han1meWinPlus\` —— 加了 `VERSIONINFO` 之后（`CompanyName\ProductName`）。
  static const _legacyFolders = ['han1me_win_plus', r'Han1meWinPlus\Han1meWinPlus'];

  final JsonStore _store;
  final Future<File?> Function() _legacyFile;

  Map<String, String>? _values;
  Future<void>? _loading;
  Future<void> _writes = Future<void>.value();

  Future<String?> getString(String key) async => (await _load())[key];

  Future<Set<String>> getKeys() async => (await _load()).keys.toSet();

  Future<void> setString(String key, String value) async {
    (await _load())[key] = value;
    await _flush();
  }

  Future<void> remove(String key) async {
    (await _load()).remove(key);
    await _flush();
  }

  Future<Map<String, String>> _load() async {
    final values = _values;
    if (values != null) return values;
    // 并发调用只读一次盘。_read 里 await 的是同一份 future，不会重复导入。
    await (_loading ??= _read());
    return _values!;
  }

  Future<void> _read() async {
    final stored = await _store.read(_fileName);
    final values = <String, String>{
      for (final entry in stored.entries)
        if (entry.value is String) entry.key: entry.value as String,
    };
    if (values.isEmpty) {
      final imported = await _readLegacy();
      if (imported.isNotEmpty) {
        values.addAll(imported);
        _values = values;
        await _flush();
        return;
      }
    }
    _values = values;
  }

  /// 把老目录（path_provider）里的 `shared_preferences.json` 搬过来。
  /// 迁移只在目标为空时发生一次，之后老文件即使还在也不会再被读。
  Future<Map<String, String>> _readLegacy() async {
    try {
      final file = await _legacyFile();
      if (file == null || !await file.exists()) return const {};
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return const {};
      return <String, String>{
        for (final entry in decoded.entries)
          if (entry.value is String) _normalizeKey(entry.key.toString()): entry.value as String,
      };
    } catch (_) {
      // 老文件读不出来就当没有：新装用户本来就没有它。
      return const {};
    }
  }

  /// 老版本（同步 API）会把键写成 `flutter.xxx`，异步 API 则是裸键。
  static String _normalizeKey(String key) => key.startsWith('flutter.') ? key.substring('flutter.'.length) : key;

  /// 串行写盘：把这次修改的快照挂在上一次写之后，避免并发写互相覆盖。
  Future<void> _flush() {
    final snapshot = Map<String, String>.from(_values ?? const {});
    final next = _writes.then((_) => _store.write(_fileName, snapshot));
    _writes = next.catchError((_) {});
    return next;
  }

  /// 取**修改时间最新**的那份老文件。
  ///
  /// 两个历史目录可能同时存在（本机就是：`han1me_win_plus\` 里还留着 9 月 13 日的
  /// 旧副本），按固定顺序取会把陈旧数据当成最新导入，反而把当前登录态换掉。
  static Future<File?> _systemLegacyFile() async {
    if (!Platform.isWindows) return null;
    final appData = Platform.environment['APPDATA'];
    if (appData == null || appData.isEmpty) return null;
    final candidates = <File>[
      for (final folder in _legacyFolders) File(path.join(appData, folder, _legacyFileName)),
      ...await _pathProviderCandidate(),
    ];
    final existing = candidates.where((file) => file.existsSync()).toList(growable: false);
    if (existing.isEmpty) return null;
    final dated = [for (final file in existing) (file, _modified(file))];
    dated.sort((a, b) => b.$2.compareTo(a.$2));
    return dated.first.$1;
  }

  static DateTime _modified(File file) {
    try {
      return file.statSync().modified;
    } catch (_) {
      return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  /// path_provider 能解析出来时也当作候选（它的目录由 `VERSIONINFO` 决定）。
  static Future<List<File>> _pathProviderCandidate() async {
    try {
      final directory = await getApplicationSupportDirectory();
      return [File(path.join(directory.path, _legacyFileName))];
    } catch (_) {
      return const [];
    }
  }
}
