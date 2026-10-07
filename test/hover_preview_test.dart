// 悬停预览（`lib/src/features/shared/hover_preview.dart`）的行为测试。
//
// 这里驱动**真实的 HoverPreviewController**，只把「起播放器」换成假工厂、仓库换成
// 假仓库、设置换成固定值（测试进程里没有播放器插件，也不该真发网络请求）。
//
// 三条刻意的约束各有一条测试兜着：
//   1. 停稳 1.5 秒才抓详情（扫过去不算）；
//   2. 同一时刻只抓一次、只播一个（单飞），抓回来的结果如果已经"过期"必须丢掉；
//   3. 连续失败 3 次熔断，本次会话不再预览。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/data/han1me_repository.dart';
import 'package:han1me_win_plus/src/domain/models/account.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/account/account_controller.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/hover_preview.dart';

/// 停稳延迟是常量，测试只能真的等过去；比 1.5 秒多留 200ms 余量。
const Duration _pastDelay = Duration(milliseconds: 1700);

/// 假播放器：只记「起过没有 / 释放过没有」，不碰真的解码器。
class _FakePlayer implements HoverPreviewPlayer {
  _FakePlayer(this.source);

  final VideoSource source;
  bool started = false;
  bool disposed = false;

  @override
  Future<void> start() async => started = true;

  @override
  Future<void> dispose() async => disposed = true;

  @override
  Widget buildSurface() => const SizedBox.shrink();
}

/// 只实现 `video()`，其余一律抛错（测试不该走到别的接口）。
///
/// [gated] 里的 id 会一直挂着，用来制造「抓取还在路上」的时序。
class _FakeRepository implements Han1meRepository {
  _FakeRepository({this.sources = const [_defaultSource]});

  final List<VideoSource> sources;
  final Map<String, Completer<VideoDetail>> gated = {};
  int fetchCount = 0;

  @override
  Future<VideoDetail> video(String baseUrl, String id) {
    fetchCount++;
    final held = gated[id];
    if (held != null) return held.future;
    return Future.value(_detail(id, sources));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} 不该被调用');
}

const VideoSource _defaultSource = VideoSource(
  quality: '720p',
  url: 'https://example.invalid/v.mp4',
);

VideoDetail _detail(String id, List<VideoSource> sources) => VideoDetail(
  id: id,
  title: '测试视频',
  sources: sources,
  tags: const [],
  playlist: const [],
  related: const [],
);

/// 固定返回一份设置的 SettingsController 替身（不读盘）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// 账号替身：build 返回永不完成的 Future，免得走到真实的资料刷新。
class _AccountStub extends AccountController {
  final _never = Completer<Account?>();

  @override
  Future<Account?> build() => _never.future;
}

/// 一次测试的环境：假仓库 + 假播放器工厂 + 固定设置。
class _Harness {
  _Harness({List<VideoSource>? sources, AppSettings? settings}) {
    repository = _FakeRepository(
      sources: sources ?? const [_defaultSource],
    );
    container = ProviderContainer(
      overrides: [
        han1meRepositoryProvider.overrideWithValue(repository),
        accountProvider.overrideWith(_AccountStub.new),
        settingsProvider.overrideWith(
          () => _StubSettings(settings ?? AppSettings()),
        ),
      ],
    );
    addTearDown(container.dispose);

    previousFactory = hoverPreviewPlayerFactory;
    hoverPreviewPlayerFactory = (source, headers) {
      final player = _FakePlayer(source);
      players.add(player);
      return player;
    };
    addTearDown(() => hoverPreviewPlayerFactory = previousFactory);

    // Notifier 是惰性的：不监听就永远不 build。
    container.listen(hoverPreviewProvider, (_, __) {});
  }

  late final _FakeRepository repository;
  late final ProviderContainer container;
  late final HoverPreviewPlayer Function(VideoSource, Map<String, String>)
  previousFactory;
  final List<_FakePlayer> players = [];

  HoverPreviewController get controller =>
      container.read(hoverPreviewProvider.notifier);

