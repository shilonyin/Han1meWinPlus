import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/settings.dart';

/// Interpolated optical values; content is deliberately outside this state.
@immutable
class GlassMaterial {
  const GlassMaterial({
    required this.blur,
    required this.liquid,
    required this.decoration,
  });
  final double blur, liquid;
  final BoxDecoration decoration;
  factory GlassMaterial.liquid({
    required Color tint,
    required bool dark,
    required bool readable,
    required BorderRadius borderRadius,
  }) => GlassMaterial(
    blur: 5,
    liquid: 1,
    decoration: BoxDecoration(
      borderRadius: borderRadius,
      border: Border.all(color: Colors.transparent, width: 1.6),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          tint.withValues(
            alpha: readable
                ? .88
                : dark
                ? .40
                : .25,
          ),
          tint.withValues(
            alpha: readable
                ? .82
                : dark
                ? .24
                : .09,
          ),
          tint.withValues(
            alpha: readable
                ? .88
                : dark
                ? .34
                : .18,
          ),
        ],
      ),
    ),
  );
  /// 按质感档位构造材质。三档的区别**不只是模糊强度**：
  /// 磨砂糊得实、超透透得清、液体玻璃走边缘折射。
  factory GlassMaterial.quality({
    required GlassQuality quality,
    required Color tint,
    required bool dark,
    required bool readable,
    required BorderRadius borderRadius,
    required double opacity,
  }) {
    // 三档刻意拉开差距，切换时一眼能看出不同。
    final blur = switch (quality) {
      GlassQuality.off => 0.0, // 关闭档不会走到这里，仅为 switch 穷尽
      GlassQuality.frosted => 26.0, // 糊得最狠
      GlassQuality.clear => 2.0, // 几乎不糊，看清底下
      GlassQuality.liquid => 6.0,
    };
    // 折射强度。超透档给一个很小的值：它需要**边缘高光**来表现"玻璃很亮很透"
    // （morrow 的 clear 就是靠一道亮白边表达的），完全为 0 的话边缘会一并消失、
    // 只剩一块淡底，看不出是玻璃。
    final liquid = switch (quality) {
      GlassQuality.off => 0.0,
      GlassQuality.frosted => 0.0, // 纯模糊，无折射无亮边
      GlassQuality.clear => .35, // 很弱的折射 + 可见亮边
      GlassQuality.liquid => 1.0, // 完整折射
    };
    // 底色浓度（照 morrow 的三档语义）：
    // - 磨砂：**基数用满值**，直接由滑条决定 —— 20% 是很透的"轻盈"、100% 接近实色的"纯粹"。
    //   原来沿用了 .25/.09/.18 这组给折射档设计的淡基数，滑条拉满也只有 0.25 不透明度，
    //   所以会"调到 100% 也不明显"。
    // - 超透：几乎全透明，只留一道很亮的边缘
    // - 液体玻璃：居中，透明度固定
    final density = switch (quality) {
      GlassQuality.off => 0.0,
      GlassQuality.frosted => opacity,
      GlassQuality.clear => .12,
      GlassQuality.liquid => .55,
    };
    // density 已经就是最终的不透明系数（磨砂档里含滑条值），不再乘别的基数 ——
    // 三个 stop 只在明暗上做一点起伏，看起来才像玻璃而不是一块死色。
    double shade(double factor) => (density * factor).clamp(0.0, 1.0);
    return GlassMaterial(
      blur: blur,
      liquid: liquid,
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: Border.all(color: Colors.transparent, width: 1.6),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            tint.withValues(alpha: shade(1.0)),
            tint.withValues(alpha: shade(.82)),
            tint.withValues(alpha: shade(.94)),
          ],
        ),
      ),
    );
  }

  static GlassMaterial lerp(GlassMaterial a, GlassMaterial b, double t) =>
      GlassMaterial(
        blur: ui.lerpDouble(a.blur, b.blur, t)!,
        liquid: ui.lerpDouble(a.liquid, b.liquid, t)!,
        decoration: BoxDecoration.lerp(a.decoration, b.decoration, t)!,
      );
  @override
  bool operator ==(Object other) =>
      other is GlassMaterial &&
      blur == other.blur &&
      liquid == other.liquid &&
      decoration == other.decoration;
  @override
  int get hashCode => Object.hash(blur, liquid, decoration);
}

class GlassMaterialTween extends Tween<GlassMaterial> {
  GlassMaterialTween({super.begin, super.end});
  @override
  GlassMaterial lerp(double t) => GlassMaterial.lerp(begin!, end!, t);
}

