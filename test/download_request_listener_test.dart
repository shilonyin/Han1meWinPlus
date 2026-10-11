// 主窗口侧的信箱监听：把播放窗口投进来的意图真正执行掉。
//
// 对应反馈：在独立播放窗口里点「下载」→ 内容应该出现在**软件本体**（主窗口）的
// 缓存页里，而不是只在播放窗口内部那一页。播放窗口只写一封意图信（见
// download_requests_test.dart），执行在这里。
//
// 这里用真实的 DownloadController 替身观察「任务被建出来了」这一件事，不去碰网络：
// 意图里的集走 repository 取详情，所以替身里直接给一份带片源的 VideoDetail。
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/han1me_repository.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart';
import 'package:han1me_win_plus/src/data/local/download_requests.dart';
import 'package:han1me_win_plus/src/domain/models/download.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/cache/download_request_listener.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';

/// 记录建出来的任务，别的什么都不做（不建目录、不下载、不写盘）。
class _RecordingDownloads extends DownloadController {
  _RecordingDownloads();

  final List<DownloadTask> created = [];
  final List<({Iterable<String> codes, String groupId})> adopted = [];

  @override
  Future<DownloadState> build() async => const DownloadState();

  @override
  Future<void> create(VideoDetail detail, VideoSource source, String groupId) async {
    created.add(
      DownloadTask(
        id: detail.id,
        videoCode: detail.id,
        title: detail.title,
        groupIds: groupId == 'default' ? const {} : {groupId},
        quality: source.quality,
        status: DownloadStatus.queued,
        progress: 0,
        downloadedBytes: 0,
        totalBytes: 0,
        createdAt: 0,
        updatedAt: 0,
      ),
    );
  }

  @override
  Future<String> resolveAutoGroup(String name, DownloadGroupSort sort) async =>
      name.isEmpty ? 'default' : 'group:$name';

  @override
  Future<int> adoptSeriesTasks(Iterable<String> videoCodes, String groupId) async {
    adopted.add((codes: videoCodes, groupId: groupId));
    return 0;
  }
}

VideoDetail _detail(String id) => VideoDetail(
      id: id,
      title: '作品 $id',
      coverUrl: '',
      // HLS 清单不能下载，这里给一个渐进式 mp4，和真实片源形态一致。
      sources: [VideoSource(quality: '480', url: 'https://example.com/$id.mp4')],
      tags: const [],
      playlist: const [],
      related: const [],
    );

class _StubRepository implements Han1meRepository {
  final List<String> fetched = [];

  @override
  Future<VideoDetail> video(String baseUrl, String id) async {
    fetched.add(id);
    return _detail(id);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _StubSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings();
}

/// 记录跳转的探针。`/downloads` 是挂在**根导航器**上的页面（与生产的
/// `app_router.dart` 同构），所以能验出监听器推的到底是哪条路由、带没带
/// `tab=active` —— 只把 `/cache` 摆成顶层路由的话，这个 bug 会被测试掩盖。
class _Probe {
  final List<String> pushed = [];
}

Widget _app(_Probe probe, _RecordingDownloads downloads, _StubRepository repository) {
  final navigatorKey = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: [
      settingsProvider.overrideWith(_StubSettings.new),
      downloadProvider.overrideWith(() => downloads),
      han1meRepositoryProvider.overrideWithValue(repository),
    ],
    child: MaterialApp.router(
      routerConfig: GoRouter(
        navigatorKey: navigatorKey,
        initialLocation: '/',
        routes: [
          GoRoute(path: '/', builder: (context, state) => const Scaffold(body: Text('home'))),
          // 生产的 `/cache` 是 StatefulShellBranch 下的分支路由，这里用一个等价
          // 的独立顶层路由占位：验的是「返回语义」而不是 shell 本身。
          GoRoute(
            path: '/cache',
            builder: (context, state) {
              probe.pushed.add(state.uri.toString());
              return const Scaffold(body: Text('cache'));
            },
          ),
          // 与生产同构：监听器应该推这条（挂根导航器 + tab=active），不是 `/cache`。
          GoRoute(
            path: '/downloads',
            builder: (context, state) {
              probe.pushed.add(state.uri.toString());
              return const Scaffold(body: Text('downloads'));
            },
          ),
        ],
      ),
      builder: (context, child) => DownloadRequestListener(
        navigatorKey: navigatorKey,
        child: child ?? const SizedBox.shrink(),
      ),
    ),
  );
}

/// 在 fake-async 测试区里跑真实文件 IO。
///
/// `testWidgets` 的默认区由 fake-async 接管，`dart:io` 的 Future 在那里**永远不会
/// 完成**（文件 IO 靠真实事件循环回调），直接 await 会把测试挂死到超时。所有
/// `postDownloadRequest` / 目录创建删除都必须包在 `runAsync` 里。
Future<T> _io<T>(WidgetTester tester, Future<T> Function() body) =>
    tester.runAsync(body).then((value) => value as T);

