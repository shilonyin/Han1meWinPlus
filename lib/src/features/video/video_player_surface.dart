import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
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

/// 滚轮调音量的单次步长：一个滚轮刻度 = 5%。
const double _volumeScrollStep = .05;
/// 把滚轮 delta 换算成「几个刻度」的参考量。
/// 一次事件最多按一个刻度计算，所以不管鼠标/引擎上报的每刻度 delta 是多少，
/// 一个刻度都稳定对应 5%；高精度滚轮的 delta 更小，按比例得到更细的步长。
const double _scrollUnitsPerNotch = 53;

class _VideoPlayerSurfaceState extends ConsumerState<VideoPlayerSurface> {
  bool _showControls = true;
  bool _locked = false;
  _DragDirection? _dragDirection;
  Duration? _seekStartPosition;
  _Adjustment? _adjustment;
  Timer? _hideTimer;
  double? _speedBeforeLongPress;
  /// 鼠标是否停在播放区域里（含底部控制按钮所在的区域）。
  /// 桌面端只要鼠标在画面里就保持控制条显示，移到窗口外才按超时隐藏。
  bool _pointerInside = false;
  /// 滚轮调音量后画面中央显示的白色音量提示（0~1，null 表示不显示）。
  double? _volumeHud;
  Timer? _volumeHudTimer;

  @override
  void initState() {
    super.initState();
    unawaited(PlaybackSpeedPolicy.initialize());
    WidgetsBinding.instance.addPostFrameCallback((_) => _restartTimer());
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _volumeHudTimer?.cancel();
    super.dispose();
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

  /// 鼠标滚轮调音量：滚轮直接改播放器音量，并在画面中央弹一个白底提示。
  ///
  /// 用 pointerSignalResolver 抢先认领事件，免得同一个滚轮既调音量又把外层列表滚起来。
  void _onPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || event.scrollDelta.dy == 0) return;
    if (_locked) return;
    final controller = widget.controller.value;
    if (controller == null || !controller.value.isInitialized) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (resolved) {
      final scroll = resolved as PointerScrollEvent;
      // 上滚加、下滚减
      final step = (-scroll.scrollDelta.dy / _scrollUnitsPerNotch * _volumeScrollStep).clamp(-_volumeScrollStep, _volumeScrollStep);
      if (step == 0) return;
      final next = (controller.value.volume + step).clamp(0.0, 1.0);
      if (next != controller.value.volume) unawaited(controller.setVolume(next));
      // 已经到顶 / 到底也要显示提示，让用户看到当前音量就是 100% 或 0%
      _showVolumeHud(next);
    });
  }

  void _showVolumeHud(double volume) {
    _volumeHudTimer?.cancel();
    setState(() => _volumeHud = volume);
    _volumeHudTimer = Timer(const Duration(milliseconds: 900), () { if (mounted) setState(() => _volumeHud = null); });
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
    _dragDirection = null;
    _seekStartPosition = widget.controller.value?.value.position;
  }

  /// 只处理横向拖动（快进 / 快退）。竖向的「左半屏亮度 / 右半屏音量」调节已移除：
  /// 桌面端亮度是空实现，音量在控制条上有独立入口，留在画面上只会误触。
  void _dragUpdate(DragUpdateDetails details) {
    if (_locked) return;
    final controller = widget.controller.value;
    if (controller == null) return;
    final size = context.size ?? MediaQuery.sizeOf(context);
    final direction = _dragDirection ??= details.delta.dx.abs() > details.delta.dy.abs() ? _DragDirection.horizontal : _DragDirection.vertical;
    if (direction != _DragDirection.horizontal) return;
    final duration = controller.value.duration;
    if (duration == Duration.zero) return;
    final sensitivity = ref.read(settingsProvider).valueOrNull?.seekSensitivity ?? .35;
    final position = (controller.value.position.inMilliseconds + details.delta.dx / size.width * duration.inMilliseconds * sensitivity).round().clamp(0, duration.inMilliseconds).toInt();
    controller.seekTo(Duration(milliseconds: position));
    final startMs = _seekStartPosition?.inMilliseconds ?? position;
    setState(() => _adjustment = _Adjustment.seek(position - startMs, Duration(milliseconds: position), duration));
  }

  void _dragEnd(DragEndDetails details) { _dragDirection = null; _seekStartPosition = null; Future<void>.delayed(const Duration(milliseconds: 700), () { if (mounted) setState(() => _adjustment = null); }); }

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
        return Listener(
          // 滚轮调音量：挂在最外层，画面、控制条、顶部操作条上的滚轮都生效
          onPointerSignal: _onPointerSignal,
          child: MouseRegion(
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
              // 播放页是沉浸页（不跟随应用主题），画面外框固定黑。
              const ColoredBox(color: Colors.black),
              _VideoViewport(controller: controller),
              ValueListenableBuilder<VideoPlayerValue>(valueListenable: controller, builder: (context, value, _) => value.isBuffering ? const Center(child: M3ELoadingIndicator(color: Colors.white)) : const SizedBox.shrink()),
              // 切超分辨率要重编译着色器链（重档位几秒）：这段时间画面会停住、声音照常，
              // 播放内核也会短暂报告「缓冲」。给一个明确的提示，而不是弹成「加载中」。
              Positioned(
                top: 72,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: ValueListenableBuilder<bool>(
                    valueListenable: ConfiguredMediaKitVideoPlayer.switchingSuperResolution,
                    builder: (context, switching, _) => !switching
                        ? const SizedBox.shrink()
                        : Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.88), borderRadius: BorderRadius.circular(999)),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                                child: Row(mainAxisSize: MainAxisSize.min, children: [
                                  const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.2, color: Colors.white)),
                                  const SizedBox(width: 12),
                                  Text(l10n.switchingQuality, style: const TextStyle(color: Colors.white)),
                                ]),
                              ),
                            ),
                          ),
                  ),
                ),
              ),
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
              if (_adjustment != null) Positioned(top: 72, left: 0, right: 0, child: Center(child: _AdjustmentHud(adjustment: _adjustment!))),
              // 滚轮调音量的白底提示：固定在画面正中，独立于控制条的显示/隐藏
              if (_volumeHud != null) Center(child: _VolumeHud(volume: _volumeHud!)),
              // 暂停时右下角常驻一个标记：白底圆角 + 黑色暂停图标。
              // 控制条显示着的时候右下角被它占着，所以此时把标记抬到控制条上方。
              ValueListenableBuilder<VideoPlayerValue>(
                valueListenable: controller,
                builder: (context, value, _) {
                  final paused = !value.isPlaying && !value.isCompleted && value.duration > Duration.zero;
                  return AnimatedPositioned(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOut,
                    right: 12,
                    bottom: paused && _showControls && !_locked ? 104 : 16,
                    child: IgnorePointer(
                      child: AnimatedOpacity(duration: const Duration(milliseconds: 180), opacity: paused ? 1 : 0, child: const _PausedBadge()),
                    ),
                  );
                },
              ),
            ]),
          ),
        ));
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
        // 量宽度时必须用环境里的文本样式（字体族/字重）和当前的文字缩放，
        // 否则量出来的宽度和实际渲染不一致，跑马灯的位移会算错（标题被截断或滚过头）。
        final style = DefaultTextStyle.of(context).style.merge(const TextStyle(color: Colors.white, fontWeight: FontWeight.w600));
        final painter = TextPainter(text: TextSpan(text: widget.title, style: style), maxLines: 1, textDirection: TextDirection.ltr, textScaler: MediaQuery.textScalerOf(context))..layout();
        final width = painter.width;
        if (width <= constraints.maxWidth) return Text(widget.title, maxLines: 1, style: style);
        final distance = width - constraints.maxWidth + 24;
        return ClipRect(child: AnimatedBuilder(animation: _controller, builder: (context, child) => Transform.translate(offset: Offset(-distance * _controller.value, 0), child: child), child: Text(widget.title, maxLines: 1, style: style)));
      });
}

