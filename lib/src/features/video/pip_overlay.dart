import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:video_player/video_player.dart';

import '../../../l10n/app_localizations.dart';
import 'pip_controller.dart';

/// 应用内画中画（迷你播放器）悬浮层，形态参考 b 站小窗：
/// 圆角画面 + 下方一条半透明控制栏（播放/暂停、上/下一集、进度条、时间、音量、关闭），
/// 可整块拖动、松手吸附到最近的角，点画面回到播放页。
///
/// 它直接渲染播放页移交过来的同一个 [VideoPlayerController]，只有一份解码与渲染；
/// 而且**不启用超分辨率放大**（`VideoOutputArea`）—— 小窗本来就小，那只会白白烧 GPU，
/// 这正是旧「独立小窗」卡顿的主因之一。
class PipOverlay extends ConsumerStatefulWidget {
  const PipOverlay({super.key});

  /// 小窗画面宽度（逻辑像素）。高度按视频比例算，再加控制栏那一条。
  static const double _width = 320;
  static const double _controlsHeight = 34;
  /// 离屏幕边缘的默认间距（也是吸附后的间距）。
  static const double _margin = 16;

  @override
  ConsumerState<PipOverlay> createState() => _PipOverlayState();
}

class _PipOverlayState extends ConsumerState<PipOverlay> {
  /// 拖动过程中的临时位置（相对内容区左上角）；null = 用 provider 里记录的吸附位置。
  Offset? _dragging;
  Size _viewport = Size.zero;

  void _openPlayer(PipState pip) {
    // 回到播放页：播放页 initState 会把画中画手里的播放器接回去（见 VideoPlayerPanel）。
    context.push('/video/${pip.video.id}');
  }

  void _commitDrop(PipState pip, Offset position, Size box) {
    // 吸附：水平贴最近的一条竖边、垂直贴最近的一条横边。
    final centerX = position.dx + box.width / 2;
    final centerY = position.dy + box.height / 2;
    final toLeft = centerX < _viewport.width / 2;
    final toTop = centerY < _viewport.height / 2;
    final maxLeft = (_viewport.width - box.width - PipOverlay._margin).clamp(0.0, double.infinity);
    final maxTop = (_viewport.height - box.height - PipOverlay._margin).clamp(0.0, double.infinity);
    final left = toLeft ? PipOverlay._margin.clamp(0.0, maxLeft) : maxLeft;
    final top = toTop ? PipOverlay._margin.clamp(0.0, maxTop) : maxTop;
    ref.read(pipControllerProvider.notifier).moveTo(left: left, top: top, right: null, bottom: null);
    setState(() => _dragging = null);
  }

  @override
  Widget build(BuildContext context) {
    final pip = ref.watch(pipControllerProvider);
    if (pip == null || !pip.visible) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, constraints) {
      _viewport = constraints.biggest;
      final controller = pip.controller;
      final value = controller.value;
      final ratio = value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio;
      final width = PipOverlay._width.clamp(0.0, (constraints.maxWidth - PipOverlay._margin * 2).clamp(120.0, PipOverlay._width));
      final videoHeight = width / ratio;
      final box = Size(width, videoHeight + PipOverlay._controlsHeight);
      // provider 里记的位置优先；没记过就默认右下角。
      final recorded = (pip.left != null && pip.top != null) ? Offset(pip.left!, pip.top!) : null;
      final defaultPosition = Offset(
        (constraints.maxWidth - box.width - PipOverlay._margin).clamp(0.0, double.infinity),
        (constraints.maxHeight - box.height - PipOverlay._margin).clamp(0.0, double.infinity),
      );
      final placed = _dragging ?? recorded ?? defaultPosition;
      final position = Offset(
        placed.dx.clamp(0.0, (constraints.maxWidth - box.width).clamp(0.0, double.infinity)),
        placed.dy.clamp(0.0, (constraints.maxHeight - box.height).clamp(0.0, double.infinity)),
      );
      return Stack(children: [
        Positioned(
          left: position.dx,
          top: position.dy,
          child: _PipFrame(
            controller: controller,
            width: width,
            videoHeight: videoHeight,
            onTapVideo: () => _openPlayer(pip),
            onDragUpdate: (delta) => setState(() => _dragging = position + delta),
            onDragEnd: () => _commitDrop(pip, position, box),
            onClose: () => ref.read(pipControllerProvider.notifier).close(),
          ),
        ),
      ]);
    });
  }
}

class _PipFrame extends StatelessWidget {
  const _PipFrame({
    required this.controller,
    required this.width,
    required this.videoHeight,
    required this.onTapVideo,
    required this.onDragUpdate,
    required this.onDragEnd,
    required this.onClose,
  });

