import 'package:flutter/material.dart';

import '../../core/app_motion.dart';

/// 里程表式滚动数字：值变化时每位数字竖向滚动到新值，涨向上、跌向下。
///
/// 借鉴 bento-ui-motion-grid 的 `roll()` 里程表做法，但收成 Flutter 组件：
/// - 只滚「数字」，货币/百分号/逗号等符号原地不动（按字符拆段，非数字直接显示）。
/// - 只在 [value] 变化时滚一次，平时静止。
/// - 系统「减少动画」开启时直接跳到终态。
/// - 用等宽数字（FontFeature.tabularFigures），滚动过程中宽度不跳。
///
/// 适合播放量、评分、倒计时、选集页码等会变的数字。
class RollingNumber extends StatefulWidget {
  const RollingNumber({
    super.key,
    required this.value,
    this.style,
    this.textAlign = TextAlign.start,
  });

  /// 要显示的数字（整数）。
  final int value;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  State<RollingNumber> createState() => _RollingNumberState();
}

class _RollingNumberState extends State<RollingNumber>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: AppMotion.standard,
  );

  late String _from = widget.value.toString();
  late String _to = widget.value.toString();

  @override
  void didUpdateWidget(covariant RollingNumber old) {
    super.didUpdateWidget(old);
    if (old.value != widget.value) {
      _from = _to;
      _to = widget.value.toString();
      if (motionEnabledOf(context)) {
        _c.forward(from: 0);
      } else {
        _c.value = 1;
        _from = _to;
      }
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = (widget.style ?? const TextStyle()).copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        final p = AppMotion.settle.transform(_c.value);
        final n = _max(_from.length, _to.length);
        final from = _from.padLeft(n, ' ');
        final to = _to.padLeft(n, ' ');
        final spans = <InlineSpan>[];
        for (var i = 0; i < n; i++) {
          final a = from[i];
          final b = to[i];
          final bothDigit = _isDigit(a) && _isDigit(b);
          if (bothDigit) {
            final y = _lerp((a.codeUnitAt(0) - 48).toDouble(),
                (b.codeUnitAt(0) - 48).toDouble(), p);
            spans.add(WidgetSpan(
              alignment: PlaceholderAlignment.middle,
              child: _DigitColumn(
                progress: y,
                style: style,
                heightFactor: 1.0,
              ),
            ));
          } else if (a == b) {
            spans.add(TextSpan(text: a == ' ' ? '' : a, style: style));
          } else {
            // 位宽变化（9→10）：直接取目标字符，不做滚动。
            spans.add(TextSpan(text: b == ' ' ? '' : b, style: style));
          }
        }
        return Text.rich(
          TextSpan(children: spans),
          style: style,
          textAlign: widget.textAlign,
        );
      },
    );
  }
}

class _DigitColumn extends StatelessWidget {
  const _DigitColumn({
    required this.progress,
    required this.style,
    required this.heightFactor,
  });

  /// 0..9 之间的浮点位置。
  final double progress;
  final TextStyle style;
  final double heightFactor;

  @override
  Widget build(BuildContext context) {
    final fontSize = style.fontSize ?? 14;
    final line = fontSize * (style.height ?? 1.2);
    return SizedBox(
      width: fontSize * 0.62,
      height: line,
      child: ClipRect(
        child: Stack(
          children: [
            for (var d = 0; d < 10; d++)
              Positioned(
                top: (d - progress) * line,
                left: 0,
                right: 0,
                child: Text(
                  '$d',
                  style: style,
                  textAlign: TextAlign.center,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

bool _isDigit(String c) => c.length == 1 && c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57;
int _max(int a, int b) => a > b ? a : b;
double _lerp(double a, double b, double p) => a + (b - a) * p;
