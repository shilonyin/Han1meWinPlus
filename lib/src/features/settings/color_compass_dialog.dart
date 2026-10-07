import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import '../../core/settings.dart';
import '../../core/app_dialog.dart';
import '../shared/press_scale.dart';
import 'settings_glass_controls.dart';

/// 调色结果：选了预设主题色，或者选了一个自定义颜色。
sealed class ColorCompassResult {
  const ColorCompassResult();
}

/// 点了下面那排预设。
class ColorPresetResult extends ColorCompassResult {
  const ColorPresetResult(this.preset);
  final AppThemeColor preset;
}

/// 用色轮 / 明暗 / HEX 调出来的颜色。
class CustomColorResult extends ColorCompassResult {
  const CustomColorResult(this.color);
  final Color color;
}

/// 配色方案的名称（设置页行副标题、预设色板的提示都用它）。
String themeColorLabel(AppLocalizations l10n, AppThemeColor color) => switch (color) {
  AppThemeColor.rose => l10n.colorRose,
  AppThemeColor.blue => l10n.colorBlue,
  AppThemeColor.teal => l10n.colorTeal,
  AppThemeColor.amber => l10n.colorAmber,
  AppThemeColor.green => l10n.colorGreen,
  AppThemeColor.orange => l10n.colorOrange,
  AppThemeColor.indigo => l10n.colorIndigo,
  AppThemeColor.pink => l10n.colorPink,
  AppThemeColor.purple => l10n.colorPurple,
  AppThemeColor.white => l10n.colorWhite,
  AppThemeColor.custom => l10n.colorCustom,
};

/// 主题色罗盘：色轮选色相 / 饱和度，滑条调明暗，HEX 可手输，
/// 下面一排小色点直接切预设主题色。
///
/// 布局照 morrow（明隙）的调色罗盘，但把预设色板并了进来（尺寸收小），
/// 免得"选预设"和"自定义"要开两个弹窗。
///
/// 弹窗时**背景不变暗**：遮罩给全透明，页面保持原亮度。
/// 返回调色结果；`null` 表示取消。
Future<ColorCompassResult?> showColorCompassDialog(
  BuildContext context, {
  required Color initial,
  required String customHex,
  AppThemeColor? currentPreset,
}) => showAppDialog<ColorCompassResult>(
  context: context,
  builder: (context) => _ColorCompassDialog(
    initial: initial,
    customHex: customHex,
    currentPreset: currentPreset,
  ),
);

class _ColorCompassDialog extends StatefulWidget {
  const _ColorCompassDialog({
    required this.initial,
    required this.customHex,
    this.currentPreset,
  });

  final Color initial;
  final String customHex;
  final AppThemeColor? currentPreset;

  @override
  State<_ColorCompassDialog> createState() => _ColorCompassDialogState();
}

class _ColorCompassDialogState extends State<_ColorCompassDialog> {
  late HSVColor _hsv = HSVColor.fromColor(widget.initial);
  late final TextEditingController _hex = TextEditingController(
    text: _hexOf(_hsv),
  );
  bool _invalid = false;

  static String _hexOf(HSVColor hsv) =>
      '#${hsv.toColor().toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}';

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _set(HSVColor value) {
    setState(() {
      _hsv = value;
      _invalid = false;
      _hex.text = _hexOf(value);
    });
  }

  /// 把点击位置换算成色相（角度）+ 饱和度（离圆心的距离）。
  void _fromWheel(Offset point, double size) {
    final delta = point - Offset(size / 2, size / 2);
    _set(
      _hsv
          .withHue((math.atan2(delta.dy, delta.dx) * 180 / math.pi + 360) % 360)
          .withSaturation((delta.distance / (size / 2 - 10)).clamp(0.0, 1.0)),
    );
  }

  Color? _readHex() {
    final value = _hex.text.trim().replaceFirst('#', '');
    if (!RegExp(r'^[0-9a-fA-F]{6}$').hasMatch(value)) {
      setState(() => _invalid = true);
      return null;
    }
    return Color(0xFF000000 | int.parse(value, radix: 16));
  }

  void _applyHex() {
    final color = _readHex();
    if (color != null) _set(HSVColor.fromColor(color));
  }

