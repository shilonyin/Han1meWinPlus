// 验证播放窗口的落地组件 PlayWindowVideo：缓存查询完成前不建播放页。
//
// 本轮改动让缓存视频也走独立播放窗口（以前是在主窗口内 push VideoPage）。
// 跨进程传不了 VideoDetail 对象，所以由播放窗口进程自己按 id 读一次缓存。
//
// 核心风险：如果先按网络源建一个播放页、查完再换成缓存源，播放器会被建两次
// —— 那正是这轮一直在修的「加载出来又重来一遍」。这个文件直接测真实组件
// （PlayWindowVideo 就是生产代码里那条路由用的组件），锁住「结果未定时不建页面」。
//
// 页面构造用 playWindowPageBuilder 换成轻量替身：真实的 VideoPage 会拉起一串
// 网络 provider，测试拆解时会留下「provider 已销毁」的噪音，反而看不清时序。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/core/video_player_shutdown.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/video/play_window_app.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// 造一个能看出「拿到的是哪份 VideoDetail」的轻量页面。
Widget _stubPage({
  required String id,
  required VideoDetail? localVideo,
  VoidCallback? onBack,
  VoidCallback? onHome,
}) => Text(
  'page:$id:${localVideo == null ? 'network' : 'cached:${localVideo.sources.single.url}'}',
);

VideoDetail _cached({String quality = '1080'}) => VideoDetail(
  id: 'v1',
  title: '缓存标题',
  coverUrl: '',
  sources: [VideoSource(quality: quality, url: r'C:\a\v1.mp4')],
  tags: const [],
  playlist: const [],
  related: const [],
);

/// 建好的页面是一段 Text；用有没有 Text 判断「是否已建页」。
bool get _hasPage => find.byType(Text).evaluate().isNotEmpty;

