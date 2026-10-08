import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import '../../data/remote/han1me_api.dart' show CloudflareChallengeException;
import 'press_scale.dart';

/// 出错时贴在顶部的一条提示：左边说原因，右边给「重试」和「关闭」。
///
/// 不复用 [showAppToast]：那条是看一眼就走的（1.7 秒后自动消失、[IgnorePointer]
/// 不接点击），这里必须留住按钮让人点。也不用 `SnackBar`：它贴窗口最底、会跟右下角
/// 的浮动刷新按钮抢位置，而且要点掉才走。挂在 root overlay 上是因为出错的地方
/// 往往在滚动视图内部，那里没有合适的布局位置给一条横幅。
///
/// [onRetry] 为空时不画重试按钮（比如「分类加载失败」这类没法原地重试的）。
/// 返回一个可以手动收起的句柄，调用方想在页面切走时撤掉就调它。
VoidCallback showAppErrorBar(BuildContext context, Object error, {VoidCallback? onRetry}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return () {};
  late final OverlayEntry entry;
  void remove() {
    if (entry.mounted) entry.remove();
  }

  entry = OverlayEntry(
    builder: (_) => _AppErrorBarHost(error: error, onRetry: onRetry, onDone: remove),
  );
  overlay.insert(entry);
  return remove;
}

/// 把异常翻成一句「该怎么办」。认不出来的返回 null —— 与其猜错，不如只显示原始信息。
///
/// 分档跟 `site_diagnostics_page` 的 `_suggestion` 保持一致（403 判 Cloudflare、
/// 5xx 判站点、DNS/连接判网络），免得同一个错误在诊断页和这里给出两种说法。
String? appErrorSuggestion(AppLocalizations l10n, Object error) {
  if (error is CloudflareChallengeException) return l10n.suggestionCloudflare;
  if (error is DioException) {
    final code = error.response?.statusCode;
    if (code == 403) return l10n.suggestionCloudflare;
    if (code != null && code >= 500) return l10n.suggestionSite;
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        l10n.suggestionTimeout,
      _ => null,
    };
  }
  if (error is SocketException || error is HttpException) return l10n.suggestionTimeout;
  return null;
}

/// 按错误种类挑图标：网络类的用断网图标，其余用通用错误图标。
IconData appErrorIcon(Object error) {
  if (error is CloudflareChallengeException) return Symbols.gpp_maybe_rounded;
  if (error is SocketException || error is HttpException) return Symbols.wifi_off_rounded;
  if (error is DioException) {
    return switch (error.type) {
      DioExceptionType.connectionTimeout ||
      DioExceptionType.sendTimeout ||
      DioExceptionType.receiveTimeout ||
      DioExceptionType.connectionError =>
        Symbols.wifi_off_rounded,
      _ => Symbols.error_outline_rounded,
    };
  }
  return Symbols.error_outline_rounded;
}

/// 整页错误态：内容区加载失败、且没有旧数据可显示时占满整块区域。
///
/// 三处调用点（首页 / 搜索 / 漫画）原先各写了一份几乎一样的实现，其中两份靠
/// `'$error'.contains('Cloudflare')` 判断要不要给「完成验证」的入口 —— 文案一改
/// 就会静默失效，这里改用类型判断。
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.error, this.onRetry, this.onCloudflareVerified});

  final Object error;
  final VoidCallback? onRetry;
  final Future<void> Function()? onCloudflareVerified;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final suggestion = appErrorSuggestion(l10n, error);
    final needsChallenge = error is CloudflareChallengeException && onCloudflareVerified != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(appErrorIcon(error), size: 56, color: colorScheme.error),
            const SizedBox(height: 16),
            Text('$error', textAlign: TextAlign.center, style: theme.textTheme.bodyMedium),
            if (suggestion case final text?) ...[
              const SizedBox(height: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Text(
                  '${l10n.suggestionLabel}：$text',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ),
            ],
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                if (onRetry case final retry?) PressScale(child: FilledButton(onPressed: retry, child: Text(l10n.retry))),
                if (needsChallenge)
                  PressScale(child: TextButton(onPressed: onCloudflareVerified, child: Text(l10n.completeCloudflareVerification))),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// 顶部那条提示的本体：滑入 + 淡入，6 秒后自己收起（比 toast 久，因为要留时间点重试）。
class _AppErrorBarHost extends StatefulWidget {
  const _AppErrorBarHost({required this.error, required this.onRetry, required this.onDone});

  final Object error;
  final VoidCallback? onRetry;
  final VoidCallback onDone;

  @override
  State<_AppErrorBarHost> createState() => _AppErrorBarHostState();
}

class _AppErrorBarHostState extends State<_AppErrorBarHost> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this, duration: AppMotion.standard);
  Timer? _timer;
  var _closing = false;

  @override
  void initState() {
    super.initState();
    _controller.forward();
    // 有无按钮给的时间不一样：能重试的多留一会儿，纯告知的早点让路。
    _timer = Timer(Duration(seconds: widget.onRetry == null ? 4 : 8), _dismiss);
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_closing) return;
    _closing = true;
    _timer?.cancel();
    await _controller.reverse();
    if (!mounted) return;
    widget.onDone();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final suggestion = appErrorSuggestion(l10n, widget.error);
    return Positioned(
      top: 12,
      left: 0,
      right: 0,
      child: SafeArea(
        child: SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, -0.6), end: Offset.zero).animate(
            CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
          ),
          child: FadeTransition(
            opacity: _controller,
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 560),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Material(
                    color: colorScheme.errorContainer,
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    clipBehavior: Clip.antiAlias,
                    elevation: 3,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(appErrorIcon(widget.error), size: 20, color: colorScheme.onErrorContainer),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  '${widget.error}',
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onErrorContainer),
                                ),
                                if (suggestion case final text?)
                                  Text(
                                    text,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(color: colorScheme.onErrorContainer.withValues(alpha: 0.78)),
                                  ),
                              ],
                            ),
                          ),
                          if (widget.onRetry case final retry?)
                            PressScale(
                              child: TextButton(
                                onPressed: () {
                                  _dismiss();
                                  retry();
                                },
                                child: Text(l10n.retry, style: TextStyle(color: colorScheme.onErrorContainer)),
                              ),
                            ),
                          PressScale(
                            child: IconButton(
                              tooltip: l10n.close,
                              visualDensity: VisualDensity.compact,
                              onPressed: _dismiss,
                              icon: Icon(Symbols.close_rounded, size: 18, color: colorScheme.onErrorContainer),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
