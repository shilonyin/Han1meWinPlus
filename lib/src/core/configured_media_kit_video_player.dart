import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../data/local/json_store.dart';
import '../data/remote/windows_http_overrides.dart';
import '../data/remote/windows_proxy.dart';
import 'settings.dart';
import 'shader_assets.dart';
import 'shader_service.dart';

/// 播放区域信息：由界面层提供，供 mpv 侧决定「按显示尺寸渲染」。
///
/// media_kit 默认是按**视频原始分辨率**渲染、再由界面层缩放的，因此 mpv 侧的
/// 放大着色器（Anime4K 的 Upscale 模组）与 `scale` 缩放器都不会真正生效，
/// 必须由界面层把显示尺寸告诉它（见 [ConfiguredMediaKitVideoPlayer.updateOutputArea]）。
class VideoOutputArea extends InheritedWidget {
  const VideoOutputArea({required this.size, required this.enabled, required this.fill, required super.child, super.key});

  /// 播放区域的物理像素尺寸。
  final Size size;

  /// 是否启用了需要 mpv 真正放大的超分方案。
  final bool enabled;

  /// 画面是否铺满区域（裁剪/拉伸模式），决定用区域宽高的较大值还是较小值换算。
  final bool fill;

  static VideoOutputArea? maybeOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<VideoOutputArea>();

  @override
  bool updateShouldNotify(VideoOutputArea oldWidget) => size != oldWidget.size || enabled != oldWidget.enabled || fill != oldWidget.fill;
}

class ConfiguredMediaKitVideoPlayer extends VideoPlayerPlatform {
  static AppSettings settings = const AppSettings();
  static final ConfiguredMediaKitVideoPlayer _instance = ConfiguredMediaKitVideoPlayer();

  final _players = HashMap<int, Player>();
  final _completers = HashMap<int, Completer<void>>();
  final _videoControllers = HashMap<int, VideoController>();
  final _streamControllers = HashMap<int, StreamController<VideoEvent>>();
  final _streamSubscriptions = HashMap<int, List<StreamSubscription>>();
  /// 播放区域信息（由界面层随布局更新）：区域物理像素尺寸 / 是否开启增强档 / 是否铺满。
  final _outputAreas = HashMap<int, (Size, bool, bool)>();
  /// 最近一次真正下发给原生侧的输出尺寸；`null` 表示跟随视频原始分辨率。
  final _appliedSizes = HashMap<int, (int, int)?>();
  final _outputSizeTimers = HashMap<int, Timer>();
  int _nextTextureId = 0;

  /// mpv 使用的 HTTP 代理（取自系统代理）。
  ///
  /// mpv/libmpv **不会**读取系统代理，必须显式通过 `http-proxy` 传入；否则在
  /// 直连被阻断的网络里，界面、评论都正常（它们走 Dart 的 HttpClient），
  /// 但视频会一直停留在缓冲状态。null 表示不使用代理。
  static String? httpProxy;
  static Future<void>? _httpProxyLookup;

  /// 重新读取系统代理。启动时调用一次即可，系统代理变化后可再次调用。
  static Future<void> refreshHttpProxy() => _httpProxyLookup = _resolveHttpProxy();

  /// 保证系统代理只解析一次。
  static Future<void> ensureHttpProxy() => _httpProxyLookup ?? refreshHttpProxy();

  static Future<void> _resolveHttpProxy() async {
    try {
      final settings = await SettingsStore(JsonStore()).load();
      final rule = await WindowsHttpOverrides.resolveRule(mode: settings.proxyMode, custom: settings.customProxy);
      httpProxy = WindowsProxy.mpvUrl(rule);
    } catch (_) {
      httpProxy = null;
    }
  }

  static void registerWith() {
    VideoPlayerPlatform.instance = _instance;
  }

  @override
  Future<void> init() async {
    final textureIds = _players.keys.toList(growable: false);
    for (final textureId in textureIds) {
      await dispose(textureId);
    }
    _players.clear();
    _completers.clear();
    _videoControllers.clear();
    _streamControllers.clear();
    _streamSubscriptions.clear();
    for (final timer in _outputSizeTimers.values) {
      timer.cancel();
    }
    _outputSizeTimers.clear();
    _outputAreas.clear();
    _appliedSizes.clear();
  }

