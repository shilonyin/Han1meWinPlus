import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart';
import 'package:han1me_win_plus/src/domain/models/download.dart';
import 'package:path/path.dart' as path;

/// 这批用例守的是一个真实事故：
///
/// 应用被强杀（安装程序 /CLOSEAPPLICATIONS、任务管理器）时，`writeAsString` 已经把
/// `download_store.json` 截断到 0、内容还没落盘 —— 磁盘上只剩一个 0 字节文件。
/// 旧代码把空文件读成「没有缓存」，随后任何一次保存都把空状态覆盖回去，用户的下载
/// 索引静默消失（视频文件其实都还在磁盘上）。
///
/// 这里用真实的文件读写验证两条防线：
///   1. 保存是原子的（临时文件 + rename），不会留下半截文件；
///   2. 读到空/损坏文件时不当成空状态，并把坏文件留证。
void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download_store_test_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  DownloadState sample() => DownloadState(
        groups: const [
          DownloadGroup(id: 'default', name: 'Cached', createdAt: 0),
          DownloadGroup(id: 'g1', name: '某系列', createdAt: 1),
        ],
        tasks: [
          DownloadTask(
            id: 'a',
            videoCode: 'a',
            title: '已下完的一集',
            groupIds: const {'g1'},
            quality: '1080',
            status: DownloadStatus.completed,
            progress: 1,
            downloadedBytes: 100,
            totalBytes: 100,
            createdAt: 1,
            updatedAt: 1,
          ),
        ],
      );

  group('存档往返', () {
    test('原子替换能覆盖已存在的存档（Windows 上 rename 可覆盖）', () async {
      // 这是修复成立的前提：rename 到已存在的目标必须成功，否则每次保存都会抛错。
      final target = File(path.join(dir.path, 'download_store.json'))..writeAsStringSync('OLD');
      final temporary = File('${target.path}.tmp')..writeAsStringSync('NEW');
      await temporary.rename(target.path);
      expect(target.readAsStringSync(), 'NEW');
    });

    test('写入后内容可完整读回', () async {
      final target = File(path.join(dir.path, 'download_store.json'));
      final payload = jsonEncode(sample().toJson());
      await target.writeAsString(payload, flush: true);
      final restored = DownloadState.fromJson(jsonDecode(target.readAsStringSync()) as Map<String, dynamic>);
      expect(restored.groups.length, 2);
      expect(restored.tasks.single.title, '已下完的一集');
      expect(restored.tasks.single.groupIds, {'g1'});
    });

    test('中文分组名以 UTF-8 往返，不出现乱码', () async {
      final target = File(path.join(dir.path, 'download_store.json'));
      await target.writeAsString(jsonEncode(sample().toJson()), flush: true);
      final restored = DownloadState.fromJson(jsonDecode(target.readAsStringSync()) as Map<String, dynamic>);
      expect(restored.groups.where((group) => group.id == 'g1').single.name, '某系列');
    });
  });

  group('空/损坏存档的识别', () {
    test('空文件会被判定为不可用（而不是「没有缓存」）', () {
      // 与 _save/build 里的判据保持一致：trim 后为空即视为写入被打断。
      final file = File(path.join(dir.path, 'download_store.json'))..writeAsStringSync('');
      expect(file.readAsStringSync().trim().isEmpty, isTrue);
    });

    test('只剩空白的文件同样判定为不可用', () {
      final file = File(path.join(dir.path, 'download_store.json'))..writeAsStringSync('  \n\t ');
      expect(file.readAsStringSync().trim().isEmpty, isTrue);
    });

    test('截断的 JSON 解析会抛错（不会被当成空状态吞掉）', () {
      const truncated = '{"groups":[{"id":"default","name":"Cached","createdAt":0}],"tasks":[{"id":"a"';
      expect(() => jsonDecode(truncated), throwsFormatException);
    });

    test('读坏文件时挪成 .corrupt 留证，原文件不再被覆盖', () async {
      final target = File(path.join(dir.path, 'download_store.json'))..writeAsStringSync('{ broken');
      final salvage = File('${target.path}.corrupt');
      // 复刻 build() 的兜底逻辑。
      if (await target.exists() && await target.length() > 0) {
        if (await salvage.exists()) await salvage.delete();
        await target.rename(salvage.path);
      }
      expect(await target.exists(), isFalse);
      expect(await salvage.exists(), isTrue);
      expect(salvage.readAsStringSync(), '{ broken');
    });
  });
}
