import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/cast_receiver.dart';
import '../../core/dlna_media_renderer.dart';
import '../../core/video_player_shutdown.dart';

/// 投屏接收页：手机投过来的片在这里播。
///
/// 播放器走的是应用现有的 video_player 链路（桌面端即 media_kit / libmpv），
/// 所以超分辨率之类的播放器设置同样生效；这一页只负责把它接到 DLNA 指令上。
class CastReceiverPage extends StatefulWidget {
  const CastReceiverPage({super.key, this.item});

  /// 由路由带进来的首条推送；为空时用 [CastReceiver.pending]。
  final CastMediaItem? item;

  @override
  State<CastReceiverPage> createState() => _CastReceiverPageState();
}

class _CastReceiverPageState extends State<CastReceiverPage> implements CastPlaybackTarget {
  VideoPlayerController? _controller;
  CastMediaItem? _loaded;
  var _loading = false;
  Object? _error;
  var _volume = 100.0;

  @override
  void initState() {
    super.initState();
    CastReceiver.instance.attach(this);
    CastReceiver.instance.pageOpen = true;
    CastReceiver.instance.incoming.addListener(_onIncoming);
    final item = widget.item ?? CastReceiver.instance.pending;
    if (item != null) unawaited(_load(item));
  }

  @override
  void dispose() {
    CastReceiver.instance.incoming.removeListener(_onIncoming);
    CastReceiver.instance.detach(this);
    CastReceiver.instance.pageOpen = false;
    final controller = _controller;
    _controller = null;
    if (controller != null) unawaited(_release(controller));
    super.dispose();
  }

  /// 投屏途中手机换了片：同一页里直接换源，不再 push 一层路由。
  void _onIncoming() {
    final item = CastReceiver.instance.incoming.value;
    if (item == null || item == _loaded) return;
    unawaited(_load(item));
  }

  Future<void> _load(CastMediaItem item) async {
    final previous = _controller;
    _controller = null;
    if (previous != null) await _release(previous);
    if (!mounted) return;
    setState(() {
      _loaded = item;
      _loading = true;
      _error = null;
    });
    final controller = VideoPlayerController.networkUrl(Uri.parse(item.url));
    VideoPlayerShutdown.track(controller);
    try {
      await controller.initialize();
      await controller.setVolume(_volume / 100);
      await controller.play();
    } catch (error) {
      await _release(controller);
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error;
      });
      return;
    }
    if (!mounted) {
      await _release(controller);
      return;
    }
    controller.addListener(_onControllerUpdated);
    _controller = controller;
    setState(() => _loading = false);
  }

  Future<void> _release(VideoPlayerController controller) async {
    controller.removeListener(_onControllerUpdated);
    VideoPlayerShutdown.untrack(controller);
    try {
      await controller.dispose();
    } catch (_) {}
  }

  void _onControllerUpdated() {
    if (mounted) setState(() {});
  }

  @override
  Future<void> load(CastMediaItem item) => _load(item);

  @override
  Future<void> play() async => _controller?.play();

  @override
  Future<void> pause() async => _controller?.pause();

  @override
  Future<void> stop() async {
    final controller = _controller;
    if (controller == null) return;
    await controller.pause();
    await controller.seekTo(Duration.zero);
  }

  @override
  Future<void> seek(Duration position) async => _controller?.seekTo(position);

  @override
  Future<void> setVolume(int volume) async {
    _volume = volume.clamp(0, 100).toDouble();
    await _controller?.setVolume(_volume / 100);
    if (mounted) setState(() {});
  }

  @override
  Future<void> setMuted(bool muted) async {
    await _controller?.setVolume(muted ? 0 : _volume / 100);
  }

  @override
  CastPlaybackState get state {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return const CastPlaybackState();
    return CastPlaybackState(
      position: controller.value.position,
      duration: controller.value.duration,
      playing: controller.value.isPlaying,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final controller = _controller;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: Text(_loaded?.title ?? l10n.dlnaReceiver),
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            tooltip: l10n.castDisconnect,
            icon: const Icon(Icons.cast_connected),
            onPressed: () {
              CastReceiver.instance.incoming.value = null;
              if (mounted) Navigator.pop(context);
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: Center(child: _buildStage(l10n))),
          if (controller != null && controller.value.isInitialized) _buildControls(controller),
        ],
      ),
    );
  }

  Widget _buildStage(AppLocalizations l10n) {
    final controller = _controller;
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white70, size: 48),
            const SizedBox(height: 12),
            Text(l10n.castLoadFailed('$_error'), style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
          ],
        ),
      );
    }
    if (controller == null) {
      return Text(
        _loading ? l10n.castLoading : l10n.castWaiting,
        style: const TextStyle(color: Colors.white70),
      );
    }
    if (!controller.value.isInitialized) {
      return const CircularProgressIndicator();
    }
    return AspectRatio(
      aspectRatio: controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio,
      child: VideoPlayer(controller),
    );
  }

  Widget _buildControls(VideoPlayerController controller) {
    final duration = controller.value.duration;
    final position = controller.value.position;
    final max = duration.inMilliseconds <= 0 ? 1.0 : duration.inMilliseconds.toDouble();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(controller.value.isPlaying ? Icons.pause : Icons.play_arrow),
                onPressed: () => controller.value.isPlaying ? unawaited(pause()) : unawaited(play()),
              ),
              Expanded(
                child: Slider(
                  value: position.inMilliseconds.clamp(0, max.round()).toDouble(),
                  max: max,
                  onChanged: (value) => unawaited(seek(Duration(milliseconds: value.round()))),
                ),
              ),
              Text('${_clock(position)} / ${_clock(duration)}', style: const TextStyle(color: Colors.white70)),
            ],
          ),
          Row(
            children: [
              const Icon(Icons.volume_up, color: Colors.white70),
              Expanded(
                child: Slider(
                  value: _volume,
                  max: 100,
                  divisions: 20,
                  label: '${_volume.round()}',
                  onChanged: (value) => unawaited(setVolume(value.round())),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _clock(Duration duration) {
    final total = duration.inSeconds;
    final hours = total ~/ 3600;
    final minutes = (total % 3600) ~/ 60;
    final seconds = total % 60;
    final mm = minutes.toString().padLeft(2, '0');
    final ss = seconds.toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$mm:$ss' : '$mm:$ss';
  }
}
