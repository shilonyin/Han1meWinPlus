import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/configured_media_kit_video_player.dart';
import '../../core/playback_speed_policy.dart';
import '../../core/platform_service.dart';
import '../../core/settings.dart';
import '../../core/video_player_shutdown.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import 'video_player_controls.dart';

class VideoPlayerSurface extends ConsumerStatefulWidget {
  const VideoPlayerSurface({required this.controller, required this.quality, required this.video, required this.fullscreen, required this.onFullscreen, required this.onQualitySelected, required this.onSuperResolutionSelected, this.onBack, this.onHome, this.onNext, this.onEpisodeSelected, this.keyframes = const [], this.onKeyframes, this.onAddKeyframe, super.key});
  final ValueListenable<VideoPlayerController?> controller;
  final ValueListenable<String?> quality;
  final VideoDetail video;
  final bool fullscreen;
  final Future<void> Function() onFullscreen;
  final ValueChanged<VideoSource> onQualitySelected;
  final ValueChanged<SuperResolutionMode> onSuperResolutionSelected;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onNext;
  final ValueChanged<VideoCard>? onEpisodeSelected;
  final List<int> keyframes;
  final VoidCallback? onKeyframes;
  final VoidCallback? onAddKeyframe;

  @override
  ConsumerState<VideoPlayerSurface> createState() => _VideoPlayerSurfaceState();
}

class _VideoPlayerSurfaceState extends ConsumerState<VideoPlayerSurface> {
  bool _showControls = true;
  bool _locked = false;
  double? _dragStartX;
  double? _dragStartY;
  _DragDirection? _dragDirection;
  Duration? _seekStartPosition;
  double _brightness = 1;
  double _volume = 1;
  _Adjustment? _adjustment;
  Timer? _hideTimer;
  double? _speedBeforeLongPress;
  /// 鼠标是否停在播放区域里（含底部控制按钮所在的区域）。
  /// 桌面端只要鼠标在画面里就保持控制条显示，移到窗口外才按超时隐藏。
  bool _pointerInside = false;

  @override
  void initState() {
    super.initState();
    _readLevels();
    unawaited(PlaybackSpeedPolicy.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartTimer());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    super.dispose();
  }

  Future<void> _readLevels() async {
    final levels = await Future.wait([PlatformService.screenBrightness(), PlatformService.volume()]);
    if (mounted) setState(() { _brightness = levels[0]; _volume = levels[1]; });
  }

  void _restartTimer() {
    _hideTimer?.cancel();
    // 鼠标还在画面上（包括停在控制按钮附近）时不安排隐藏，避免刚要去点按钮就消失
    if (!_showControls || _locked || _pointerInside) return;
    final seconds = ref.read(settingsProvider).valueOrNull?.playerControlsTimeoutSeconds ?? 4;
    _hideTimer = Timer(Duration(seconds: seconds), () { if (mounted) setState(() => _showControls = false); });
  }

  /// 鼠标进入/离开播放区域：进入时立即恢复控制条并暂停隐藏计时，离开后重新开始计时。
  void _setPointerInside(bool inside) {
    if (_pointerInside == inside) return;
    _pointerInside = inside;
    if (inside) {
      _holdControls();
      return;
    }
    _restartTimer();
  }

  /// 鼠标在画面上移动（或停在控制按钮附近）时保持控制条显示，已隐藏则重新显示。
  void _holdControls() {
    _hideTimer?.cancel();
    if (!_showControls && !_locked) setState(() => _showControls = true);
  }

  void _toggleControls() { if (_locked) return; setState(() => _showControls = !_showControls); _restartTimer(); }
  void _togglePlayback() {
    final controller = widget.controller.value;
    if (controller == null) return;
    controller.value.isPlaying ? controller.pause() : controller.play();
    _restartTimer();
  }

  void _longPress(bool active) {
    final controller = widget.controller.value;
    if (active) {
      if (controller == null || !controller.value.isInitialized || _speedBeforeLongPress != null) return;
      final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
      _speedBeforeLongPress = controller.value.playbackSpeed;
      final speed = PlaybackSpeedPolicy.longPressSpeed(
        settings,
        isThreeDimensional: PlaybackSpeedPolicy.isThreeDimensional(widget.video.genre, widget.video.title),
      );
      unawaited(_applySpeed(controller, speed));
      setState(() => _adjustment = _Adjustment.speed(speed));
      return;
    }
    if (controller == null) {
      _speedBeforeLongPress = null;
      return;
    }
    final speed = _speedBeforeLongPress ?? controller.value.playbackSpeed;
    _speedBeforeLongPress = null;
    if (!controller.value.isInitialized) return;
    unawaited(_applySpeed(controller, speed));
    setState(() => _adjustment = null);
  }

