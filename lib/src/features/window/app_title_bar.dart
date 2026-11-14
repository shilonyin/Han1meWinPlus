import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../app/app_theme.dart';
import '../../core/window_chrome.dart';
import '../settings/settings_controller.dart';
import 'pip_overlay_controls.dart';

/// Height of the in-app title bar.
///
/// 主窗口「合并标题栏」之后，这条栏只铺一条可拖拽的窄带 + 右侧窗口按钮，
/// 锁标交给侧栏顶部。取 28：嵌在侧栏顶部留白带（12 + 28 + 4 = 44）的上沿里，
/// 右侧三个按钮就落在侧栏白底上、和锁标同一行，不额外占垂直空间。
/// 播放窗口用的是自己的 [playWindowTitleBarHeight]，不受这里影响。
const double appTitleBarHeight = 28;

/// Draws the app's own title bar when the appearance settings ask for it, so
/// turning the system title bar off still leaves a draggable window with the
/// usual minimize / maximize / close buttons.
class AppWindowFrame extends ConsumerWidget {
  const AppWindowFrame({required this.child, this.titleBar, super.key});

  final Widget child;

  /// 换一条标题栏。独立播放窗口传 [PlayWindowTitleBar]——它比主窗口那条多出
  /// 「回到主界面 / 上下集 / 居中标题 / 置顶 / 画中画」，因为播放窗口没有导航壳，
  /// 用户只有这一条可操作。省略时用主窗口的 [AppTitleBar]。
  final Widget? titleBar;

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
            Widget bar = titleBar ?? const AppTitleBar();
            // 自定义标题栏自带配色（播放窗口那条是照参考实现的固定深色），
            // 不再套主题，免得被浅色主题叠成亮条。
            if (immersive && titleBar == null) {
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
            // 注意：这里的自定义标题栏**没有 Overlay 祖先**。
            //
            // AppWindowFrame 跑在 MaterialApp.builder 里，也就是包在 Navigator **外面**；
            // 而 Overlay 是每个 route 各自建在 Navigator **内部**。所以标题栏里**不要放
            // 依赖 Overlay 的组件**（Tooltip / PopupMenuButton / showMenu 等）：
            // 缺 Overlay 会抛「No Overlay widget found ... require an Overlay widget
            // ancestor」，整条标题栏被 RenderErrorBox（默认底色 0xF0C0C0C0，叠在深色上
            // 就是一块 (183,183,183) 灰块）顶掉。
            //
            // 曾经试过套一层 `Overlay.wrap(alwaysSizeToContent: true)` 来喂 Tooltip，
            // 但那条 Overlay 只有标题栏本身那么高，提示气泡往下弹就被裁掉半截（实测），
            // 所以改成不挂 Tooltip —— 图标按钮用悬停高亮表达状态，无障碍标签走 Semantics。
            // 若将来确实需要气泡/菜单，正确做法是把**整个 Column（标题栏 + 内容）**包进
            // Overlay，而不是只包标题栏。
            // 主窗口：顶部悬浮层只让出窗口按钮那一小段宽度来拖拽（左侧全透明，
            // 点击穿透给下面的侧栏 / 顶栏）。播放窗口那条仍铺满整宽（它自带标题栏
            // 内容，且没有导航壳可穿透）。
            // 主窗口的顶部悬浮层：一条窄带负责拖窗口 / 双击最大化，右上角挂按钮。
            //
            // 关键：用 HitTestBehavior.translucent —— 单击会穿透给下面的侧栏品牌块 /
            // 顶栏控件（它们仍在命中测试里），只有「拖动」这个手势才被这条带子接走，
            // 交给平台去移动窗口。以前这里是个裸 Container + WindowTitleControls，
            // 没有任何拖拽手势，所以「合并标题栏」之后主窗口就拖不动了。
            final overlayBar = titleBar == null
                ? GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onPanStart: (_) => WindowChrome.startDragging(),
                    onDoubleTap: WindowChrome.toggleMaximize,
                    child: SizedBox(
                      height: 64,
                      child: const Align(
                        alignment: Alignment.centerRight,
                        child: WindowTitleControls(height: 40),
                      ),
                    ),
                  )
                : bar;
            return ValueListenableBuilder<bool>(
              valueListenable: WindowChrome.pipMode,
              builder: (context, pip, ___) => pip
                  // 画中画小窗：视频铺满整窗，标题栏与中央大圆按钮**浮在画面上**，
                  // 而不是把画面挤掉一条（参考实现里小窗就是这么做的）。
                  ? Stack(children: [
                      Positioned.fill(child: child),
                      Positioned(top: 0, left: 0, right: 0, child: bar),
                      const Center(child: PipOverlayControls()),
                    ])
                  // 主窗口：标题栏不再占一条高度，改成**右上角悬浮层** —— 一条可拖拽的
                  // 顶部窄带（负责拖窗口 / 双击最大化）+ 右上角三个窗口按钮。
                  // 这样 logo 只出现在侧栏一次，视觉上和系统标题栏一致，也不挤任何一列。
                  : Stack(children: [
                      Positioned.fill(child: child),
                      Positioned(top: 0, left: 0, right: 0, child: overlayBar),
                    ]),
            );
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
  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  // 最大化 / 还原状态由 [WindowTitleControls] 订阅，这里只保留监听以维持原有
  // 生命周期约定（避免 WindowListener 注册行为变化带来的副作用）。
  @override
  void onWindowMaximize() {}
  @override
  void onWindowUnmaximize() {}

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 主窗口把「锁标」交给侧栏顶部（见 _DesktopSidebar 的品牌锁标块），
    // 标题栏这里只铺一条**可拖拽的窄带**，右侧挂窗口按钮 —— 两行 logo 合成一行，
    // 省掉原来那条独立标题栏。整条透明、以悬浮层叠在内容之上，点击空白处穿透。
    //
    // 高度取 appTitleBarHeight（28）：与侧栏顶部留白带对齐，按钮就压在最右上角，
    // 和锁标同一水平线。宽度由 AppWindowFrame 控制（只占窗口按钮那段），
    // 所以这里用 Row 把按钮推到左端即可 —— 不要再塞 Expanded（Expanded 需要
    // 有界宽度，而外层是 Spacer 包着的只能收缩到内容宽度）。
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        // The window is frameless, so dragging and double clicking have to be
        // forwarded to the platform by hand.
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => WindowChrome.startDragging(),
        onDoubleTap: WindowChrome.toggleMaximize,
        child: SizedBox(
          height: appTitleBarHeight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const WindowTitleControls(),
              const SizedBox(width: 6),
              // 拖拽热区：按钮右侧留一截窄条让人能拖窗口 / 双击最大化。
              Semantics(
                label: l10n.appTitle,
                child: const SizedBox(width: 24, height: appTitleBarHeight),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 窗口的 最小化 / 最大化还原 / 关闭 三个按钮，主窗口标题栏与侧栏顶部共用。
///
/// 单拎出来是因为「合并标题栏」之后，按钮既要能挂在标题栏窄带里（默认），
/// 也要能挂进侧栏顶部那一行品牌锁标的右边；两处共用一个实现，别各画一套。
class WindowTitleControls extends StatefulWidget {
  const WindowTitleControls({this.height = appTitleBarHeight, super.key});

  /// 按钮高度，跟随所挂的那一行。
  final double height;

  @override
  State<WindowTitleControls> createState() => _WindowTitleControlsState();
}

class _WindowTitleControlsState extends State<WindowTitleControls> with WindowListener {
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
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _TitleBarButton(label: l10n.minimizeWindow, onPressed: WindowChrome.minimize, icon: Symbols.remove_rounded, iconSize: 18, height: widget.height),
        _TitleBarButton(
          label: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
          onPressed: WindowChrome.toggleMaximize,
          icon: _maximized ? Symbols.filter_none_rounded : Symbols.crop_square_rounded,
          iconSize: _maximized ? 16 : 15,
          height: widget.height,
        ),
        _TitleBarButton(label: l10n.close, onPressed: WindowChrome.close, icon: Symbols.close_rounded, iconSize: 18, height: widget.height, danger: true),
      ],
    );
  }
}