  HoverPreviewState get state => container.read(hoverPreviewProvider);
}

void main() {
  test('停稳之前不抓详情、不起播放器，停稳之后才起', () async {
    final h = _Harness();
    h.controller.hover('v1');

    // 光标刚进：连详情都不该抓 —— 扫过一整屏卡片会连发一串请求。
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(h.state.hoveredId, 'v1');
    expect(h.repository.fetchCount, 0);
    expect(h.players, isEmpty);

    await Future<void>.delayed(_pastDelay);
    expect(h.repository.fetchCount, 1);
    expect(h.players, hasLength(1));
    expect(h.players.single.started, isTrue);
    expect(h.state.playingId, 'v1');
  });

  test('鼠标移开：播放器被释放，playingId 清空', () async {
    final h = _Harness();
    h.controller.hover('v1');
    await Future<void>.delayed(_pastDelay);
    expect(h.state.playingId, 'v1');

    h.controller.unhover('v1');
    await Future<void>.delayed(Duration.zero);

    expect(h.state.playingId, isNull);
    expect(h.state.hoveredId, isNull);
    expect(h.players.single.disposed, isTrue);
  });

  test('抓取还在路上时移到另一张：只起后一张的播放器', () async {
    final h = _Harness();
    final gate = Completer<VideoDetail>();
    h.repository.gated['v1'] = gate;

    h.controller.hover('v1');
    await Future<void>.delayed(_pastDelay);
    expect(h.repository.fetchCount, 1);
    expect(h.players, isEmpty);

    // 中途换到 v2，然后 v1 的详情才回来 —— 这份结果已经过期，必须丢掉。
    h.controller.hover('v2');
    gate.complete(_detail('v1', const [_defaultSource]));
    await Future<void>.delayed(Duration.zero);
    expect(h.players, isEmpty);
    expect(h.state.playingId, isNull);

    // 单飞让 v2 的排定被推迟了一轮，这里等它自己补上。
    await Future<void>.delayed(_pastDelay);
    expect(h.players, hasLength(1));
    expect(h.state.playingId, 'v2');
  });

  test('详情页没给可播地址：连续失败 3 次后熔断，本会话不再预览', () async {
    final h = _Harness(sources: const []);

    for (final id in ['w1', 'w2', 'w3']) {
      h.controller.hover(id);
      await Future<void>.delayed(_pastDelay);
    }

    expect(h.players, isEmpty);
    expect(h.repository.fetchCount, 3);
    expect(h.state.disabled, isTrue);

    // 熔断之后连详情都不抓了。
    h.controller.hover('w4');
    await Future<void>.delayed(_pastDelay);
    expect(h.repository.fetchCount, 3);
    expect(h.state.hoveredId, isNull);
  });

  test('AV 源不做悬停预览，但也不会因此熔断', () async {
    final h = _Harness(settings: AppSettings(baseUrl: 'https://jable.tv'));
    // 必须先等设置就绪再悬停：设置还在加载时 `homeBaseUrl` 读出来是空字符串，
    // 就判不出"这是不是 AV 源"了（`video_card.dart` 的 `_resolved` 是同一套判断）。
    await h.container.read(settingsProvider.future);

    h.controller.hover('v1');
    await Future<void>.delayed(_pastDelay);

    expect(h.repository.fetchCount, 0);
    expect(h.players, isEmpty);
    expect(h.state.disabled, isFalse);
  });

  test('同一张卡片第二次悬停不再发详情请求（详情 provider 的 keepAlive）', () async {
    final h = _Harness();
    h.controller.hover('v1');
    await Future<void>.delayed(_pastDelay);
    expect(h.repository.fetchCount, 1);

    h.controller.unhover('v1');
    await Future<void>.delayed(Duration.zero);

    h.controller.hover('v1');
    await Future<void>.delayed(_pastDelay);
    expect(h.repository.fetchCount, 1);
    expect(h.state.playingId, 'v1');
  });
}
