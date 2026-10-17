import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../core/app_radius.dart';

/// 播放器浮层的统一材质：半透明黑底 + 背景模糊 + 极淡白边 + 圆角。
///
/// 底部控制条、暂停标记、音量提示、快进提示、导航胶囊都盖在视频画面上。
/// 它们曾经各写各的（控制条是渐隐底衬、暂停标记和音量提示是纯白实底卡片），
/// 换掉其中一个的观感之后其余几个就显得像从别的界面拼过来的，所以收成一处。
///
/// 圆角默认用 [AppRadius.xl]，小尺寸的角标类浮层传 [AppRadius.sm] 或
/// [AppRadius.pill]。
class PlayerOverlaySurface extends StatelessWidget {
  const PlayerOverlaySurface({
    required this.child,
    this.radius = AppRadius.xl,
    this.padding = EdgeInsets.zero,
    this.blurSigma = 18,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 背景模糊半径。大块的条用默认值，小角标可以调小一点省开销。
  final double blurSigma;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // 边框画在模糊层之外：模糊会把条内的一切糊掉，边框留在外层才能保持清晰。
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: Colors.white.withValues(alpha: .08)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: ColoredBox(
          color: Colors.black.withValues(alpha: .48),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}
