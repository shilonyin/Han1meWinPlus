import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/video_player_shutdown.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../video/video_controller.dart';

/// 鼠标在封面上停稳多久才开始抓详情、拉起播放器。
///
/// 1.5 秒是「确定用户真的想看这个视频」的下限：更短的话，扫过一整屏卡片会连发
/// 一串详情页请求 —— 而仓库里已经踩过这个坑（见 `video_card.dart` 里 `_resolved`
/// 的注释：一屏十几张卡片各抓一次详情页会触发站点 Cloudflare 限流，实测 jable
/// 返回 Error 1015）。
const Duration hoverPreviewDelay = Duration(milliseconds: 1500);

/// 一次预览最多播多久。
///
/// 正常的收尾路径是「鼠标移开」和「卡片被销毁」；这条只是兜底，避免某个边界
/// 情况下留一个静音播放器一直在后台解码。
const Duration hoverPreviewMaxDuration = Duration(seconds: 30);

/// 连续失败多少次就整个会话关掉预览。
///
/// 失败基本都来自站点侧（限流 / 403 / 页面结构变了）。悬停预览是锦上添花的功能，
/// 不能让它把首页拖成「一直转圈」或「图片全加载不出来」这种用户看不出原因的坏体验，
/// 所以连续失败到阈值就直接停掉，并打一条日志说明原因。
const int hoverPreviewMaxFailures = 3;

/// 预览播放器的最小抽象。
///
/// 真实实现下面是 `video_player`（桌面端即 media_kit / libmpv）。测试进程里没有
/// 播放器插件，起不了真播放器，所以把「起播放器」收成一个可替换的工厂
/// （[hoverPreviewPlayerFactory]），让节流、单飞、熔断这些**编排逻辑**能被测试覆盖。
abstract class HoverPreviewPlayer {
  /// 静音、循环开播。抛错表示这一路源播不了。
  Future<void> start();

  /// 释放底层解码器。必须能重复调用：移开鼠标与卡片销毁可能都会走到。
  Future<void> dispose();

  /// 铺满封面的那一层画面。
  Widget buildSurface();
}

/// 建预览播放器的方式。测试里替换成假实现。
@visibleForTesting
HoverPreviewPlayer Function(VideoSource source, Map<String, String> headers)
hoverPreviewPlayerFactory = _videoPlayerPreview;

HoverPreviewPlayer _videoPlayerPreview(
  VideoSource source,
  Map<String, String> headers,
) => _VideoPlayerPreview(source, headers);

class _VideoPlayerPreview implements HoverPreviewPlayer {
  _VideoPlayerPreview(this.source, this.headers);

  final VideoSource source;
  final Map<String, String> headers;
  VideoPlayerController? _controller;

  @override
  Future<void> start() async {
    // 与播放页同一套建法（见 `video_player_panel.dart`）：本地路径走 file，
    // 网络源带上 Referer / UA —— 有的 CDN 少一个 Referer 直接 403。
    final controller = source.url.startsWith('/')
        ? VideoPlayerController.file(File(source.url))
        : VideoPlayerController.networkUrl(
            Uri.parse(source.url),
            httpHeaders: headers,
          );
    _controller = controller;
    VideoPlayerShutdown.track(controller);
    await controller.initialize();
    await controller.setVolume(0);
    await controller.setLooping(true);
    await controller.play();
  }

  @override
  Future<void> dispose() async {
    final controller = _controller;
    _controller = null;
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause().timeout(const Duration(milliseconds: 500));
      }
    } catch (_) {}
    try {
      await controller.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    VideoPlayerShutdown.untrack(controller);
  }

  @override
  Widget buildSurface() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }
    final ratio = controller.value.aspectRatio == 0
        ? 16 / 9
        : controller.value.aspectRatio;
    // 铺满封面用「裁剪填充」：整块画布按比例放大到框外再裁掉多余部分。
    // 与播放页 `_VideoSurface` 的 crop 分支同一套写法。
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: ratio * 1000,
        height: 1000,
        child: VideoPlayer(controller),
      ),
    );
  }
}

@immutable
class HoverPreviewState {
  const HoverPreviewState({
    this.hoveredId,
    this.playingId,
    this.disabled = false,
  });

  /// 鼠标当前停在这张封面上：可能还在等 [hoverPreviewDelay]，也可能正在抓详情。
  final String? hoveredId;

  /// 正在这张封面里播预览。
  final String? playingId;

  /// 熔断已触发：本次会话不再做任何悬停预览。
  final bool disabled;

  HoverPreviewState copyWith({
    String? hoveredId,
    bool clearHovered = false,
    String? playingId,
    bool clearPlaying = false,
    bool? disabled,
  }) => HoverPreviewState(
    hoveredId: clearHovered ? null : (hoveredId ?? this.hoveredId),
    playingId: clearPlaying ? null : (playingId ?? this.playingId),
    disabled: disabled ?? this.disabled,
  );
}

