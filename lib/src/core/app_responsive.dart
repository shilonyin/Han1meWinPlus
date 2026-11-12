import 'dart:math' as math;

import 'package:flutter/material.dart';

/// 响应式布局的唯一真相：按窗口宽度推导留白、内容宽度与列数，
/// 按文字缩放推导间距和控件高度。
///
/// 这里**不收**设计稿的固定基准值 —— 那些在 `AppDesignTokens`，例如侧栏 176、
/// 顶栏 112，它们是稿子上量出来的一个数，跟着窗口变反而不对。
/// 判断标准和 `app_design_tokens.dart` 一致：这个值有推导规则吗？有规则才进来。
///
/// 全应用的文字缩放由 `app_widget.dart` 写入 MediaQuery，
/// 普通 `Text` 会自动缩放；本模块补的是 `Text` 之外的部分：
/// 容器高度、间距、网格列数不会自己跟着变，写死就会在放大或拉宽时裁切、留白失衡。
abstract final class AppResponsive {
  /// 窄窗断点：低于此宽度按单列处理，导航收成抽屉。
  static const compactBreakpoint = 900.0;

  /// 宽窗断点：达到此宽度后内容区限宽，不再跟着窗口一起拉宽。
  static const expandedBreakpoint = 1600.0;

  /// 宽窗下**正文**的最大宽度。超过这个行宽，一行要读的字太多，眼睛容易串行。
  ///
  /// 只适用于成段的正文。表格型内容（设置分组、数据卡片）宽一点更好用，
  /// 调用点传 [wideContentStart] 以上的 `cap` 覆盖本值，别被这一条坑住。
  static const contentWidthCap = 1400.0;

  /// 表格型内容（设置列表、数据看板）的宽度上限。
  ///
  /// 取值远大于 [contentWidthCap]，因为这类内容不是「一行读到底」的正文，
  /// 2560 窗口里铺开到 2200 也没问题；真正该收的是正文。上限定在这里是为了
  /// 超宽屏（4K 竖屏拼多窗）不至于把一行设置项拉得眼睛追不上。
  static const wideContentCap = 2200.0;

  static bool isCompact(double width) => width < compactBreakpoint;

  static bool isExpanded(double width) => width >= expandedBreakpoint;

  /// 当前文字缩放倍率。上限与 `AppSettings.fromJson` 的 `.clamp(.8, 1.4)` 对齐，
  /// 避免旧配置里被手改过的值把布局撑爆。
  static double textScaleOf(BuildContext context) =>
      MediaQuery.textScalerOf(context).scale(1.0).clamp(0.8, 1.4);

  /// 与文字同尺度变化的量：间距、控件高度、最小命中区、最小卡片宽。
  ///
  /// **布局宽度不要用这个**。放大文字时把内容区一起拉宽，行宽会跟着失控；
  /// 宽度一律走 [contentWidthFor] 按可用宽度推导。
  static double scaled(BuildContext context, double base) =>
      base * textScaleOf(context);

  /// 水平留白，按可用宽度分档。
  /// 窄窗收紧、宽窗放开，避免 1280 和 2560 用同一个 24，
  /// 导致宽屏内容挤在中间一小块、四周空一大片。
  static double gutterFor(double availableWidth) {
    if (availableWidth < 600) return 16;
    if (availableWidth < 1000) return 24;
    if (availableWidth < expandedBreakpoint) return 32;
    return 48;
  }

  /// 内容区实际宽度。窄窗铺满（只扣留白），宽窗限宽后由调用方居中。
  ///
  /// [cap] 默认 [contentWidthCap]（正文行宽）。表格型内容传 [wideContentCap]，
  /// 否则 2560 窗口里设置卡片会挤在 1400 宽、两侧空出一大片。
  static double contentWidthFor(double availableWidth, {double cap = contentWidthCap}) {
    final usable =
        (availableWidth - gutterFor(availableWidth) * 2).clamp(0.0, double.infinity);
    if (isExpanded(availableWidth)) {
      return math.min(usable, cap);
    }
    return usable;
  }

  /// 网格列数：由可用宽度与最小卡片宽推导，不写死 4 列。
  static int columnsFor({
    required double availableWidth,
    required double minCardWidth,
    double gap = 16,
    int maxColumns = 10,
  }) =>
      ((availableWidth + gap) / (minCardWidth + gap)).floor().clamp(
        1,
        maxColumns,
      );

  /// 列数确定后均分的卡片宽度。与 [columnsFor] 用同一套算式，
  /// 避免两处各算一遍后差一个 gap，末列被挤到下一行。
  static double cardWidthFor({
    required double availableWidth,
    required double minCardWidth,
    double gap = 16,
    int maxColumns = 10,
  }) {
    final cols = columnsFor(
      availableWidth: availableWidth,
      minCardWidth: minCardWidth,
      gap: gap,
      maxColumns: maxColumns,
    );
    return (availableWidth - gap * (cols - 1)) / cols;
  }
}
