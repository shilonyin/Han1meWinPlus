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
  const PressScale({super.key, required this.child, this.scale = .96});

  final Widget child;

  /// 按下时的缩放比例。
  final double scale;

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
    return Listener(
      onPointerDown: (_) => _setPressed(true),
      onPointerUp: (_) => _setPressed(false),
      onPointerCancel: (_) => _setPressed(false),
      child: AnimatedScale(
        scale: _pressed ? widget.scale : 1,
        duration: motionDuration(context, AppMotion.brief),
        curve: AppMotion.standardCurve,
        child: widget.child,
      ),
    );
  }
}
