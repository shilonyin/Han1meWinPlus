import 'package:flutter/material.dart';

import '../../core/app_responsive.dart';

/// 设置页在宽屏下的分栏宽度阈值。低于它落回单栏列表（每种设置页各自 push 打开）。
const double settingsPaneMinWidth = 760;

/// 当前这个设置子页是不是**嵌在宽屏右栏里**渲染的。
///
/// 宽屏下左栏已经列出了所有分类并把当前页高亮，右栏再顶一个 AppBar 标题就是重复。
/// 窄屏时这些页面是被独立 push 打开的，AppBar 还要负责标题和返回按钮，不能去掉。
///
/// 用法：`appBar: embeddedInSettingsPanes(context) ? null : AppBar(...)`。
bool embeddedInSettingsPanes(BuildContext context) =>
    MediaQuery.sizeOf(context).width >= settingsPaneMinWidth;

/// 设置内容的宽度：窄窗铺满，宽窗按可用宽度限宽。
///
/// 窄窗若直接取 [AppResponsive.contentWidthFor] 的结果，会再扣一份留白，
/// 横幅里主题名那一行会被缩略图的让位挤到溢出，所以窄窗返回完整可用宽度。
///
/// 上限用 [AppResponsive.wideContentCap] 而不是正文那一档：设置是成片的卡片列表，
/// 不是一行读到底的正文。用正文的 1400 会让 2560 窗口里卡片挤在中间、两侧空一大片。
double settingsContentWidth(double availableWidth) =>
    AppResponsive.isCompact(availableWidth)
        ? availableWidth
        : AppResponsive.contentWidthFor(
            availableWidth,
            cap: AppResponsive.wideContentCap,
          );

/// 把设置内容按可用宽度限宽后居中。
///
/// 横幅、配色卡、设置列都从这里读取父级给的完整可用宽度，
/// 用同一个 [settingsContentWidth] 推导，左右边缘才会落在同一条线上，
/// 宽窗口下也不会再钉死在一个固定宽度上、四周留出大片空白。
class SettingsContentFrame extends StatelessWidget {
  const SettingsContentFrame({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Center(
      child: SizedBox(
        width: settingsContentWidth(constraints.maxWidth),
        child: child,
      ),
    ),
  );
}
