import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../core/glass_budget.dart';
import '../../../core/runtime_visual_guard.dart';
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
  /// 各档玻璃的**底色浓度**（不透明系数）。
  ///
  /// 提取成静态方法，是因为"面板到底呈现多不透明"不只影响渲染 ——
  /// `GlassPanel` 还要按这个系数把面板压成一层等效底色，才能判断面板上的
  /// 文字读不读得清。两处若各写一份，迟早会不一致，那正是可读性失守的开始。
  ///
  /// 注意磨砂档的浓度**由滑条决定**，另外两档是固定值：三档的差异不只在模糊强度。
  static double densityFor(GlassQuality quality, double opacity) =>
      switch (quality) {
        GlassQuality.off => 0.0, // 关闭档不走玻璃渲染，仅为穷尽 switch
        GlassQuality.frosted => opacity, // 磨砂：浓度直接由滑条决定
        GlassQuality.clear => .12, // 超透：几乎全透明，只留一道亮边
        GlassQuality.liquid => .55, // 液体玻璃：居中，透明度固定
      };

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
    final density = densityFor(quality, opacity);
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

  /// 仅供测试：每次解析出折射路径时回调一次。
  ///
  /// 存在的理由：路径最终只体现为一个 `ui.ImageFilter`，而它没有可比较的相等性，
  /// 从外部断言不了"滚动时确实换了路径"。有了这个钩子，测试可以在**真实 widget 树**
  /// 里断言滚动的确触发降级、静止时又回到默认路径 —— 而不是只测纯函数。
  @visibleForTesting
  static void Function(GlassRefractionPath path)? debugOnRefractionPathResolved;

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

  /// 最近祖先滚动视图的滚动状态；不在滚动视图里时为 `null`。
  ///
  /// 订阅它而不是在别处广播"是否在滚动"，是为了让玻璃自己知道自己正被滚过
  /// —— `GlassPanel` 的 19 个调用点分散在各页，没有一处适合统一告知。
  ValueNotifier<bool>? _scrollNotifier;

  /// 光学值 + 预算输入的合并监听源。
  ///
  /// **必须缓存**：`Listenable.merge` 每次调用都返回**新对象**，而
  /// `AnimatedBuilder` 在 `animation` 换对象时会退订旧的、订阅新的。若每次
  /// build 都新建，滚动期间就等于每帧把订阅拆掉重装一遍 —— 白做，且面板越多越贵。
  ///
  /// `_optics` 与 `degraded` 都是稳定对象，只有 `_scrollNotifier` 会随祖先滚动
  /// 视图变化，所以只在它变化时让缓存失效（见 [_syncScrollNotifier]）。
  Listenable? _opticsAndBudgetCache;
  Listenable get _opticsAndBudget =>
      _opticsAndBudgetCache ??= Listenable.merge([
        _optics,
        _scrollNotifier,
        RuntimeVisualGuard.instance.degraded,
      ]);

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
    _syncScrollNotifier();
  }

  /// 找到最近祖先滚动视图的滚动状态通知器，并在变化时切换订阅。
  ///
  /// `Scrollable.maybeOf` 必须在 `didChangeDependencies` 里调用 —— 它会向
  /// `_ScrollableScope` 建立依赖，把这一步放进 `build` 会破坏"build 中不建依赖"
  /// 的约束。
  void _syncScrollNotifier() {
    final next = Scrollable.maybeOf(context)?.position.isScrollingNotifier;
    if (identical(next, _scrollNotifier)) return;
    _scrollNotifier?.removeListener(_reportScrollToGuard);
    _scrollNotifier = next;
    // 监听源变了，缓存作废，下次 build 重新合并。
    _opticsAndBudgetCache = null;
    next?.addListener(_reportScrollToGuard);
    _reportScrollToGuard();
  }

  /// 把"这个面板是否正在被滚动"报给运行时守卫。
  ///
  /// 守卫只统计**连续交互期间**的帧；静止帧进分母会把真实掉帧率稀释掉
  /// （静止时几乎不掉帧），那样守卫永远不会触发。
  ///
  /// 源键用 `this`（而不是那个 notifier 对象）：同一个滚动视图上的多个面板
  /// **共享同一个 `isScrollingNotifier`**，拿它当键的话，其中一个面板销毁就会
  /// 把源摘掉，而其它面板还在滚 —— 守卫会误以为交互已结束。每个 State 各算
  /// 一个源，销毁时只摘掉自己的。
  void _reportScrollToGuard() {
    RuntimeVisualGuard.instance.setSourceActive(
      this,
      _scrollNotifier?.value ?? false,
    );
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
    // 摘掉自己的滚动源：不摘的话守卫的活跃集合里会一直留着这个已销毁的面板，
    // 于是"永远有人在滚动"，静止帧被算进分母、守卫再也降不了级。
    _scrollNotifier?.removeListener(_reportScrollToGuard);
    RuntimeVisualGuard.instance.setSourceActive(this, false);
    _press.dispose();
    _light.dispose();
    _shader?.dispose();
    super.dispose();
  }

  ui.ImageFilter _filter(
    Size size,
    GlassMaterial material, {
    GlassRefractionPath path = GlassRefractionPath.realtime,
  }) {
    if (material.liquid <= .001) {
      return ui.ImageFilter.blur(sigmaX: material.blur, sigmaY: material.blur);
    }
    final ui.ImageFilter refraction;
    // 只有 realtime 路径才用逐像素着色器。fallback 走下面那支放大平移，
    // 参数与"着色器不可用"时完全相同 —— 两侧观感一致是它成立的前提。
    final shader = path == GlassRefractionPath.realtime ? _shader : null;
    if (shader != null) {
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
                      // 光学值（光照/按压）**或**预算输入（滚动/守卫降级）任一变化
                      // 都要重算滤镜。合并成一个 listenable，免去嵌套两层 builder。
                      animation: _opticsAndBudget,
                      builder: (_, _) => LayoutBuilder(
                        builder: (_, constraints) {
                          // 预算只决定走哪条折射路径；模糊强度与底色都来自
                          // material，不经过这里 —— 滚动期间它们不可能变化。
                          final path = resolveGlassRefractionPath(
                            isScrolling: _scrollNotifier?.value ?? false,
                            tickerActive: TickerMode.valuesOf(context).enabled,
                            guardDegraded: RuntimeVisualGuard.instance.degraded.value,
                          );
                          LiquidGlassSurface.debugOnRefractionPathResolved?.call(path);
                          final filter = _filter(
                            constraints.biggest,
                            material,
                            path: path,
                          );
                          final glass = DecoratedBox(
                            decoration: material.decoration.copyWith(
                              boxShadow: const [],
                            ),
                          );
                          // 纯模糊档（磨砂）的滤镜在**所有面板上完全相同**，可以让
                          // 引擎只采样一次背景给一屏玻璃共用 —— 多块玻璃时这是最大的
                          // 一笔节省。`BackdropGroup` 由上层提供（见 app_widget）。
                          //
                          // 走折射的档位**不共享**：着色器 uniform 里带着这一块自己的
                          // 光照与按压值，各块滤镜不同，共享背景输入没有意义。
                          if (material.liquid <= .001) {
                            return BackdropFilter.grouped(
                              filter: filter,
                              child: glass,
                            );
                          }
                          return BackdropFilter(filter: filter, child: glass);
                        },
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
