import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_motion.dart';
import '../shared/glass/glass_panel.dart';
import 'settings_glass_controls.dart';

/// Settings list primitives.
///
/// Layout follows the flat, grouped style: every tile is its own surface with a
/// small gap between rows, only the outermost corners of a group get the large
/// radius. Content is centred with a maximum width so settings do not stretch
/// across a wide desktop window.
const double settingsListMaxWidth = 1000;
// 参考 morrow（明隙）：大圆角 + 更宽的卡片间距，靠"一块块浮起来的卡片"分区。
// 每张卡片四角**统一** —— 卡片之间有 `_rowGap` 间隙，本来就是独立的块，
// 再按分组给首尾大、中间小的圆角，只会看起来像圆角没对齐。
const double _cardRadius = 18;
const double _rowGap = 6;
const Duration _pressDuration = AppMotion.emphasis;

/// Scrollable list of [SettingsSection]s.
class SettingsList extends StatelessWidget {
  const SettingsList({super.key, required this.sections, this.contentPadding, this.shrinkWrap = false, this.physics, this.maxWidth = settingsListMaxWidth});

  final List<Widget> sections;
  final EdgeInsetsGeometry? contentPadding;
  final bool shrinkWrap;
  final ScrollPhysics? physics;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => ListView.builder(
        shrinkWrap: shrinkWrap,
        physics: physics,
        padding: contentPadding ?? const EdgeInsets.symmetric(vertical: 12),
        itemCount: sections.length,
        itemBuilder: (context, index) => Center(
          child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: sections[index]),
        ),
      );
}

/// A titled group of tiles.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.tiles, this.title, this.bottomInfo, this.margin});

  final List<Widget> tiles;
  final Widget? title;
  final Widget? bottomInfo;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: margin ?? const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Semantics(
                header: true,
                child: DefaultTextStyle.merge(
                  style: textTheme.titleSmall?.copyWith(color: colorScheme.primary, fontWeight: FontWeight.w600),
                  child: title!,
                ),
              ),
            ),
          _SplitListGroup(children: tiles),
          if (bottomInfo != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: DefaultTextStyle.merge(
                style: textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                child: bottomInfo!,
              ),
            ),
        ],
      ),
    );
  }
}

/// A single settings row.
class SettingsTile<T> extends StatelessWidget {
  const SettingsTile({super.key, required this.title, this.leading, this.description, this.value, this.trailing, this.bottom, this.onPressed, this.enabled = true})
      : initialValue = null,
        onToggle = null,
        radioValue = null,
        groupValue = null,
        onChanged = null;

  const SettingsTile.navigation({super.key, required this.title, this.leading, this.description, this.value, this.onPressed, this.enabled = true})
      : trailing = null,
        bottom = null,
        initialValue = null,
        onToggle = null,
        radioValue = null,
        groupValue = null,
        onChanged = null;

  /// Row taps report a null value; the switch itself reports the new one.
  const SettingsTile.switchTile({super.key, required this.title, required this.initialValue, required this.onToggle, this.leading, this.description, this.enabled = true})
      : value = null,
        trailing = null,
        bottom = null,
        onPressed = null,
        radioValue = null,
        groupValue = null,
        onChanged = null;

  const SettingsTile.radioTile({super.key, required this.title, required T this.radioValue, required this.groupValue, this.onChanged, this.leading, this.description, this.enabled = true})
      : value = null,
        trailing = null,
        bottom = null,
        onPressed = null,
        initialValue = null,
        onToggle = null;

  final Widget title;
  final Widget? leading;
  final Widget? description;
  final Widget? value;
  final Widget? trailing;

  /// Rendered under the row, inside the same surface (used by slider tiles).
  final Widget? bottom;

  final void Function(BuildContext context)? onPressed;
  final void Function(bool? value)? onToggle;
  final bool? initialValue;
  final T? radioValue;
  final T? groupValue;
  final ValueChanged<T?>? onChanged;
  final bool enabled;

