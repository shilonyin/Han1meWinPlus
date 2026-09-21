import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/window_chrome.dart';
import '../settings/settings_controller.dart';

/// Height of the in-app title bar. Close to the system caption height so the
/// window keeps roughly the same proportions whichever style is selected.
const double appTitleBarHeight = 34;

/// Draws the app's own title bar when the appearance settings ask for it, so
/// turning the system title bar off still leaves a draggable window with the
/// usual minimize / maximize / close buttons.
class AppWindowFrame extends ConsumerWidget {
  const AppWindowFrame({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    return ValueListenableBuilder<bool>(
      valueListenable: WindowChrome.visible,
      builder: (context, visible, _) {
        if (settings == null || settings.useSystemTitleBar || !visible) return child;
        return Column(children: [const AppTitleBar(), Expanded(child: child)]);
      },
    );
  }
}

class AppTitleBar extends StatefulWidget {
  const AppTitleBar({super.key});

  @override
  State<AppTitleBar> createState() => _AppTitleBarState();
}

class _AppTitleBarState extends State<AppTitleBar> with WindowListener {
  var _maximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    WindowChrome.isMaximized().then((value) {
      if (mounted && value) setState(() => _maximized = true);
    });
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  void _setMaximized(bool value) {
    if (mounted && value != _maximized) setState(() => _maximized = value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    return Material(
      color: colorScheme.surface,
      child: GestureDetector(
        // The window is frameless, so dragging and double clicking have to be
        // forwarded to the platform by hand.
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => WindowChrome.startDragging(),
        onDoubleTap: WindowChrome.toggleMaximize,
        child: SizedBox(
          height: appTitleBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 14),
              // 左上角的应用图标，与标题文字同一行
              Image.asset('assets/logo.png', width: 16, height: 16, filterQuality: FilterQuality.high),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  l10n.appTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
              _TitleBarButton(label: l10n.minimizeWindow, onPressed: WindowChrome.minimize, icon: Icons.remove, iconSize: 16),
              _TitleBarButton(
                label: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
                onPressed: WindowChrome.toggleMaximize,
                icon: _maximized ? Icons.filter_none : Icons.crop_square,
                iconSize: _maximized ? 14 : 13,
              ),
              _TitleBarButton(label: l10n.close, onPressed: WindowChrome.close, icon: Icons.close, iconSize: 16, danger: true),
            ],
          ),
        ),
      ),
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({required this.label, required this.onPressed, required this.icon, required this.iconSize, this.danger = false});

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final double iconSize;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  static const _closeColor = Color(0xffc42b1c);
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final background = !_hovered
        ? Colors.transparent
        : widget.danger
            ? _closeColor
            : colorScheme.onSurface.withValues(alpha: .08);
    final foreground = widget.danger && _hovered ? Colors.white : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: widget.label,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Container(
            width: 46,
            height: appTitleBarHeight,
            color: background,
            child: Icon(widget.icon, size: widget.iconSize, color: foreground),
          ),
        ),
      ),
    );
  }
}
