import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/json_store.dart';
import 'package:han1me_win_plus/src/data/local/preferences_store.dart';

/// 内存版存储，避免测试写真实的应用数据目录。
class _MemoryStore extends JsonStore {
  final Map<String, Map<String, dynamic>> files = {};

  @override
  Future<Map<String, dynamic>> read(String fileName) async => files[fileName] ?? {};

  @override
  Future<void> write(String fileName, Map<String, dynamic> value) async => files[fileName] = value;
}

Future<File> _legacyFile(Map<String, dynamic> content, {required String tag}) async {
  final file = File('${Directory.systemTemp.path}/han1me_prefs_${tag}_${DateTime.now().microsecondsSinceEpoch}.json');
  await file.writeAsString(jsonEncode(content));
  addTearDown(() {
    if (file.existsSync()) file.deleteSync();
  });
  return file;
}

void main() {
  test('键值读写与删除都会落到 preferences.json', () async {
    final store = _MemoryStore();
    final preferences = PreferencesStore(store: store, legacyFile: () async => null);

    await preferences.setString('accounts_v2:hanime1.com', '[{"id":"1"}]');
    expect(await preferences.getString('accounts_v2:hanime1.com'), '[{"id":"1"}]');
    expect(await preferences.getKeys(), {'accounts_v2:hanime1.com'});

    // 落到同一个文件后，新实例（重启场景）仍能读到。
    final reopened = PreferencesStore(store: store, legacyFile: () async => null);
    expect(await reopened.getString('accounts_v2:hanime1.com'), '[{"id":"1"}]');

    await reopened.remove('accounts_v2:hanime1.com');
    expect(await reopened.getKeys(), isEmpty);
    expect(await PreferencesStore(store: store, legacyFile: () async => null).getKeys(), isEmpty);
  });

  test('首次启动会把老目录的 shared_preferences.json 搬过来', () async {
    final legacy = await _legacyFile(
      {
        'accounts_v2:hanime1.com': 'legacy-accounts',
        'flutter.old_sync_key': 'legacy-value',
        'not_a_string': 3,
      },
      tag: 'import',
    );

    final store = _MemoryStore();
    final preferences = PreferencesStore(store: store, legacyFile: () async => legacy);

    expect(await preferences.getString('accounts_v2:hanime1.com'), 'legacy-accounts');
    // 老同步 API 的 `flutter.` 前缀要去掉，非字符串值直接跳过。
    expect(await preferences.getString('old_sync_key'), 'legacy-value');
    expect(await preferences.getKeys(), {'accounts_v2:hanime1.com', 'old_sync_key'});
    // 导入结果要立刻落盘，否则下次启动又会去读老文件。
    expect(store.files['preferences.json']?['accounts_v2:hanime1.com'], 'legacy-accounts');
  });

  test('写盘是整份快照，因此同一实例下连续修改不会互相丢键', () async {
    final store = _MemoryStore();
    final preferences = PreferencesStore(store: store, legacyFile: () async => null);

    await preferences.setString('home_feed_v2:comics', 'feed');
    await preferences.setString('accounts_v2:hanime1.com', 'accounts');
    await preferences.setString('http_cache_v1:abc', 'cached');
    await preferences.remove('http_cache_v1:abc');

    expect(store.files['preferences.json'], {
      'home_feed_v2:comics': 'feed',
      'accounts_v2:hanime1.com': 'accounts',
    });
  });

  test('已有 preferences.json 时不会被老文件覆盖', () async {
    final legacy = await _legacyFile({'accounts_v2:hanime1.com': 'legacy-accounts'}, tag: 'stale');
    final store = _MemoryStore()..files['preferences.json'] = {'accounts_v2:hanime1.com': 'current-accounts'};

    final preferences = PreferencesStore(store: store, legacyFile: () async => legacy);

    expect(await preferences.getString('accounts_v2:hanime1.com'), 'current-accounts');
  });
}