  Future<void> _applySpeed(VideoPlayerController controller, double speed) async {
    try {
      if ((controller.value.playbackSpeed - speed).abs() > .001) {
        await controller.setPlaybackSpeed(speed);
      }
    } catch (_) {}
  }

  void _dragStart(DragStartDetails details) {
    _dragStartX = details.localPosition.dx;
    _dragStartY = details.localPosition.dy;
    _dragDirection = null;
    _seekStartPosition = widget.controller.value?.value.position;
  }

  void _dragUpdate(DragUpdateDetails details) {
    final startX = _dragStartX;
    if (startX == null || _locked) return;
    final controller = widget.controller.value;
    if (controller == null) return;
    final size = context.size ?? MediaQuery.sizeOf(context);
    final direction = _dragDirection ??= details.delta.dx.abs() > details.delta.dy.abs() ? _DragDirection.horizontal : _DragDirection.vertical;
    if (direction == _DragDirection.horizontal) {
      final duration = controller.value.duration;
      final sensitivity = ref.read(settingsProvider).valueOrNull?.seekSensitivity ?? .35;
      if (duration != Duration.zero) {
        final position = (controller.value.position.inMilliseconds + details.delta.dx / size.width * duration.inMilliseconds * sensitivity).round().clamp(0, duration.inMilliseconds).toInt();
        controller.seekTo(Duration(milliseconds: position));
        final startMs = _seekStartPosition?.inMilliseconds ?? position;
        setState(() => _adjustment = _Adjustment.seek(position - startMs, Duration(milliseconds: position), duration));
      }
      return;
    }
    final value = (startX < size.width / 2 ? _brightness : _volume) - details.delta.dy / size.height;
    if (startX < size.width / 2) { _brightness = value.clamp(0.01, 1).toDouble(); PlatformService.setScreenBrightness(_brightness); setState(() => _adjustment = _Adjustment.brightness(_brightness)); }
    else {
      _volume = value.clamp(0, 1).toDouble();
      // 桌面端的平台音量接口是空实现，直接改播放器音量才有效
      if (Platform.isAndroid || Platform.isIOS) {
        PlatformService.setVolume(_volume);
      } else {
        unawaited(_applyVolume(controller, _volume));
      }
      setState(() => _adjustment = _Adjustment.volume(_volume));
    }
  }

  Future<void> _applyVolume(VideoPlayerController controller, double volume) async {
    try {
      if ((controller.value.volume - volume).abs() > .001) await controller.setVolume(volume);
    } catch (_) {}
  }
  void _dragEnd(DragEndDetails details) { _dragStartX = null; _dragStartY = null; _dragDirection = null; _seekStartPosition = null; Future<void>.delayed(const Duration(milliseconds: 700), () { if (mounted) setState(() => _adjustment = null); }); }