enum _DragDirection { horizontal, vertical }
enum _AdjustmentKind { speed, seek }
class _Adjustment {
  const _Adjustment(this.kind, this.value, {this.delta, this.position, this.duration});
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

}

/// 滚轮调音量的提示：白底圆角卡片 + 喇叭图标 + 百分比。
class _VolumeHud extends StatelessWidget {
  const _VolumeHud({required this.volume});
  final double volume;

  @override
  Widget build(BuildContext context) {
    final percent = (volume.clamp(0.0, 1.0) * 100).round();
    return IgnorePointer(
      child: DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(percent <= 0 ? Icons.volume_off : (percent < 50 ? Icons.volume_down : Icons.volume_up), color: Colors.black, size: 26),
              const SizedBox(width: 10),
              Text('$percent%', style: const TextStyle(color: Colors.black, fontSize: 22, height: 1, fontWeight: FontWeight.w500, fontFeatures: [FontFeature.tabularFigures()])),
            ],
          ),
        ),
      ),
    );
  }
}

/// 暂停时右下角的常驻标记：白底圆角卡片 + 黑色三角播放图标（B 站那种）。
class _PausedBadge extends StatelessWidget {
  const _PausedBadge();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(10))),
        child: Padding(padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10), child: Icon(Icons.play_arrow, color: Colors.black, size: 28)),
      );
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