void main() {
  setUp(() => playWindowPageBuilder = _stubPage);
  tearDown(() {
    cachedVideoLookup = (id) async => null;
  });

  testWidgets('查询未完成前不建播放页', (tester) async {
    final completer = Completer<VideoDetail?>();
    cachedVideoLookup = (_) => completer.future;

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();

    expect(_hasPage, isFalse, reason: '结果未定时不该建播放页');

    completer.complete(_cached());
    await tester.pump();
    await tester.pump();

    expect(_hasPage, isTrue);
    expect(find.text(r'page:v1:cached:C:\a\v1.mp4'), findsOneWidget);
  });

  testWidgets('命中缓存 → 建页面时带上本地 VideoDetail', (tester) async {
    cachedVideoLookup = (_) async => _cached();

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(find.text(r'page:v1:cached:C:\a\v1.mp4'), findsOneWidget);
  });

  testWidgets('没有缓存 → 建页面时 localVideo 为空（走网络）', (tester) async {
    cachedVideoLookup = (_) async => null;

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(find.text('page:v1:network'), findsOneWidget);
  });

  testWidgets('查询抛异常 → 回退网络播放，而不是卡在加载态', (tester) async {
    cachedVideoLookup = (_) async => throw StateError('boom');

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('page:v1:network'),
      findsOneWidget,
      reason: '读缓存失败也必须能打开视频',
    );
  });

  testWidgets('整段过程中只查询一次缓存', (tester) async {
    var lookups = 0;
    cachedVideoLookup = (_) async {
      lookups++;
      return _cached();
    };

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(lookups, 1, reason: '不该反复读盘');
  });

  // 播放窗口同时只允许一个：已有播放窗口时再点别的视频，runner 会把新 id
  // 经 `han1me/play-window` 通道转发进来（见 windows/runner/main.cpp），
  // 本窗口负责就地换片。这里模拟 runner 那次 native → Dart 调用。
  group('runner 转发的换片请求', () {
    /// 模拟 runner 侧 InvokeMethod("loadVideo", id)。
    Future<void> forward(WidgetTester tester, Object? arguments) async {
      final call = MethodCall('loadVideo', arguments);
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'han1me/play-window',
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
      await tester.pumpAndSettle();
    }

    Future<void> pumpPlayWindow(WidgetTester tester) async {
      cachedVideoLookup = (_) async => null;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _StubSettings(AppSettings())),
          ],
          child: const PlayWindowApp(videoId: 'v1'),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('收到新视频 id → 就地换片，不开新窗口', (tester) async {
      await pumpPlayWindow(tester);
      expect(find.text('page:v1:network'), findsOneWidget);

      await forward(tester, 'v2');

      expect(
        find.text('page:v2:network'),
        findsOneWidget,
        reason: '转发来的视频要在同一个窗口里播',
      );
      expect(find.text('page:v1:network'), findsNothing);
    });

    testWidgets('换片也要重新查一次本地缓存（缓存源不能丢）', (tester) async {
      var lookups = <String>[];
      cachedVideoLookup = (id) async {
        lookups.add(id);
        return id == 'v2' ? _cached() : null;
      };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            settingsProvider.overrideWith(() => _StubSettings(AppSettings())),
          ],
          child: const PlayWindowApp(videoId: 'v1'),
        ),
      );
      await tester.pumpAndSettle();

      await forward(tester, 'v2');

      expect(lookups, ['v1', 'v2']);
      expect(find.text(r'page:v2:cached:C:\a\v1.mp4'), findsOneWidget);
    });

    testWidgets('空 id / 非字符串参数 → 保持原视频不动', (tester) async {
      await pumpPlayWindow(tester);

      await forward(tester, '');
      await forward(tester, 42);

      expect(
        find.text('page:v1:network'),
        findsOneWidget,
        reason: '坏参数不该把正在播的视频换掉',
      );
    });

    testWidgets('未知方法 → 不换片也不抛异常', (tester) async {
      await pumpPlayWindow(tester);

      final call = MethodCall('somethingElse', 'v2');
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'han1me/play-window',
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
      await tester.pumpAndSettle();

      expect(find.text('page:v1:network'), findsOneWidget);
    });

    // 用户报的：「点新视频加载时，原视频没暂停、声音还在响」。
    //
    // 旧播放页要到这一帧之后才 dispose，而它 dispose 里的 pause 是
    // fire-and-forget、还排在「等初始化结束」后面，所以加载新视频这段时间旧视频
    // 一直在出声。修法是换片时先全局暂停（不等销毁链）。
    testWidgets('换片时先把正在播的旧视频暂停（不留声音）', (tester) async {
      final platform = _RecordingVideoPlatform();
      final previous = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = platform;
      addTearDown(() => VideoPlayerPlatform.instance = previous);

      await pumpPlayWindow(tester);

      // 造一个「正在播放」的旧播放器并登记进全局表，模拟播放页里那个。
      // initialize 必须放在 runAsync 里：widget 测试默认用假时钟，不推帧就永远
      // 等不到 initialized 事件。
      final old = VideoPlayerController.networkUrl(
        Uri.parse('https://x/old.mp4'),
      );
      await tester.runAsync(() async {
        await old.initialize();
        await old.play();
      });
      VideoPlayerShutdown.track(old);
      addTearDown(() async {
        VideoPlayerShutdown.untrack(old);
        await tester.runAsync(old.dispose);
      });
      expect(old.value.isPlaying, isTrue, reason: '前置条件：旧播放器正在播');

      platform.pausedIds.clear();

      final call = const MethodCall('loadVideo', 'v2');
      await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
        'han1me/play-window',
        const StandardMethodCodec().encodeMethodCall(call),
        (_) {},
      );
      // 只推帧，**不用** pumpAndSettle：正在播放的 controller 带轮询计时器，
      // 每 500ms 通知一次并排帧，界面永远不会静止，pumpAndSettle 会一直等到超时。
      await tester.pump();
      await tester.pump();

      expect(
        platform.pausedIds,
        isNotEmpty,
        reason: '换片必须先暂停旧播放器，否则旧视频会在加载期间继续出声',
      );
    });
  });
}

/// 记录 pause 调用的假平台层：只为观察「换片到底有没有去暂停旧播放器」。
class _RecordingVideoPlatform extends VideoPlayerPlatform {
  final pausedIds = <int>[];
  final _events = <int, StreamController<VideoEvent>>{};
  var _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> create(DataSource dataSource) async {
    final id = _nextId++;
    // 必须是带缓冲的 StreamController，**不能**用 broadcast：controller 订阅之前
    // 发出的事件会被 broadcast 直接丢掉，而 initialized 正是它判断「已就绪」的
    // 唯一信号，丢了就永远初始化不完（表现为测试挂住）。
    final controller = StreamController<VideoEvent>();
    _events[id] = controller;
    controller.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        duration: const Duration(minutes: 1),
        size: const Size(640, 360),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) =>
      _events[playerId]?.stream ?? const Stream.empty();

  @override
  Future<void> dispose(int playerId) async {
    await _events.remove(playerId)?.close();
  }

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async => pausedIds.add(playerId);

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildView(int playerId) => const SizedBox.shrink();

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}

  @override
  Future<void> setWebOptions(int playerId, VideoPlayerWebOptions options) async {}
}

/// 固定返回一份设置的 SettingsController 替身（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}
