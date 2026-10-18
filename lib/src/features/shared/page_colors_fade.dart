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

  /// 下沿延伸量。BiliPai 是 20dp 起步、渐隐满了再加 28dp，这里压到 2 / 6。
  ///
  /// 两个原因。一是顶栏高度差着量级：BiliPai 的顶栏含搜索栏与 tab 有一百多
  /// dp，20–48dp 只占它一小截；本项目只有 56px，同样比例就是一条显眼的带子。
  /// 二是 `BackdropFilter` 的模糊会往外扩散，视觉边界比这里给的数值还宽
  /// 一截（sigma 5 大约再多一个 sigma 的距离）。首页轮播图滚到顶栏下方时
  /// 上缘正好落在延伸带里，24px 的延伸配上扩散，实测要糊掉四十多逻辑像素，
  /// 那是内容，不是顶栏。
  static const double _minExtension = 2;
  static const double _extraExtension = 6;

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

  /// 遮罩分三档叠出来，alpha 归零处的距离依次拉长。
  ///
  /// 每项是（原来的 sigma 系数，现在不参与模糊了、留作记录；alpha 归零处占
  /// 整块高度的比例；起始 alpha）。三档叠起来在顶部合计
  /// 1-(1-.6)(1-.55)(1-.5) ≈ 0.91，压得住顶栏上的字，往下按 5 阶台阶收干净。
  ///
  /// 早先这三档各自还带一层不同强度的模糊，本意是让模糊本身也渐隐。实际
  /// 不行：`BackdropFilter` 会往外扩散，延伸带上的内容被糊掉一条，首页
  /// 轮播图滚到顶栏下方时上缘就花了。现在模糊只剩平台那一段一层，这三档
  /// 纯做遮罩。
  static const List<(double sigma, double reach, double alpha)> _layers = [
    (1.0, 0.50, 0.60),
    (0.45, 0.75, 0.55),
    (0.18, 1.00, 0.50),
  ];

  @override
  Widget build(BuildContext context) {
    final t = progress.clamp(0.0, 1.0);
    if (t <= 0) {
      return SizedBox(height: extent, child: child);
    }
    final total = totalHeight(extent, t);
    final colour = AppPageColors.of(Theme.of(context).brightness);
    return SizedBox(
      height: total,
      width: double.infinity,
      child: Stack(
        children: [
          // 模糊只裁在实色平台那一段里。平台的 alpha 是 1，模糊本来也透不
          // 出来；可要是让它跟着铺到延伸带上，延伸带就变成「模糊 + 薄色」，
          // 内容滚到那儿会被糊成一条 —— 首页轮播图的上缘正是落在这里。
          // 下沿的过渡交给下面那层纯色渐隐，不参与模糊。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: extent,
            child: IgnorePointer(
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(_radius),
                ),
                child: BackdropFilter(
                  filter: ui.ImageFilter.blur(
                    sigmaX: blurSigma * t,
                    sigmaY: blurSigma * t,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          // 三档遮罩由强到弱铺开，每档自己按 5 阶台阶把 alpha 收到 0。
          // 它们铺满整块（平台 + 延伸），负责画底色并让下沿融进画布。
          for (final (_, reach, alpha) in _layers)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _LayerFadePainter(
                    colour: colour,
                    strength: t,
                    alpha: alpha,
                    reach: reach,
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
}

/// 单层模糊的遮罩：顶部按 [alpha] 起，到 [reach] 处收到 0。
///
/// 台阶走 Telegram 那套 5 阶非线性 alpha（1.0 → 232/255 → 176/255 → 96/255
/// → 0）。用线性的话，感知亮度变化不均会出马赫带，看着像一道生硬的切面。
class _LayerFadePainter extends CustomPainter {
  const _LayerFadePainter({
    required this.colour,
    required this.strength,
    required this.alpha,
    required this.reach,
  });

  final Color colour;

  /// 整体强度，跟着滚动进度从 0 长到 1。
  final double strength;

  /// 顶部这一层的不透明度。
  final double alpha;

  /// 收到 0 的位置，占整块高度的比例。
  final double reach;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.height <= 0 || colour.a <= 0 || strength <= 0 || reach <= 0) {
      return;
    }
    final end = reach.clamp(0.05, 1.0);
    final positions = <double>[
      for (final p in PageColorsFade._positions) p * end,
    ];
    final alphas = <double>[
      for (final f in PageColorsFade._alphaFactors) f * alpha,
    ];
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
  bool shouldRepaint(_LayerFadePainter oldDelegate) =>
      oldDelegate.colour != colour ||
      oldDelegate.strength != strength ||
      oldDelegate.alpha != alpha ||
      oldDelegate.reach != reach;
}