/// 悬停预览：鼠标在封面上停住 [hoverPreviewDelay] 之后，去详情页取可播地址，
/// 在封面里静音循环播放；鼠标移开就停掉并释放播放器。
///
/// 三条刻意的约束：
/// 1. **同一时刻只抓一次、只播一个**（单飞）。一屏卡片各抓一次详情页会触发站点
///    限流，所以这里连并发都不给。
/// 2. **结果靠 `videoDetailProvider` 的 keepAlive 复用**：同一张卡片第二次悬停
///    不会再发请求。
/// 3. **连续失败 [hoverPreviewMaxFailures] 次就熔断**，本会话不再预览。
final hoverPreviewProvider =
    NotifierProvider<HoverPreviewController, HoverPreviewState>(
      HoverPreviewController.new,
    );

class HoverPreviewController extends Notifier<HoverPreviewState> {
  Timer? _timer;
  Timer? _stopTimer;
  HoverPreviewPlayer? _player;
  var _failures = 0;
  var _loading = false;

  @override
  HoverPreviewState build() {
    ref.onDispose(() => unawaited(_release()));
    return const HoverPreviewState();
  }

  /// 正在播的预览播放器（封面层用它画画面）。
  HoverPreviewPlayer? get player => _player;

  /// 鼠标进入某张封面。只是**排定**一次预览，真正的抓取在
  /// [hoverPreviewDelay] 之后 —— 扫过去不算。
  void hover(String id) {
    if (id.isEmpty || state.disabled) return;
    if (state.hoveredId == id || state.playingId == id) return;
    _timer?.cancel();
    state = state.copyWith(hoveredId: id);
    _timer = Timer(hoverPreviewDelay, () => unawaited(_start(id)));
  }

  /// 鼠标离开某张封面。
  ///
  /// 只处理「离开的正是当前这张」：鼠标从 A 滑到 B 会先 exit A 再 enter B
  /// （顺序也可能反过来），不能让后到的 exit A 把 B 刚排定的预览取消掉。
  void unhover(String id) {
    if (state.hoveredId == id) {
      _timer?.cancel();
      _timer = null;
      state = state.copyWith(clearHovered: true);
    }
    if (state.playingId == id) unawaited(_stop());
  }

  Future<void> _start(String id) async {
    if (state.disabled || _player != null || _loading) return;
    if (state.hoveredId != id) return;
    if (!_previewAllowed()) return;
    _loading = true;
    try {
      final detail = await ref.read(videoDetailProvider(id).future);
      if (state.hoveredId != id || _player != null) return;
      if (detail.sources.isEmpty) throw StateError('详情页没有给可播地址');
      final source = detail.sources.first;
      final player = hoverPreviewPlayerFactory(source, _headersFor(id, source));
      await player.start();
      if (state.hoveredId != id || _player != null) {
        await player.dispose();
        return;
      }
      _player = player;
      _failures = 0;
      state = state.copyWith(playingId: id);
      _stopTimer = Timer(hoverPreviewMaxDuration, () => unawaited(_stop()));
    } catch (error) {
      _registerFailure(id, error);
    } finally {
      _loading = false;
      // 单飞被占用的那一次（鼠标已经移到另一张上了）在这里补一次排定，
      // 否则「A 还在抓的时候移到 B」会让 B 一直停在封面上却永远不预览。
      final hovered = state.hoveredId;
      if (hovered != null && hovered != id && state.playingId == null) {
        _timer?.cancel();
        _timer = Timer(hoverPreviewDelay, () => unawaited(_start(hovered)));
      }
    }
  }

  Future<void> _stop() async {
    _stopTimer?.cancel();
    _stopTimer = null;
    final player = _player;
    _player = null;
    if (state.playingId != null) state = state.copyWith(clearPlaying: true);
    await player?.dispose();
  }

  /// Provider 销毁（关页面 / 应用退出）时的收尾。
  Future<void> _release() async {
    _timer?.cancel();
    _stopTimer?.cancel();
    _timer = null;
    _stopTimer = null;
    final player = _player;
    _player = null;
    await player?.dispose();
  }

  void _registerFailure(String id, Object error) {
    _failures++;
    debugPrint('[hover-preview] 预览 $id 失败（连续第 $_failures 次）：$error');
    if (state.hoveredId == id) state = state.copyWith(clearHovered: true);
    if (_failures >= hoverPreviewMaxFailures) {
      state = state.copyWith(clearHovered: true, disabled: true);
      debugPrint(
        '[hover-preview] 连续失败 $hoverPreviewMaxFailures 次，本次会话不再做悬停预览',
      );
    }
  }

  bool _previewAllowed() {
    final settings = ref.read(settingsProvider).valueOrNull;
    // AV 源的列表页自己就带全部信息，而且对它的详情页请求最容易触发
    // Cloudflare 限流（见 video_card.dart 里 _resolved 的注释）—— 那条源不做预览。
    return javSiteFor(settings?.homeBaseUrl ?? '') == null;
  }

  Map<String, String> _headersFor(String id, VideoSource source) {
    final settings = ref.read(settingsProvider).valueOrNull;
    // 解析层给了请求头就用它（AV 源必须带自己的 Referer），否则按 hanime1 的惯例拼 ——
    // 与播放页 `video_player_panel.dart` 里那段保持同一套判断。
    return source.headers ??
        {
          'User-Agent': Han1meApi.userAgent,
          'Referer': '${settings?.resolvedBaseUrl ?? ''}/watch?v=$id',
        };
  }
}