  VoidCallback? _tapHandler(BuildContext context) {
    if (!enabled) return null;
    if (onToggle != null) return () => onToggle!(null);
    if (onPressed != null) return () => onPressed!(context);
    if (onChanged != null && radioValue != null) return () => onChanged!(radioValue);
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 次要文字/图标色。**必须走面板可读性兜底**：实测浅色玻璃面板下
    // `onSurfaceVariant` 只有 4.2 左右，够不到正文所需的 4.5（深色下没问题，7 以上）。
    // 兜底只推明度、保住色相，所以次要文字仍是"次要"的样子，不会变成正文色。
    // 禁用态（38% 透明度）刻意**不走**兜底：它本来就该显得弱，强行拉到达标线
    // 会让"不可用"看起来像"可用"。
    final secondary = enabled
        ? GlassPanelTextColor.resolve(context)
        : colorScheme.onSurface.withValues(alpha: 0.38);
    // 悬停/按下不再铺底色块，改为把图标与标题染成主题色
    // （与主侧栏、设置分类栏一套规矩：底色块比图标还抢眼）。
    return SettingsHoverTracker(
      enabled: enabled,
      child: InkWell(
        onTap: _tapHandler(context),
        onHighlightChanged: _SplitListRow.pressReporterOf(context),
        hoverColor: Colors.transparent,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 32),
                child: Row(
                  children: [
                    Expanded(
                      child: _TileLabel(title: title, leading: leading, description: description, secondary: secondary),
                    ),
                    if (value != null) ...[
                      const SizedBox(width: 12),
                      DefaultTextStyle.merge(
                        style: textTheme.bodyMedium?.copyWith(color: secondary),
                        child: value!,
                      ),
                    ],
                    if (trailing != null) ...[
                      const SizedBox(width: 8),
                      IconTheme.merge(data: IconThemeData(color: secondary), child: trailing!),
                    ],
                    if (onToggle != null) ...[
                      const SizedBox(width: 12),
                      SettingsSwitch(value: initialValue ?? false, onChanged: enabled ? onToggle : null),
                    ],
                    if (radioValue != null) ...[
                      const SizedBox(width: 12),
                      _RadioDot(selected: radioValue == groupValue, enabled: enabled),
                    ],
                  ],
                ),
              ),
              if (bottom != null) ...[
                const SizedBox(height: 4),
                bottom!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 行内悬停状态：子节点（标题/图标）据此变色。
/// 目前只有一种反馈方式 —— 变主题色，不铺底色块。
class SettingsHoverScope extends InheritedWidget {
  const SettingsHoverScope({required this.hovered, required super.child, super.key});

  final bool hovered;

  static bool of(BuildContext context) => context.dependOnInheritedWidgetOfExactType<SettingsHoverScope>()?.hovered ?? false;

  @override
  bool updateShouldNotify(SettingsHoverScope oldWidget) => oldWidget.hovered != hovered;
}

/// 把鼠标悬停状态广播给子树（见 [SettingsHoverScope]）。
class SettingsHoverTracker extends StatefulWidget {
  const SettingsHoverTracker({required this.enabled, required this.child, super.key});

  final bool enabled;
  final Widget child;

  @override
  State<SettingsHoverTracker> createState() => _SettingsHoverTrackerState();
}

class _SettingsHoverTrackerState extends State<SettingsHoverTracker> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: SettingsHoverScope(hovered: _hovered, child: widget.child),
    );
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({required this.title, this.leading, this.description, required this.secondary});

  final Widget title;
  final Widget? leading;
  final Widget? description;
  final Color secondary;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    // 悬停时图标与标题染主题色 —— 这是行内唯一的交互反馈。
    final hovered = SettingsHoverScope.of(context);
    return Row(
      children: [
        if (leading != null) ...[
          IconTheme.merge(data: IconThemeData(size: 24, color: hovered ? colorScheme.primary : secondary), child: leading!),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.bodyLarge?.copyWith(color: hovered ? colorScheme.primary : colorScheme.onSurface),
                child: title,
              ),
              if (description != null) ...[
                const SizedBox(height: 2),
                DefaultTextStyle.merge(
                  style: textTheme.bodySmall?.copyWith(color: secondary),
                  child: description!,
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Hand-drawn so the tile does not depend on the deprecated Radio parameters.
class _RadioDot extends StatelessWidget {
  const _RadioDot({required this.selected, required this.enabled});

  final bool selected;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final active = selected ? colorScheme.primary : colorScheme.outline;
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: enabled ? active : active.withValues(alpha: 0.38), width: selected ? 6 : 2),
      ),
    );
  }
}

class _SplitListGroup extends StatelessWidget {
  const _SplitListGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(height: _rowGap),
            _SplitListRow(child: children[i]),
          ],
        ],
      );
}

class _SplitListRow extends StatelessWidget {
  const _SplitListRow({required this.child});

  final Widget child;

  /// Tiles forward their InkWell highlight here so the row can animate its
  /// shape as well as its colour.
  static ValueChanged<bool>? pressReporterOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SplitRowScope>()?.onPressChanged;

  @override
  Widget build(BuildContext context) {
    // 四角统一（此前按分组给首行 20/6、中间 6/6、尾行 6/20）。
    // 卡片之间本来就有 `_rowGap` 间隙，连不成一整块，分组圆角只会让
    // 每张卡的四个角各不相同 —— 看起来就是「圆角不统一」。
    // 底色交给共用的 GlassPanel，质感和左栏、其他卡片保持一致；
    // 这里同样不加投影：卡片上下紧挨着，投影会连成一条灰带。
    return GlassPanel(
      borderRadius: BorderRadius.circular(_cardRadius),
      child: Material(
        type: MaterialType.transparency,
        // 圆角已固定，按下态不再影响外观；保留这个 scope 是因为条目的 InkWell
        // 仍会通过 `pressReporterOf` 取它。
        child: _SplitRowScope(onPressChanged: (_) {}, child: child),
      ),
    );
  }
}

class _SplitRowScope extends InheritedWidget {
  const _SplitRowScope({required this.onPressChanged, required super.child});

  final ValueChanged<bool> onPressChanged;

  @override
  bool updateShouldNotify(_SplitRowScope oldWidget) => false;
}