  void _submit() {
    final color = _readHex();
    if (color != null) Navigator.pop(context, CustomColorResult(color));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Dialog(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: scheme.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Symbols.palette_rounded,
                      size: 22,
                      color: scheme.onSecondaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          l10n.colorCompassTitle,
                          style: textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          l10n.colorCompassGuide,
                          style: textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  PressScale(child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Symbols.close_rounded, size: 20),
                    tooltip: l10n.cancel,
                  )),
                ],
              ),
              const SizedBox(height: 16),
              // 色轮：拖动即改色相 / 饱和度。
              //
              // 它是一张**纯绘制**的色环（CustomPaint + GestureDetector），节点树里
              // 没有任何文字，不挂 Semantics 时读屏读过去是"空白一块"。这里给它一个
              // 标签，让它在无障碍树里是一张有名字的图（旁边那句说明已经有文字节点，
              // 不再重复写进 label）。
              Semantics(
                image: true,
                label: l10n.colorCompassTitle,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final size = math.min(212.0, constraints.maxWidth);
                    return Center(
                      child: GestureDetector(
                        onPanDown: (d) => _fromWheel(d.localPosition, size),
                        onPanUpdate: (d) => _fromWheel(d.localPosition, size),
                        child: MouseRegion(
                          cursor: SystemMouseCursors.precise,
                          child: SizedBox(
                            width: size,
                            height: size,
                            child: CustomPaint(painter: _ColorWheelPainter(_hsv)),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Icon(
                    Symbols.brightness_6_rounded,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  Expanded(
                    child: SettingsSlider(
                      value: _hsv.value,
                      onChanged: (value) => _set(_hsv.withValue(value)),
                    ),
                  ),
                  SizedBox(
                    width: 42,
                    child: Text(
                      '${(_hsv.value * 100).round()}%',
                      textAlign: TextAlign.end,
                      style: textTheme.labelSmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  AnimatedContainer(
                    duration: AppMotion.brief,
                    curve: AppMotion.standardCurve,
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      color: _hsv.toColor(),
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      border: Border.all(color: scheme.outlineVariant),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: TextField(
                      controller: _hex,
                      onSubmitted: (_) => _applyHex(),
                      onChanged: (_) {
                        if (_invalid) setState(() => _invalid = false);
                      },
                      decoration: InputDecoration(
                        labelText: l10n.colorHex,
                        hintText: '#7662BA',
                        isDense: true,
                        errorText: _invalid ? l10n.colorHexInvalid : null,
                        suffixIcon: PressScale(child: IconButton(
                          tooltip: l10n.colorPreview,
                          onPressed: _applyHex,
                          icon: const Icon(Symbols.check_rounded, size: 18),
                        )),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // 预设色板并到罗盘下面：尺寸收小到 26px，不再带文字标签（标签走 tooltip），
              // 这样一排能放下全部预设，也不用为了选预设再开另一个弹窗。
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final preset in AppThemeColor.values)
                    _PresetDot(
                      color: preset.swatchColor(widget.customHex),
                      label: themeColorLabel(l10n, preset),
                      icon: preset == AppThemeColor.custom
                          ? Symbols.colorize_rounded
                          : null,
                      selected: preset == widget.currentPreset,
                      onTap: () => Navigator.pop(
                        context,
                        ColorPresetResult(preset),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  PressScale(child: TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: Text(l10n.cancel),
                  )),
                  const SizedBox(width: 8),
                  PressScale(child: FilledButton(
                    onPressed: _submit,
                    child: Text(l10n.colorApply),
                  )),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 缩小版预设色点：26px 圆，选中打勾，悬停显示名称。
class _PresetDot extends StatelessWidget {
  const _PresetDot({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.icon,
  });

  final Color color;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground = icon != null
        ? scheme.onSurfaceVariant
        : (ThemeData.estimateBrightnessForColor(color) == Brightness.dark
              ? Colors.white
              : Colors.black87);
    return Tooltip(
      message: label,
      waitDuration: const Duration(milliseconds: 400),
      child: PressScale(child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: icon != null ? scheme.surfaceContainerHighest : color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? scheme.onSurface : scheme.outlineVariant,
              width: selected ? 2.5 : 1,
            ),
          ),
          child: icon != null
              ? Icon(icon, size: 13, color: foreground)
              : (selected
                    ? Icon(Symbols.check_rounded, size: 14, color: foreground)
                    : null),
        ),
      )),
    );
  }
}

/// 色轮：色相铺一圈，饱和度由中心向外递增，明暗整体压一层黑，最后画选中点。
class _ColorWheelPainter extends CustomPainter {
  _ColorWheelPainter(this.hsv);

  final HSVColor hsv;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.width / 2 - 10;
    final rect = Rect.fromCircle(center: center, radius: radius);

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const SweepGradient(
          colors: [
            Color(0xFFFF0000),
            Color(0xFFFFFF00),
            Color(0xFF00FF00),
            Color(0xFF00FFFF),
            Color(0xFF0000FF),
            Color(0xFFFF00FF),
            Color(0xFFFF0000),
          ],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..shader = const RadialGradient(
          colors: [Colors.white, Color(0x00FFFFFF)],
        ).createShader(rect),
    );
    canvas.drawCircle(
      center,
      radius,
      Paint()..color = Colors.black.withValues(alpha: 1 - hsv.value),
    );

    // 选中点：色相角度 + 饱和度半径。
    final angle = hsv.hue * math.pi / 180;
    final pointer =
        center +
        Offset(math.cos(angle), math.sin(angle)) * radius * hsv.saturation;
    canvas.drawCircle(
      pointer,
      9,
      Paint()
        ..color = Colors.black.withValues(alpha: .22)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    canvas.drawCircle(pointer, 8, Paint()..color = hsv.toColor());
    canvas.drawCircle(
      pointer,
      8,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(_ColorWheelPainter old) => hsv != old.hsv;
}
