import 'package:flutter/material.dart';

import 'app_page_colors.dart';

/// 全应用背景画布：一层近乎平的页面底色，外加三道**很淡**的径向光晕。
///
/// 底色取 g1455 演示站的两个主题（见 [AppPageColors]）—— 页面要读起来就是站点
/// 那种干净的中性底，玻璃的层次由内容和玻璃自己撑，不靠背景造。
///
/// 光晕只留一点点。这里早先参照 morrow 做的是「多色渐变」：深色底压着紫黑、
/// 三个光晕开到 0.32~0.46，整屏肉眼可见地偏色。站点是平的，所以现在压到
/// 0.06~0.08 —— 只保证玻璃折射时抽得出一丝颜色，页面本身仍读作纯底色。
///
/// 纯 Flutter 实现，不依赖任何资源；颜色从 [ColorScheme.primary] 派生，
/// 所以换主题色时整片背景跟着走。
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
    // 底色照 g1455 演示站的两个主题来（见 AppPageColors）：亮色 `#F2F2F7`、
    // 暗色 `#070A12`，两个都是中性色。原来的深色底是 morrow 的紫黑
    // （`#0d0c10` → `#1a1726`），整屏会偏紫——那正是和演示站的差别所在。
    //
    // **为什么深色底仍然压得这么暗**：玻璃的 tint 是 `rgba(29,29,32,0.693)`
    // （明度约 11%）。背景只要比它亮，玻璃就浮不起来 —— 看上去只是"一块略暗的
    // 圆角矩形"，折射和亮边全都消失。
    //
    // 代价：底越暗，**不透明的普通卡片**越难靠底色深浅拉开层次，得靠描边与
    // 阴影。这是有意的取舍 —— 玻璃是这套界面的主角。
    final page = AppPageColors.of(
      dark ? Brightness.dark : Brightness.light,
    );
    // 渐变的另两端只在底色上偏一点点：演示站的页面本身是近乎平的，
    // 竖直方向的明度变化全靠滚动内容撑，底色自己不造层次。
    // 数值由 test/app_backdrop_test.dart 的「画布的光晕压得够淡」兜着：
    // 那里会真画一遍再采样，量出页面离纯底色最多偏多少。
    final mid = dark ? _mix(page, glow, .04) : _mix(page, glow, .03);
    final far = dark ? _mix(page, glow, .05) : _mix(page, glow, .05);
    final base = page;

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

    // 三个柔和光晕：暖橙、冷绿、粉紫。位置沿用 morrow 的画布参考图。
    //
    // 不透明度压到 0.06~0.08（早先是 0.32~0.46）：演示站的页面是**平的**，光晕开大了
    // 整屏就偏成暖粉/紫，底色取得再准也白搭 —— 实测早先那组数值下，暗色页面最偏的
    // 角落会从 `#070A12` 抬到 `#3F3D50`，完全是另一块颜色。留这一点是为了玻璃折射时
    // 抽得出一丝颜色，完全去掉的话整屏玻璃抽出来都是同一块灰。
    final halos = <(Alignment, Color, double, double)>[
      // (位置, 参考色, 半径相对短边, 不透明度)
      (const Alignment(-.85, .95), const Color(0xffeddcd0), .95, dark ? .07 : .07),
      (const Alignment(.95, -.75), const Color(0xffd9e5db), .85, dark ? .06 : .06),
      (const Alignment(.75, .9), const Color(0xffe8d5ee), .90, dark ? .08 : .07),
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
