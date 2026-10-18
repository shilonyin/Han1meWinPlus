import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/app_page_colors.dart';

/// 顶栏底下那条「内容滚过来就融进画布」的边缘，连带顶栏自己的底色。
///
/// 结构照 BiliPai（`feature/home/components/ProgressiveTopChrome.kt` 的
/// `BiliPaiImmersiveTopBar` + `design-system/.../blur/ProgressiveFade.kt`）：
///
/// 1. 顶栏那 [extent] 像素是一段**实色平台**，内容滚到它下面完全看不见；
/// 2. 平台之下接一段下沿延伸，alpha 按 Telegram / Nagram 那套 5 阶非线性
///    停靠点衰减（1.0 → 232/255 → 176/255 → 96/255 → 0）；
/// 3. 整块底边两角圆角 28（BiliPai 的 `BiliPaiProgressiveTopBlurShape`），
///    嵌在画布上时能看出这是一块浮起的带子，而不是一条通栏色带。
///
/// 为什么要 5 阶而不是线性：线性渐变在感知亮度上变化不均，会出现马赫带，
/// 滚过去时看着像一道生硬的切面。
///
/// 模糊半径必须小。BiliPai 能用 10dp 是因为它的模糊**随高度衰减**（顶部最强、
/// 底部归零）；Flutter 的 `BackdropFilter` 只有统一 sigma，照抄会把整条带子
/// 糊成一块色斑 —— 那就是上一版被说成「液化」的样子。这里取 5，配合下面
/// 那段渐隐遮罩，只有贴着顶栏的一窄条能看到磨砂。
class PageColorsFade extends StatelessWidget {
  const PageColorsFade({
    super.key,
    required this.extent,
    required this.progress,
    this.blurSigma = 5,
    this.child,
  });

  /// 顶栏高度。这一段是实色平台，不会透出底下的内容。
  final double extent;

  /// 0 = 完全不显示，1 = 完整强度。由滚动位置线性给出。
  final double progress;

  /// 模糊半径（逻辑像素）。保持小值，理由见类文档。
  final double blurSigma;

  /// 顶栏内容。它压在实色平台之上，高度应当等于 [extent]。
  final Widget? child;

  /// 下沿延伸量：BiliPai 从 20dp 起步，渐隐满了再加 28dp。
  static const double _minExtension = 20;
  static const double _extraExtension = 28;

  /// 底角圆角，与 BiliPai 的 `BiliPaiProgressiveTopBlurShape` 一致。
  static const double _radius = 28;

  /// 整块的总高度（实色平台 + 下沿延伸）。
  static double totalHeight(double extent, double progress) =>
      extent + extensionOf(progress);

  /// 下沿延伸的高度。
  static double extensionOf(double progress) =>
      _minExtension + _extraExtension * progress.clamp(0.0, 1.0);

  /// Telegram 原生 alpha 阶梯（255 基准）。
  static const List<double> _alphaFactors = [
    1.0,
    232 / 255,
    176 / 255,
    96 / 255,
    0.0,
  ];
  static const List<double> _positions = [0.0, 0.25, 0.5, 0.75, 1.0];

  /// 下沿延伸分成几段做递减模糊。
  ///
  /// Flutter 的 `BackdropFilter` 只有统一 sigma，而 BiliPai 的模糊是「顶部最强、
  /// 到底归零」。整条用同一个 sigma，滚过去的内容会被糊成一整块色斑 ——
  /// 那就是「液化」。这里把延伸段切成几档，逐档换更小的 sigma 逼近那条曲线。
  static const int _segments = 6;

  /// 平台段的不透明度。
  ///
  /// 不给 1.0：留一点缝，滚到下面去的内容会以糊化的影子透出来，这才是玻璃。
  /// 给 1.0 就是一条实色通栏，与没有顶栏底色的区别只剩下面那道渐隐。
  /// 也不能再低：低于 0.8 内容轮廓会清晰地游过去，压不住顶栏上的字。
  static const double _platformAlpha = 0.9;

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) {
      return SizedBox(height: extent, child: child);
    }
    final total = totalHeight(extent, t);
    // 平台在整块里的占比。BiliPai 的 createStops 把这个钳到 0.85。
    final plateau = (extent / total).clamp(0.0, 0.85);
    final platformHeight = total * plateau;
    final colour = AppPageColors.of(Theme.of(context).brightness);
    return SizedBox(
      height: total,
      width: double.infinity,
      child: Stack(
        children: [
          // 模糊层：平台段用满强度，延伸段按 [t] 分段递减。
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(_radius),
                ),
                child: Stack(
                  children: [
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: platformHeight,
                      child: _blur(blurSigma * t),
                    ),
                    for (var i = 0; i < _segments; i++)
                      if (blurSigma * t * (1 - i / _segments) > 0.05)
                        Positioned(
                          top: platformHeight + (total - platformHeight) * i / _segments,
                          left: 0,
                          right: 0,
                          height: (total - platformHeight) / _segments + 0.5,
                          child: _blur(blurSigma * t * (1 - i / _segments)),
                        ),
                  ],
                ),
              ),
            ),
          ),
          // 渐隐遮罩：压在模糊层之上，把带子下沿按 5 阶非线性 alpha 溶进画布。
          Positioned.fill(
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(_radius),
                ),
                child: CustomPaint(
                  painter: _ProgressiveFadePainter(
                    colour: colour,
                    strength: t,
                    plateau: plateau,
                  ),
                ),
              ),
            ),
          ),
          if (child != null)
            SizedBox(height: extent, child: child),
        ],
      ),
    );
  }

  Widget _blur(double sigma) => ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: const SizedBox.expand(),
        ),
      );
}

/// 在 [plateau] 之前保持纯色，之后按 5 阶非线性 alpha 衰减到 0。
class _ProgressiveFadePainter extends CustomPainter {
  const _ProgressiveFadePainter({
    required this.colour,
    required this.strength,
    required this.plateau,
  });

  final Color colour;

  /// 整体不透明度系数，跟着滚动进度从 0 长到 1。
  final double strength;

  /// 纯色平台在整块高度里的占比（0–0.85）。
  final double plateau;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || colour.a <= 0 || strength <= 0) return;
    final p = plateau.clamp(0.0, 0.85);
    // 平台段整段同一档不透明度，剩下 4 个停靠点重映射到 [p, 1]。
    final positions = <double>[0, p];
    final alphas = <double>[
      PageColorsFade._platformAlpha,
      PageColorsFade._platformAlpha,
    ];
    for (var i = 1; i < PageColorsFade._positions.length; i++) {
      positions.add(p + (1 - p) * PageColorsFade._positions[i]);
      alphas.add(
        PageColorsFade._alphaFactors[i] * PageColorsFade._platformAlpha,
      );
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset.zero,
          Offset(0, size.height),
          [
            for (final a in alphas)
              colour.withValues(alpha: colour.a * strength * a),
          ],
          positions,
        ),
    );
  }

  @override
  bool shouldRepaint(_ProgressiveFadePainter oldDelegate) =>
      oldDelegate.colour != colour ||
      oldDelegate.strength != strength ||
      oldDelegate.plateau != plateau;
}
