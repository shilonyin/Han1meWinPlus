import 'package:flutter/material.dart';

/// 全应用背景画布：柔和的**多色渐变**，参照 morrow（明隙）。
///
/// 原来整套界面走的是「纯色 Scaffold + 同色调卡片」，背景和卡片只差几个百分点亮度，
/// 卡片之间又只用一条 7.5% 的淡线分隔，结果整屏是一片没有色彩倾向的灰白——
/// 这正是和 morrow 差距最大的地方：它的背景本身就是一层带紫、粉、绿、橙的柔和渐变，
/// 卡片半透明地浮在上面，层次由「背景有内容」撑起来，而不是靠画线。
///
/// 这里不照搬它的原生背景层（morrow 的紫调底走 Windows 原生合成）。
/// 纯 Flutter 实现：一层对角主渐变 + 若干柔和径向光晕，颜色全部从
/// [ColorScheme.primary] 派生，所以换主题色时整片背景跟着走。
class AppBackdrop extends StatelessWidget {
  const AppBackdrop({
    super.key,
    required this.child,
    this.enabled = true,
    this.opacity = 1,
  });

  final Widget child;

  /// 关掉时直接透传（AMOLED 纯黑、播放页等不需要画布的场景）。
  final bool enabled;

  /// 画布整体不透明度。开着窗口材质（Mica / 亚克力）时调低，让系统那层
  /// 半透明透上来——否则这层不透明画布会把窗口材质整个盖住，材质开关就白开了。
  final double opacity;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _BackdropPainter(
                glow: scheme.primary,
                dark: dark,
                opacity: opacity.clamp(0, 1),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}

/// 画布只用纯色 + 渐变，不依赖任何资源，开销固定在一次静态绘制。
class _BackdropPainter extends CustomPainter {
  const _BackdropPainter({
    required this.glow,
    required this.dark,
    this.opacity = 1,
  });

  final Color glow;
  final bool dark;
  final double opacity;

  static Color _mix(Color a, Color b, double t) => Color.lerp(a, b, t)!;

  /// 所有颜色统一乘上画布不透明度，让整层能半透明地叠在窗口材质上。
  Color _a(Color color, [double alpha = 1]) =>
      color.withValues(alpha: (color.a * alpha * opacity).clamp(0, 1));

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    final rect = Offset.zero & size;
    // 亮色：带紫的白；深色：morrow 的深色画布配方（蓝紫 → 紫灰），
    // 关键是**不用纯黑**——纯黑会把层叠的卡片全部吃掉，看不出前后关系。
    final base = dark ? const Color(0xff131118) : const Color(0xfff9f8fc);
    final mid = dark
        ? _mix(const Color(0xff1e1b2c), glow, .14)
        : _mix(base, glow, .13);
    final far = dark
        ? _mix(const Color(0xff2a2440), glow, .18)
        : _mix(base, glow, .26);

    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [_a(base), _a(mid), _a(far)],
          stops: const [0, .52, 1],
        ).createShader(rect),
    );

    // 三个柔和光晕：暖橙、冷绿、粉紫。位置与 morrow 的画布参考图一致，
    // 半径给得很大、透明度压得很低，只为让底色"有颜色在流动"而不抢内容。
    // 深色下参考色要更向主色靠（否则绿/橙在暗底上会发脏），透明度也要抬起来，
    // 否则整片背景看不出颜色。
    final halos = <(Alignment, Color, double, double)>[
      // (位置, 参考色, 半径相对短边, 不透明度)
      (const Alignment(-.85, .95), const Color(0xffeddcd0), .95, dark ? .20 : .40),
      (const Alignment(.95, -.75), const Color(0xffd9e5db), .85, dark ? .16 : .32),
      (const Alignment(.75, .9), const Color(0xffe8d5ee), .90, dark ? .24 : .36),
    ];
    final shortest = size.shortestSide;
    for (final (alignment, reference, radiusScale, alpha) in halos) {
      final center = alignment.alongSize(size);
      final radius = shortest * radiusScale;
      // 参考色也要带一点主题色，否则绿/橙光晕会和紫主题打架。
      final color = _mix(reference, glow, dark ? .52 : .22);
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..shader = RadialGradient(
            colors: [_a(color, alpha), _a(color, 0)],
            stops: const [0, 1],
          ).createShader(Rect.fromCircle(center: center, radius: radius)),
      );
    }
  }

  @override
  bool shouldRepaint(_BackdropPainter old) =>
      old.glow != glow || old.dark != dark || old.opacity != opacity;
}
