import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/app_design_tokens.dart';
import '../../core/app_responsive.dart';
import 'settings_glass_controls.dart';
import 'settings_list.dart';

class SettingsCardList extends StatelessWidget {
  const SettingsCardList({
    super.key,
    required this.children,
    this.title,
    this.padding = EdgeInsets.zero,
    this.rowPadding = 3,
  });

  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;

  /// 行内上下留白。**设置页统一传 3**（行高 = 内容 36 + 3 × 2 = 42），
  /// 这样同一类设置项在主题 / 布局 / 播放 / 网络 / 快捷键各页的疏密一致。
  ///
  /// 例外只有一处：快捷键页顶部的「全局快捷键」开关卡在设计稿里是 76 高
  /// （白区 y104~180），那一张传 20。
  ///
  /// 默认 2 是「不覆盖」的哨兵值（见 `SettingsTile` 里 `rowPadding != 2` 的判断），
  /// 不是给页面用的行距。
  final double rowPadding;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();
    // 全部 children 一律按卡片项渲染，**不按运行时类型分派**。
    //
    // 这里曾经是 `whereType<SettingsCardItem>()` 拿 `.tile`、其余走一个只加
    // `Padding` 的分支。那个分支会把「被包了一层」的条目悄悄降级成裸行：
    // 设置页里为了监听状态，`SettingsCardItem` 常被 `ValueListenableBuilder`
    // 或 `Focus` 包住（投屏接收端、热键捕获态），运行时类型就不再是这个类，
    // 于是卡片皮肤整个丢失 —— 看起来就是「这一块和别处不统一」。
    //
    // 而 `SettingsCardItem` 本身就是把 `.tile` 渲染出来的 StatelessWidget，
    // 直接当 widget 传给 `SettingsSection.tiles`（它收 `List<Widget>`）即可，
    // 顺序天然保持，包装与否都无所谓。
    return LayoutBuilder(
      builder: (context, constraints) => Padding(
        padding: padding,
        child: SettingsList(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          contentPadding: EdgeInsets.zero,
          // 宽度已由外层 `SettingsSubPageBody` 按可用宽度限好并居中（设置首页那条
          // 路径则由调用方自己包 frame）。这里直接用父级宽度，不再二次推导 ——
          // 否则会在已限宽的父级上再扣一份 gutter，卡片比可用宽度窄一圈。
          maxWidth: constraints.maxWidth,
          sections: [
            SettingsSection(
              // 宽度已由 `settingsContentWidth` 统一推导并居中，这里不再左右各扣
              // 39/29 —— 再扣一层，卡片就比可用宽度窄一截，右侧空出来的地方看着像没对齐。
              margin: const EdgeInsets.only(bottom: 16),
              rowPadding: rowPadding,
              title: title == null
                  ? null
                  : Text(
                      title!,
                      // 设计稿（`setTitle`）的卡片标题是**墨色 13 号粗体**，不是主题色：
                      // 原来取 `colorScheme.primary`，换紫主题后每条分组标题都是紫的，
                      // 和下面那列设置项抢注意力。标题只需要「区分分组」，不需要强调。
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.inkOf(context),
                      ),
                    ),
              tiles: children,
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsCardItem extends StatelessWidget {
  const SettingsCardItem({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.onTap,
    this.enabled = true,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  SettingsTile get tile {
    // 设计稿的设置项**没有左侧图标**：一张卡里就是一列「标题 + 副标题 …… 开关」，
    // 靠 1px 分隔线分行（见 v6 的 `setCard` / `stT*` / `stS*`，节点里只有文字与开关，
    // 没有任何 icon 节点）。原来每条都挂一个 Material Symbols 图标，一列下来
    // 左边一条彩色图标竖排，和设计稿差得最明显。
    //
    // 这里统一不传 `leading`：调用点那 30 多个 `leading: Icon(...)` 参数留着不动
    // （删起来动静太大、且以后若要按场景恢复也有据可依），只是不再画出来。
    if (trailing case final Switch toggle) {
      // 这里把传进来的 `Switch` **拆成**一个 onToggle 回调（行本身要能整行点），
      // 真开关由 settings_list 里的 SettingsSwitch 重建。副作用是读屏只看到
      // 「一行 + 一段文字」：既没有 switch 角色，也念不出当前是开还是关。
      // 走 `toggled` 把状态交给 SettingsTile，由它在行外层补语义 —— 可见标题
      // 由子节点自己报，所以只补角色与开关状态、不去动 label（给了就会念两遍）。
      return SettingsTile.switchTile(
        initialValue: toggle.value,
        onToggle: (value) {
          toggle.onChanged?.call(value ?? !toggle.value);
        },
        title: Text(title),
        description: subtitle == null ? null : Text(subtitle!),
        enabled: enabled && toggle.onChanged != null,
        toggled: toggle.value,
      );
    }
    return SettingsTile.navigation(
      onPressed: onTap == null ? null : (_) => onTap!(),
      title: Text(title),
      description: subtitle == null ? null : Text(subtitle!),
      value: trailing,
      enabled: enabled,
    );
  }

  @override
  Widget build(BuildContext context) => tile;
}

class SettingsSliderItem extends SettingsCardItem {
  const SettingsSliderItem({
    super.key,
    required super.title,
    super.subtitle,
    super.leading,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.label,
    required this.onChanged,
  });

  final double value;
  final double min;
  final double max;
  final int divisions;
  final String label;
  final ValueChanged<double> onChanged;

  @override
  SettingsTile get tile => SettingsTile(
    // 与 SettingsCardItem 一致：设计稿的滑块行也没有左侧图标，
    // 只有「标题 + 副标题 + 右侧滑块 + 百分比」。
    title: Text(title),
    description: subtitle == null ? null : Text(subtitle!),
    // 设计稿的滑块**在标题这一行的右侧**（`stSl` 与 `stSlVal` 同排），
    // 不是单独占一整行。原来把它挂在 `bottom` 里，这一行就变成
    // 「标题行 36 + 滑块行 44」= 80 高，正好是设计稿 40 的两倍 ——
    // 一屏在「文字大小」这里就被吃掉一整行的空间。
    //
    // 所以：滑块跟在标题后面、数值再跟在滑块右边，宽度按可用宽度收。
    // 行高仍由 36 的 `ConstrainedBox` 管，整行回到 40。
    value: Builder(
      builder: (context) => LayoutBuilder(
        builder: (context, constraints) {
          // 滑块宽度：设计稿实测（`文字大小` 行）滑块轨道 x760~1139 = 380 宽，
          // 右侧紧跟 `100%` 灰字。原来它挂在 `bottom` 里单独占一整行（行高 80），
          // 现在并到标题行右侧，行高回到 40。
          //
          // 宽度取 `min(基准 380, 可用 - 基准 60)`：减 60 留给右侧的
          // `100%` 文字与间距。窄窗口（<900，以及 widget 测试默认的 800×600）
          // 里写死会直接撑爆行宽抛 `RenderFlex overflowed`，所以要跟着可用宽度收。
          // 380/60/80 是设计稿实测的基准，随文字缩放一起放大，避免放大后
          // 滑块与数值挤在一起。
          final minSliderWidth = AppResponsive.scaled(context, 80);
          final sliderWidth = math.min(
            AppResponsive.scaled(context, 380),
            constraints.maxWidth - AppResponsive.scaled(context, 60),
          );
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: sliderWidth < minSliderWidth
                    ? minSliderWidth
                    : sliderWidth,
                // 高度基准 38：给 32 时滑块被压得太扁，和设计稿那种「有一定厚度」的
                // 轨道不像；给满 44 又会让这一行比别的行高出 6。
                // 38 是两者折中，行高和相邻行只差 1~2px，看不出来。
                height: AppResponsive.scaled(context, 38),
                child: SettingsSlider(
                  value: value,
                  min: min,
                  max: max,
                  divisions: divisions,
                  onChanged: onChanged,
                ),
              ),
              SizedBox(width: AppResponsive.scaled(context, 12)),
              Text(
                label,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  fontSize: 13,
                  color: AppDesignTokens.inkMutedOf(context),
                ),
              ),
            ],
          );
        },
      ),
    ),
  );
}

class SettingsMenuItem<T> extends SettingsCardItem {
  const SettingsMenuItem({
    super.key,
    required super.title,
    super.subtitle,
    super.leading,
    super.enabled,
    required this.value,
    required this.options,
    required this.label,
    required this.onSelected,
  });

  final T value;
  final List<T> options;
  final String Function(T value) label;
  final ValueChanged<T> onSelected;

  /// 点击行时弹出选项菜单。位置取**行本身**的矩形（`SettingsTile` 的
  /// `onPressed` 不给 context，所以由下面的 `Builder` 把 context 传进来）。
  Future<void> _showMenu(BuildContext context) async {
    final renderBox = context.findRenderObject()! as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final selected = await showMenu<T>(
      context: context,
      initialValue: value,
      position: RelativeRect.fromRect(
        position,
        Offset.zero & MediaQuery.sizeOf(context),
      ),
      items: [
        for (final option in options)
          PopupMenuItem(value: option, child: Text(label(option))),
      ],
    );
    if (selected != null) onSelected(selected);
  }

  @override
  SettingsTile get tile => SettingsTile.navigation(
    // `onPressed` 本身就是 `void Function(BuildContext)`（见 `settings_list.dart`
    // 的第 195 行），菜单直接用行自己的 context 定位。
    onPressed: _showMenu,
    // 与 SettingsCardItem / SettingsSliderItem 一致：设计稿的设置行没有左侧图标。
    title: Text(title),
    description: subtitle == null ? null : Text(subtitle!),
    // 右侧显示**当前值的文字** + 一个 chevron（设计稿：`1080P >`、`已开启 >`）。
    //
    // 之前这里塞了一个 `PopupMenuButton`，它在右侧渲染出来的是一个 **⋮ 菜单图标** ——
    // 一列下来每行右边都挂着一个三点菜单，和设计稿那串「值 + 箭头」完全不是一回事，
    // 用户也看不出当前选的是哪个值。
    value: Builder(
      builder: (context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label(value),
            style: TextStyle(fontSize: 13, color: AppDesignTokens.inkMutedOf(context)),
          ),
          SizedBox(width: AppResponsive.scaled(context, 4)),
          Icon(
            Symbols.chevron_right_rounded,
            size: 18,
            color: AppDesignTokens.inkSubtleOf(context),
          ),
        ],
      ),
    ),
    enabled: enabled,
  );
}
