import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/app_page_colors.dart';

/// 顶栏下方那条「内容滚过来就淡进画布」的边缘。
///
/// 形状照抄 g1455 的 `GlassScrollEdge`（soft / top）：alpha 随距离按
/// `1 - Φ((d - centre) / sigma)` 衰减 —— Apple 那条 ramp 在读数分辨率内就是
/// erf（(y75-y25)/(y90-y10) 实测 0.50–0.55，erf 是 0.526，smoothstep 是 0.572）。
///
/// **为什么不直接用 `GlassScrollEdge`**：它的 tint 在浅色模式下恒为
/// `rgba(255,255,255,.85)`，会把顶栏那 56 像素推成近纯白（实测 253,253,254，
/// 而画布是 242,242,247），于是只有首页看着底色和别的页面不一样。它的
/// `appearance` 只有 light / dark 两个枚举，改不了颜色，所以在这里重画一遍，
/// 唯一区别是 tint 取画布色。
///
/// 玻璃质感靠 [blurSigma] 那层 `BackdropFilter`：先模糊底下滚过来的内容，
/// 再叠上画布色渐变。淡出带只覆盖顶栏下沿下面那几十像素，模糊代价有限。
class PageColorsFade extends StatelessWidget {
  const PageColorsFade({
    super.key,
    required this.extent,
    required this.progress,
    this.reach,
    this.blurSigma = 0,
  });

  /// 顶栏自身的高度：从屏幕顶端到这里是完全遮住的区域。
  final double extent;

  /// 淡出带与模糊的强度，0 完全透明、1 完全显出。
  ///
  /// 由滚动位置线性给出（滚到顶栏高度时为 1），所以往下滚是渐渐显出来，
  /// 不是越过某个阈值才「啪」地出现。
  final double progress;

  /// 淡出带总高度（含 [extent]）。缺省按 `GlassScrollEdge` 的 soft 上沿公式。
  final double? reach;

  /// 毛玻璃模糊半径。0 表示只画渐变。
  final double blurSigma;

  static const double _tintCentre = -10.5;
  static const double _tintSigma = 17;

  double get _effectiveReach =>
      reach ?? extent + math.max(13.8, _tintCentre + 3 * _tintSigma);

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) return const SizedBox.shrink();
    Widget band = SizedBox(
      height: _effectiveReach,
      width: double.infinity,
      child: CustomPaint(
        painter: _ErfFadePainter(
          colour: AppPageColors.of(Theme.of(context).brightness),
          centre: extent + _tintCentre,
          sigma: _tintSigma,
          strength: t,
        ),
      ),
    );
    if (blurSigma > 0) {
      band = ClipRect(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: blurSigma * t,
            sigmaY: blurSigma * t,
          ),
          child: band,
        ),
      );
    }
    return IgnorePointer(child: band);
  }
}

/// alpha 按 `1 - Φ((d - centre) / sigma)` 随距离 d（从屏幕顶端算起）衰减。
class _ErfFadePainter extends CustomPainter {
  const _ErfFadePainter({
    required this.colour,
    required this.centre,
    required this.sigma,
    required this.strength,
  });

  final Color colour;
  final double centre;
  final double sigma;

  /// 整体不透明度系数，跟着滚动进度从 0 长到 1。
  final double strength;

  static const int _stops = 17;

  @override
  void paint(Canvas canvas, Size size) {
    if (colour.a <= 0 || sigma <= 0 || strength <= 0) return;
    final double near = math.max(0, centre - 3 * sigma);
    final double far = centre + 3 * sigma;
    final colours = <Color>[];
    final stops = <double>[];
    for (var i = 0; i < _stops; i++) {
      final double t = i / (_stops - 1);
      final double d = near + (far - near) * t;
      colours.add(
        colour.withValues(
          alpha:
              colour.a * strength * (1 - _phi((d - centre) / sigma)),
        ),
      );
      stops.add(t);
    }
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = ui.Gradient.linear(
          Offset(0, near),
          Offset(0, far),
          colours,
          stops,
        ),
    );
  }

  /// 标准正态分布的 CDF，Abramowitz & Stegun 7.1.26（|error| < 1.5e-7）。
  static double _phi(double x) {
    final double z = x.abs() / math.sqrt2;
    final double t = 1 / (1 + 0.3275911 * z);
    final double erf = 1 -
        (((((1.061405429 * t - 1.453152027) * t) + 1.421413741) * t -
                    0.284496736) *
                t +
            0.254829592) *
            t *
            math.exp(-z * z);
    return x >= 0 ? 0.5 * (1 + erf) : 0.5 * (1 - erf);
  }

  @override
  bool shouldRepaint(_ErfFadePainter oldDelegate) =>
      oldDelegate.colour != colour ||
      oldDelegate.centre != centre ||
      oldDelegate.sigma != sigma;
}
