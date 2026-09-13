import 'package:flutter/material.dart';

/// Settings list primitives.
///
/// Layout follows the flat, grouped style: every tile is its own surface with a
/// small gap between rows, only the outermost corners of a group get the large
/// radius. Content is centred with a maximum width so settings do not stretch
/// across a wide desktop window.
const double settingsListMaxWidth = 1000;
const double _groupOuterRadius = 16;
const double _groupInnerRadius = 4;
const double _rowGap = 4;
const Duration _pressDuration = Duration(milliseconds: 250);

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
    final secondary = enabled ? colorScheme.onSurfaceVariant : colorScheme.onSurface.withValues(alpha: 0.38);
    return InkWell(
      onTap: _tapHandler(context),
      onHighlightChanged: _SplitListRow.pressReporterOf(context),
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
                    Switch(value: initialValue ?? false, onChanged: enabled ? onToggle : null),
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
    return Row(
      children: [
        if (leading != null) ...[
          IconTheme.merge(data: IconThemeData(size: 24, color: secondary), child: leading!),
          const SizedBox(width: 16),
        ],
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DefaultTextStyle.merge(
                style: textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
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
            _SplitListRow(
              topRadius: i == 0 ? _groupOuterRadius : _groupInnerRadius,
              bottomRadius: i == children.length - 1 ? _groupOuterRadius : _groupInnerRadius,
              child: children[i],
            ),
          ],
        ],
      );
}

class _SplitListRow extends StatefulWidget {
  const _SplitListRow({required this.child, required this.topRadius, required this.bottomRadius});

  final Widget child;
  final double topRadius;
  final double bottomRadius;

  /// Tiles forward their InkWell highlight here so the row can animate its
  /// shape as well as its colour.
  static ValueChanged<bool>? pressReporterOf(BuildContext context) => context.dependOnInheritedWidgetOfExactType<_SplitRowScope>()?.onPressChanged;

  @override
  State<_SplitListRow> createState() => _SplitListRowState();
}

class _SplitListRowState extends State<_SplitListRow> {
  var _pressed = false;

  void _reportPress(bool pressed) {
    if (mounted) setState(() => _pressed = pressed);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final duration = MediaQuery.disableAnimationsOf(context) ? Duration.zero : _pressDuration;
    return AnimatedContainer(
      duration: duration,
      curve: Curves.easeInOutCubic,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(_pressed ? _groupOuterRadius : widget.topRadius),
          bottom: Radius.circular(_pressed ? _groupOuterRadius : widget.bottomRadius),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: _SplitRowScope(onPressChanged: _reportPress, child: widget.child),
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
