import 'package:flutter/material.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import 'press_scale.dart';

/// 列表底部要给右下角浮动操作（[ScrollActions]：刷新 / 回到顶部）留的净空。
///
/// 那组按钮是浮在内容**之上**、不占独立列的，所以每个用到它的列表都得自己把这段
/// 高度让出来；不让的话滚到底时最后一行右侧那张卡会永远压着一个按钮，右下角点不到
/// （BiliDesk 的首页也是为它的浮动工具列在内容末尾留了 250px，同一个道理）。
/// 44 + 间隙 10 + 44 + 下边距 16 = 114，取 120 留一点余量。
const double floatingActionsClearance = 120;

/// 列表页右下角的悬浮操作：刷新 + 回到顶部。
///
/// 需要调用方给出列表自己的 [controller]（不在滚动树里面时 `Scrollable.of` 拿不到），
/// 以及刷新回调。[visibleAfter] 是「回到顶部」按钮出现的滚动距离。
class ScrollActions extends StatefulWidget {
  const ScrollActions({super.key, required this.controller, required this.onRefresh, this.visibleAfter = 240, this.inset = 16});

  final ScrollController controller;
  final Future<void> Function() onRefresh;
  final double visibleAfter;
  final double inset;

  @override
  State<ScrollActions> createState() => _ScrollActionsState();
}

class _ScrollActionsState extends State<ScrollActions> {
  var _busy = false;
  var _showTop = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleScroll);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleScroll);
    super.dispose();
  }

  void _handleScroll() {
    if (!mounted) return;
    final show = widget.controller.hasClients && widget.controller.offset > widget.visibleAfter;
    if (show != _showTop) setState(() => _showTop = show);
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toTop() {
    if (!widget.controller.hasClients) return;
    widget.controller.animateTo(0, duration: AppMotion.dialog, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    // 图标色跟着主题走：玻璃在浅色主题下是浅的，再画白图标就看不见了。
    final ink = Theme.of(context).colorScheme.onSurface;
    return Padding(
      padding: EdgeInsets.only(right: widget.inset, bottom: widget.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ActionButton(tooltip: l10n.refresh, onTap: _refresh, child: _busy ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: ink)) : Icon(Symbols.refresh_rounded, size: 22, color: ink)),
          AnimatedSize(
            // 原为字面量 180ms。同一次「回到顶部」里，滚动动画用的是 AppMotion.dialog
            // （300ms）而按钮展开只用 180ms，按钮会先冒出来、列表还在往上滑，看着是两段。
            // 归到最接近的 standard（200ms）：它是 180 的最近一档（差 20ms，brief 差 30ms），
            // 且语义上「标准过渡」正是这里要的；升到 dialog 反而比点击反馈慢半拍。
            duration: AppMotion.standard,
            curve: Curves.easeOutCubic,
            alignment: Alignment.bottomCenter,
            child: _showTop
                ? Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: _ActionButton(
                      tooltip: l10n.backToTop,
                      onTap: _toTop,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Symbols.arrow_upward_rounded, size: 18, color: ink),
                          const SizedBox(height: 1),
                          Text(l10n.backToTop, style: TextStyle(fontSize: 11, color: ink, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  )
                : const SizedBox(width: 44),
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  const _ActionButton({required this.tooltip, required this.onTap, required this.child});

  final String tooltip;
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        // 悬浮控件回到主题自己的面（玻璃已停用，决策见 `docs/ui-polish.md`）。
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(AppRadius.md),
          clipBehavior: Clip.antiAlias,
          child: PressScale(child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Center(child: child)),
          )),
        ),
      );
}
