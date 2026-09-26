import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:video_player/video_player.dart';

import '../../core/video_player_shutdown.dart';
import '../../data/local/watch_repository.dart';
import '../../domain/models/video.dart';

/// 应用内画中画（迷你播放器）的全局状态。
///
/// 与旧的「独立小窗」不同，画中画**不新建窗口、不新建播放器**：它直接接管播放页
/// 正在用的那个 [VideoPlayerController]，所以只有一份解码 / 渲染，不会出现
/// 「两个引擎同时画同一部片」的卡顿。播放页离开时把播放器「移交」给它，
/// 由它继续持有；用户关掉画中画时才真正销毁播放器。
///
/// 位置用「距各边的偏移」记录（左下 / 右下角以 right/bottom 为准），这样窗口
/// 尺寸变化时小窗仍然贴在用户放的那个角上，而不是跟着漂到屏幕中间。
class PipState {
  const PipState({
    required this.video,
    required this.controller,
    required this.visible,
    this.qualityLabel,
    this.left,
    this.top,
    this.right,
    this.bottom,
  });

  final VideoDetail video;
  final VideoPlayerController controller;
  final bool visible;

  /// 当前播放的清晰度标签（用于回到播放页时还原「当前选中清晰度」）。
  final String? qualityLabel;

  /// 拖动后的位置（相对整个应用内容区）。全部为 null 表示还没拖过，
  /// 使用默认的右下角位置。
  final double? left;
  final double? top;
  final double? right;
  final double? bottom;

  PipState copyWith({
    bool? visible,
    Object? left = _unset,
    Object? top = _unset,
    Object? right = _unset,
    Object? bottom = _unset,
  }) =>
      PipState(
        video: video,
        controller: controller,
        visible: visible ?? this.visible,
        qualityLabel: qualityLabel,
        left: identical(left, _unset) ? this.left : left as double?,
        top: identical(top, _unset) ? this.top : top as double?,
        right: identical(right, _unset) ? this.right : right as double?,
        bottom: identical(bottom, _unset) ? this.bottom : bottom as double?,
      );

  static const _unset = Object();
}

class PipController extends Notifier<PipState?> {
  /// 播放页移交过来的播放器：离页时不能销毁它，交给画中画继续持有。
  VideoPlayerController? _adopted;

  /// 画中画自己的观看进度记录（播放页已经不再监听这个播放器了）。
  DateTime _lastSaved = DateTime.fromMillisecondsSinceEpoch(0);
  VoidCallback? _progressListener;

  @override
  PipState? build() {
    ref.onDispose(_detachProgressListener);
    return null;
  }

  /// 播放页进入画中画：接管当前播放器与视频。
  ///
  /// 不改变播放状态（接着播，不重头开始），也**不销毁**播放器。
  void adopt({required VideoDetail video, required VideoPlayerController controller, String? qualityLabel}) {
    _detachProgressListener();
    _adopted = controller;
    state = PipState(video: video, controller: controller, visible: true, qualityLabel: qualityLabel);
    // 播放页 off-page 后不会再保存进度，画中画要自己接着记，否则这段观看不会进入历史。
    _progressListener = () => _saveProgress(video, controller);
    controller.addListener(_progressListener!);
    try {
      VideoPlayerShutdown.track(controller);
    } catch (_) {}
  }

  /// 节流写入观看进度（沿用播放页的 5 秒节流）。
  void _saveProgress(VideoDetail video, VideoPlayerController controller) {
    if (!identical(_adopted, controller)) return;
    final value = controller.value;
    if (!value.isInitialized) return;
    if (DateTime.now().difference(_lastSaved).inSeconds < 5) return;
    _lastSaved = DateTime.now();
    ref.read(watchProvider.notifier).progress(id: video.id, title: video.title, coverUrl: video.coverUrl, positionMs: value.position.inMilliseconds, durationMs: value.duration.inMilliseconds);
  }

  void _detachProgressListener() {
    final listener = _progressListener;
    final controller = _adopted;
    _progressListener = null;
    if (listener != null && controller != null) {
      try {
        controller.removeListener(listener);
      } catch (_) {}
    }
  }

  /// 这个播放器当前是否已经交给画中画持有（播放页 dispose 时据此跳过销毁）。
  bool owns(VideoPlayerController controller) => identical(_adopted, controller);

  /// 播放页重新接管画中画：把播放器交还给播放页，画中画本身退场但**不销毁**播放器。
  ///
  /// 返回被交还的播放器（没有画中画或视频对不上时返回 null）。
  VideoPlayerController? takeBack(String videoId) {
    final current = state;
    if (current == null || current.video.id != videoId) return null;
    final controller = current.controller;
    // 记录一下这段进度的最后位置，然后把监听交还给播放页（播放页会重新 addListener）。
    _saveProgress(current.video, controller);
    _detachProgressListener();
    _adopted = null;
    state = null;
    return controller;
  }

  void hide() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(visible: false);
  }

  void show() {
    final current = state;
    if (current == null) return;
    state = current.copyWith(visible: true);
  }

  /// 记录吸附后的位置。水平方向只给 left 或 right 之一，垂直方向只给 top 或 bottom 之一；
  /// 每个方向传 null 表示「用默认值」（默认贴在右下角）。
  void moveTo({double? left, double? top, double? right, double? bottom}) {
    final current = state;
    if (current == null) return;
    state = current.copyWith(left: left, top: top, right: right, bottom: bottom);
  }

  /// 关闭画中画：真正销毁播放器。
  Future<void> close() async {
    final controller = _adopted;
    final video = state?.video;
    if (controller != null && video != null) _saveProgress(video, controller);
    _detachProgressListener();
    _adopted = null;
    state = null;
    if (controller == null) return;
    try {
      if (controller.value.isInitialized && controller.value.isPlaying) {
        await controller.pause().timeout(const Duration(milliseconds: 600));
      }
    } catch (_) {}
    try {
      await controller.dispose().timeout(const Duration(seconds: 3));
    } catch (_) {}
    try {
      VideoPlayerShutdown.untrack(controller);
    } catch (_) {}
  }
}

/// 当前画中画状态（null = 没有画中画）。
final pipControllerProvider = NotifierProvider<PipController, PipState?>(PipController.new);

/// 画中画是否正在显示。
final pipVisibleProvider = Provider<bool>((ref) => ref.watch(pipControllerProvider)?.visible ?? false);

/// 桌面端（有窗口、可悬浮）才提供画中画能力。
bool get pipSupported => switch (defaultTargetPlatform) {
      TargetPlatform.windows || TargetPlatform.macOS || TargetPlatform.linux => true,
      _ => false,
    };
