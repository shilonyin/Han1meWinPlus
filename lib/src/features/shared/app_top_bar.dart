import 'package:flutter/material.dart';

import '../../core/app_design_tokens.dart';

/// 应用内页面统一使用的顶栏。
///
/// **存在的理由**：主窗口的自绘标题栏是**悬浮**在内容之上的（见 `_AppTitleBarState`），
/// 右上角那三个窗口按钮（最小化 / 最大化 / 关闭）压在 y0~28 这条带子里，点击会穿透，
/// 但**视觉上会盖住页面自己的右上角控件**。缓存页的「清理」按钮就正好被盖住了一半
/// —— 这不是点不到，而是看着像被压扁了。
///
/// 所以每个页面的 AppBar 都要把顶部让出 [AppDesignTokens.windowControlsHeight]。
/// 让 35 个页面各自写一遍 padding 不现实（漏一个就又是一处重叠），统一收在这里。
///
/// 首页不吃这一套：它自绘顶栏，由 `_HomeFeedBody` 自己按 `topBarChromeHeight` 让位。
class AppTopBar extends StatelessWidget implements PreferredSizeWidget {
  const AppTopBar({
    super.key,
    this.title,
    this.leading,
    this.actions,
    this.bottom,
    this.backgroundColor,
    this.elevation,
    this.surfaceTintColor,
    this.automaticallyImplyLeading = true,
    this.leadingWidth,
    this.titleSpacing,
    this.centerTitle,
    this.toolbarHeight,
    this.shape,
    this.flexibleSpace,
    this.scrolledUnderElevation,
    this.foregroundColor,
  });

  /// 顶部窗口按钮带的高度。AppBar 内容整体下移这么多，按钮就不再压住页面控件。
  ///
  /// 取值与标题栏一致（`appTitleBarHeight` 28）：窗口按钮正好落在 y0~28 这一段，
  /// 让 28 之后的内容从按钮下沿开始，两者不再叠。
  static const double controlsInset = AppDesignTokens.windowControlsHeight;

  final Widget? title;
  final Widget? leading;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final Color? backgroundColor;
  final double? elevation;
  final Color? surfaceTintColor;
  final bool automaticallyImplyLeading;
  final double? leadingWidth;
  final double? titleSpacing;
  final bool? centerTitle;

  /// 调用方自定义的工具栏高度（**不含**顶部让位）。内部会在其之上叠加 [controlsInset]。
  final double? toolbarHeight;
  final ShapeBorder? shape;
  final Widget? flexibleSpace;

  /// 内容滚到顶栏下方时的抬升阴影。默认沿用主题（本项目是 0，要那条「滚动边缘」
  /// 由页面自己画），这里放出来只是为了让个别页面能显式覆盖。
  final double? scrolledUnderElevation;

  /// 顶栏前景色（标题与图标）。播放窗口那条是照参考实现的固定深色，需要单独指定。
  final Color? foregroundColor;

  @override
  Size get preferredSize {
    final bar = toolbarHeight ?? kToolbarHeight;
    final extra = bottom?.preferredSize.height ?? 0;
    return Size.fromHeight(controlsInset + bar + extra);
  }

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: controlsInset),
    child: AppBar(
      title: title,
      leading: leading,
      actions: actions,
      bottom: bottom,
      backgroundColor: backgroundColor,
      elevation: elevation,
      surfaceTintColor: surfaceTintColor,
      automaticallyImplyLeading: automaticallyImplyLeading,
      leadingWidth: leadingWidth,
      titleSpacing: titleSpacing,
      centerTitle: centerTitle,
      toolbarHeight: toolbarHeight,
      shape: shape,
      flexibleSpace: flexibleSpace,
      scrolledUnderElevation: scrolledUnderElevation,
      foregroundColor: foregroundColor,
    ),
  );
}