class _TitleBarButton extends StatefulWidget {
  const _TitleBarButton({required this.label, required this.onPressed, required this.icon, required this.iconSize, this.height = appTitleBarHeight, this.danger = false});

  final String label;
  final VoidCallback onPressed;
  final IconData icon;
  final double iconSize;
  final double height;
  final bool danger;

  @override
  State<_TitleBarButton> createState() => _TitleBarButtonState();
}

class _TitleBarButtonState extends State<_TitleBarButton> {
  static const _closeColor = Color(0xffc42b1c);
  var _hovered = false;
  var _focused = false;

  /// 键盘激活：Enter / Space 与鼠标点击同义（Windows 上按钮的通行约定）。
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey != LogicalKeyboardKey.enter &&
        event.logicalKey != LogicalKeyboardKey.space) {
      return KeyEventResult.ignored;
    }
    widget.onPressed();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // 焦点态必须**自己画**：本组件是裸 GestureDetector（没有 InkWell 那层焦点高亮），
    // 而标题栏位于 MaterialApp.builder（Navigator 之外，没有 Overlay），所以既不能
    // 用 Tooltip 也不能用 InkWell 的水波纹。这里用主题色 12% 的底色 + 主题色图标
    // 表达"键盘现在停在这儿"，和鼠标悬停的灰底（8%）能区分开。
    final background = _focused
        ? colorScheme.primary.withValues(alpha: .12)
        : !_hovered
            ? Colors.transparent
            : widget.danger
                ? _closeColor
                : colorScheme.onSurface.withValues(alpha: .08);
    final foreground = _focused
        ? colorScheme.primary
        : widget.danger && _hovered
            ? Colors.white
            : colorScheme.onSurfaceVariant;
    return Semantics(
      button: true,
      label: widget.label,
      child: Focus(
        canRequestFocus: true,
        onFocusChange: (value) => setState(() => _focused = value),
        onKeyEvent: _onKey,
        child: MouseRegion(
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: widget.onPressed,
            child: Container(
              width: 46,
              height: widget.height,
              color: background,
              child: Icon(widget.icon, size: widget.iconSize, color: foreground),
            ),
          ),
        ),
      ),
    );
  }
}
