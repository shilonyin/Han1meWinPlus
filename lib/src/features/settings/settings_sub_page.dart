import 'package:flutter/material.dart';

/// 设置页内「二级页」的返回通道。
///
/// 设置页在宽窗下是「左分类 + 右内容」（`_SettingsPanes`），用 `context.push` 打开二级页会
/// 把左侧分类栏整个盖住，退出后还得重新点一次分类才能回来。所以父页改成**在右侧内容区里
/// 切换视图**：用这个 InheritedWidget 把「返回父页」的回调递给子页。
///
/// 好处是子页不用各自加构造参数 —— 只要在标题栏写 `leading: settingsSubPageBack(context)`，
/// 嵌入时显示「返回父页」，而走独立路由（窄窗、深链）时返回 null、照旧用路由默认返回。
class SettingsSubPageScope extends InheritedWidget {
  const SettingsSubPageScope({super.key, required this.onBack, required super.child});

  final VoidCallback onBack;

  static VoidCallback? maybeOnBack(BuildContext context) => context.getInheritedWidgetOfExactType<SettingsSubPageScope>()?.onBack;

  @override
  bool updateShouldNotify(SettingsSubPageScope oldWidget) => onBack != oldWidget.onBack;
}

/// 二级页标题栏的返回键；不在设置页内嵌环境里时返回 null（交回路由处理）。
Widget? settingsSubPageBack(BuildContext context) {
  final onBack = SettingsSubPageScope.maybeOnBack(context);
  return onBack == null ? null : BackButton(onPressed: onBack);
}
