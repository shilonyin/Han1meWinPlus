import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 可切换图标（如收藏的实心/描边）在切换时做一次「轻弹」。
///
/// 借鉴 affectUI Tool Call Card 的「二元切换要交叉淡化、不要硬切」原则，
/// 以及 bento 动效里「从静止起的弹簧」手感：只在 [filled] 变化的那一刻动，
/// 平时完全静止——不常驻播放，不占 Ticker。
///
/// - 由描边变实心（[filled] false→true）：图标轻微放大回弹 + 填充从 0 淡到 1。
/// - 由实心变描边：反向，同样一次性的回弹。
/// - 系统「减少动画」开启（[motionDuration] 归零）时直接跳到终态。
class BouncyToggleIcon extends StatefulWidget {
  const BouncyToggleIcon({
    super.key,
    required this.icon,
    required this.filled,
    this.size = 20,
    this.color,
  });

  final IconData icon;
  final bool filled;
  final double size;
  final Color? color;

  @override
  State<BouncyToggleIcon> createState() => _BouncyToggleIconState();
}

class _BouncyToggleIconState extends State<BouncyToggleIcon>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  @override
  void didUpdateWidget(covariant BouncyToggleIcon old) {
    super.didUpdateWidget(old);
    // 只在 filled 真正翻转时播放一次；其它属性变化不动。
    if (old.filled != widget.filled) {
      if (motionEnabledOf(context)) {
        _c.forward(from: 0);
      } else {
        _c.value = 1;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final target = widget.color;
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // p:0→1。单次过冲回弹：sin(πp) 在 p=0.5 取峰值、两端归 0，
        // 所以 scale 从 1 平滑弹到 1.10 再回落 1——不 hard clamp，不会有「停住」的顿感。
        final p = _c.value;
        final pop = math.sin(math.pi * p); // 0→1→0
        final scale = 1 + 0.10 * pop;
        // 填充做交叉淡化：切换瞬间从 0 淡到目标（实心=1，描边=0），同样用 easeOut 让收尾干净。
        final fillValue = widget.filled
            ? Curves.easeOut.transform(p)
            : 1 - Curves.easeOut.transform(p);
        return Transform.scale(
          scale: scale,
          child: Icon(
            widget.icon,
            size: widget.size,
            // 描边态用 color，实心态用更强的填充色；两者按 fillValue 混合。
            color: target,
            fill: fillValue.clamp(0.0, 1.0),
          ),
        );
      },
    );
  }
}