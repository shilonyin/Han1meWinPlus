import 'package:flutter/material.dart';

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
    return Padding(
      padding: EdgeInsets.only(right: widget.inset, bottom: widget.inset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _ActionButton(tooltip: l10n.refresh, onTap: _refresh, child: _busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const Icon(Icons.refresh, size: 22, color: Colors.white)),
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
                          const Icon(Icons.arrow_upward, size: 18, color: Colors.white),
                          const SizedBox(height: 1),
                          Text(l10n.backToTop, style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w600)),
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
        child: Material(
          color: const Color(0xB3000000),
          borderRadius: BorderRadius.circular(12),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: SizedBox(width: 44, height: 44, child: Center(child: child)),
          ),
        ),
      );
}
