import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

/// 设置页统一用的开关：g1455 的 [GlassSwitch]，配色接回应用主题。
///
/// **为什么专门包一层**：设置页里 35 个开关全部走 `SettingsCardItem` → `SettingsTile`
/// 这一条路，最终只在 `settings_list.dart` 渲染一次。包在这里，那 35 个调用点
/// 一行都不用改；而 [GlassSwitch] 的默认色是 iOS 绿加一层固定灰，散在各页里
/// 各传一遍主题色只会重复 35 次。
///
/// **为什么值得换**：Material 的开关按下就是原地变色，而 `GlassSwitch` 的滑块
/// 按下去会像水珠一样抬起来、被拖动时按加速度拉长 —— 这是 g1455 那套液体动效
/// 里出现频率最高的一处，也是设置页里唯一每天都会碰到的手感。
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({required this.value, required this.onChanged, super.key});

  final bool value;

  /// 传 null 即禁用，与 Material 的 `Switch` 一致（`GlassSwitch` 也这么解释）。
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final bool disabled = onChanged == null;
    return GlassSwitch(
      value: value,
      onChanged: onChanged,
      // 用主题色而不是 iOS 绿：设置页整体是主题配色，一块孤立的绿会显得没接上主题。
      activeColor: scheme.primary,
      // 轨道底色跟着 surface 走。禁用态再压淡一档，与其它禁用控件一致 ——
      // 它本来就该显得弱，不能因为换了控件就看起来仍然可用。
      trackColor: scheme.surfaceContainerHighest.withValues(alpha: disabled ? .28 : .55),
    );
  }
}

/// 设置页统一用的滑块：g1455 的 [GlassSlider]，把 Material 那套 min/max/divisions 接过来。
///
/// [GlassSlider] 只认 0..1 的连续值，而设置页的滑块全是"0.25x–3x、11 档"这种区间，
/// 所以映射与量化都在这里做一次，调用点不必各自换算。
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({required this.value, required this.onChanged, this.min = 0, this.max = 1, this.divisions, super.key});

  final double value;

  /// 传 null 即禁用，与 Material 的 `Slider` 一致。
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// 档位数。为空表示连续；有档位时按 Material 的规矩量化到档位上，
  /// 否则滑块的落点会在两档之间，与换控件之前的手感对不上。
  final int? divisions;

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final double span = max - min;
    final int? steps = divisions;
    return GlassSlider(
      value: span == 0 ? 0 : ((value - min) / span).clamp(0.0, 1.0),
      activeColor: scheme.primary,
      onChanged: onChanged == null || span == 0
          ? null
          : (double ratio) {
              final double raw = min + ratio * span;
              final double snapped = steps == null || steps <= 0 ? raw : min + ((raw - min) / span * steps).round() / steps * span;
              onChanged!(snapped.clamp(min, max));
            },
    );
  }
}