  @override
  Future<void> dispose(int textureId) async {
    final player = _players.remove(textureId);
    final streamController = _streamControllers.remove(textureId);
    final subscriptions = _streamSubscriptions.remove(textureId);
    _videoControllers.remove(textureId);
    _outputAreas.remove(textureId);
    _appliedSizes.remove(textureId);
    _outputSizeTimers.remove(textureId)?.cancel();
    final completer = _completers.remove(textureId);
    if (completer != null && !completer.isCompleted) {
      completer.complete();
    }
    for (final subscription in subscriptions ?? const <StreamSubscription>[]) {
      try {
        await subscription.cancel();
      } catch (_) {}
    }
    if (streamController != null) {
      try {
        await streamController.close();
      } catch (_) {}
    }
    if (player != null) {
      try {
        await player.dispose().timeout(const Duration(seconds: 2));
      } catch (_) {}
    }
  }

  @override
  Future<int?> create(DataSource dataSource) async {
    final player = Player();
    int? textureId;
    try {
      final native = player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      await ensureHttpProxy();
      await _applyHttpProxy(native);
      await _applyCustomParameters(native, settings);
      final videoController = VideoController(
        player,
        configuration: _videoConfiguration(settings),
      );
      await _applySuperResolution(native, settings);
      final completer = Completer<void>();
      final streamController = StreamController<VideoEvent>();
      final streamSubscriptions = <StreamSubscription>[];
      textureId = ++_nextTextureId;

      _players[textureId] = player;
      _completers[textureId] = completer;
      _videoControllers[textureId] = videoController;
      _streamControllers[textureId] = streamController;
      _streamSubscriptions[textureId] = streamSubscriptions;

      // media_kit 自己会在 videoParams 变化时把输出尺寸改回视频原始尺寸，
      // 而视频就绪（尺寸已知）本身也不会引发 Widget 重建，所以这里一并重算。
      streamSubscriptions.add(videoController.player.stream.videoParams.listen((_) {
        final id = textureId;
        if (id != null) _refreshOutputSize(id);
      }));

      _initialize(textureId);

      final resource = switch (dataSource.sourceType) {
        DataSourceType.asset => dataSource.package == null
            ? 'asset:///${dataSource.asset}'
            : 'asset:///packages/${dataSource.package}/${dataSource.asset}',
        DataSourceType.network || DataSourceType.file || DataSourceType.contentUri => dataSource.uri!,
      };

      await player.open(
        Media(resource, httpHeaders: dataSource.httpHeaders),
        play: false,
      );
      return textureId;
    } catch (_) {
      if (textureId != null && identical(_players[textureId], player)) {
        await dispose(textureId);
      } else {
        try {
          await player.dispose().timeout(const Duration(seconds: 2));
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// 把系统代理交给 mpv。
  ///
  /// 故意放在 [_applyCustomParameters] 之前：用户在「自定义参数」里显式写了
  /// `http-proxy=...` 时，以自己的设置为准。
  Future<void> _applyHttpProxy(NativePlayer native) async {
    final proxy = httpProxy;
    if (proxy == null || proxy.isEmpty) return;
    try {
      await native.setProperty('http-proxy', proxy);
    } catch (_) {}
  }

  Future<void> _applyCustomParameters(NativePlayer native, AppSettings settings) async {
    for (final parameter in settings.customParameters) {
      final separator = parameter.indexOf('=');
      if (separator <= 0) continue;
      try {
        await native.setProperty(
          parameter.substring(0, separator).trim(),
          parameter.substring(separator + 1).trim(),
        );
      } catch (_) {}
    }
  }

  /// 应用「超分辨率」设置。
  ///
  /// 各方案互不相容，且切换方案时播放器会被重建（见 `VideoPlayerPanel`），
  /// 所以这里只负责写入当前方案，不需要清理上一个方案留下的设置。
  Future<void> _applySuperResolution(NativePlayer native, AppSettings settings) async {
    final embed = settings.videoRenderer == VideoRenderer.mediacodecEmbed;
    final mode = settings.superResolutionMode;
    if (embed || mode == SuperResolutionMode.off) return;
    try {
      if (mode == SuperResolutionMode.natural) {
        // 不接着色器，改用 libplacebo 的高质量缩放器（对齐 mpv 的 high-quality 预设）。
        // 注意：只有 mpv 真的需要缩放时才会用到 `scale`，所以界面层必须把显示尺寸
        // 交给它（见 [setVideoOutputSize]），否则这一档等于没开。
        await native.setProperty('scale', 'ewa_lanczossharp');
        await native.setProperty('scale-antiring', '0.6');
        return;
      }
      final shaders = mode == SuperResolutionMode.efficiency ? mpvAnime4KShadersLite : mpvAnime4KShaders;
      final directory = ShaderService.directory?.path;
      if (directory == null) return;
      await native.waitForVideoControllerInitializationIfAttached;
      await native.command([
        'change-list',
        'glsl-shaders',
        'set',
        buildShadersAbsolutePath(directory, shaders),
      ]);
    } catch (_) {}
  }

  VideoControllerConfiguration _videoConfiguration(AppSettings settings) {
    final embed = settings.videoRenderer == VideoRenderer.mediacodecEmbed;
    final acceleration = embed || settings.hardwareAcceleration;
    return VideoControllerConfiguration(
      vo: settings.videoRenderer.mpvValue,
      enableHardwareAcceleration: acceleration,
      hwdec: embed ? 'mediacodec' : acceleration ? settings.hardwareDecoder : 'no',
    );
  }

  @override
  Stream<VideoEvent> videoEventsFor(int textureId) {
    if (_streamControllers[textureId] == null) {
      throw StateError('VideoPlayer for textureId $textureId is not found, Check if its disposed.');
    }
    return _streamControllers[textureId]!.stream;
  }

  @override
  Future<void> setLooping(int textureId, bool looping) async {
    final playlistMode = looping ? PlaylistMode.single : PlaylistMode.none;
    return _players[textureId]?.setPlaylistMode(playlistMode);
  }

  @override
  Future<void> play(int textureId) async {
    return _players[textureId]?.play();
  }

  @override
  Future<void> pause(int textureId) async {
    return _players[textureId]?.pause();
  }

  @override
  Future<void> setVolume(int textureId, double volume) async {
    return _players[textureId]?.setVolume(volume * 100);
  }

  @override
  Future<void> seekTo(int textureId, Duration position) async {
    return _players[textureId]?.seek(position);
  }

  @override
  Future<void> setPlaybackSpeed(int textureId, double speed) async {
    final player = _players[textureId];
    if (player == null) return;
    try {
      await player.setRate(speed);
    } catch (_) {}
  }

  @override
  Future<Duration> getPosition(int textureId) async {
    return _players[textureId]?.platform?.state.position ?? Duration.zero;
  }

  @override
  Widget buildView(int textureId) {
    if (_videoControllers[textureId] == null) {
      throw StateError('VideoPlayer for textureId $textureId is not found, Check if its disposed.');
    }
    final controller = _videoControllers[textureId]!;
    return LayoutBuilder(builder: (context, constraints) {
      final area = VideoOutputArea.maybeOf(context);
      updateOutputArea(textureId, area?.size ?? Size.zero, area?.enabled ?? false, area?.fill ?? false);
      return Video(
        key: ValueKey(controller),
        controller: controller,
        wakelock: false,
        controls: NoVideoControls,
        fill: const Color(0x00000000),
        pauseUponEnteringBackgroundMode: false,
        resumeUponEnteringForegroundMode: false,
      );
    });
  }

  /// 由界面层在每次布局变化时调用：记录播放区域信息并按需调整 mpv 的输出尺寸。
  void updateOutputArea(int textureId, Size size, bool enabled, bool fill) {
    final area = (size, enabled, fill);
    if (_outputAreas[textureId] == area) return;
    _outputAreas[textureId] = area;
    // 拖窗口时尺寸会连续变化，稍缓一下，避免每帧重建渲染表面（会卡）。
    _outputSizeTimers.remove(textureId)?.cancel();
    _outputSizeTimers[textureId] = Timer(const Duration(milliseconds: 150), () {
      _outputSizeTimers.remove(textureId);
      _refreshOutputSize(textureId);
    });
  }

  /// 根据播放区域与当前视频尺寸算出目标输出尺寸，与上次不同时才真正下发。
  ///
  /// 未开启增强档（或视频尺寸还没就绪）时目标为 `null`，即恢复「跟随视频原始分辨率」——
  /// 那是默认行为，也是开销最低的路径。
  void _refreshOutputSize(int textureId) {
    final controller = _videoControllers[textureId];
    if (controller == null) return;
    final state = controller.player.state;
    final videoWidth = state.width ?? 0;
    final videoHeight = state.height ?? 0;
    final target = videoWidth > 0 && videoHeight > 0 && settings.superResolutionMode != SuperResolutionMode.off ? _outputSizeFor(textureId, videoWidth, videoHeight) : null;
    if (_appliedSizes.containsKey(textureId) && _appliedSizes[textureId] == target) return;
    _appliedSizes[textureId] = target;
    unawaited(_applyOutputSize(textureId, target));
  }

  /// 目标输出尺寸：优先按界面层给出的播放区域换算；界面层还没报上来时退回「视频 2 倍」
  /// ——Anime4K 的 x2 放大模组正是按 2 倍设计的，这样即使拿不到界面尺寸也能生效。
  (int, int) _outputSizeFor(int textureId, int videoWidth, int videoHeight) {
    final area = _outputAreas[textureId];
    double factor;
    if (area != null && area.$2 && area.$1.width >= 1 && area.$1.height >= 1) {
      // 渲染尺寸要与视频宽高比一致，否则会把黑边烘进纹理；裁剪/拉伸模式按「铺满」算。
      final box = area.$1;
      factor = (area.$3 ? math.max(box.width / videoWidth, box.height / videoHeight) : math.min(box.width / videoWidth, box.height / videoHeight)).clamp(1.0, 3.0);
    } else {
      factor = 2.0;
    }
    var width = (videoWidth * factor).round();
    var height = (videoHeight * factor).round();
    // 上限约 4K，避免极小的视频在超大窗口里把渲染纹理撑爆。
    const budget = 3840 * 2160;
    if (width * height > budget) {
      final shrink = math.sqrt(budget / (width * height));
      width = (width * shrink).round();
      height = (height * shrink).round();
    }
    return (width, height);
  }

  /// 真正把尺寸下发给 media_kit。
  ///
  /// `NativeVideoController.setSize` 在「与上次请求相同」时会直接跳过，而 media_kit
  /// 自己会在 videoParams 变化时把原生尺寸改回视频原始尺寸（并不更新它自己的记录），
  /// 所以这里先下发一次不带参数的调用重置记录（原生侧本来就是视频尺寸，属空操作），
  /// 再下发目标尺寸，保证每次都能真正生效。
  Future<void> _applyOutputSize(int textureId, (int, int)? target) async {
    final controller = _videoControllers[textureId];
    if (controller == null) return;
    try {
      await controller.setSize();
      if (target != null) await controller.setSize(width: target.$1, height: target.$2);
    } catch (_) {}
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future.value();

  @override
  Future<void> setWebOptions(int textureId, VideoPlayerWebOptions options) => Future.value();

  void _initialize(int textureId) {
    if (_streamSubscriptions[textureId]?.isNotEmpty ?? false) return;

    final player = _players[textureId];
    final completer = _completers[textureId];
    final streamController = _streamControllers[textureId];
    final streamSubscriptions = _streamSubscriptions[textureId];

    if (player == null ||
        completer == null ||
        streamController == null ||
        streamSubscriptions == null) {
      return;
    }

    int? width;
    int? height;
    Duration? duration;

    bool isActive() => identical(_streamControllers[textureId], streamController) &&
        !streamController.isClosed;

    void notify() {
      if (isActive() && !completer.isCompleted) {
        if (width != null && height != null && duration != null) {
          streamController.add(
            VideoEvent(
              eventType: VideoEventType.initialized,
              size: Size((width ?? 0) * 1.0, (height ?? 0) * 1.0),
              duration: player.state.duration,
            ),
          );
          completer.complete();
        }
      }
    }

    streamSubscriptions.add(
      player.stream.duration.listen((event) {
        if (event > Duration.zero) {
          duration = event;
          notify();
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.videoParams.listen((event) {
        width = event.dw;
        height = event.dh;
        if ((width ?? 0) > 0 && (height ?? 0) > 0) notify();
      }),
    );
    streamSubscriptions.add(
      player.stream.tracks.listen((event) {
        if (event.video.length == 2 && event.audio.length > 2) {
          width = 0;
          height = 0;
          notify();
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.playing.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(VideoEvent(eventType: VideoEventType.isPlayingStateUpdate, isPlaying: event));
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.completed.listen((event) async {
        await completer.future;
        if (event && isActive()) {
          streamController.add(VideoEvent(eventType: VideoEventType.completed));
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.buffering.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(
            VideoEvent(eventType: event ? VideoEventType.bufferingStart : VideoEventType.bufferingEnd),
          );
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.buffer.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.add(
            VideoEvent(
              eventType: VideoEventType.bufferingUpdate,
              buffered: [DurationRange(Duration.zero, event)],
            ),
          );
        }
      }),
    );
    streamSubscriptions.add(
      player.stream.error.listen((event) async {
        await completer.future;
        if (isActive()) {
          streamController.addError(PlatformException(code: '', message: event));
        }
      }),
    );
  }
}
