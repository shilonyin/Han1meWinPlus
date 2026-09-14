import 'dart:async';

import 'package:flutter/material.dart';

/// 屏幕中间的半透明圆角提示，用来代替贴底的 SnackBar。
///
/// 出现约 1.7 秒后自动淡出，期间 [IgnorePointer] 不拦截点击，也不会挤动页面布局。
void showAppToast(BuildContext context, String message, {IconData? icon}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  late final OverlayEntry entry;
  entry = OverlayEntry(builder: (_) => _AppToast(message: message, icon: icon, onDone: () => entry.remove()));
  overlay.insert(entry);
}

class _AppToast extends StatefulWidget {
  const _AppToast({required this.message, required this.onDone, this.icon});

  final String message;
  final IconData? icon;
  final VoidCallback onDone;

  @override
  State<_AppToast> createState() => _AppToastState();
}

class _AppToastState extends State<_AppToast> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 180));
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    _timer = Timer(const Duration(milliseconds: 1700), () async {
      await _controller.reverse();
      widget.onDone();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return IgnorePointer(
      child: Center(
        child: FadeTransition(
          opacity: _controller,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.94, end: 1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 32),
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 6))],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.icon case final icon?) ...[Icon(icon, size: 18, color: colorScheme.primary), const SizedBox(width: 10)],
                    Flexible(
                      child: Text(
                        widget.message,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurface),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
