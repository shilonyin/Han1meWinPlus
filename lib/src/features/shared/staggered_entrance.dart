import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 列表／区块的**交错入场**：位移 20px + 淡入，逐项延后 100ms。
///
/// 配方来自 flutter_beautiful_ui 的 `CusAnimatedDelayItem`。
/// 那套作品集里几乎每个页面都用 `AnimationController(250ms)` 起手。
/// 再配 `CurvedAnimation(easeIn)` 与 `Transform.translate(±20px)`。
/// 最后用 `Opacity(v)` 淡入，按 `index * 100ms` 把列表错开。
/// 这里把它收成一个组件。
/// 时长与曲线全部走 [AppMotion]。
/// 并通过 `motionDuration()` 尊重系统「减少动画」开关。
/// 上游那份实现没做这一步。
///
/// 参数 [index] 是该项在列表中的位置。
/// 参数 [roundDelay] 决定多少项之后重新从 0 计延迟。
/// 长列表不该让第 50 项等 5 秒。
class StaggeredEntrance extends StatefulWidget {
  const StaggeredEntrance({
    super.key,
    required this.index,
    required this.child,
    this.roundDelay = 10,
    this.axis = Axis.vertical,
    this.distance = 20.0,
  });

  final int index;
  final Widget child;
  final int roundDelay;

  /// 位移方向。默认纵向（从下往上浮入），横向可用于从右滑入的侧栏块。
  final Axis axis;

  /// 位移距离（逻辑像素）。
  final double distance;

  @override
  State<StaggeredEntrance> createState() => _StaggeredEntranceState();
}

class _StaggeredEntranceState extends State<StaggeredEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: motionDuration(context, AppMotion.emphasis),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: AppMotion.standardCurve,
    );
    // 交错延迟不是动画时长，是「什么时候开始」，属于节流而非视觉过渡，
    // 所以这里不用 AppMotion。减少动画开关打开时 duration 归零，
    // 直接跳到终态，延迟也就没有意义了 —— 一并跳过。
    final delay = Duration(
      milliseconds: (widget.index % widget.roundDelay) * 100,
    );
    if (delay == Duration.zero) {
      _controller.forward();
    } else {
      Future<void>.delayed(delay, () {
        if (mounted) _controller.forward(from: 0);
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      child: widget.child,
      builder: (context, child) {
        final t = 1.0 - _animation.value;
        final offset = widget.axis == Axis.vertical
            ? Offset(0, widget.distance * t)
            : Offset(widget.distance * t, 0);
        return Transform.translate(
          offset: offset,
          child: Opacity(opacity: _animation.value, child: child),
        );
      },
    );
  }
}