/// 等某个条件成立，期间既推进假时钟（让 `Timer.periodic` 触发）也让真实 IO 前进。
///
/// 不能用 `pumpAndSettle`：监听器靠 `Timer.periodic` 轮询，周期性定时器会让
/// `pumpAndSettle` 永远等不到静止而超时。
///
/// 也不能只给固定时间：`_drain` 里的真实文件 IO 与建任务都是跨事件循环的，
/// 快慢取决于机器。所以循环「推进一档 → 让真实 IO 跑一小会 → 检查条件」，
/// 而不是猜一个总时长。
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int rounds = 40,
}) async {
  for (var i = 0; i < rounds; i++) {
    await tester.pump(const Duration(seconds: 2));
    // 让 _drain 里那些 await（读信箱、建任务、跳转）走完。
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    if (done()) return;
  }
}

void main() {
  late Directory dir;

  setUp(() async {
    // 这两个 setUp/tearDown 跑在 fake-async 区之外（普通异步回调），真实 IO 可用，
    // 所以不用包 runAsync —— 真正要包的是测试体里的 IO。
    dir = await Directory.systemTemp.createTemp('download_listener_test_');
    downloadRequestDirectoryOverride = dir;
  });

  tearDown(() async {
    downloadRequestDirectoryOverride = null;
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  testWidgets('播放窗口投来的下载意图 → 主窗口建任务并切到「正在缓存」', (tester) async {
    final downloads = _RecordingDownloads();
    final repository = _StubRepository();
    final probe = _Probe();

    await tester.pumpWidget(_app(probe, downloads, repository));
    await tester.pumpAndSettle();

    await _io(
      tester,
      () => postDownloadRequest(
        DownloadRequest(
          kind: DownloadRequestKind.download,
          episodes: const [
            VideoCard(id: '101', title: '第一集', coverUrl: ''),
            VideoCard(id: '102', title: '第二集', coverUrl: ''),
          ],
          quality: '480',
          groupName: '某系列',
          seriesIds: const ['101', '102', '103'],
        ),
      ),
    );
    await _pumpUntil(tester, () => probe.pushed.isNotEmpty);

    expect(
      downloads.created.map((task) => task.videoCode),
      ['101', '102'],
      reason: '勾选的两集都要在主窗口建出任务',
    );
    expect(downloads.created.first.quality, '480');
    expect(downloads.created.first.groupIds, {'group:某系列'});
    // 同系列的旧任务一并归组（把整个 playlist 的 id 都带上）。
    expect(downloads.adopted.first.codes, containsAll(['101', '102', '103']));
    // 必须落在「正在缓存」页签：用户点完下载要看的是刚加进队列的那条。
    expect(probe.pushed, ['/downloads?tab=active'], reason: '建完任务要把用户送到缓存页的「正在缓存」');
  });

  testWidgets('「我的下载」意图 → 不建任务，只切到「正在缓存」', (tester) async {
    final downloads = _RecordingDownloads();
    final repository = _StubRepository();
    final probe = _Probe();

    await tester.pumpWidget(_app(probe, downloads, repository));
    await tester.pumpAndSettle();

    await _io(
      tester,
      () => postDownloadRequest(
        const DownloadRequest(kind: DownloadRequestKind.openDownloads),
      ),
    );
    await _pumpUntil(tester, () => probe.pushed.isNotEmpty);

    expect(downloads.created, isEmpty);
    expect(repository.fetched, isEmpty, reason: '不该为了跳转去请求详情页');
    expect(probe.pushed, ['/downloads?tab=active']);
  });

  testWidgets('已经在缓存页时不再往栈上叠一层', (tester) async {
    final downloads = _RecordingDownloads();
    final repository = _StubRepository();
    final probe = _Probe();

    await tester.pumpWidget(_app(probe, downloads, repository));
    await tester.pumpAndSettle();

    // 先手动进缓存页（模拟用户自己已经打开着缓存页）。
    final context = tester.element(find.text('home'));
    GoRouter.of(context).push('/cache');
    await tester.pumpAndSettle();
    expect(probe.pushed, ['/cache']);

    await _io(
      tester,
      () => postDownloadRequest(
        const DownloadRequest(kind: DownloadRequestKind.openDownloads),
      ),
    );
    // 这里没有"跳转成功"可等，只能给足一轮让监听器把信取走并做出判断。
    await _pumpUntil(tester, () => false, rounds: 10);

    expect(probe.pushed, ['/cache'], reason: '已经在缓存页，不该再 push 一次');
  });

  testWidgets('信箱里没有意图时什么都不发生', (tester) async {
    final downloads = _RecordingDownloads();
    final repository = _StubRepository();
    final probe = _Probe();

    await tester.pumpWidget(_app(probe, downloads, repository));
    // 信箱本来就是空的，没有可等的条件；给几轮让轮询跑过即可，断言的是"什么都没发生"。
    await _pumpUntil(tester, () => false, rounds: 6);

    expect(downloads.created, isEmpty);
    expect(probe.pushed, isEmpty);
  });
}
