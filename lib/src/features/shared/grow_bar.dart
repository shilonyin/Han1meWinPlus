import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 同组柱子的错开步长（第几根就往后推几档）。
/// 不是动效时长本身，减少动画时整段被跳过，不套 motionDuration。
const Duration _staggerStep = Duration(milliseconds: 25);

/// 数据条形「入场生长」：从 0 长到 [factor] 指定的大小，带一点延迟错开。
///
/// 借鉴 CodedVisuals 那类「数据小幅动画」的做法：静置时只是一张静态图，
/// 一旦进入视野就轻轻长出来，让人注意到「这是一组真实数据」而不是占位。
/// 只做**一次**入场，不做循环闪烁 —— 工具类应用里持续的动效是噪音。
///
/// - [factor] 是目标比例（0~1）。纵向柱状传 [axis] = vertical，横向进度条传 horizontal。
/// - [delay] 让一排元素先后生长（相邻多 40ms 左右），顺序感来自这里。
/// - 系统「减少动画」开启时（[motionEnabledOf] 为假）直接到终态，不播。
class GrowBar extends StatefulWidget {
  const GrowBar({
    super.key,
    required this.factor,
    required this.child,
    this.axis = Axis.vertical,
    this.order = 0,
  });

  /// 目标比例，0~1。
  final double factor;

  /// 真正要显示的柱子/条（通常是一个 DecoratedBox / ColoredBox）。
  final Widget child;

  /// vertical：按高度生长（柱状图）；horizontal：按宽度生长（进度条）。
  final Axis axis;

  /// 在同组里是第几个（从 0 起），用来错开入场先后。
  final int order;

  @override
  State<GrowBar> createState() => _GrowBarState();
}

class _GrowBarState extends State<GrowBar>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.emphasis,
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // 只在第一次挂载时排一次入场；减少动画时直接到终态。
    if (_c.isAnimating || _c.isCompleted) return;
    if (!motionEnabledOf(context)) {
      _c.value = 1;
      return;
    }
    final step = _staggerStep * widget.order;
    if (step == Duration.zero) {
      _c.forward();
    } else {
      Future<void>.delayed(step, () {
        if (mounted) _c.forward();
      });
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, child) {
        final t = AppMotion.settle.transform(_c.value);
        final f = (widget.factor.clamp(0.0, 1.0)) * t;
        return Align(
          alignment: widget.axis == Axis.vertical
              ? Alignment.bottomCenter
              : Alignment.centerLeft,
          child: FractionallySizedBox(
            widthFactor: widget.axis == Axis.horizontal ? f : null,
            heightFactor: widget.axis == Axis.vertical ? f : null,
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
