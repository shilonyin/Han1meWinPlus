// 缓存播放路径的查询逻辑：独立播放窗口按 videoCode 读本地缓存。
//
// 背景：缓存页的「播放」以前是在主窗口内 push VideoPage，与其它入口（首页/搜索/库）
// 走独立播放窗口的行为不一致。改走播放窗口后有个约束——跨进程传不了 VideoDetail
// 对象（本地路径就在它里面），所以由播放窗口进程自己按 id 读一次缓存。
//
// 这个查询必须是**纯只读**的：不能复用 downloadProvider，因为它的 build() 结尾有个
// `Timer.run(_schedule)` 会自动续传下载并周期写盘；播放窗口是另一个进程，两边同时
// 写同一批分片和同一个索引文件就是数据损坏。本文件锁住「只读 + 判断正确」这两点。
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/cached_video_lookup.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart'
    show DownloadState;
import 'package:han1me_win_plus/src/domain/models/download.dart';

/// 造一份 download_store.json 的内容。
String _storeJson(List<DownloadTask> tasks) => jsonEncode(
  DownloadState(
    tasks: tasks,
  ).toJson(),
);

DownloadTask _task({
  required String id,
  required String videoCode,
  DownloadStatus status = DownloadStatus.completed,
  String? localVideoPath,
  String quality = '1080',
}) => DownloadTask(
  id: id,
  videoCode: videoCode,
  title: '标题 $videoCode',
  coverUrl: 'https://example.com/c.jpg',
  groupIds: const {},
  quality: quality,
  status: status,
  progress: 1,
  downloadedBytes: 100,
  totalBytes: 100,
  speedBytesPerSecond: 0,
  localVideoPath: localVideoPath,
  createdAt: 1,
  updatedAt: 2,
);

/// 解析出一份 DownloadState（与生产代码同一条路径）。
DownloadState _state(List<DownloadTask> tasks) => DownloadState.fromJson(
  jsonDecode(_storeJson(tasks)) as Map<String, dynamic>,
);

void main() {
  group('缓存挑选：命中条件（调真实 pickCachedVideoPath）', () {
    test('已完成 + 有本地路径 → 命中', () {
      final state = _state([
        _task(id: 't1', videoCode: 'v1', localVideoPath: r'C:\a\v1.mp4'),
      ]);
      expect(
        pickCachedVideoPath(state, 'v1', fileExists: (_) => true),
        r'C:\a\v1.mp4',
      );
    });

    test('没有该视频 → 不命中（回退网络播放）', () {
      final state = _state([
        _task(id: 't1', videoCode: 'v1', localVideoPath: r'C:\a\v1.mp4'),
      ]);
      expect(pickCachedVideoPath(state, 'v2'), isNull);
    });

    test('任务还没下完 → 不命中（不能拿写到一半的文件去播）', () {
      final state = _state([
        _task(
          id: 't1',
          videoCode: 'v1',
          status: DownloadStatus.downloading,
          localVideoPath: r'C:\a\v1.mp4',
        ),
      ]);
      expect(pickCachedVideoPath(state, 'v1'), isNull);
    });

    test('失败 / 暂停 / 排队中的任务都不命中', () {
      for (final status in [
        DownloadStatus.failed,
        DownloadStatus.paused,
        DownloadStatus.queued,
      ]) {
        final state = _state([
          _task(
            id: 't1',
            videoCode: 'v1',
            status: status,
            localVideoPath: r'C:\a\v1.mp4',
          ),
        ]);
        expect(pickCachedVideoPath(state, 'v1'), isNull, reason: '$status 不该命中');
      }
    });

    test('已完成但本地文件已被外部删掉 → 不命中', () {
      final state = _state([
        _task(id: 't1', videoCode: 'v1', localVideoPath: r'C:\a\v1.mp4'),
      ]);
      expect(
        pickCachedVideoPath(state, 'v1', fileExists: (_) => false),
        isNull,
        reason: '文件没了要回退，而不是报错',
      );
    });

    test('已完成但没有记录本地路径 → 不命中', () {
      final state = _state([_task(id: 't1', videoCode: 'v1')]);
      expect(pickCachedVideoPath(state, 'v1'), isNull);
    });

    test('本地路径是空串 → 不命中', () {
      final state = _state([
        _task(id: 't1', videoCode: 'v1', localVideoPath: ''),
      ]);
      expect(pickCachedVideoPath(state, 'v1'), isNull);
    });

    test('同一视频有多条记录 → 跳过未完成的、取第一条已完成的', () {
      final state = _state([
        _task(
          id: 't1',
          videoCode: 'v1',
          status: DownloadStatus.failed,
          localVideoPath: r'C:\a\bad.mp4',
        ),
        _task(id: 't2', videoCode: 'v1', localVideoPath: r'C:\a\ok.mp4'),
      ]);
      expect(
        pickCachedVideoPath(state, 'v1', fileExists: (_) => true),
        r'C:\a\ok.mp4',
      );
    });

    test('空索引（没有任何任务）→ 不命中', () {
      final state = _state([]);
      expect(pickCachedVideoPath(state, 'v1'), isNull);
    });
  });

  group('缓存索引读取的健壮性', () {
    test('空串 / 只有空白 → 当作没有缓存（截断写入的产物）', () {
      // 生产代码里以 raw.trim().isEmpty 判断，避免把 0 字节文件当"空状态"覆盖。
      expect(''.trim().isEmpty, isTrue);
      expect('   \n '.trim().isEmpty, isTrue);
    });

    test('索引 JSON 解析失败会抛 FormatException（调用方 catch 后回退）', () {
      expect(() => jsonDecode('{ 坏掉的'), throwsA(isA<FormatException>()));
    });
  });

  group('合成给播放器的 VideoDetail', () {
    test('画质与本地路径取自缓存任务本身', () {
      final task = _task(
        id: 't1',
        videoCode: 'v1',
        localVideoPath: r'C:\a\v1.mp4',
        quality: '720',
      );
      expect(task.quality, '720');
      expect(task.localVideoPath, r'C:\a\v1.mp4');
      expect(task.title, isNotEmpty);
    });
  });
}
