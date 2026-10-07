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
    // 亮色：带紫的白；深色：压到近黑（g1455 的演示底是 #101014）。
    //
    // **为什么深色要压这么暗**：玻璃的 tint 是 `rgba(29,29,32,0.693)`
    // （明度约 11%）。背景只要比它亮，玻璃就浮不起来 —— 看上去只是"一块略暗的
    // 圆角矩形"，折射和亮边全都消失。原来那套 morrow 配方（蓝紫 → 紫灰，
    // 最亮到 #2a2440）在浅色区域正确，在深色下恰好踩中这一点。
    //
    // 代价：底越暗，**不透明的普通卡片**越难靠底色深浅拉开层次，得靠描边与
    // 阴影。这是有意的取舍 —— 玻璃是这套界面的主角。
    final base = dark ? const Color(0xff0d0c10) : const Color(0xfff9f8fc);
    final mid = dark
        ? _mix(const Color(0xff14121c), glow, .10)
        : _mix(base, glow, .13);
    final far = dark
        ? _mix(const Color(0xff1a1726), glow, .13)
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

    // 三个柔和光晕：暖橙、冷绿、粉紫。位置与 morrow 的画布参考图一致。
    //
    // 深色下的不透明度**抬得比浅色更高**：底压到近黑之后，光晕成了玻璃唯一
    // 能折射出颜色的来源 —— 没有它，整屏玻璃抽出来都是同一块灰。
    final halos = <(Alignment, Color, double, double)>[
      // (位置, 参考色, 半径相对短边, 不透明度)
      (const Alignment(-.85, .95), const Color(0xffeddcd0), .95, dark ? .42 : .40),
      (const Alignment(.95, -.75), const Color(0xffd9e5db), .85, dark ? .34 : .32),
      (const Alignment(.75, .9), const Color(0xffe8d5ee), .90, dark ? .46 : .36),
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