  Future<void> _enterPictureInPicture(VideoPlayerController controller) async {
    var entered = false;
    try {
      entered = await PlatformService.enterPictureInPicture();
    } catch (_) {}
    if (entered) VideoPlayerShutdown.pipActive = controller;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ValueListenableBuilder<VideoPlayerController?>(
      valueListenable: widget.controller,
      builder: (context, activeController, _) {
        final controller = activeController;
        if (controller == null || !controller.value.isInitialized) {
          return const Center(child: M3ELoadingIndicator(color: Colors.white));
        }
        return MouseRegion(
          // 悬停在画面（包括底部控制条、顶部操作条）上时保持显示，移出去才重新计时
          onEnter: (_) => _setPointerInside(true),
          onHover: (_) => _holdControls(),
          onExit: (_) => _setPointerInside(false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _toggleControls,
            onDoubleTap: _togglePlayback,
            onLongPressStart: (_) => _longPress(true),
            onLongPressEnd: (_) => _longPress(false),
            onPanStart: _dragStart,
            onPanUpdate: _dragUpdate,
            onPanEnd: _dragEnd,
            child: Stack(fit: StackFit.expand, children: [
              const ColoredBox(color: Colors.black),
              _VideoViewport(controller: controller),
              ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) => value.isBuffering ? const Center(child: M3ELoadingIndicator(color: Colors.white)) : const SizedBox.shrink()),
              ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) => _showControls && !_locked ? VideoPlayerControls(controller: controller, fullscreen: widget.fullscreen, onFullscreen: widget.onFullscreen, onInteraction: _restartTimer, video: widget.video, quality: widget.quality, onQualitySelected: widget.onQualitySelected, onSuperResolutionSelected: widget.onSuperResolutionSelected, onNext: widget.onNext, onEpisodeSelected: widget.onEpisodeSelected) : const SizedBox.shrink()),
              if (_locked) Align(alignment: Alignment.centerRight, child: IconButton(color: Colors.white, tooltip: l10n.unlockControls, onPressed: () { setState(() => _locked = false); _restartTimer(); }, icon: const Icon(Icons.lock))),
              // 顶部：返回 / 标题 / 次要操作；底部：进度 + 播放控制，和参考实现一致
              if (_showControls && !_locked)
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _PlayerTopBar(
                    controller: controller,
                    video: widget.video,
                    quality: widget.quality,
                    fullscreen: widget.fullscreen,
                    onInteraction: _restartTimer,
                    onBack: widget.onBack,
                    onHome: widget.fullscreen ? null : widget.onHome,
                    onQualitySelected: widget.onQualitySelected,
                    onSuperResolutionSelected: widget.onSuperResolutionSelected,
                    onPictureInPicture: () => _enterPictureInPicture(controller),
                    onKeyframes: widget.fullscreen ? widget.onKeyframes : null,
                    onAddKeyframe: widget.fullscreen ? widget.onAddKeyframe : null,
                  ),
                ),
              if (_showControls && widget.fullscreen && !_locked) Align(alignment: Alignment.centerRight, child: IconButton(color: Colors.white, tooltip: l10n.lockControls, onPressed: () => setState(() => _locked = true), icon: const Icon(Icons.lock_open_outlined))),
              if (widget.fullscreen && widget.keyframes.isNotEmpty) _KeyframeCountdown(controller: controller, keyframes: widget.keyframes),
              if (_adjustment != null)
                switch (_adjustment!.kind) {
                  _AdjustmentKind.brightness => Positioned(top: 72, left: 16, child: _AdjustmentHud(adjustment: _adjustment!)),
                  _AdjustmentKind.volume => Positioned(top: 72, right: 16, child: _AdjustmentHud(adjustment: _adjustment!)),
                  _ => Positioned(top: 72, left: 0, right: 0, child: Center(child: _AdjustmentHud(adjustment: _adjustment!))),
                },
            ]),
          ),
        );
      },
    );
  }
}

/// 播放器顶部操作条：返回 / 回主页、标题跑马灯，以及跳转、画中画、更多等次要入口。
class _PlayerTopBar extends StatelessWidget {
  const _PlayerTopBar({required this.controller, required this.video, required this.quality, required this.fullscreen, required this.onInteraction, required this.onQualitySelected, required this.onSuperResolutionSelected, required this.onPictureInPicture, this.onBack, this.onHome, this.onKeyframes, this.onAddKeyframe});

  final VideoPlayerController controller;
  final VideoDetail video;
  final ValueListenable<String?> quality;
  final bool fullscreen;
  final VoidCallback onInteraction;
  final ValueChanged<VideoSource> onQualitySelected;
  final ValueChanged<SuperResolutionMode> onSuperResolutionSelected;
  final VoidCallback onPictureInPicture;
  final VoidCallback? onBack;
  final VoidCallback? onHome;
  final VoidCallback? onKeyframes;
  final VoidCallback? onAddKeyframe;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black87, Colors.transparent])),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(4, 4, 4, 20),
        child: Row(
          children: [
            if (onBack != null) IconButton(color: Colors.white, visualDensity: VisualDensity.compact, tooltip: MaterialLocalizations.of(context).backButtonTooltip, onPressed: onBack, icon: const Icon(Icons.arrow_back)),
            if (onHome != null) IconButton(color: Colors.white, visualDensity: VisualDensity.compact, tooltip: l10n.home, onPressed: onHome, icon: const Icon(Icons.home_outlined)),
            const SizedBox(width: 6),
            Expanded(child: _MarqueeTitle(title: video.title)),
            if (Platform.isAndroid) IconButton(color: Colors.white, visualDensity: VisualDensity.compact, tooltip: l10n.pictureInPicture, onPressed: onPictureInPicture, icon: const Icon(Icons.picture_in_picture_alt_outlined)),
            if (onKeyframes != null)
              Tooltip(
                message: l10n.longPressAddKeyframe,
                child: GestureDetector(
                  onTap: onKeyframes,
                  onLongPress: onAddKeyframe,
                  child: const Padding(padding: EdgeInsets.all(12), child: Text('🥵', style: TextStyle(fontSize: 22))),
                ),
              ),
            if (fullscreen)
              VideoPlayerFullscreenMoreMenu(sources: video.sources, quality: quality)
            else
              VideoPlayerPortraitMoreMenu(controller: controller, video: video, quality: quality, onQualitySelected: onQualitySelected, onSuperResolutionSelected: onSuperResolutionSelected),
          ],
        ),
      ),
    );
  }
}

