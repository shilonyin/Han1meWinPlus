import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 按下时整块轻微缩小的反馈：`scale .96 / 150ms`（better-ui 清单里的按下稿）。
///
/// 为什么用 [Listener] 而不是 [GestureDetector]：Listener 只「听」指针、不进手势
/// 竞技场，包在任何按钮外面都不会把按钮自己的点击吃掉（GestureDetector 会争抢，
/// 包住按钮后按钮就不响应了）。
///
/// 为什么要逐个按钮包、而不是挂在主题上：Flutter 没有给按钮整体加 transform 的
/// 主题钩子 —— `ButtonStyle.backgroundBuilder` 拿到的只是按钮的**内容层**，缩放它
/// 会出现「底色和边框不动、只有文字缩小」，那正是要避免的不统一。要让底色、边框、
/// 文字一起缩，只能包在按钮外面。代价是每个按钮一处，好在形态完全一致。
///
/// 系统开了「减少动画」时 [motionDuration] 归零，缩放直接跳变。
class PressScale extends StatefulWidget {
  const PressScale({
    super.key,
    required this.child,
    this.scale = .96,
    this.enabled = true,
  });

  final Widget child;

  /// 按下时的缩放比例。
  final double scale;

  /// 关掉后完全不响应按下。
  ///
  /// 禁用的按钮必须传 `false`：不然按下去照样缩一下，等于给了一个「点了有
  /// 反应」的假信号 —— 用起来就是「悬停不动、点了却会动」，比完全没反馈
  /// 更让人以为它其实是能点的。
  final bool enabled;

  @override
  State<PressScale> createState() => _PressScaleState();
}

class _PressScaleState extends State<PressScale> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    // 两条约束同时成立才算对：
    //   ① 缩放只缩**绘制**、不缩命中区（`transformHitTests: false`）；
    //   ② 这个 `Listener` 的命中区严格等于**子组件自己的矩形**。
    //
    // 第 ② 条是这次真正修掉「点按钮、别处文字跟着缩」的关键。
    // `Listener` 默认 `deferToChild` 看起来够用，但把它放在 `Transform` 外面时，
    // 命中链要先经过 `Transform` 才能回到它 —— 按下事件有时收不到，于是又得
    // 改成 `translucent`；而 `translucent` 会让 `Listener` 在**父级给的整个
    // 约束范围**内都参与命中。`PressScale` 常被塞进 `Row`/`Column` 并被撑满宽，
    // 于是点同一横向带上的任何位置，这个实例都会 `_pressed = true` 缩一下 ——
    // 侧栏和内容区恰好都在这一带里，看起来就是「点按钮，左边的字跟着缩」。
    //
    // 所以：`Listener` 放到 `Transform` **里面**（命中区就是子组件本身），
    // 缩放包在外面只管画。
    return TweenAnimationBuilder<double>(
      // `end` 用 0/1 表示「未按下 / 按下」，再映射到 1/scale。
      tween: Tween<double>(end: _pressed ? 1 : 0),
      duration: motionDuration(context, AppMotion.brief),
      curve: AppMotion.standardCurve,
      builder: (context, t, child) => Transform.scale(
        scale: 1 + (widget.scale - 1) * t,
        // 命中测试不跟着缩：否则鼠标停在边缘会「离开 → 进入」反复触发，
        // 靠悬停着色的文字会跟着闪。
        transformHitTests: false,
        child: child,
      ),
      // `RepaintBoundary` 必须有：`Transform` 会把它包住的绘制结果整体重放，
      // 而 `PressScale` 大多嵌在 `ListView` 里。没有独立图层时，缩放期间的
      // 旧帧不会被裁掉，滚动列表会留下一份缩小版的**重影**（用户看到的就是
      // 「卡片里多出一个缩小的一块」）。
      child: RepaintBoundary(
        child: Listener(
          onPointerDown: widget.enabled ? (_) => _setPressed(true) : null,
          onPointerUp: widget.enabled ? (_) => _setPressed(false) : null,
          onPointerCancel: widget.enabled ? (_) => _setPressed(false) : null,
          child: widget.child,
        ),
      ),
    );
  }
}
