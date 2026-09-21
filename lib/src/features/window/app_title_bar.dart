import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
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
        return ValueListenableBuilder<bool>(
          valueListenable: WindowChrome.immersivePage,
          builder: (context, immersive, __) {
            // 播放页是沉浸页：标题栏一起走深色，别在纯黑播放页上方留一条浅色。
            // 字体与配色开关跟 App 层保持一致，否则标题栏的字会跟应用其它地方不一样。
            Widget bar = const AppTitleBar();
            if (immersive) {
              bar = Theme(
                data: appTheme(
                  null,
                  settings.themeColor.seedColor(settings.customThemeColor),
                  brightness: Brightness.dark,
                  amoled: settings.amoledMode,
                  useSystemFont: settings.useSystemFont,
                  variant: settings.themeColor.schemeVariant,
                  neutralSurfaces: true,
                ),
                child: bar,
              );
            }
            return Column(children: [bar, Expanded(child: child)]);
          },
        );
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
              // 左上角整张锁标（图标 + 字标一体，和关于页 / README 同源）。
              // 标题栏只有 34px 高：按设计稿比例（图标:字标 = 2.4:1）显示时字标只剩
              // 8~11px，改用紧凑版（1.5:1）—— 16px 高时图标 16px、字标约 11px，
              // 与 Windows 标题栏图标的常规尺寸一致。
              Image.asset('assets/logo_lockup_compact.png', height: 16, filterQuality: FilterQuality.high, semanticLabel: l10n.appTitle),
              const Spacer(),
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
