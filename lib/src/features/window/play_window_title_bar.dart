import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
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

/// 标题栏的两档收缩阈值（逻辑像素）。
///
/// 栏里固定宽度的东西加起来约 414px：回到主界面（含文字）113 + 上下集 72 +
/// 置顶/画中画 72 + 分隔线 9 + 三个窗口按钮 138 + 间距 10。而画中画小窗只有
/// 380px 宽 —— 不收缩就会溢出：实测「关闭」被推到 x383..399（窗口外，用户点不到），
/// 标题被压成 0 宽。低于 [_compactTitleBarWidth] 收起「回到主界面」文字并缩窄按钮，
/// 低于 [_tightTitleBarWidth]（画中画 380 落在这一档）再缩一档。
const double _compactTitleBarWidth = 600;
const double _tightTitleBarWidth = 400;

/// 标题栏底色。参考实现是固定的深色，不跟主题走——播放窗口整条都是深色调，
/// 用浅色主题的 surface 会在纯黑画面之上割出一块亮条。
const Color _barColor = Color(0xFF1E2022);

// ---------- 标题栏里所有可点项共用的一套视觉参数 ----------
//
// 之前四处各写各的：「回到主界面」是 8px 圆角胶囊、上一集/下一集直接用了
// IconButton（Material 默认是**圆形**水波）、置顶/画中画是**直角**满高方块、
// 最小化/最大化/关闭也是直角方块。鼠标在栏上扫过去，高亮形状一直在变
// （圆角→圆形→直角），看着就不是一套东西。
//
// 现在统一成**同一个圆角矩形**：圆角、悬停底色、尺寸都从这里取，改一处即可。
const double _barButtonRadius = 8;
const Color _barHoverColor = Color(0xFF2E3134);
const Color _barActiveColor = Color(0xFF4FC3F7);
const Color _barDangerColor = Color(0xFFC42B1C);
const Color _barIconColor = Color(0xFFE6E6E9);
const Color _barDisabledColor = Color(0xFF5A5E63);

