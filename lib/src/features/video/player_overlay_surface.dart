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
    this.blurSigma = 10,
    super.key,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;

  /// 背景模糊半径。
  ///
  /// 默认值调得比早期（18）小：压在视频上时 18 会把背后的画面糊成一团色块，
  /// 磨砂感过重、看起来像一块不透明的塑料板。10 仍能压住画面细节，但底下的
  /// 内容透得出来，观感更接近「悬在画面之上」而不是「贴在画面上」。
  /// 小角标可以再调小一点省开销。
  final double blurSigma;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    // 边框画在模糊层之外：模糊会把条内的一切糊掉，边框留在外层才能保持清晰。
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      // 白边也压淡一档：底色变透之后，原来那道 8% 的边会显得比面板本身还重。
      border: Border.all(color: Colors.white.withValues(alpha: .06)),
    ),
    child: ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
        child: ColoredBox(
          // 底黑从 48% 降到 34%：模糊减弱之后需要更透的底色才看得出背后的画面，
          // 否则两处一起收会让面板看起来跟改之前一样实。
          color: Colors.black.withValues(alpha: .34),
          child: Padding(padding: padding, child: child),
        ),
      ),
    ),
  );
}
