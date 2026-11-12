import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 同组入场的错开步长（第几个就往后推几档）。这不是动效时长本身，
/// 只是让几块内容先后出现；减少动画时整段被跳过，不套 motionDuration。
const Duration _staggerStep = Duration(milliseconds: 60);

/// 内容块入场：淡入 + 轻微上移（8px），一次性，按 [order] 错开。
///
/// 借鉴 CodedVisuals 的做法：页面首次出现时，几块数据卡先后浮上来。
/// 观感比「啪一下全在」更有层次。只做一次，不回退、不循环。
/// 之后再 build 不会重播（用 [\_played] 记住）。
///
/// 系统「减少动画」开启时直接呈现终态。
class FadeSlideIn extends StatefulWidget {
  const FadeSlideIn({
    super.key,
    required this.child,
    this.order = 0,
    this.offset = 8,
  });

  final Widget child;

  /// 在同组里是第几个（从 0 起），用来把入场先后错开。
  /// 用序号而不是裸 Duration：错开量由组件内部算，减少动画时统一归零。
  final int order;

  /// 起始下移的像素，到位后归 0。
  final double offset;

  @override
  State<FadeSlideIn> createState() => _FadeSlideInState();
}

class _FadeSlideInState extends State<FadeSlideIn>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.emphasis,
    value: 0,
  );
  bool _played = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_played) return;
    _played = true;
    if (!motionEnabledOf(context)) {
      _c.value = 1;
      return;
    }
    _schedule();
  }

  /// 按 order 错开播放；错开量是设计选择（60ms 一档），不是动效时长本身，
  /// 所以不套 motionDuration，但减少动画时整段跳过（见 didChangeDependencies）。
  void _schedule() {
    final step = _staggerStep * widget.order;
    if (step == Duration.zero) {
      _c.forward();
      return;
    }
    Future<void>.delayed(step, () {
      if (mounted) _c.forward();
    });
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
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, widget.offset * (1 - t)),
            child: child,
          ),
        );
      },
      child: widget.child,
    );
  }
}
