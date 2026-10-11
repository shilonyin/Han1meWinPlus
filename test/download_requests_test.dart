// 跨进程下载信箱：播放窗口投递意图，主窗口取走并执行。
//
// 守的是一个真实反馈：在独立播放窗口里点「下载」，内容没有出现在软件本体（主窗口）
// 的缓存页，而是在播放窗口自己的缓存页里；反过来点「我的下载」，跳转也发生在播放
// 窗口内部的那一页上。根因是播放窗口与主窗口是**两个进程**（见 play_window.dart 的
// --play-window），而下载调度器 DownloadController 只有一份内存状态、只写一份
// download_store.json —— 在播放窗口里就地建任务，等于把索引写进了没人看的那一份。
//
// 修法：播放窗口只把意图写进信箱（本文件测的就是这套约定），主窗口取走执行。所以这里
// 锁两件事：① 写进去能原样取出来（含勾选集与分组名）；② **取走即删除**，同一条意图
// 不会被处理两次、也不会在重启后又冒出来重下一遍。
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/download_requests.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';

VideoCard _episode(String id, {String? title}) =>
    VideoCard(id: id, title: title ?? '第 $id 集', coverUrl: 'https://example.com/$id.jpg');

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('download_requests_test_');
    downloadRequestDirectoryOverride = dir;
  });

  tearDown(() async {
    downloadRequestDirectoryOverride = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  test('下载意图往返：勾选的集、画质、分组名、系列 id 都原样带过去', () async {
    await postDownloadRequest(
      DownloadRequest(
        kind: DownloadRequestKind.download,
        episodes: [_episode('101'), _episode('102')],
        quality: '480',
        groupName: '某系列',
        seriesIds: ['101', '102', '103'],
        createdAt: 1700000000000,
      ),
    );

    final taken = await takeDownloadRequests();
    expect(taken, hasLength(1));
    final request = taken.single;
    expect(request.kind, DownloadRequestKind.download);
    expect(request.episodes.map((episode) => episode.id), ['101', '102']);
    expect(request.episodes.first.title, '第 101 集');
    expect(request.quality, '480');
    expect(request.groupName, '某系列');
    expect(request.seriesIds, ['101', '102', '103']);
  });

  test('「我的下载」不带勾选集，只表达跳转意图', () async {
    await postDownloadRequest(
      const DownloadRequest(kind: DownloadRequestKind.openDownloads),
    );

    final taken = await takeDownloadRequests();
    expect(taken.single.kind, DownloadRequestKind.openDownloads);
    expect(taken.single.episodes, isEmpty);
  });

  test('取走即删除：同一条意图不会被处理两次', () async {
    await postDownloadRequest(
      DownloadRequest(kind: DownloadRequestKind.download, episodes: [_episode('1')]),
    );

    expect(await takeDownloadRequests(), hasLength(1));
    expect(await takeDownloadRequests(), isEmpty, reason: '第二次取应该什么都没有');
  });

  test('多条意图按投递先后取回（用户点了两次不该乱序）', () async {
    for (final id in ['a', 'b', 'c']) {
      await postDownloadRequest(
        DownloadRequest(kind: DownloadRequestKind.download, episodes: [_episode(id)]),
      );
      // 文件名的时间戳精度是微秒，同一次循环里不会撞；这里仍留一点间隔让顺序确定。
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }

    final taken = await takeDownloadRequests();
    expect(
      taken.map((request) => request.episodes.single.id),
      ['a', 'b', 'c'],
    );
  });

  test('信箱目录不存在时返回空列表（首次启动、从没下载过）', () async {
    await dir.delete(recursive: true);
    expect(await takeDownloadRequests(), isEmpty);
  });

  test('坏掉的信被跳过并清掉，不会把整个信箱卡死', () async {
    await File('${dir.path}/0_broken.json').writeAsString('{ 不是合法 JSON');
    await postDownloadRequest(
      DownloadRequest(kind: DownloadRequestKind.download, episodes: [_episode('ok')]),
    );

    final taken = await takeDownloadRequests();
    expect(taken, hasLength(1), reason: '好的那条要照常取到');
    expect(taken.single.episodes.single.id, 'ok');
    // 坏文件也清掉了，否则它会一直被重读。
    expect(await File('${dir.path}/0_broken.json').exists(), isFalse);
  });

  test('写一半的 .tmp 文件不会被当成意图取走', () async {
    await File('${dir.path}/9999_1234.json.tmp').writeAsString('{"kind":"download"');
    expect(await takeDownloadRequests(), isEmpty);
  });
}
