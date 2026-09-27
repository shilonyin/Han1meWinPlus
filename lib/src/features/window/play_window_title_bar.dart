import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/play_window_title_target.dart';
import '../../core/window_chrome.dart';

/// 独立播放窗口专用的标题栏。
///
/// 与主窗口的 [AppTitleBar] 不同：主窗口那条只放 logo 与窗口按钮，而播放窗口
/// 需要在**同一条**里给出「回到主界面 / 上一集 / 下一集 / 居中标题 / 置顶 /
/// 画中画 / 窗口按钮」——因为播放窗口没有导航壳，用户只有这一条可操作。
///
/// 尺寸照抄参考实现（实测 72 物理 px @150% DPI = 48 逻辑 px，底色 #1E2022）。
///
/// 标题与上下集能力来自播放页（见 [PlayWindowTitleTarget]）：本组件挂在窗口级，
/// 而 VideoDetail 属于播放页内部，两者不在同一棵子树上，所以通过那张登记表桥接。
class PlayWindowTitleBar extends StatefulWidget {
  const PlayWindowTitleBar({required this.onHome, super.key});

  /// 「回到主界面」：唤起主窗口（没在运行就冷启动）。
  final VoidCallback onHome;

  @override
  State<PlayWindowTitleBar> createState() => _PlayWindowTitleBarState();
}

/// 与参考实现一致：72 物理 px @150% = 48 逻辑 px。
const double playWindowTitleBarHeight = 48;

/// 标题栏底色。参考实现是固定的深色，不跟主题走——播放窗口整条都是深色调，
/// 用浅色主题的 surface 会在纯黑画面之上割出一块亮条。
const Color _barColor = Color(0xFF1E2022);

class _PlayWindowTitleBarState extends State<PlayWindowTitleBar> {
  var _maximized = false;
  var _pinned = false;

  /// 进入画中画前的窗口矩形；非 null 表示现在正处于画中画小窗。
  Rect? _boundsBeforePip;

  @override
  void initState() {
    super.initState();
    WindowChrome.isMaximized().then((value) {
      if (mounted && value) setState(() => _maximized = value);
    });
  }

  Future<void> _togglePin() async {
    final next = !_pinned;
    if (await WindowChrome.setAlwaysOnTop(next) && mounted) {
      setState(() => _pinned = next);
    }
  }

