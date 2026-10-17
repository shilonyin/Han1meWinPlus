import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 亮暗主题切换的过渡：**圆形揭示**，新画面从中心扩散把旧画面推开。
///
/// **为什么不能直接把 `themeAnimationDuration` 调大**：那个参数是对整套
/// [ThemeData] 的颜色做 lerp。页面底色暗色是 `#070A12`、亮色是 `#F2F2F7`，
/// 两者插值的中间值是 `#7D7E85` —— 一段没有色相的中灰。整屏底色、卡片、文字
/// 会在过渡中途一起变成灰的，看起来像蒙了一层雾。这正是 `app_widget.dart`
/// 把 `themeAnimationDuration` 设成 [Duration.zero] 的原因。
///
/// **为什么不是交叉淡入淡出**：把旧画面截下来半透明盖在新画面上，底色那一层
/// 的混合结果和直接 lerp 完全相同（`0.5×242 + 0.5×7 = 124.5`），照样路过中灰。
/// 唯一不经过中灰的做法是让新旧画面**不重叠混合** —— 交界处是硬边界。
///
/// **这里的做法**：主题本身仍然瞬时切换（`themeAnimationDuration` 保持零），
/// 但在检测到明暗变化的那一刻，把**切换前的画面**截成一张图，盖在已经变成
/// 新主题的内容上面，只在圆外可见（圆内挖空露出新内容）。圆从**用户按下的
/// 那个位置**扩到覆盖全屏，旧画面被一圈推开。
///
/// 内容树只渲染一次（新主题那一次），旧画面只是一张位图，所以没有重复构建、
/// 也没有两份状态。
///
/// **截图的时机**：在 [didChangeDependencies] 里。此时 `Theme` 已经换成新的，
/// 但 [RenderRepaintBoundary] 还是**上一帧**的合成结果（本帧尚未 paint），
/// 所以 [RenderRepaintBoundary.toImageSync] 拿到的正是旧主题的画面。
///
/// **失败即降级**：截图拿不到（首帧、尺寸为空、后端不支持同步光栅化）时
/// 直接不做过渡，主题照常瞬时切换 —— 过渡是锦上添花，不能因为它让切换本身失效。
class ThemeTransition extends StatefulWidget {
  const ThemeTransition({
    super.key,
    required this.child,
    this.duration = const Duration(milliseconds: 420),
    this.origin = Alignment.center,
  });

  /// 旧画面那一层的 key。测试用它判断过渡层在不在 —— `FadeTransition` 在
  /// `MaterialApp` 内部（路由、对话框）到处都是，按类型找会误判。
  static const overlayKey = ValueKey<String>('theme-transition-overlay');

  final Widget child;

  /// 圆形扩散的时长。太短看起来像闪一下，太长用户会觉得点完没反应。
  final Duration duration;

  /// **没有点击时**的扩散圆心。正常由用户点击触发，圆心取那次按下的位置
  /// （见 `_resolveOrigin`），这个值只在没有指针事件时兜底 —— 比如「跟随系统」
  /// 时由系统主题变化引起的切换。
  final Alignment origin;

  /// 把指针的全局坐标换算成相对本层尺寸的 [Alignment]。
  ///
  /// 单独抽出来是为了能测：`toImageSync` 在测试环境里不一定成功，过渡层可能
  /// 压根铺不上，那样就没法从界面上反推圆心。
  @visibleForTesting
  static Alignment originFromPointer(Offset pointer, RenderBox box) {
    final local = box.globalToLocal(pointer);
    final size = box.size;
    // Alignment 的取值是 [-1, 1]：左上角 (-1,-1)，右下角 (1,1)。
    return Alignment(
      (local.dx / size.width) * 2 - 1,
      (local.dy / size.height) * 2 - 1,
    );
  }

  /// 测试用：按进度算出旧画面那一层被裁成什么样。
  ///
  /// 暴露它是为了让「交界是硬边界、不是透明度混合」这条能写成断言 ——
  /// 换成整层 `Opacity` 的实现会让底色在过渡中途变成中灰，测试会立刻发现。
  @visibleForTesting
  static Path debugRevealPath(
    double progress,
    Size size, {
    Alignment origin = Alignment.center,
  }) => ThemeRevealClipper(progress: progress, origin: origin).getClip(size);

  @override
  State<ThemeTransition> createState() => _ThemeTransitionState();
}

