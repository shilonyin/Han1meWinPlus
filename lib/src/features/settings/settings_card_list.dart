import 'package:flutter/material.dart';

import '../../core/app_radius.dart';
import 'settings_glass_controls.dart';
import 'settings_list.dart';

class SettingsCardList extends StatelessWidget {
  const SettingsCardList({super.key, required this.children, this.title, this.padding = EdgeInsets.zero});

  final List<Widget> children;
  final String? title;
  final EdgeInsetsGeometry padding;

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
    return Padding(
      padding: padding,
      child: SettingsList(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        contentPadding: EdgeInsets.zero,
        sections: [
          SettingsSection(
            title: title == null ? null : Text(title!, style: TextStyle(color: Theme.of(context).colorScheme.primary)),
            tiles: children,
          ),
        ],
      ),
    );
  }
}

class SettingsCardItem extends StatelessWidget {
  const SettingsCardItem({super.key, required this.title, this.subtitle, this.leading, this.trailing, this.onTap, this.enabled = true});

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool enabled;

  SettingsTile get tile {
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
        leading: leading,
        title: Text(title),
        description: subtitle == null ? null : Text(subtitle!),
        enabled: enabled && toggle.onChanged != null,
        toggled: toggle.value,
      );
    }
    return SettingsTile.navigation(
      onPressed: onTap == null ? null : (_) => onTap!(),
      leading: leading,
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
        leading: leading,
        title: Text(title),
        description: subtitle == null ? null : Text(subtitle!),
        value: Builder(
          builder: (context) {
            final colorScheme = Theme.of(context).colorScheme;
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: colorScheme.secondaryContainer, borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSecondaryContainer)),
            );
          },
        ),
        bottom: SettingsSlider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
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

  Future<void> _showMenu(BuildContext context) async {
    final renderBox = context.findRenderObject()! as RenderBox;
    final position = renderBox.localToGlobal(Offset.zero) & renderBox.size;
    final selected = await showMenu<T>(
      context: context,
      initialValue: value,
      position: RelativeRect.fromRect(position, Offset.zero & MediaQuery.sizeOf(context)),
      items: [for (final option in options) PopupMenuItem(value: option, child: Text(label(option)))],
    );
    if (selected != null) onSelected(selected);
  }

  @override
  SettingsTile get tile => SettingsTile.navigation(
        onPressed: _showMenu,
        leading: leading,
        title: Text(title),
        description: subtitle == null ? null : Text(subtitle!),
        value: Builder(
          builder: (context) => PopupMenuButton<T>(
            initialValue: value,
            onSelected: onSelected,
            itemBuilder: (context) => [for (final option in options) PopupMenuItem(value: option, child: Text(label(option)))],
          ),
        ),
        enabled: enabled,
      );
}
