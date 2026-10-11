import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/platform_paths.dart';
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

  group('JsonStore', () {
    test('写盘不会留下半截文件：目标文件在写完前后都能被解析', () async {
      final store = JsonStore();
      await store.write('cache.json', {'a': '1'});
      // 写完就是完整 JSON，读回来一致。
      expect(await store.read('cache.json'), {'a': '1'});

      await store.write('cache.json', {'a': '2', 'b': '3'});
      expect(await store.read('cache.json'), {'a': '2', 'b': '3'});
    });

    test('原子写盘的临时文件用完就清掉，不留在数据目录里', () async {
      // 数据目录在 Windows 上是 `%APPDATA%\han1me_win_plus`，临时文件名是
      // `<名字>.tmp` —— 直接看目录里有没有残留。
      final directory = await appStorageDirectory();
      final name = 'atomic_probe_${DateTime.now().microsecondsSinceEpoch}.json';
      addTearDown(() {
        for (final file in [File('${directory.path}/$name'), File('${directory.path}/$name.tmp')]) {
          if (file.existsSync()) file.deleteSync();
        }
      });

      await JsonStore().write(name, {'ok': true});

      expect(File('${directory.path}/$name').existsSync(), isTrue);
      expect(File('${directory.path}/$name.tmp').existsSync(), isFalse);
    });

    test('磁盘上没有文件时读回空表（不抛异常）', () async {
      expect(await JsonStore().read('missing_probe.json'), isEmpty);
    });

    // 回归：同一文件被并发写时，两个 rename 会抢同一个目标路径，Windows 回
    // `errno 5 拒绝访问`。实测 AddressRanker 多主机探测同时结束就会踩到，
    // 表现是启动时刷一屏 PathAccessException。修复方式是按文件名串行化。
    test('同一文件并发写：全部成功，且最终内容是最后一次写入的', () async {
      final store = JsonStore();
      final name = 'concurrent_probe_${DateTime.now().microsecondsSinceEpoch}.json';
      addTearDown(() async {
        final directory = await appStorageDirectory();
        for (final entry in await directory.list().toList()) {
          if (entry.path.contains(name)) await entry.delete();
        }
      });

      // 20 个并发写：修复前后者的 rename 会撞上前者。
      final writes = [for (var index = 0; index < 20; index++) store.write(name, {'n': index})];
      await Future.wait(writes);

      // 没有异常抛出即达标；内容应为其中一个完整的快照（不是半截 JSON）。
      final read = await store.read(name);
      expect(read['n'], isA<int>());
      expect(read['n'], inInclusiveRange(0, 19));
    });

    test('并发写之后不残留临时文件', () async {
      final store = JsonStore();
      final name = 'concurrent_tmp_probe_${DateTime.now().microsecondsSinceEpoch}.json';
      final directory = await appStorageDirectory();
      await Future.wait([for (var index = 0; index < 10; index++) store.write(name, {'n': index})]);

      final leftovers = (await directory.list().toList()).where((entry) => entry.path.contains(name) && entry.path.endsWith('.tmp')).toList();
      expect(leftovers, isEmpty);
      for (final entry in (await directory.list().toList()).where((entry) => entry.path.contains(name))) {
        await entry.delete();
      }
    });
  });
}