class _ThemeTransitionState extends State<ThemeTransition>
    with SingleTickerProviderStateMixin {
  final GlobalKey _boundaryKey = GlobalKey();

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  )..addStatusListener(_onStatus);

  /// 切换前那一帧的画面。动画结束后立即释放 —— `ui.Image` 持有的是
  /// 显存/原生内存，不 dispose 会一直累积。
  ui.Image? _previousFrame;

  /// 截图时用的像素比，绘制时按它还原成逻辑尺寸。
  double _previousFrameRatio = 1;

  /// 上一次看到的明暗。`null` 表示还没建立基线（首帧不做过渡）。
  Brightness? _lastBrightness;

  /// 最后一次指针按下的全局位置。主题切换基本都由点击触发，用按下点当圆心，
  /// 圆就从用户点的那个按钮扩散出去。
  ///
  /// 跟随系统时由系统主题变化触发的切换没有对应的点击，退回
  /// [ThemeTransition.origin]（默认屏幕中心）。
  Offset? _lastPointerDown;

  /// 本次过渡的圆心，在检测到明暗变化的那一刻定下来 —— 动画期间不再改，
  /// 否则中途点别处会让圆心跳走，看起来像画面抖了一下。
  Alignment _origin = Alignment.center;

  /// 半径线性增长时，覆盖面积按平方增长 —— 观感是「先慢后快」，像突然糊上来。
  /// 用 `easeInOutCubic` 把两端都缓下来，扩散过程更均匀。
  static final Animatable<double> _revealCurve = CurveTween(
    curve: Curves.easeInOutCubic,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final brightness = Theme.of(context).brightness;
    final previous = _lastBrightness;
    _lastBrightness = brightness;
    if (previous == null || previous == brightness) return;
    _origin = _resolveOrigin();
    if (_capturePreviousFrame()) {
      _controller.forward(from: 0);
    }
  }

  /// 把指针的全局坐标换算成相对本层尺寸的 [Alignment]。
  ///
  /// 单独抽出来是为了能测：`toImageSync` 在测试环境里不一定成功，过渡层可能
  /// 压根铺不上，那样就没法从界面上反推圆心。
  @visibleForTesting
  static Alignment originFromPointer(Offset pointer, RenderBox box) =>
      ThemeTransition.originFromPointer(pointer, box);

  /// 把最后一次按下的全局坐标换算成圆心。
  ///
  /// 用掉即清空：这样「跟随系统」时由系统主题变化触发的切换（没有点击）不会
  /// 继承上一次点别处留下的圆心，而是退回 [ThemeTransition.origin]。
  Alignment _resolveOrigin() {
    final pointer = _lastPointerDown;
    _lastPointerDown = null;
    if (pointer == null) return widget.origin;
    final object = _boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderBox || !object.hasSize || object.size.isEmpty) {
      return widget.origin;
    }
    return originFromPointer(pointer, object);
  }

  @override
  void didUpdateWidget(ThemeTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      _controller.duration = widget.duration;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _previousFrame?.dispose();
    super.dispose();
  }

  void _onStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    // 动画结束：把旧画面丢掉，别让一层位图一直留在树上。
    final frame = _previousFrame;
    if (frame == null) return;
    setState(() => _previousFrame = null);
    frame.dispose();
  }

  /// 抓取当前（= 上一帧的）画面。成功返回 true。
  bool _capturePreviousFrame() {
    final object = _boundaryKey.currentContext?.findRenderObject();
    if (object is! RenderRepaintBoundary) return false;
    if (!object.hasSize || object.size.isEmpty) return false;
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    try {
      final image = object.toImageSync(pixelRatio: ratio);
      final stale = _previousFrame;
      _previousFrame = image;
      _previousFrameRatio = ratio;
      stale?.dispose();
      return true;
    } catch (_) {
      // 拿不到就降级：不做过渡，主题照常瞬时切换。
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final previous = _previousFrame;
    return Listener(
      // 记下按下的位置，等明暗真的变了再用它当圆心。默认的 `deferToChild` 就够：
      // 触发点（侧栏按钮、托盘菜单项）都在子树里，命中后事件一定经过这里。
      // 不用 `translucent`，免得整块空白区域也跟着参与命中测试。
      onPointerDown: (event) => _lastPointerDown = event.position,
      child: Stack(
        // `passthrough`：非定位子项拿到与父相同的约束，不改变原有布局。
        fit: StackFit.passthrough,
        children: [
          RepaintBoundary(key: _boundaryKey, child: widget.child),
          if (previous != null)
            Positioned.fill(
              key: ThemeTransition.overlayKey,
              child: IgnorePointer(
                // 只让这一层跟着动画重建，`widget.child` 不受影响（否则每帧都要
                // 重建整棵页面树）。
                child: ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => ClipPath(
                    clipper: ThemeRevealClipper(
                      progress: _revealCurve.transform(_controller.value),
                      origin: _origin,
                    ),
                    child: RawImage(
                      image: previous,
                      // `RawImage.scale` 是「一个逻辑像素对应多少 image 像素」：截图按
                      // `pixelRatio` 放大过，所以要乘回去才回到原来的逻辑尺寸。
                      scale: _previousFrameRatio,
                      fit: BoxFit.fill,
                      // 截图与显示用同一个 DPR，是 1:1 映射，`none` 最锐利。
                      filterQuality: FilterQuality.none,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 把整块区域挖掉一个圆 —— 旧画面只在圆外可见，圆内露出下层的新内容。
class ThemeRevealClipper extends CustomClipper<Path> {
  const ThemeRevealClipper({required this.progress, required this.origin});

  /// 0 → 圆半径为零（旧画面铺满），1 → 圆覆盖全屏（旧画面完全消失）。
  final double progress;
  final Alignment origin;

  @override
  Path getClip(Size size) {
    // 空路径 = 整块裁掉 = 旧画面完全不可见。
    if (progress >= 1) return Path();
    final full = Path()..addRect(Offset.zero & size);
    final center = origin.alongSize(size);
    // 到最远那个角的距离：半径走到这里才算真正覆盖全屏，否则角上会留残影。
    final radius = _farthestCorner(size, center) * progress;
    if (radius <= 0) return full;
    final hole = Path()
      ..addOval(Rect.fromCircle(center: center, radius: radius));
    return Path.combine(PathOperation.difference, full, hole);
  }

  static double _farthestCorner(Size size, Offset center) {
    final corners = <Offset>[
      Offset.zero,
      Offset(size.width, 0),
      Offset(0, size.height),
      Offset(size.width, size.height),
    ];
    var farthest = 0.0;
    for (final corner in corners) {
      final distance = (corner - center).distance;
      if (distance > farthest) farthest = distance;
    }
    return farthest;
  }

  @override
  bool shouldReclip(ThemeRevealClipper oldClipper) =>
      oldClipper.progress != progress || oldClipper.origin != origin;
}
