import 'package:flutter/material.dart';

/// 全应用统一的弹窗入口：**遮罩全透明**，浮窗出现时页面不变暗。
///
/// 各处原来直接调 `showDialog`，默认遮罩是 `Colors.black54` —— 一弹窗整页就压暗一层。
/// 这套界面是浅色渐变 + 半透明卡片，压暗之后观感很闷，也和 morrow 那种
/// "浮窗浮在原亮度的页面上"不一致。
///
/// 需要**真正聚焦**的弹窗（例如全屏看图要有黑底衬托）继续直接用 `showDialog`
/// 并自己指定 `barrierColor`，不要走这里。
Future<T?> showAppDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  bool useRootNavigator = true,
  RouteSettings? routeSettings,
  Offset? anchorPoint,
  TraversalEdgeBehavior? traversalEdgeBehavior,
}) => showDialog<T>(
  context: context,
  builder: builder,
  barrierColor: Colors.transparent,
  barrierDismissible: barrierDismissible,
  useRootNavigator: useRootNavigator,
  routeSettings: routeSettings,
  anchorPoint: anchorPoint,
  traversalEdgeBehavior: traversalEdgeBehavior,
);
