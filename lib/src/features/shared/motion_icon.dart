import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 状态图标切换（播放 ↔ 暂停这类）不该瞬间替换成另一个图标。
///
/// 换值时旧图标缩到 .25 并淡出、新图标从 .25 放大淡入，同时把 4 逻辑像素的模糊收掉，
/// 两个图标在同一格里插值、不动布局。数值来源见 `docs/ui-polish.md`（better-ui 的
/// 图标切换条目：`scale .25→1` + `opacity 0→1` + `blur 4→0`，300ms、不回弹）。
///
/// 系统关掉动效时 [motionDuration] 归零，[AnimatedSwitcher] 直接跳到终态。
class MotionStateIcon extends StatelessWidget {
  const MotionStateIcon({super.key, required this.icon, this.size, this.color});

  /// 当前该显示的图标；换值即触发过渡。
  final IconData icon;

  final double? size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: motionDuration(context, AppMotion.dialog),
      switchInCurve: AppMotion.enter,
      switchOutCurve: AppMotion.exit,
      // 默认布局是「新旧并排放」，换图标时会让这一格忽宽忽窄；这里改成叠放。
      layoutBuilder: (current, previous) => Stack(
        alignment: Alignment.center,
        children: [...previous, if (current != null) current],
      ),
      transitionBuilder: (child, animation) {
        final blur = Tween<double>(begin: 4, end: 0).animate(animation);
        return FadeTransition(
          opacity: animation,
          child: ScaleTransition(
            scale: Tween<double>(begin: .25, end: 1).animate(animation),
            child: AnimatedBuilder(
              animation: blur,
              builder: (context, inner) => ImageFiltered(
                imageFilter: ui.ImageFilter.blur(
                  sigmaX: blur.value,
                  sigmaY: blur.value,
                ),
                child: inner,
              ),
              child: child,
            ),
          ),
        );
      },
      child: Icon(icon, key: ValueKey<IconData>(icon), size: size, color: color),
    );
  }
}