  /// 画中画：把窗口缩成右下角的小窗并置顶；再点一次还原。
  ///
  /// 桌面端没有系统级画中画可用（PlatformService.enterPictureInPicture 在非 Android
  /// 直接返回 false），而参考实现里这个按钮的语义就是「缩成小窗浮在其它窗口之上」，
  /// 所以用「改窗口尺寸 + 置顶」在窗口层面实现。还原时恢复原来的位置与尺寸，
  /// 并记住用户原本是否置顶（画中画必置顶，退出时还原成原样）。
  Future<void> _togglePictureInPicture() async {
    final entering = _boundsBeforePip == null;
    if (entering) {
      final current = await WindowChrome.getBounds();
      if (current == null) return;
      // 小窗尺寸照参考比例：宽 360 逻辑像素、按 16:9 得高 202，再给整窗加一点余量。
      const size = Size(380, 240);
      final screen = await WindowChrome.workArea();
      final target = Rect.fromLTWH(
        (screen?.right ?? current.right) - size.width - 16,
        (screen?.bottom ?? current.bottom) - size.height - 16,
        size.width,
        size.height,
      );
      final pinned = await WindowChrome.setAlwaysOnTop(true);
      if (!await WindowChrome.setBounds(target)) return;
      if (!mounted) return;
      setState(() {
        _boundsBeforePip = current;
        _pinned = pinned;
      });
    } else {
      final restore = _boundsBeforePip!;
      await WindowChrome.setBounds(restore);
      // 退出画中画时取消置顶，回到进入前的状态。
      await WindowChrome.setAlwaysOnTop(false);
      if (!mounted) return;
      setState(() {
        _boundsBeforePip = null;
        _pinned = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final inPip = _boundsBeforePip != null;
    return Material(
      color: _barColor,
      child: GestureDetector(
        // 窗口无边框，拖动与双击最大化要自己转给平台。
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => WindowChrome.startDragging(),
        onDoubleTap: () => _toggleMaximize(),
        child: SizedBox(
          height: playWindowTitleBarHeight,
          child: Row(
            children: [
              const SizedBox(width: 8),
              _HomeButton(label: l10n.backToMainWindow, onPressed: widget.onHome),
              const SizedBox(width: 4),
              // 上一集 / 下一集：能不能点由播放页登记的可用性决定。
              ValueListenableBuilder<bool>(
                valueListenable: PlayWindowTitleTarget.hasPrevious,
                builder: (context, enabled, _) => _NavArrow(
                  icon: Icons.chevron_left,
                  label: l10n.hotkeyActionPreviousEpisode,
                  onPressed: enabled ? PlayWindowTitleTarget.previousEpisode : null,
                ),
              ),
              ValueListenableBuilder<bool>(
                valueListenable: PlayWindowTitleTarget.hasNext,
                builder: (context, enabled, _) => _NavArrow(
                  icon: Icons.chevron_right,
                  label: l10n.hotkeyActionNextEpisode,
                  onPressed: enabled ? PlayWindowTitleTarget.nextEpisode : null,
                ),
              ),
              // 居中标题：Expanded 让它占据剩余空间并居中。
              Expanded(
                child: ValueListenableBuilder<String>(
                  valueListenable: PlayWindowTitleTarget.title,
                  builder: (context, title, _) => Center(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFFE6E6E9),
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
              _IconAction(
                icon: _pinned ? Icons.push_pin : Icons.push_pin_outlined,
                label: _pinned ? l10n.unpinWindow : l10n.pinWindow,
                active: _pinned,
                onPressed: _togglePin,
              ),
              _IconAction(
                icon: inPip
                    ? Icons.branding_watermark
                    : Icons.branding_watermark_outlined,
                label: l10n.pictureInPicture,
                active: inPip,
                onPressed: _togglePictureInPicture,
              ),
              const _BarDivider(),
              _WindowButton(
                label: l10n.minimizeWindow,
                icon: Icons.remove,
                onPressed: WindowChrome.minimize,
              ),
              _WindowButton(
                label: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
                icon: _maximized ? Icons.filter_none : Icons.crop_square,
                iconSize: _maximized ? 14 : 13,
                onPressed: () => _toggleMaximize(),
              ),
              _WindowButton(
                label: l10n.close,
                icon: Icons.close,
                danger: true,
                onPressed: WindowChrome.close,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _toggleMaximize() async {
    await WindowChrome.toggleMaximize();
    final value = await WindowChrome.isMaximized();
    if (mounted) setState(() => _maximized = value);
  }
}

/// 「回到主界面」：图标 + 文字的胶囊按钮。
class _HomeButton extends StatefulWidget {
  const _HomeButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback onPressed;

  @override
  State<_HomeButton> createState() => _HomeButtonState();
}

class _HomeButtonState extends State<_HomeButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
    cursor: SystemMouseCursors.click,
    onEnter: (_) => setState(() => _hovered = true),
    onExit: (_) => setState(() => _hovered = false),
    child: GestureDetector(
      // opaque：整个胶囊（含内边距）都可点，而不是只有文字那几像素。
      behavior: HitTestBehavior.opaque,
      onTap: widget.onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: _hovered ? const Color(0xFF2E3134) : const Color(0xFF25282B),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.home_outlined, size: 17, color: Color(0xFFE6E6E9)),
            const SizedBox(width: 6),
            Text(
              widget.label,
              style: const TextStyle(color: Color(0xFFE6E6E9), fontSize: 13),
            ),
          ],
        ),
      ),
    ),
  );
}

/// 上一集 / 下一集箭头；[onPressed] 为 null 时置灰不可点。
class _NavArrow extends StatelessWidget {
  const _NavArrow({required this.icon, required this.label, this.onPressed});

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
    message: label,
    child: IconButton(
      onPressed: onPressed,
      icon: Icon(icon, size: 22),
      color: const Color(0xFFE6E6E9),
      disabledColor: const Color(0xFF5A5E63),
      visualDensity: VisualDensity.compact,
      splashRadius: 18,
    ),
  );
}

/// 置顶 / 画中画这类图标按钮。
class _IconAction extends StatefulWidget {
  const _IconAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool active;

  @override
  State<_IconAction> createState() => _IconActionState();
}

class _IconActionState extends State<_IconAction> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final color = widget.active
        ? const Color(0xFF4FC3F7)
        : const Color(0xFFE6E6E9);
    return Tooltip(
      message: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: Container(
            width: 38,
            height: playWindowTitleBarHeight,
            color: _hovered ? const Color(0xFF2E3134) : Colors.transparent,
            child: Icon(widget.icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

/// 窗口按钮之间那条细分隔线。
class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 20,
    margin: const EdgeInsets.symmetric(horizontal: 4),
    color: const Color(0xFF3A3D41),
  );
}

/// 最小化 / 最大化 / 关闭，行为与应用内标题栏一致（含关闭键的红色悬停）。
class _WindowButton extends StatefulWidget {
  const _WindowButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.iconSize = 16,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback onPressed;
  final double iconSize;
  final bool danger;

  @override
  State<_WindowButton> createState() => _WindowButtonState();
}

class _WindowButtonState extends State<_WindowButton> {
  static const _closeColor = Color(0xFFC42B1C);
  var _hovered = false;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: widget.label,
    child: MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: Container(
          width: 46,
          height: playWindowTitleBarHeight,
          color: !_hovered
              ? Colors.transparent
              : widget.danger
              ? _closeColor
              : const Color(0xFF2E3134),
          child: Icon(
            widget.icon,
            size: widget.iconSize,
            color: widget.danger && _hovered
                ? Colors.white
                : const Color(0xFFE6E6E9),
          ),
        ),
      ),
    ),
  );
}