/// 窗口模式（非全屏）下常驻在播放器左上角的导航按钮：返回上一级 + 回到主页。
///
/// 播放中控制栏会自动隐藏，若导航按钮跟着一起隐藏，用户就没法中途退出播放页，
/// 所以窗口模式下始终显示；全屏模式仍沿用「跟随控制栏」的原有行为。
class PlayerNavCapsule extends StatelessWidget {
  const PlayerNavCapsule({required this.onBack, this.onHome, super.key});

  final VoidCallback onBack;
  final VoidCallback? onHome;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.black.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(999),
        clipBehavior: Clip.antiAlias,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              color: Colors.white,
              visualDensity: VisualDensity.compact,
              tooltip: MaterialLocalizations.of(context).backButtonTooltip,
              onPressed: onBack,
              icon: const Icon(Icons.arrow_back),
            ),
            if (onHome != null) ...[
              SizedBox(height: 18, child: VerticalDivider(width: 1, thickness: 1, color: Colors.white.withValues(alpha: 0.24))),
              IconButton(
                color: Colors.white,
                visualDensity: VisualDensity.compact,
                tooltip: AppLocalizations.of(context)!.home,
                onPressed: onHome,
                icon: const Icon(Icons.home_outlined),
              ),
            ],
          ],
        ),
      );
}

class _VideoViewport extends ConsumerWidget {
  const _VideoViewport({required this.controller});
  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final aspect = settings?.videoAspectRatio ?? VideoAspectRatio.auto;
    final enhance = (settings?.superResolutionMode ?? SuperResolutionMode.off) != SuperResolutionMode.off;
    final ratio = controller.value.aspectRatio == 0 ? 16 / 9 : controller.value.aspectRatio;
    return LayoutBuilder(builder: (context, constraints) {
      final dpr = MediaQuery.devicePixelRatioOf(context);
      final fill = aspect == VideoAspectRatio.crop || aspect == VideoAspectRatio.stretch;
      return VideoOutputArea(
        enabled: enhance,
        fill: fill,
        size: Size(constraints.maxWidth.isFinite ? constraints.maxWidth * dpr : 0, constraints.maxHeight.isFinite ? constraints.maxHeight * dpr : 0),
        child: switch (aspect) {
        VideoAspectRatio.auto => Center(child: AspectRatio(aspectRatio: ratio, child: VideoPlayer(controller))),
        VideoAspectRatio.ratio4x3 => Center(child: AspectRatio(aspectRatio: 4 / 3, child: FittedBox(fit: BoxFit.contain, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller))))),
        VideoAspectRatio.crop => Positioned.fill(child: FittedBox(fit: BoxFit.cover, clipBehavior: Clip.hardEdge, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller)))),
        VideoAspectRatio.stretch => Positioned.fill(child: FittedBox(fit: BoxFit.fill, child: SizedBox(width: ratio * 1000, height: 1000, child: VideoPlayer(controller)))),
        },
      );
    });
  }
}

class _MarqueeTitle extends StatefulWidget {
  const _MarqueeTitle({required this.title});
  final String title;

  @override
  State<_MarqueeTitle> createState() => _MarqueeTitleState();
}

class _MarqueeTitleState extends State<_MarqueeTitle> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: Duration(milliseconds: (widget.title.length * 85).clamp(4000, 16000).toInt()))..repeat();
  }

  @override
  void didUpdateWidget(_MarqueeTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.title == widget.title) return;
    _controller
      ..duration = Duration(milliseconds: (widget.title.length * 85).clamp(4000, 16000).toInt())
      ..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, constraints) {
        final style = const TextStyle(color: Colors.white, fontWeight: FontWeight.w600);
        final painter = TextPainter(text: TextSpan(text: widget.title, style: style), maxLines: 1, textDirection: TextDirection.ltr)..layout();
        final width = painter.width;
        if (width <= constraints.maxWidth) return Text(widget.title, maxLines: 1, style: style);
        final distance = width - constraints.maxWidth + 24;
        return ClipRect(child: AnimatedBuilder(animation: _controller, builder: (context, child) => Transform.translate(offset: Offset(-distance * _controller.value, 0), child: child), child: Text(widget.title, maxLines: 1, style: style)));
      });
}

