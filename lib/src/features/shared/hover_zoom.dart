import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 悬停时封面推近的幅度。
///
/// 与首页卡片（`video_card.dart` 的 `coverHoverScale`）同值：整套界面里
/// 悬停推近只有这一档，同一张封面换到哪个页面观感都一样。
///
/// 只放大**图片**，外层裁切框不动 —— 所以角标、描边、卡片占位都留在原位，
/// 观感是「图在框里推近」，而不是整张卡片被撑大把邻居挤走。
const double hoverCoverScale = 1.06;

/// 悬停推近的时长。
///
/// 比按下态（`AppMotion.brief`，150ms）慢一档：鼠标划过一排卡片时，
/// 太快会看起来像在抖，慢半拍才有「凑近看」的意思。
const Duration hoverCoverDuration = Duration(milliseconds: 260);

/// 卡片的悬停状态：鼠标进入整张卡片时把 [builder] 的 `hovered` 置真。
///
/// 命中区是**整张卡**（封面 + 标题），不是只有封面：用户的动作是「鼠标移到
/// 卡片上」，停在标题上时封面也该保持推近；否则鼠标一往标题上移封面就缩回去，
/// 看着像在闪。
///
/// 只负责状态，不决定长什么样 —— 各张卡片结构差得远（角标、描边、多选圈
/// 都不一样），统一的是「什么时候算悬停」，而不是「悬停时画什么」。
class CardHover extends StatefulWidget {
  const CardHover({super.key, required this.builder, this.enabled = true});

  final Widget Function(BuildContext context, bool hovered) builder;

  /// 关掉时永远当作没悬停。多选态、禁用态这类不该有悬停反馈的场合用它。
  final bool enabled;

  @override
  State<CardHover> createState() => _CardHoverState();
}

class _CardHoverState extends State<CardHover> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
  }

  @override
  Widget build(BuildContext context) => MouseRegion(
    onEnter: widget.enabled ? (_) => _setHovered(true) : null,
    onExit: widget.enabled ? (_) => _setHovered(false) : null,
    child: widget.builder(context, widget.enabled && _hovered),
  );
}

/// 悬停时把封面推近的那一层。
///
/// 必须放在裁切框（`ClipRRect`）**里面**：推近后多出来的部分要被裁掉，
/// 漏到框外会盖住相邻卡片。压在封面上的角标、标题也留在它**外面** ——
/// 它们跟着放大会一起变模糊、还会从卡片边缘溢出去。
class ZoomOnHover extends StatelessWidget {
  const ZoomOnHover({
    super.key,
    required this.hovered,
    required this.child,
    this.scale = hoverCoverScale,
  });

  final bool hovered;
  final Widget child;
  final double scale;

  @override
  Widget build(BuildContext context) => AnimatedScale(
    scale: hovered ? scale : 1,
    duration: motionDuration(context, hoverCoverDuration),
    curve: AppMotion.standardCurve,
    child: child,
  );
}