/// A cross-platform optical material. Impeller gets curved per-pixel refraction;
/// other backends use a real magnifying backdrop filter with the same light rim.
class LiquidGlassSurface extends StatefulWidget {
  const LiquidGlassSurface({
    super.key,
    required this.child,
    required this.tint,
    required this.dark,
    required this.borderRadius,
    this.canvas = false,
    this.readable = false,
    this.transparentCanvas = true,
    this.material,
  });
  final GlassMaterial? material;
  final Widget child;
  final Color tint;
  final bool dark, canvas, readable;

  /// Only transparent canvases must leave the desktop-facing interior unpainted.
  final bool transparentCanvas;
  final BorderRadius borderRadius;
  @override
  State<LiquidGlassSurface> createState() => _LiquidGlassSurfaceState();
}

class _LiquidGlassSurfaceState extends State<LiquidGlassSurface>
    with SingleTickerProviderStateMixin {
  static Future<ui.FragmentProgram>? _program;
  ui.FragmentShader? _shader;
  bool _loadingShader = false;
  late final AnimationController _press;
  final ValueNotifier<Offset> _light = ValueNotifier(const Offset(-.65, -.8));
  late final Listenable _optics = Listenable.merge([_light, _press]);
  bool get _filterEnabled => !widget.canvas || !widget.transparentCanvas;
  bool get _needsRefraction => (widget.material?.liquid ?? 1) > .001;

  @override
  void initState() {
    super.initState();
    _press =
        AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 180),
          reverseDuration: const Duration(milliseconds: 320),
        )..addStatusListener((status) {
          if (status == AnimationStatus.completed) _press.reverse();
        });
    if (_filterEnabled &&
        _needsRefraction &&
        ui.ImageFilter.isShaderFilterSupported) {
      _loadShader();
    }
  }

  @override
  void didUpdateWidget(LiquidGlassSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_needsRefraction) _resetInteraction();
    if (_filterEnabled &&
        _needsRefraction &&
        _shader == null &&
        ui.ImageFilter.isShaderFilterSupported) {
      _loadShader();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_motionEnabled) _resetInteraction();
  }

  bool get _motionEnabled =>
      !MediaQuery.disableAnimationsOf(context) && TickerMode.valuesOf(context).enabled;

  void _resetInteraction() {
    if (_press.isAnimating || _press.value != 0) _press.reset();
    if (_light.value != const Offset(-.65, -.8)) {
      _light.value = const Offset(-.65, -.8);
    }
  }

  Future<void> _loadShader() async {
    if (_loadingShader) return;
    _loadingShader = true;
    try {
      final program = await (_program ??= ui.FragmentProgram.fromAsset(
        'assets/shaders/liquid_glass.frag',
      ));
      if (mounted && _filterEnabled && _needsRefraction) {
        setState(() => _shader = program.fragmentShader());
      }
    } catch (_) {
      // A backend/asset failure retains the magnifying backdrop material.
    } finally {
      _loadingShader = false;
    }
  }

  @override
  void dispose() {
    _press.dispose();
    _light.dispose();
    _shader?.dispose();
    super.dispose();
  }

  ui.ImageFilter _filter(Size size, GlassMaterial material) {
    if (material.liquid <= .001) {
      return ui.ImageFilter.blur(sigmaX: material.blur, sigmaY: material.blur);
    }
    final ui.ImageFilter refraction;
    if (_shader case final shader?) {
      shader.setFloat(2, widget.borderRadius.topLeft.x);
      shader.setFloat(3, (widget.canvas ? 4 : 9) * material.liquid);
      shader.setFloat(4, _light.value.dx);
      shader.setFloat(5, _light.value.dy);
      shader.setFloat(6, _press.value);
      refraction = ui.ImageFilter.shader(shader);
    } else {
      final zoom =
          1 +
          (widget.canvas ? .004 : .014) *
              material.liquid *
              (1 + .3 * _press.value);
      final transform = Matrix4.identity()
        ..setEntry(0, 0, zoom)
        ..setEntry(1, 1, zoom)
        ..setEntry(0, 3, size.width * (1 - zoom) / 2)
        ..setEntry(1, 3, size.height * (1 - zoom) / 2);
      refraction = ui.ImageFilter.matrix(transform.storage);
    }
    return ui.ImageFilter.compose(
      outer: ui.ImageFilter.blur(sigmaX: material.blur, sigmaY: material.blur),
      inner: refraction,
    );
  }

  void _updateLight(PointerEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || box.size.isEmpty) return;
    final point = box.globalToLocal(event.position);
    final next = Offset(
      (point.dx / box.size.width * 2 - 1).clamp(-1.0, 1.0),
      (point.dy / box.size.height * 2 - 1).clamp(-1.0, 1.0),
    );
    if ((_light.value - next).distanceSquared > .0004) _light.value = next;
  }

  void _pressAt(PointerDownEvent event) {
    if (!_needsRefraction || !_motionEnabled) return;
    if (event.kind != ui.PointerDeviceKind.touch &&
        (event.buttons & kPrimaryButton) == 0) {
      return;
    }
    _updateLight(event);
    _press.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final motionEnabled = _motionEnabled;
    final material =
        widget.material ??
        GlassMaterial.liquid(
          tint: widget.tint,
          dark: widget.dark,
          readable: MediaQuery.highContrastOf(context) || widget.readable,
          borderRadius: widget.borderRadius,
        );
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _pressAt,
      onPointerCancel: (_) => _resetInteraction(),
      child: MouseRegion(
        onHover: !motionEnabled || !_needsRefraction ? null : _updateLight,
        onExit: !motionEnabled || !_needsRefraction
            ? null
            : (_) => _light.value = const Offset(-.65, -.8),
        child: CustomPaint(
          painter: widget.canvas
              ? null
              : _OuterGlassShadowPainter(
                  borderRadius: widget.borderRadius,
                  shadows: material.decoration.boxShadow ?? const [],
                ),
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              children: [
                // The transparent canvas cannot sample the OS desktop through a
                // Flutter backdrop. Leave its interior unpainted; retain the rim.
                if (_filterEnabled)
                  Positioned.fill(
                    child: AnimatedBuilder(
                      animation: _optics,
                      builder: (_, _) => LayoutBuilder(
                        builder: (_, constraints) => BackdropFilter(
                          filter: _filter(constraints.biggest, material),
                          child: DecoratedBox(
                            decoration: material.decoration.copyWith(
                              boxShadow: const [],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                widget.child,
                Positioned.fill(
                  child: IgnorePointer(
                    child: AnimatedBuilder(
                      animation: _optics,
                      builder: (_, _) => CustomPaint(
                        painter: LiquidRimPainter(
                          radius: widget.borderRadius.topLeft.x,
                          light: _light.value,
                          dark: widget.dark,
                          canvas: widget.canvas,
                          intensity: material.liquid,
                          press: _press.value,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Keeps blurred shadows outside the original glass outline. Clear materials
/// have a transparent fill, so a shifted shadow must not tint their interior.
class _OuterGlassShadowPainter extends CustomPainter {
  const _OuterGlassShadowPainter({
    required this.borderRadius,
    required this.shadows,
  });

  final BorderRadius borderRadius;
  final List<BoxShadow> shadows;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || shadows.isEmpty) return;
    final outline = borderRadius.toRRect(Offset.zero & size);
    canvas.save();
    final outside = Path()
      ..fillType = ui.PathFillType.evenOdd
      ..addRect(canvas.getLocalClipBounds())
      ..addRRect(outline);
    canvas.clipPath(outside);
    for (final shadow in shadows) {
      canvas.drawRRect(
        outline.shift(shadow.offset).inflate(shadow.spreadRadius),
        shadow.toPaint(),
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterGlassShadowPainter old) =>
      old.borderRadius != borderRadius || old.shadows != shadows;
}

class LiquidRimPainter extends CustomPainter {
  LiquidRimPainter({
    required this.radius,
    required this.light,
    required this.dark,
    this.canvas = false,
    this.intensity = 1,
    this.press = 0,
  });
  final double intensity;
  final double press;
  final double radius;
  final Offset light;
  final bool dark, canvas;
  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || intensity <= 0) return;
    final rect = (Offset.zero & size).deflate(.8);
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(radius));
    final glow = 1 + .38 * press;
    final gradient = LinearGradient(
      begin: Alignment(light.dx, light.dy),
      end: Alignment(-light.dx, -light.dy),
      colors: [
        Colors.white.withValues(
          alpha: ((dark ? .70 : .94) * intensity * glow)
              .clamp(0.0, 1.0)
              .toDouble(),
        ),
        Colors.white.withValues(alpha: .08 * intensity),
        const Color(0xFF77799F).withValues(alpha: .12 * intensity),
        Colors.white.withValues(
          alpha: (.55 * intensity * glow).clamp(0.0, 1.0).toDouble(),
        ),
      ],
      stops: const [0, .36, .66, 1],
    );
    canvas.drawRRect(
      rrect,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..shader = gradient.createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(2),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..shader = LinearGradient(
          begin: Alignment(light.dx, light.dy),
          end: Alignment.center,
          colors: [
            Colors.white.withValues(alpha: .17 * intensity),
            Colors.transparent,
          ],
        ).createShader(rect),
    );
    canvas.drawRRect(
      rrect.deflate(5),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = .65
        ..color = Colors.white.withValues(alpha: .10 * intensity),
    );
  }

  @override
  bool shouldRepaint(LiquidRimPainter old) =>
      old.intensity != intensity ||
      old.press != press ||
      old.radius != radius ||
      old.light != light ||
      old.dark != dark ||
      old.canvas != canvas;
}