enum _DragDirection { horizontal, vertical }
enum _AdjustmentKind { brightness, volume, speed, seek }
class _Adjustment {
  const _Adjustment(this.kind, this.value, {this.delta, this.position, this.duration});
  factory _Adjustment.brightness(double value) => _Adjustment(_AdjustmentKind.brightness, value);
  factory _Adjustment.volume(double value) => _Adjustment(_AdjustmentKind.volume, value);
  factory _Adjustment.speed(double value) => _Adjustment(_AdjustmentKind.speed, value);
  factory _Adjustment.seek(int delta, Duration position, Duration duration) => _Adjustment(_AdjustmentKind.seek, 0, delta: delta, position: position, duration: duration);
  final _AdjustmentKind kind;
  final double value;
  final int? delta;
  final Duration? position;
  final Duration? duration;
}

class _AdjustmentHud extends StatelessWidget {
  const _AdjustmentHud({required this.adjustment});
  final _Adjustment adjustment;

  @override
  Widget build(BuildContext context) => switch (adjustment.kind) {
        _AdjustmentKind.seek => _seekCard(),
        _AdjustmentKind.speed => _pill(Text('${adjustment.value}x', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
        _ => _levelCard(),
      };

  Widget _pill(Widget child) => DecoratedBox(
        decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(999)),
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14), child: child),
      );

  Widget _seekCard() {
    final delta = adjustment.delta ?? 0;
    final position = adjustment.position ?? Duration.zero;
    final duration = adjustment.duration ?? Duration.zero;
    return _pill(Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(delta >= 0 ? Icons.fast_forward : Icons.fast_rewind, color: Colors.white, size: 28),
      const SizedBox(width: 12),
      Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        Text('${delta >= 0 ? '+' : '-'}${_formatDuration(Duration(milliseconds: delta.abs()))}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        Text('${_formatDuration(position)}/${_formatDuration(duration)}', style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ]),
    ]));
  }

  Widget _levelCard() {
    final brightness = adjustment.kind == _AdjustmentKind.brightness;
    final level = adjustment.value.clamp(0, 1).toDouble();
    return _pill(Row(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        width: 180,
        height: 56,
        child: IgnorePointer(
          child: M3ESlider(
            value: level,
            onChanged: (_) {},
            icon: Icon(brightness ? Icons.brightness_6 : Icons.volume_up, size: 20),
            trailingIcon: false,
            decoration: M3ESliderDecoration(
              trackHeight: 44,
              trackCornerRadius: 22,
              thumbWidth: 6,
              thumbHeight: 56,
              trackIconSize: 20,
              trackIconActiveColor: Colors.white,
              trackIconInactiveColor: Colors.white70,
              colors: M3ESliderColors(
                thumbColor: Colors.white,
                activeTrackColor: Colors.white,
                inactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                disabledThumbColor: Colors.white,
                disabledActiveTrackColor: Colors.white,
                disabledInactiveTrackColor: Colors.white.withValues(alpha: 0.25),
                activeTickColor: Colors.transparent,
                inactiveTickColor: Colors.transparent,
                disabledActiveTickColor: Colors.transparent,
                disabledInactiveTickColor: Colors.transparent,
              ),
            ),
          ),
        ),
      ),
      const SizedBox(width: 12),
      Text('${(level * 100).round()}%', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
    ]));
  }
}

class _KeyframeCountdown extends StatelessWidget {
  const _KeyframeCountdown({required this.controller, required this.keyframes});
  final VideoPlayerController controller;
  final List<int> keyframes;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          final next = keyframes.where((item) => item >= value.position.inMilliseconds).firstOrNull;
          final remaining = next == null ? null : next - value.position.inMilliseconds;
          if (remaining == null || remaining > 10000) return const SizedBox.shrink();
          return Positioned(left: 16, top: 60, child: DecoratedBox(decoration: BoxDecoration(color: Colors.black54, borderRadius: BorderRadius.circular(6)), child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), child: Text(AppLocalizations.of(context)!.keyframeCountdown((remaining / 1000).toStringAsFixed(1)), style: const TextStyle(color: Colors.white)))));
        },
      );
}

String _formatDuration(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours > 0 ? '${duration.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
