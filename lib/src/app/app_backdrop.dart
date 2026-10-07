import 'package:flutter/material.dart';

import 'app_page_colors.dart';

/// 全应用背景画布：**一块平的页面底色**。
///
/// 底色取 g1455 演示站的两个主题（见 [AppPageColors]）—— 页面要读起来就是站点
/// 那种干净的中性底。
///
/// **为什么现在是纯平**：这里早先照 morrow 做「多色渐变 + 三个径向光晕」，
/// 而光晕存在的唯一理由是**给玻璃抽色**：玻璃折射时要能从背景里抽出一丝颜色，
/// 否则整屏玻璃抽出来都是同一块灰。玻璃已经退役（决策与验收记在
/// `docs/ui-polish.md`），这个理由随之消失，光晕只剩副作用 —— 整屏偏色、
/// 角落发暖。参考图里页面本身也就是一块平的浅灰，所以这里回到单一底色。
///
/// 纯 Flutter 实现，不依赖任何资源；颜色按明暗取 [AppPageColors]。
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
    final page = AppPageColors.of(Theme.of(context).brightness);
    return Stack(
      children: [
        Positioned.fill(
          child: ColoredBox(
            color: page.withValues(alpha: opacity.clamp(0, 1)),
          ),
        ),
        child,
      ],
    );
  }
}
