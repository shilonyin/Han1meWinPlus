import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

import '../../core/app_design_tokens.dart';

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
  const SettingsSwitch({
    required this.value,
    required this.onChanged,
    super.key,
  });

  final bool value;

  /// 传 null 即禁用，与 Material 的 `Switch` 一致（`GlassSwitch` 也这么解释）。
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final bool disabled = onChanged == null;
    // 设计稿的开关是 **56×30 的实心胶囊**（`主题与色彩页 · v6` 实测：轨道
    // x1204~1259 = 56 宽、y455~484 = 30 高；开着时实心主题色 + 白色圆钮，
    // 关着时实心中灰 #B7B7B9 + 白色圆钮）。
    //
    // 这里**不再用 g1455 的 `GlassSwitch`**：它是玻璃控件，轨道是半透明的
    // 玻璃面而不是实心填充 —— 关掉时在白色卡片上几乎看不见（实测渲染出来
    // 是一条空心白胶囊，和设计稿那根明显的灰条差得远）。而且它的原生尺寸
    // 是 `kGlassSwitchSize = 64×28`，还得靠 `FittedBox` 缩放才能对上，
    // 缩放后圆钮会被压扁。
    //
    // Material 的 `Switch` 只要把 `thumbSize` / `trackSize` / `trackOutline`
    // 调对就是设计稿那种实心胶囊，而且它是实心绘制的，颜色给什么就是什么。
    return SizedBox(
      // 布局占位就是 **56×30**，不再靠缩放去凑：设计稿实测轨道 x1204~1259 = 56 宽、
      // y455~484 = 30 高，直接把框钉死到这个数。
      //
      // 里面那个 `Switch` 的逻辑尺寸是 52×32，用 `OverflowBox` 让它按自己的
      // 尺寸绘制、再被外面的框裁掉多出来的 2px 高 —— 这样：
      //   ① 布局高度严格是 30，每行才能落在设计稿的 40 上（原来它撑到 40+，
      //      每行被拉到 50，一屏少看到两项）；
      //   ② 圆钮按 52×32 的原生比例绘制，不会被 `FittedBox(fill)` 纵向压扁
      //      （之前用的是 fill，圆钮被压成椭圆、看着偏小）。
      //
      // 之前那条路（`Transform.scale`）行不通：它只缩放绘制、不改布局，
      // 52×32 的开关画在 56×30 的框里，上下各被裁掉 1px，圆钮就偏了一块。
      width: 56,
      height: 30,
      // 这里**不能裁**。
      //
      // `OverflowBox` 不裁剪，52×32 的 `Switch` 会往上下各溢出 1px。之前以为
      // 溢出会在相邻行留下白块，于是套了 `ClipRect` —— 结果那 1px 正好是圆钮
      // 的上下边缘，裁完开关看起来就像被切掉了上下各一条，圆钮变成一段扁的，
      // 比溢出本身难看得多。
      //
      // 真实情况是：那个 1px 溢出画在行自己的留白里（行高 42、开关 30，上下各
      // 有 6px 余量），根本压不到相邻行。所以保持不裁剪。
      child: OverflowBox(
        minWidth: 52,
        maxWidth: 52,
        minHeight: 32,
        maxHeight: 32,
        alignment: Alignment.centerRight,
        child: SizedBox(
          width: 52,
          height: 32,
          child: Switch(
            value: value,
            onChanged: onChanged,
            // **跟随主题色**（`scheme.primary`），不是固定某一支。
            //
            // 之前这里写死了 `AppDesignTokens.accentDeep`（胭脂粉 #B3265A），当时的理由是
            // 「设计稿里设置页全是这个粉」。那个判断是错的：设计稿截图画的是**玫瑰主题**，
            // 粉色只是这支配色在当前主题下的表现，不是写死的值。用户把主题切到「青」之后
            // 开关和滑块还停在粉色，就变成「换色不生效」了。
            activeThumbColor: Theme.of(context).colorScheme.primary,
            activeTrackColor: Theme.of(context).colorScheme.primary,
            // 关闭态的轨道：设计稿是**实心中灰**（实测 #B7B7B9）。
            // 禁用态再压淡一档，表示它不可操作。
            inactiveTrackColor: AppDesignTokens.switchTrackOff.withValues(
              alpha: disabled ? .5 : 1,
            ),
            // 圆钮永远是**白色实心**（设计稿两种状态都是白色圆钮）。
            // 必须用 `WidgetStateProperty.resolveWith` 而不是一个固定色：
            // Material 3 的 `Switch` 在关闭态读的是 `inactiveThumbColor`
            // 那条分支，只给 `thumbColor` 一个常量时它会被 Material 3 的
            // 默认 `outline`（灰）盖掉 —— 渲染出来就是一颗灰钮，和设计稿不符。
            thumbColor: WidgetStateProperty.resolveWith((states) {
              if (states.contains(WidgetState.disabled)) {
                return Colors.white.withValues(alpha: .7);
              }
              return Colors.white;
            }),
            // 去掉 Material 的描边：设计稿的开关没有边框，
            // 描边一留在白卡上就是两道灰线。
            trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
            trackOutlineWidth: const WidgetStatePropertyAll(0),
            // 关掉 Material 的 48×48 最小点按区，否则它会把整行撑高到 48，
            // 而设计稿每行只有 40。点按由整行承担（`SettingsTile` 整行可点）。
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
        ),
      ),
    );
  }
}

/// 设置页统一用的滑块：g1455 的 [GlassSlider]，把 Material 那套 min/max/divisions 接过来。
///
/// [GlassSlider] 只认 0..1 的连续值，而设置页的滑块全是"0.25x–3x、11 档"这种区间，
/// 所以映射与量化都在这里做一次，调用点不必各自换算。
class SettingsSlider extends StatelessWidget {
  const SettingsSlider({
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    super.key,
  });

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
    final double span = max - min;
    final int? steps = divisions;
    return GlassSlider(
      value: span == 0 ? 0 : ((value - min) / span).clamp(0.0, 1.0),
      // 与开关同一支色：跟随主题（原因见 `SettingsSwitch` 的说明）。
      activeColor: Theme.of(context).colorScheme.primary,
      onChanged: onChanged == null || span == 0
          ? null
          : (double ratio) {
              final double raw = min + ratio * span;
              final double snapped = steps == null || steps <= 0
                  ? raw
                  : min + ((raw - min) / span * steps).round() / steps * span;
              onChanged!(snapped.clamp(min, max));
            },
    );
  }
}
