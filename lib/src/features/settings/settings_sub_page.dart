import 'package:flutter/material.dart';

import 'settings_pane_scope.dart';

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
/// 设置二级页的正文容器，把子页的滚动内容按可用宽度限宽并居中。
///
/// 之前各子页直接 `body: ListView(...)`，分组卡片靠 `SettingsSection` 的 39/29 外边距撑开。
/// 卡片本身又被 `SettingsList` 的 `maxWidth`（默认 1000）限宽居中。
/// 两层一叠加，宽窗口下白卡又窄又贴左，右侧空出大片，和顶部横幅的宽度也对不上。
/// 把宽度推导收到这一层之后，子页里的横幅与卡片都只留竖直间距。
/// 宽窗才真正铺开并对齐。
///
/// 直接包住 `ListView`，`shrinkWrap` 由调用方决定，这里只管宽度与居中。
class SettingsSubPageBody extends StatelessWidget {
  const SettingsSubPageBody({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Align(
      alignment: Alignment.topCenter,
      child: SizedBox(
        width: settingsContentWidth(constraints.maxWidth),
        child: child,
      ),
    ),
  );
}