/// 标题栏里图标按钮的统一高度；上下各留 6px，让圆角高亮不贴满整条栏。
const double _barButtonHeight = playWindowTitleBarHeight - 12;

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
      // 外壳（AppWindowFrame）据此把标题栏从「占位」换成「半透明浮层」，
      // 并把中央大圆按钮浮到画面上。
      WindowChrome.pipMode.value = true;
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
      WindowChrome.pipMode.value = false;
      setState(() {
        _boundsBeforePip = null;
        _pinned = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 画中画的唯一状态源是 [WindowChrome.pipMode]：外壳（AppWindowFrame）也读它，
    // 两边各判各的（这里原来用 _boundsBeforePip）迟早会不同步——外壳已经把标题栏
    // 换成浮层了，标题栏自己却还画着实心底色。[_boundsBeforePip] 只用来还原窗口尺寸。
    final inPip = WindowChrome.pipMode.value;
    return Material(
      // 画中画小窗里这条标题栏是**浮在画面上**的：用半透明黑（参考实现实测约
      // 30% 不透明度，透光率 0.72），视频从底下透出来；普通播放窗口保持实心 #1E2022。
      color: inPip ? Colors.black.withValues(alpha: 0.30) : _barColor,
      child: GestureDetector(
        // 窗口无边框，拖动与双击最大化要自己转给平台。
        behavior: HitTestBehavior.opaque,
        onPanStart: (_) => WindowChrome.startDragging(),
        onDoubleTap: () => _toggleMaximize(),
        child: SizedBox(
          height: playWindowTitleBarHeight,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < _compactTitleBarWidth;
              final tight = constraints.maxWidth < _tightTitleBarWidth;
              // 窄窗收起「回到主界面」的文字（省 66px），按钮统一收窄成同一宽度——
              // 一栏里混着 26/30/32 三种宽度会显得参差。
              final buttonWidth = tight ? 30.0 : 34.0;
              final navIconSize = tight ? 18.0 : 20.0;
              final windowIconSize = tight ? 14.0 : 15.0;
              return Row(
                children: [
                  const SizedBox(width: 8),
                  _BarButton(
                    label: l10n.backToMainWindow,
                    // 画中画小窗里文字占 66px，收掉它才腾得出标题和窗口按钮的位置。
                    text: compact ? null : l10n.backToMainWindow,
                    icon: Symbols.home_rounded,
                    width: compact ? buttonWidth : null,
                    onPressed: widget.onHome,
                  ),
                  const SizedBox(width: 2),
                  // 上一集 / 下一集：能不能点由播放页登记的可用性决定。
                  //
                  // 画中画小窗里这两个操作已经放大到画面中央（PipOverlayControls），
                  // 这里不再重复占位——参考实现的小窗也只留主页 / 标题 / 置顶 / 关闭。
                  if (!inPip) ...[
                    ValueListenableBuilder<bool>(
                      valueListenable: PlayWindowTitleTarget.hasPrevious,
                      builder: (context, enabled, _) => _BarButton(
                        label: l10n.hotkeyActionPreviousEpisode,
                        icon: Symbols.chevron_left_rounded,
                        iconSize: compact ? navIconSize : 22,
                        width: compact ? buttonWidth : 36,
                        onPressed: enabled
                            ? PlayWindowTitleTarget.previousEpisode
                            : null,
                      ),
                    ),
                    ValueListenableBuilder<bool>(
                      valueListenable: PlayWindowTitleTarget.hasNext,
                      builder: (context, enabled, _) => _BarButton(
                        label: l10n.hotkeyActionNextEpisode,
                        icon: Symbols.chevron_right_rounded,
                        iconSize: compact ? navIconSize : 22,
                        width: compact ? buttonWidth : 36,
                        onPressed: enabled ? PlayWindowTitleTarget.nextEpisode : null,
                      ),
                    ),
                  ],
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
                  _BarButton(
                    label: _pinned ? l10n.unpinWindow : l10n.pinWindow,
                    icon: Symbols.push_pin_rounded,
                    width: compact ? buttonWidth : 36,
                    active: _pinned,
                    onPressed: _togglePin,
                  ),
                  _BarButton(
                    label: l10n.pictureInPicture,
                    icon: Symbols.branding_watermark_rounded,
                    width: compact ? buttonWidth : 36,
                    active: inPip,
                    onPressed: _togglePictureInPicture,
                  ),
                  // 窄窗把分隔线也收掉：它连外边距占 9px，小窗里不值这个宽度。
                  if (!compact && !inPip) const _BarDivider(),
                  // 窗口按钮与应用内标题栏保持同一套尺寸（宽屏 46 宽、圆角高亮）。
                  //
                  // 画中画小窗里最小化 / 最大化没有意义（本来就是浮在角上的小窗），
                  // 收掉它们把宽度让给标题，只留关闭——与参考实现一致。
                  if (!inPip) ...[
                    _BarButton(
                      label: l10n.minimizeWindow,
                      icon: Symbols.remove_rounded,
                      iconSize: compact ? windowIconSize : 16,
                      width: compact ? buttonWidth : 46,
                      onPressed: WindowChrome.minimize,
                    ),
                    _BarButton(
                      label: _maximized ? l10n.restoreWindow : l10n.maximizeWindow,
                      icon: _maximized ? Symbols.filter_none_rounded : Symbols.crop_square_rounded,
                      iconSize: _maximized ? (compact ? 13 : 14) : (compact ? 12 : 13),
                      width: compact ? buttonWidth : 46,
                      onPressed: () => _toggleMaximize(),
                    ),
                  ],
                  _BarButton(
                    label: l10n.close,
                    icon: Symbols.close_rounded,
                    iconSize: compact ? windowIconSize : 16,
                    width: compact ? buttonWidth : 46,
                    danger: true,
                    onPressed: WindowChrome.close,
                  ),
                ],
              );
            },
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

/// 标题栏里所有可点项的**唯一**实现：统一的圆角悬停高亮。
///
/// 之前这里是四份各写各的（胶囊 / IconButton 圆形水波 / 直角方块 / 直角方块），
/// 鼠标扫过去高亮形状会变，看着不是一套。现在形状、尺寸、配色都走
/// [_barButtonRadius] / [_barButtonHeight] / [_barHoverColor] 这几个常量。
///
/// 不挂 Tooltip：AppWindowFrame 位于 MaterialApp.builder 里（Navigator 之外，
/// 没有 Overlay 祖先），Tooltip 会在第一次悬停时抛「No Overlay widget found」，
/// 把整条标题栏换成灰色错误框。无障碍标签走 Semantics。
class _BarButton extends StatefulWidget {
  const _BarButton({
    required this.label,
    required this.onPressed,
    this.icon,
    this.iconSize = 18,
    this.text,
    this.width,
    this.active = false,
    this.danger = false,
  });

  /// 无障碍标签。
  final String label;

  /// 为 null 表示禁用（图标置灰）。
  final VoidCallback? onPressed;

  final IconData? icon;
  final double iconSize;

  /// 给了文字就画成「图标 + 文字」的宽按钮（回到主界面）。
  final String? text;

  /// 固定宽度；不给就按内容自适应。
  final double? width;

  /// 激活态（置顶 / 画中画已开启）用强调色。
  final bool active;

  /// 关闭键：悬停变红底白字。
  final bool danger;

  @override
  State<_BarButton> createState() => _BarButtonState();
}

class _BarButtonState extends State<_BarButton> {
  var _hovered = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final foreground = !enabled
        ? _barDisabledColor
        : widget.danger && _hovered
        ? Colors.white
        : widget.active
        ? _barActiveColor
        : _barIconColor;

    final background = !_hovered || !enabled
        ? Colors.transparent
        : widget.danger
        ? _barDangerColor
        : _barHoverColor;

    final label = widget.text;
    final content = label == null
        // 激活态（置顶 / 画中画已开）：图标走 fill:1 实心，与强调色一起表达「已开启」。
        ? Icon(widget.icon, size: widget.iconSize, color: foreground, fill: widget.active ? 1 : 0)
        : Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 17, color: foreground),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: foreground,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          );

    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          // opaque：整个圆角块（含内边距）都可点，而不是只有图标那几像素。
          behavior: HitTestBehavior.opaque,
          onTap: widget.onPressed,
          child: Center(
            child: Container(
              width: widget.width,
              height: _barButtonHeight,
              padding: label == null
                  ? null
                  : const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: background,
                borderRadius: BorderRadius.circular(_barButtonRadius),
              ),
              child: Center(child: content),
            ),
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
