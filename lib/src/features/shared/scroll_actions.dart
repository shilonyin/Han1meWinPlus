import 'package:flutter/material.dart';

import 'package:g1455/g1455.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';

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
    widget.controller.animateTo(0, duration: const Duration(milliseconds: 320), curve: Curves.easeOutCubic);
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
            duration: const Duration(milliseconds: 180),
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
        // 玻璃按钮。刻意不传 finish：这样它直接吃 GlassHost 上那一份，
        // 于是「材质 / 玻璃染色」一改，这个按钮跟着变（原来是一块 70% 黑的不透明板）。
        // 它是悬浮在列表之上的控件、不随内容滚动，所以不会吃到内容卡片那种滞后一帧的糊块。
        child: GlassSurface(
          borderRadius: BorderRadius.circular(12),
          // 文字色由我们给，别让包按它那个我们从不画的白标签把材质压暗。
          labelled: false,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              child: SizedBox(width: 44, height: 44, child: Center(child: child)),
            ),
          ),
        ),
      );
}
