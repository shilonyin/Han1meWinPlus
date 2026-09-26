import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import 'dlna_media_renderer.dart';
import 'window_chrome.dart';

/// 投屏播放页登记给接收端的播放能力。
///
/// 接收端只懂协议，真正的播放由打开着的投屏页来做；页面关掉后这些调用会被忽略。
abstract class CastPlaybackTarget {
  Future<void> load(CastMediaItem item);
  Future<void> play();
  Future<void> pause();
  Future<void> stop();
  Future<void> seek(Duration position);
  Future<void> setVolume(int volume);
  Future<void> setMuted(bool muted);

  /// 真实进度（给 SOAP 的 GetPositionInfo / GetMediaInfo 回填）。
  CastPlaybackState get state;
}

/// DLNA 接收端的全局入口：管 renderer 的生命周期，并把指令转给当前投屏页。
class CastReceiver implements CastRendererDelegate {
  CastReceiver._();

  static final CastReceiver instance = CastReceiver._();

  DlnaMediaRenderer? _renderer;
  CastPlaybackTarget? _target;
  CastMediaItem? _pending;

  /// 最近一次推送（手机端 SetAVTransportURI），界面层据此打开投屏页。
  final ValueNotifier<CastMediaItem?> incoming = ValueNotifier(null);

  /// 接收端是否在跑，供设置页显示状态。
  final ValueNotifier<bool> running = ValueNotifier(false);

  /// 投屏页是否已经打开：避免每次推送都重复 push 路由。
  var pageOpen = false;

  /// 接收端只对桌面端有意义（手机端本来就是投屏的发起方）。
  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  CastMediaItem? get pending => _pending;
  String get location => _renderer?.location ?? '';
  List<String> get addresses => _renderer?.addresses ?? const <String>[];

  void attach(CastPlaybackTarget target) => _target = target;

  void detach(CastPlaybackTarget target) {
    if (identical(_target, target)) _target = null;
  }

  /// 开关接收端。开不通（端口被占等）不抛，状态留在 [running] 里。
  Future<void> setEnabled(bool enabled) async {
    if (!enabled || !isSupported) {
      await _renderer?.stop();
      running.value = false;
      return;
    }
    if (_renderer?.isRunning == true) return;
    final renderer = _renderer ??= DlnaMediaRenderer(
      deviceName: 'Han1meWinPlus (${Platform.localHostname})',
      delegate: this,
    );
    await renderer.start();
    running.value = renderer.isRunning;
    if (!renderer.isRunning) debugPrint('[cast] renderer start failed: ${renderer.status.detail}');
  }

  @override
  void onSetMedia(CastMediaItem item) {
    _pending = item;
    // 手机推片时窗口可能收在托盘里，先把它拉回来。
    unawaited(WindowChrome.reveal());
    incoming.value = item;
  }

  @override
  void onPlay() => unawaited(_target?.play());

  @override
  void onPause() => unawaited(_target?.pause());

  @override
  void onStop() => unawaited(_target?.stop());

  @override
  void onSeek(Duration position) => unawaited(_target?.seek(position));

  @override
  void onVolume(int volume) => unawaited(_target?.setVolume(volume));

  @override
  void onMute(bool muted) => unawaited(_target?.setMuted(muted));

  @override
  CastPlaybackState get playbackState => _target?.state ?? const CastPlaybackState();
}
