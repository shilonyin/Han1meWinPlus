import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/settings.dart';
import '../../settings/settings_controller.dart';
import 'liquid_glass.dart';

/// 按「玻璃质感」设置渲染的面板：关闭档走纯色底，其余档走对应的玻璃材质。
///
/// 抽出来是为了让质感**全局统一** —— 设置页左栏的分组卡片、右栏的条目卡片、
/// 以及其他地方的卡片都用它，改档位时整个界面一起变，
/// 而不是只有用了 `LiquidGlassSurface` 的那一处变。
class GlassPanel extends ConsumerWidget {
  const GlassPanel({
    super.key,
    required this.child,
    required this.borderRadius,
    this.tint,
    this.solidColor,
    this.margin,
    this.padding,
    this.glassEnabled = true,
    this.border,
  });

  final Widget child;
  final BorderRadius borderRadius;

  /// 玻璃底色。省略时用 `surfaceContainerLow`。
  final Color? tint;

  /// 关闭档（`GlassQuality.off`）用的纯色底。省略时用半透明的 `surface`
  /// —— 各页原来的卡片底色不尽相同，传进来可以让"关闭"档保持各页原本的观感。
  final Color? solidColor;

  /// 外边距 / 内边距。各页原来的卡片是 `Container(margin:, padding:)` 画的，
  /// 这里接住这两个，替换时布局才不会变。
  final EdgeInsetsGeometry? margin;
  final EdgeInsetsGeometry? padding;

  /// 为 `false` 时即使开着玻璃也走纯色底。
  /// 用于列表里的选中项这类**需要突出显示**的场合（玻璃会把选中态的色块冲淡）。
  final bool glassEnabled;

  /// 额外描边（例如选中项的主色边框）。
  final BorderSide? border;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value;
    final quality = glassEnabled
        ? (settings?.glassQuality ?? GlassQuality.off)
        : GlassQuality.off;
    final opacity = settings?.glassSurfaceOpacity ?? .72;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final glassTint = tint ?? scheme.surfaceContainerLow;

    if (quality == GlassQuality.off) {
      return Container(
        margin: margin,
        padding: padding,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          // 半透明卡片浮在背景画布上：透出一点底下的渐变，卡片才有"材质感"。
          color:
              solidColor ?? scheme.surface.withValues(alpha: dark ? .62 : .72),
          borderRadius: borderRadius,
          border: border == null ? null : Border.fromBorderSide(border!),
        ),
        child: child,
      );
    }
    final panel = DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        border: border == null ? null : Border.fromBorderSide(border!),
      ),
      child: LiquidGlassSurface(
        tint: glassTint,
        dark: dark,
        borderRadius: borderRadius,
        material: GlassMaterial.quality(
          quality: quality,
          tint: glassTint,
          dark: dark,
          readable: false,
          borderRadius: borderRadius,
          opacity: opacity,
        ),
        // padding 在玻璃**内部**（内容距边缘），margin 在外。
        child: padding == null
            ? child
            : Padding(padding: padding!, child: child),
      ),
    );
    return margin == null ? panel : Padding(padding: margin!, child: panel);
  }
}