  final VideoPlayerController controller;
  final double width;
  final double videoHeight;
  final VoidCallback onTapVideo;
  final ValueChanged<Offset> onDragUpdate;
  final VoidCallback onDragEnd;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      elevation: 16,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        width: width,
        child: DecoratedBox(
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
              height: videoHeight,
              child: GestureDetector(
                // 拖动整块小窗：按下即开始拖（点击优先，短按不动视为「回到播放页」）。
                onTap: onTapVideo,
                onPanUpdate: (details) => onDragUpdate(details.delta),
                onPanEnd: (_) => onDragEnd(),
                child: Stack(fit: StackFit.expand, children: [
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) => !value.isInitialized
                        ? const ColoredBox(color: Colors.black)
                        : Center(child: AspectRatio(aspectRatio: value.aspectRatio == 0 ? 16 / 9 : value.aspectRatio, child: VideoPlayer(controller))),
                  ),
                  // 暂停时给一个淡淡的播放标记，和 b 站小窗一致（只画图标，不铺底色块）。
                  ValueListenableBuilder<VideoPlayerValue>(
                    valueListenable: controller,
                    builder: (context, value, _) {
                      final paused = !value.isPlaying && !value.isCompleted && value.duration > Duration.zero;
                      if (!paused) return const SizedBox.shrink();
                      return const Center(child: Icon(Icons.play_arrow, color: Colors.white70, size: 40));
                    },
                  ),
                ]),
              ),
            ),
            _PipControls(controller: controller, onClose: onClose),
          ]),
        ),
      ),
    );
  }
}

/// 小窗底部控制栏：播放/暂停、快退/快进、进度条 + 时间、关闭。
/// 按 b 站小窗的紧凑形态，只保留最常用的几项。
class _PipControls extends StatelessWidget {
  const _PipControls({required this.controller, required this.onClose});

  final VideoPlayerController controller;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: PipOverlay._controlsHeight,
        child: ColoredBox(
          color: const Color(0xE6000000),
          child: ValueListenableBuilder<VideoPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              final l10n = AppLocalizations.of(context)!;
              final progress = value.duration == Duration.zero ? 0.0 : (value.position.inMilliseconds / value.duration.inMilliseconds).clamp(0.0, 1.0);
              return Row(children: [
                _PipButton(
                  tooltip: value.isPlaying ? l10n.pause : l10n.play,
                  icon: value.isPlaying ? Icons.pause : Icons.play_arrow,
                  onPressed: () => value.isPlaying ? controller.pause() : controller.play(),
                ),
                Text('${_format(value.position)}/${_format(value.duration)}', style: const TextStyle(color: Colors.white70, fontSize: 10, fontFeatures: [FontFeature.tabularFigures()])),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(trackHeight: 2, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 4), overlayShape: const RoundSliderOverlayShape(overlayRadius: 8), activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24, thumbColor: Colors.white, year2023: true),
                    child: Slider(value: progress, onChanged: (next) => controller.seekTo(Duration(milliseconds: (next * value.duration.inMilliseconds).round()))),
                  ),
                ),
                _PipVolumeButton(controller: controller),
                _PipButton(tooltip: l10n.close, icon: Icons.close, onPressed: onClose),
              ]);
            },
          ),
        ),
      );
}

/// 小窗里的音量入口：点一下弹出一条横向滑条（弹在按钮上方，避免超出小窗右边界）。
class _PipVolumeButton extends StatelessWidget {
  const _PipVolumeButton({required this.controller});

  final VideoPlayerController controller;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<VideoPlayerValue>(
        valueListenable: controller,
        builder: (context, value, _) => MenuAnchor(
          style: const MenuStyle(
            alignment: Alignment.topCenter,
            padding: WidgetStatePropertyAll(EdgeInsets.zero),
            backgroundColor: WidgetStatePropertyAll(Color(0xE6000000)),
            surfaceTintColor: WidgetStatePropertyAll(Colors.transparent),
            elevation: WidgetStatePropertyAll(0),
            shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(8)))),
          ),
          // 面板朝上弹，且相对按钮水平居中稍稍右移（按钮贴近小窗右缘）。
          alignmentOffset: const Offset(-60, -46),
          menuChildren: [
            SizedBox(
              width: 130,
              height: 34,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5), overlayShape: const RoundSliderOverlayShape(overlayRadius: 10), activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24, thumbColor: Colors.white, year2023: true),
                child: Slider(value: value.volume.clamp(0.0, 1.0).toDouble(), onChanged: (next) => controller.setVolume(next)),
              ),
            ),
          ],
          builder: (context, menu, _) => _PipButton(
            tooltip: AppLocalizations.of(context)!.volume,
            icon: value.volume <= 0.001 ? Icons.volume_off : (value.volume < 0.5 ? Icons.volume_down : Icons.volume_up),
            onPressed: () => menu.isOpen ? menu.close() : menu.open(),
          ),
        ),
      );
}

class _PipButton extends StatefulWidget {
  const _PipButton({required this.tooltip, required this.icon, required this.onPressed});

  final String tooltip;
  final IconData icon;
  final VoidCallback onPressed;

  @override
  State<_PipButton> createState() => _PipButtonState();
}

class _PipButtonState extends State<_PipButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: InkWell(
            onTap: widget.onPressed,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            highlightColor: Colors.transparent,
            child: SizedBox(
              width: 30,
              height: PipOverlay._controlsHeight,
              child: Icon(widget.icon, size: 16, color: _hovered ? const Color(0xfffb7299) : Colors.white),
            ),
          ),
        ),
      );
}

String _format(Duration duration) {
  final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
  return duration.inHours > 0 ? '${duration.inHours}:$minutes:$seconds' : '$minutes:$seconds';
}
