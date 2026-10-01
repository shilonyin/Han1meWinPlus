import 'dart:ui';

import 'package:flutter/material.dart';

/// 全局滚动行为：**不画任何滚动条**。
///
/// 桌面端默认会给每个可滚动区域画一条指示条；设置页左栏那条灰色竖条
/// 紧贴在分组卡片旁边尤其突兀，和这套卡片造型不是一套语言。
/// 这里直接返回 child，等于全应用关掉滚动指示条。
///
/// 只去掉"画出来的条"，滚轮 / 鼠标拖动 / 触控板手势都保留 ——
/// [dragDevices] 继续把鼠标和触控板算进拖动设备。
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {
    ...super.dragDevices,
    PointerDeviceKind.mouse,
    PointerDeviceKind.trackpad,
  };

  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) => child;
}
