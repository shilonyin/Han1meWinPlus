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
  /// 播放稳定起点：改渲染尺寸必须等到播放真的稳下来（见 [_canResizeNow]）。
  final _playingSince = HashMap<int, DateTime>();
  /// 改尺寸的暂缓截止时间：重着色器链编译期间绝不能重建渲染表面。
  final _resizeHoldUntil = HashMap<int, DateTime>();
  /// 「等播放稳下来再改尺寸」的重试计时器与次数。
  final _resizeRetryTimers = HashMap<int, Timer>();
  final _resizeRetryCounts = HashMap<int, int>();
  /// 视频输出「卡死」（在播但画面不再更新）的持续秒数与恢复标记。
  final _stallSeconds = HashMap<int, int>();
  final _stallTimers = HashMap<int, Timer>();
  final _stallRecovered = HashMap<int, bool>();
  /// 正在改画质（重新编译着色器链）的纹理：这段时间内核上报的「缓冲」要压掉。
  final _switchingQuality = HashMap<int, bool>();
  final _switchingTimers = HashMap<int, Timer>();
  /// 每个纹理当前用的传输方式：textureId →（主机名, 是否走代理），见 [_switchTransport]。
  final _transports = HashMap<int, (String, bool)>();
  /// 「迟迟开不出来就换另一条传输方式」的看门狗与已换次数。
  final _transportTimers = HashMap<int, Timer>();
  final _transportSwitches = HashMap<int, int>();
  int _nextTextureId = 0;

  /// 正在切换画质（重编译着色器链），界面据此显示提示条。
  ///
  /// 重档位（Anime4K 质量档）要编译一大串着色器，要几秒；期间渲染线程被占住，
  /// 内核会短暂进入缓冲状态——但线程没死，音频一直在放。直接把它当成「加载中」
  /// 上报，界面就会弹一个转圈，看起来像卡住。
  static final ValueNotifier<bool> switchingSuperResolution = ValueNotifier<bool>(false);

  /// 视频输出卡死时的兜底回调（由播放页接管：重新加载当前片源）。
  ///
  /// mpv 的渲染上下文一旦被搞坏就再也不会自己恢复（画面永久转圈、声音照旧），
  /// 此时唯一的解法是重建播放器，所以留一个钩子给界面层。
  static void Function()? onVideoOutputStalled;

  /// mpv 使用的 HTTP 代理（取自系统代理）。
  ///
  /// mpv/libmpv **不会**读取系统代理，必须显式通过 `http-proxy` 传入；否则在
  /// 直连被阻断的网络里，界面、评论都正常（它们走 Dart 的 HttpClient），
  /// 但视频会一直停留在缓冲状态。null 表示不使用代理。
  static String? httpProxy;

  /// 设置里没给出代理（`direct` 模式）时，播放器可退而使用的系统代理。
  ///
  /// `direct` 只对**站点请求**有意义：那边有内置地址兜底，直连还更快、也不吃
  /// Cloudflare 对代理出口 IP 的风控。但**片源 CDN 不一样** —— 国内直连
  /// `vdownload.hembed.com` 这类主机在 TLS 握手阶段就被阻断
  /// （`mbedtls_ssl_handshake returned -0x4e`），于是详情页一切正常、视频却永远转圈。
  /// 所以只要机器上确实有系统代理，播放器仍然用它。
  static String? fallbackHttpProxy;
  static Future<void>? _httpProxyLookup;

  /// 片源主机实测可用的传输方式（true = 走代理）。
  ///
  /// 两个方向都会用到：有些 CDN（javchu 在用的 cdn2020）对代理出口 IP 直接回 `451`，
  /// 同一个地址直连却是 200；反过来 CDN77 这类只认代理。试出结果就记下来，
  /// 同一主机后续片源不必再经历一次失败。
  static final Map<String, bool> _hostUsesProxy = <String, bool>{};

  /// 重新读取系统代理。启动时调用一次即可，系统代理变化后可再次调用。
  static Future<void> refreshHttpProxy() => _httpProxyLookup = _resolveHttpProxy();

  /// 保证系统代理只解析一次。
  static Future<void> ensureHttpProxy() => _httpProxyLookup ?? refreshHttpProxy();

  static Future<void> _resolveHttpProxy() async {
    try {
      final settings = await SettingsStore(JsonStore()).load();
      final rule = await WindowsHttpOverrides.resolveRule(mode: settings.proxyMode, custom: settings.customProxy);
      httpProxy = WindowsProxy.mpvUrl(rule);
      // 另一条路：系统代理。与首选相同（或系统没开代理）时不留后路。
      final system = WindowsProxy.mpvUrl(await WindowsHttpOverrides.systemProxy());
      fallbackHttpProxy = system == null || system == httpProxy ? null : system;
    } catch (_) {
      httpProxy = null;
      fallbackHttpProxy = null;
    }
  }

  /// 这台机器上是否有代理可用（首选或系统代理）。
  static String? get _availableProxy => httpProxy ?? fallbackHttpProxy;

  /// 该主机这次该用的传输方式。默认走代理（只要机器上有），实测过的按记录来。
  static bool _prefersProxy(String host) => _hostUsesProxy[host] ?? (_availableProxy != null);

  /// 对应传输方式的 mpv `http-proxy` 取值（null = 直连）。
  static String? _proxyFor(String host) => _prefersProxy(host) ? _availableProxy : null;

  static void registerWith() {
    VideoPlayerPlatform.instance = _instance;
  }

  /// 新建播放器时用的配置：在 media_kit 的默认协议白名单上补一个 `httpproxy`。
  ///
  /// media_kit 会把白名单原样下发给 mpv（`--demuxer-lavf-o=protocol_whitelist=...`），
  /// 默认值是 `udp,rtp,tcp,tls,data,file,http,https,crypto`。而 ffmpeg 的 http 协议在
  /// **配了代理**时会用 `httpproxy` 协议去连代理：白名单里没有它，取分片与解密密钥时就会
  /// 直接 `avformat_open_input() failed`。此时 mpv 会退而用「播放列表」解复用器把 m3u8
  /// 里的每一行当成独立文件播——于是 HLS 片源的表现变成「只播几秒就卡」
  /// （每个分片被当成一个几百 KB 的小文件），或者干脆一直加载。
  ///
  /// 本应用的场景里代理是常态（番剧站与 AV 源都不能直连），所以这一项必须有。
  static final PlayerConfiguration _playerConfiguration = PlayerConfiguration(
    protocolWhitelist: [...const PlayerConfiguration().protocolWhitelist, 'httpproxy'],
  );

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
    for (final timer in _resizeRetryTimers.values) {
      timer.cancel();
    }
    _resizeRetryTimers.clear();
    for (final timer in _stallTimers.values) {
      timer.cancel();
    }
    _stallTimers.clear();
    for (final timer in _switchingTimers.values) {
      timer.cancel();
    }
    _switchingTimers.clear();
    _switchingQuality.clear();
    for (final timer in _transportTimers.values) {
      timer.cancel();
    }
    _transportTimers.clear();
    _transports.clear();
    _transportSwitches.clear();
    switchingSuperResolution.value = false;
    _playingSince.clear();
    _resizeHoldUntil.clear();
    _resizeRetryCounts.clear();
    _stallSeconds.clear();
    _stallRecovered.clear();
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
    _playingSince.remove(textureId);
    _resizeHoldUntil.remove(textureId);
    _resizeRetryTimers.remove(textureId)?.cancel();
    _transportTimers.remove(textureId)?.cancel();
    _transports.remove(textureId);
    _transportSwitches.remove(textureId);
    _resizeRetryCounts.remove(textureId);
    _stallTimers.remove(textureId)?.cancel();
    _stallSeconds.remove(textureId);
    _stallRecovered.remove(textureId);
    _switchingTimers.remove(textureId)?.cancel();
    if (_switchingQuality.remove(textureId) != null) {
      switchingSuperResolution.value = _switchingQuality.isNotEmpty;
    }
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
    final player = Player(configuration: _playerConfiguration);
    int? textureId;
    try {
      final native = player.platform as NativePlayer;
      await native.waitForPlayerInitialization;
      await ensureHttpProxy();
      final host = _mediaHost(dataSource.uri);
      final prefersProxy = _prefersProxy(host);
      await _applyHttpProxy(native, useProxy: prefersProxy);
      // 渲染后端要在视频输出初始化**之前**定下来，所以放在所有画质参数之前。
      await _applyGpuApi(native, settings);
      if (dataSource.sourceType == DataSourceType.network) await _applyStreamTuning(native);
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

      // 先建立初始化监听（它会发出 `initialized` 事件），再挂平台层自己的监听，
      // 避免两者争用同一个订阅列表的顺序。
      _initialize(textureId);

      // media_kit 自己会在 videoParams 变化时把输出尺寸改回视频原始尺寸，
      // 而视频就绪（尺寸已知）本身也不会引发 Widget 重建，所以这里一并重算。
      streamSubscriptions.add(videoController.player.stream.videoParams.listen((_) {
        final id = textureId;
        if (id != null) _refreshOutputSize(id);
      }));

      // 播放稳定计时：只有「正在播放、没在缓冲、并且已经这样持续了一会儿」
      // 才允许改渲染尺寸（原因见 [_canResizeNow]）。
      streamSubscriptions.add(videoController.player.stream.playing.listen((playing) {
        final id = textureId;
        if (id == null) return;
        if (playing) {
          _playingSince[id] = DateTime.now();
        } else {
          _playingSince.remove(id);
        }
        _refreshOutputSize(id);
      }));
      streamSubscriptions.add(videoController.player.stream.buffering.listen((buffering) {
        final id = textureId;
        if (id == null) return;
        if (buffering) {
          _playingSince.remove(id);
        } else {
          _playingSince[id] = DateTime.now();
          // 切画质造成的短暂缓冲到此结束，提示条可以收了。
          _endSwitchingQuality(id);
        }
        _refreshOutputSize(id);
      }));

      // 兜底看门狗：万一渲染上下文还是被搞坏了，通报界面层重载。
      _stallTimers[textureId] = Timer.periodic(const Duration(seconds: 2), (_) => _checkStall(textureId!));

      final resource = switch (dataSource.sourceType) {
        DataSourceType.asset => dataSource.package == null
            ? 'asset:///${dataSource.asset}'
            : 'asset:///packages/${dataSource.package}/${dataSource.asset}',
        DataSourceType.network || DataSourceType.file || DataSourceType.contentUri => dataSource.uri!,
      };

      if (dataSource.sourceType == DataSourceType.network && host.isNotEmpty) {
        _transports[textureId] = (host, prefersProxy);
      }

      await player.open(
        Media(resource, httpHeaders: dataSource.httpHeaders),
        play: false,
      );
      _watchTransport(textureId, player, dataSource);
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

  /// 把当前传输方式交给 mpv（[useProxy] 为 false 表示这一轮走直连）。
  ///
  /// 故意放在 [_applyCustomParameters] 之前：用户在「自定义参数」里显式写了
  /// `http-proxy=...` 时，以自己的设置为准。
  Future<void> _applyHttpProxy(NativePlayer native, {required bool useProxy}) async {
    final proxy = useProxy ? _availableProxy : null;
    if (proxy == null || proxy.isEmpty) return;
    try {
      await native.setProperty('http-proxy', proxy);
    } catch (_) {}
  }

  static String _mediaHost(String? uri) => Uri.tryParse(uri ?? '')?.host ?? '';

  /// 「开不出来就换另一条传输方式」的看门狗（仅限网络源）。
  ///
  /// 之前只在 `player.stream.error` 上挂监听做这件事，实测**这条路根本不会响**：
  /// mpv 打开片源失败时只写一条日志（`stream: Failed to open ...`）走 `stream.log`，
  /// 不发 native error 事件。于是片源打不开时既没有换路重试、也没有任何错误上报，
  /// 界面上就只剩一个永远转的圈（用户报的「点进去一直在加载」就是这个）。
  /// 改成看门狗：规定时间内没有等到 `initialized` 就先换路重试，
  /// 两条路都试过还是不行就明确报错，让界面能显示「播放失败 + 重试」。
  void _watchTransport(int textureId, Player player, DataSource dataSource) {
    if (dataSource.sourceType != DataSourceType.network) return;
    if (_transports[textureId] == null) return;
    _transportTimers.remove(textureId)?.cancel();
    _transportTimers[textureId] = Timer(_transportSwitchDelay, () => unawaited(_switchTransport(textureId, player, dataSource)));
  }

  /// 首帧前最多等多久就认为这条传输方式不行。正常片源初始化只要 1~4 秒。
  static const _transportSwitchDelay = Duration(seconds: 15);

  Future<void> _switchTransport(int textureId, Player player, DataSource dataSource) async {
    if (_completers[textureId]?.isCompleted ?? true) return;
    if (!identical(_players[textureId], player)) return;
    final transport = _transports[textureId];
    if (transport == null) return;
    final (host, useProxy) = transport;
    final alternateUsesProxy = !useProxy;
    final alternateProxy = alternateUsesProxy ? _availableProxy : null;
    // 换过两条路还是开不出来，或压根没有另一条路：明确报错，
    // 让界面能显示「播放失败 + 重试」，而不是一直转圈。
    if ((_transportSwitches[textureId] ?? 0) >= 2 || (alternateUsesProxy && alternateProxy == null)) {
      _transportTimers.remove(textureId)?.cancel();
      _hostUsesProxy.remove(host);
      _streamControllers[textureId]?.addError(
        PlatformException(code: '', message: 'stream open timed out: ${dataSource.uri}'),
      );
      return;
    }
    _transportSwitches[textureId] = (_transportSwitches[textureId] ?? 0) + 1;
    _transports[textureId] = (host, alternateUsesProxy);
    try {
      await (player.platform as NativePlayer).setProperty('http-proxy', alternateProxy ?? '');
      if ((_completers[textureId]?.isCompleted ?? true) || !identical(_players[textureId], player)) return;
      await player.open(Media(dataSource.uri!, httpHeaders: dataSource.httpHeaders), play: false);
    } catch (_) {}
    _watchTransport(textureId, player, dataSource);
  }

  /// 取「自定义参数」里的属性名，非 `key=value` 形式一律视为无效。
  static String? _parameterName(String parameter) {
    final separator = parameter.indexOf('=');
    if (separator <= 0) return null;
    return parameter.substring(0, separator).trim();
  }

  /// 网络源让解复用器多预读一些（默认只有十来秒）。
  ///
  /// 进度条上的「已缓冲」就是内核解复用缓存的位置：预读太少时那条几乎看不出余量，
  /// 卡住时也不好判断是「缓冲跟不上」还是别的问题；顺带也能多扛一点网络抖动。
  /// 只动这一项 —— `cache-secs` 在 `cache-on-disk=yes` 下默认就很大，不该去改小它。
  Future<void> _applyStreamTuning(NativePlayer native) async {
    try {
      await native.setProperty('demuxer-readahead-secs', '60');
    } catch (_) {}
  }

  /// libmpv 的 `gpu-api`：默认的 ANGLE（OpenGL ES 3.0）不支持 compute shader，
  /// 切到 Vulkan / D3D11 才有（这是收录 ArtCNN 的前置条件）。
  ///
  /// mpv 把它当成视频输出的初始化参数，晚于首帧再设不会生效，所以只在建播放器时写一次。
  Future<void> _applyGpuApi(NativePlayer native, AppSettings settings) async {
    final value = switch (settings.gpuApi) {
      MpvGpuApi.auto => null,
      MpvGpuApi.vulkan => 'vulkan',
      MpvGpuApi.d3d11 => 'd3d11',
    };
    if (value == null) return;
    try {
      await native.setProperty('gpu-api', value);
    } catch (error) {
      debugPrint('[player] gpu-api=$value failed: $error');
    }
  }

  Future<void> _applyCustomParameters(NativePlayer native, AppSettings settings) async {
    for (final parameter in settings.customParameters) {
      final name = _parameterName(parameter);
      if (name == null) continue;
      try {
        await native.setProperty(name, parameter.substring(parameter.indexOf('=') + 1).trim());
      } catch (_) {}
    }
  }

  /// 把 media_kit 无条件下发的「移动端省电」画质选项改回 mpv 的 high-quality 取向。
  ///
  /// media_kit 创建播放器时会写 `scale` / `dscale` = bilinear、`dither` = no、
  /// `correct-downscaling` / `linear-downscaling` / `sigmoid-upscaling` = no、
  /// `hdr-compute-peak` = no（见其 `real.dart` 的 `_create`）。这些在桌面端纯属降质：
  /// `dscale=bilinear` 降采样会糊且闪；`dither=no` 让渐变与 10bit 转 8bit 出色带；
  /// `sigmoid-upscaling=no` 会让 EWA 缩放器完全失去抗振铃（
  /// `scale-antiring` 对 vo_gpu 的极坐标 EWA 缩放器本来就不起作用）。
  ///
  /// 只在开启「超分辨率」时改，「关闭」档不碰，默认播放的开销与观感保持不变；
  /// 用户在「自定义参数」里显式写过的项一律以用户为准。
  ///
  /// 注意这些全程依赖「mpv 真的需要缩放」：`scaler-resizes-only` 默认开启，
  /// 不变形时并不会额外耗时，所以界面层必须把显示尺寸交给它（见 [setVideoOutputSize]），
  /// 否则这一组选项等于没开。
  Future<void> _applyDesktopQuality(NativePlayer native, AppSettings settings) async {
    final overridden = settings.customParameters.map(_parameterName).whereType<String>().toSet();
    const options = {
      'scale': 'ewa_lanczossharp',
      'scale-antiring': '0.6',
      'dscale': 'mitchell',
      'dither': 'fruit',
      'correct-downscaling': 'yes',
      'linear-downscaling': 'yes',
      'sigmoid-upscaling': 'yes',
      // mpv 默认关闭，而番剧的平坦渐变最容易出色带，值得为它付这点开销。
      'deband': 'yes',
      // 恢复 mpv 默认值：本应用的上下文是 GLES 3.0，mpv 会自行判定不可用而跳过。
      'hdr-compute-peak': 'auto',
    };
    for (final entry in options.entries) {
      if (overridden.contains(entry.key)) continue;
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
  }

  /// 应用「超分辨率」设置。
  ///
  /// [created] 为 true 表示刚新建的播放器（还没动过任何设置，不存在需要清理的旧方案）；
  /// 为 false 表示在**活着的播放器**上就地切档，必须把上一个档位留下的东西撤干净。
  Future<void> _applySuperResolution(NativePlayer native, AppSettings settings, {bool created = true}) async {
    final embed = settings.videoRenderer == VideoRenderer.mediacodecEmbed;
    final mode = settings.superResolutionMode;
    if (embed) return;
    if (mode == SuperResolutionMode.off) {
      // 「关闭」档就是 media_kit 的默认画质，新建时不该去动它。
      if (created) return;
      await _clearShaders(native);
      await _resetDesktopQuality(native, settings);
      return;
    }
    try {
      await _applyDesktopQuality(native, settings);
      if (mode == SuperResolutionMode.natural) {
        // 这一档只用缩放器（见 [_applyDesktopQuality]），不接着色器。
        if (!created) await _clearShaders(native);
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

  /// 清空着色器链（切回「关闭」或「自然放大」时用）。
  Future<void> _clearShaders(NativePlayer native) async {
    try {
      await native.command(['change-list', 'glsl-shaders', 'clear']);
    } catch (_) {}
  }

  /// 把 [_applyDesktopQuality] 改过的选项恢复成 media_kit 的默认值。
  ///
  /// 就地切回「关闭」档时必须做这一步，否则上一个档位留下的缩放器/抖动设置会一直生效。
  Future<void> _resetDesktopQuality(NativePlayer native, AppSettings settings) async {
    final overridden = settings.customParameters.map(_parameterName).whereType<String>().toSet();
    const options = {
      'scale': 'bilinear',
      'scale-antiring': '0',
      'dscale': 'bilinear',
      'dither': 'no',
      'correct-downscaling': 'no',
      'linear-downscaling': 'no',
      'sigmoid-upscaling': 'no',
      'deband': 'no',
      'hdr-compute-peak': 'no',
    };
    for (final entry in options.entries) {
      if (overridden.contains(entry.key)) continue;
      try {
        await native.setProperty(entry.key, entry.value);
      } catch (_) {}
    }
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
    if (_players[textureId] == null || _videoControllers[textureId] == null) return;
    final target = _targetSizeFor(textureId);
    if (_appliedSizes.containsKey(textureId) && _appliedSizes[textureId] == target) {
      _resizeRetryTimers.remove(textureId)?.cancel();
      _resizeRetryCounts.remove(textureId);
      return;
    }
    if (!_canResizeNow(textureId)) {
      // 现在改尺寸不安全（刚起播 / 在缓冲 / 着色器链刚换），过会儿再补。
      _scheduleResizeRetry(textureId);
      return;
    }
    unawaited(_applyOutputSize(textureId, target));
  }

  /// 目标输出尺寸；`null` 表示「跟随视频原始分辨率」（即不下发任何尺寸）。
  (int, int)? _targetSizeFor(int textureId) {
    final controller = _videoControllers[textureId];
    if (controller == null) return null;
    final state = controller.player.state;
    final videoWidth = state.width ?? 0;
    final videoHeight = state.height ?? 0;
    if (videoWidth < 1 || videoHeight < 1) return null;
    if (settings.superResolutionMode == SuperResolutionMode.off) return null;
    final target = _outputSizeFor(textureId, videoWidth, videoHeight);
    // 目标等于视频原始尺寸时不需要下发：那本来就是播放内核的默认状态。
    // 多下发一次只会白白重建一次渲染表面，而实测「先按放大倍数、再改回原尺寸」
    // 这种往返在增强档的着色器链路下会把播放直接搞崩。
    return target.$1 == videoWidth && target.$2 == videoHeight ? null : target;
  }

  /// 现在能不能改渲染尺寸？
  ///
  /// 实测（mpv 0.36 + media_kit_video 2.0.1 + ANGLE）：**改渲染尺寸必须避开重着色器链的编译**。
  /// 两件事撞在一起时 ANGLE 表面会被重建、mpv 的渲染上下文随即坏掉，日志里留下
  /// `mpv_render_context_render() not being called or stuck.`，之后画面永久停在转圈、
  /// 声音却照旧（渲染线程死了，音频线程不受影响）——用户看到的就是「卡死、没法操作」。
  /// 所以这里要求：正在播放、没在缓冲、已经稳定播放 1.5s 以上，且不在链切换后的冷却期。
  bool _canResizeNow(int textureId) {
    final player = _players[textureId];
    if (player == null) return false;
    final holdUntil = _resizeHoldUntil[textureId];
    if (holdUntil != null) {
      if (DateTime.now().isBefore(holdUntil)) return false;
      _resizeHoldUntil.remove(textureId);
    }
    final state = player.state;
    if (!state.playing || state.buffering) return false;
    final since = _playingSince[textureId];
    if (since == null) return false;
    return DateTime.now().difference(since) >= const Duration(milliseconds: 1500);
  }

  /// 改尺寸现在不安全，过 500ms 再看一次（最多 30s）。
  void _scheduleResizeRetry(int textureId) {
    if (_resizeRetryTimers.containsKey(textureId)) return;
    final attempt = (_resizeRetryCounts[textureId] ?? 0) + 1;
    _resizeRetryCounts[textureId] = attempt;
    if (attempt > 60) return;
    _resizeRetryTimers[textureId] = Timer(const Duration(milliseconds: 500), () {
      _resizeRetryTimers.remove(textureId);
      _refreshOutputSize(textureId);
    });
  }

  /// 在接下来的这段时间内不要改渲染尺寸（用于着色器链刚换上的编译期）。
  void _holdResizes(int textureId, [Duration duration = const Duration(seconds: 3)]) {
    _resizeHoldUntil[textureId] = DateTime.now().add(duration);
    _resizeRetryTimers.remove(textureId)?.cancel();
    _resizeRetryCounts.remove(textureId);
    // 冷却结束后主动重算一次，不依赖外部事件来触发。
    _resizeRetryTimers[textureId] = Timer(duration, () {
      _resizeRetryTimers.remove(textureId);
      _refreshOutputSize(textureId);
    });
  }

  /// 目标输出尺寸：按界面层给出的播放区域换算。
  ///
  /// 界面层还没报上区域时返回视频原始尺寸（即不下发任何尺寸），不做凭空的倍数猜测——
  /// 那样会让每次加载都多走一次「放大→改回」的往返，既白重建渲染表面又很危险。
  (int, int) _outputSizeFor(int textureId, int videoWidth, int videoHeight) {
    final area = _outputAreas[textureId];
    if (area == null || !area.$2 || area.$1.width < 1 || area.$1.height < 1) return (videoWidth, videoHeight);
    // 渲染尺寸要与视频宽高比一致，否则会把黑边烘进纹理；裁剪/拉伸模式按「铺满」算。
    final box = area.$1;
    final factor = (area.$3 ? math.max(box.width / videoWidth, box.height / videoHeight) : math.min(box.width / videoWidth, box.height / videoHeight)).clamp(1.0, 3.0);
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
    _resizeRetryTimers.remove(textureId)?.cancel();
    _resizeRetryCounts.remove(textureId);
    _appliedSizes[textureId] = target;
    try {
      await controller.setSize();
      if (target != null) await controller.setSize(width: target.$1, height: target.$2);
    } catch (_) {}
  }

  /// 等原生侧真的重建完渲染表面。
  ///
  /// media_kit 重建表面后会下发新的纹理 id，用它当「表面已就绪」的信号，
  /// 这样才能保证「改尺寸」和「换着色器链」在时间上真正错开。
  Future<void> _waitForTextureChange(VideoController controller, int? previous, Duration timeout) async {
    if (controller.id.value != previous) return;
    final completer = Completer<void>();
    void listener() {
      if (controller.id.value != previous && !completer.isCompleted) completer.complete();
    }

    controller.id.addListener(listener);
    try {
      await completer.future.timeout(timeout);
    } catch (_) {
      // 超时就不等了：宁可不改尺寸，也不能把链的切换无限推迟。
    } finally {
      controller.id.removeListener(listener);
    }
  }

  /// 兜底看门狗：渲染上下文万一还是坏了，通报界面层重载。
  ///
  /// 只用「在缓冲」判断不够：网络真卡时也会缓冲，那种情况不能动手。
  /// 缓冲区明明领先播放位置却一直不播，说明数据早就够了，卡的是画面输出。
  void _checkStall(int textureId) {
    final player = _players[textureId];
    if (player == null) return;
    final state = player.state;
    final ahead = state.buffer - state.position;
    if (!state.playing || !state.buffering || ahead < const Duration(seconds: 3)) {
      _stallSeconds[textureId] = 0;
      return;
    }
    final seconds = (_stallSeconds[textureId] ?? 0) + 2;
    _stallSeconds[textureId] = seconds;
    if (seconds < 6 || _stallRecovered[textureId] == true) return;
    _stallRecovered[textureId] = true;
    onVideoOutputStalled?.call();
  }

  /// 在活着的播放器上就地切换「超分辨率」档位（不重建播放器）。
  ///
  /// 以前的做法是「改设置 + 重建播放器」，那会让新实例的**重着色器链编译**与
  /// **渲染表面重建**挤在同一瞬间，实测会把 mpv 的渲染上下文搞坏；而且重建过程本身
  /// 必然出现一次转圈。就地切换后两件事都被拆开：先让尺寸落地（此时链还是旧的、
  /// 管线是热的、不涉及编译），确认表面真的重建完（纹理 id 变化）再换链，
  /// 换完链再压住尺寸几秒不让它被打扰。
  Future<void> _switchSuperResolution() async {
    for (final textureId in _players.keys.toList(growable: false)) {
      final controller = _videoControllers[textureId];
      final native = _players[textureId]?.platform;
      if (controller == null || native is! NativePlayer) continue;
      _beginSwitchingQuality(textureId);
      try {
        final target = _targetSizeFor(textureId);
        if (_appliedSizes[textureId] != target && _canResizeNow(textureId)) {
          _holdResizes(textureId);
          final previous = controller.id.value;
          await _applyOutputSize(textureId, target);
          await _waitForTextureChange(controller, previous, const Duration(seconds: 2));
        }
        // 尺寸没变（或现在不适合改尺寸）：直接换链，尺寸留给 _refreshOutputSize
        // 在播放稳下来之后自己补上。
        await _applySuperResolution(native, settings, created: false);
        _holdResizes(textureId);
      } finally {
        // 没进缓冲就说明没有重编译（或已瞬间完成），提示条可以立刻收。
        if (!(_players[textureId]?.state.buffering ?? false)) _endSwitchingQuality(textureId);
      }
    }
  }

  /// 标记「正在改画质」：这段时间压掉内核上报的缓冲事件，并让界面显示提示条。
  ///
  /// [timeout] 是兜底：万一内核没有上报缓冲结束，也不会让提示条一直挂着。
  void _beginSwitchingQuality(int textureId, [Duration timeout = const Duration(seconds: 20)]) {
    _switchingQuality[textureId] = true;
    switchingSuperResolution.value = true;
    _switchingTimers.remove(textureId)?.cancel();
    _switchingTimers[textureId] = Timer(timeout, () => _endSwitchingQuality(textureId));
  }

  void _endSwitchingQuality(int textureId) {
    _switchingTimers.remove(textureId)?.cancel();
    if (_switchingQuality.remove(textureId) != null) {
      switchingSuperResolution.value = _switchingQuality.isNotEmpty;
    }
  }

  /// 就地切换「超分辨率」档位（供播放页调用）。
  ///
  /// 返回 false 表示当前平台实现不是本类（例如 Android 上用的是官方插件），
  /// 调用方应当退回「重建播放器」的老做法。
  static Future<bool> applySuperResolutionMode(SuperResolutionMode mode) async {
    final platform = VideoPlayerPlatform.instance;
    if (platform is! ConfiguredMediaKitVideoPlayer) return false;
    // 先让本类的设定与调用方一致，避免依赖设置流的更新时机。
    settings = settings.copyWith(superResolutionMode: mode);
    if (platform._players.isEmpty) return true;
    await platform._switchSuperResolution();
    return true;
  }

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) => Future.value();

  @override
  Future<void> setWebOptions(int textureId, VideoPlayerWebOptions options) => Future.value();

  void _initialize(int textureId) {
    // 不能用「订阅列表非空」当作「已初始化」的标志：平台层自己也会往同一个列表里挂
    // 监听（见 `create()` 里用于重算输出尺寸的 `videoParams` 监听）。一旦那样，本方法
    // 会直接返回，`initialized` 事件永远发不出去 —— 表现为播放页一直转圈、不自动播放。
    // 改用「初始化完成时才 complete 的 Completer」判断。
    if (_completers[textureId]?.isCompleted ?? true) return;

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
          // 开了张：这次用的传输方式确实可行，记下来供同主机的后续片源直接用。
          _transportTimers.remove(textureId)?.cancel();
          final transport = _transports[textureId];
          if (transport != null) _hostUsesProxy[transport.$1] = transport.$2;
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
        if (!isActive()) return;
        // 改画质要重新编译着色器链（重档位好几秒），内核会短暂进入缓冲状态：
        // 那不是网络加载，也不是卡死（音频一直在放），上报出去界面就会弹个转圈。
        if (event && (_switchingQuality[textureId] ?? false)) return;
        streamController.add(
          VideoEvent(eventType: event ? VideoEventType.bufferingStart : VideoEventType.bufferingEnd),
        );
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
