import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/press_scale.dart';

enum TagEditorMode { add, remove }

/// 标签编辑页（设计稿 `p_tageditor`，1280×800）。
///
/// 页面本体仍然是 WebView 里站点自己那套「添加/删除标签」弹窗 —— 增删逻辑、
/// 持久化、Cookie 同步、路由一概不动（见 [_prepare] / [_syncCookies]）。
/// 这里只把**宿主外壳**按设计稿重做：页面底换成 `pageBackground`，顶部换成
/// 设计稿那条 64 高的浮白页头（返回圆钮 + 标题 19 Bold + 副标题 + 右侧「保存」），
/// 中间白卡承托 WebView，底部留出页底呼吸。
///
/// 强调色用 [AppDesignTokens.accentDeep]：设计稿的「保存」按钮与选中态都是 #B3265A。
class TagEditorPage extends ConsumerStatefulWidget {
  const TagEditorPage({super.key, required this.videoId, required this.mode});

  final String videoId;
  final TagEditorMode mode;

  @override
  ConsumerState<TagEditorPage> createState() => _TagEditorPageState();
}

class _TagEditorPageState extends ConsumerState<TagEditorPage> {
  String? _url;
  var _opened = false;
  var _allowPop = false;
  var _closing = false;

  Future<void> _prepare(InAppWebViewController controller) async {
    if (_opened) return;
    final selector = widget.mode == TagEditorMode.add ? '#add-tags-modal' : '#remove-tags-modal';
    final result = await controller.evaluateJavascript(source: '''
      (() => {
        const modal = document.querySelector('$selector');
        if (!modal) return false;
        const trigger = document.querySelector('[data-target="$selector"], [data-bs-target="$selector"], [href="$selector"]');
        if (trigger) trigger.click();
        if (!modal.classList.contains('show')) {
          modal.style.display = 'block';
          modal.classList.add('show');
          modal.setAttribute('aria-modal', 'true');
          modal.removeAttribute('aria-hidden');
        }
        document.querySelectorAll('body > *').forEach((element) => {
          if (element !== modal && !element.contains(modal) && !element.classList.contains('modal-backdrop')) element.style.display = 'none';
        });
        document.body.style.background = 'transparent';
        document.body.style.overflow = 'auto';
        modal.style.position = 'relative';
        modal.style.inset = 'auto';
        modal.style.padding = '0';
        modal.querySelector('.modal-dialog')?.style.setProperty('margin', '0 auto');
        return true;
      })()
    ''');
    if (result == true || result == 'true') _opened = true;
  }

  Future<void> _syncCookies() async {
    final url = _url;
    if (url == null) return;
    final cookies = await ref.read(han1meHttpClientProvider).webViewCookies(url);
    if (cookies.isEmpty) return;
    try {
      await ref.read(accountProvider.notifier).saveCookie(cookies);
    } catch (_) {}
  }

  /// 与 [PopScope] 里原来那段完全一致的退出流程：先同步 Cookie，再 pop。
  /// 区别只是现在它可以由页头返回钮和右侧「保存」钮触发（把「保存」理解为
  /// 「带着改动回去」—— 提交仍然由页面内部的 web 表单完成，这里只负责退出）。
  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _syncCookies();
    if (!mounted) return;
    setState(() => _allowPop = true);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    final title = widget.mode == TagEditorMode.add ? l10n.addTags : l10n.removeTags;
    if (settings == null) return _loadingScaffold(context, title);
    _url ??= '${settings.resolvedBaseUrl}/watch?v=${Uri.encodeQueryComponent(widget.videoId)}';
    return PopScope(
      canPop: _allowPop,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _closing) return;
        _closing = true;
        await _syncCookies();
        // 这里用的是 build 的 context（它遮蔽了 State.context），所以要按 BuildContext 的规矩守卫。
        if (!context.mounted) return;
        setState(() => _allowPop = true);
        Navigator.pop(context);
      },
      child: Scaffold(
        backgroundColor: AppDesignTokens.pageBackground,
        body: Column(
          children: [
            _header(context, title),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: AppDesignTokens.surface,
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    border: Border.all(color: AppDesignTokens.stroke),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    child: InAppWebView(
                      initialUrlRequest: URLRequest(url: WebUri(_url!)),
                      initialSettings: InAppWebViewSettings(javaScriptEnabled: true, domStorageEnabled: true, thirdPartyCookiesEnabled: true, userAgent: Han1meApi.userAgent),
                      onLoadStart: (controller, url) {
                        _opened = false;
                        _url = url?.toString() ?? _url;
                      },
                      onLoadStop: (controller, url) async {
                        _url = url?.toString() ?? _url;
                        await _prepare(controller);
                      },
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 设计稿页头：返回圆钮 / 「编辑标签」19 Bold + 副描述 / 右侧 accentDeep「保存」。
  Widget _header(BuildContext context, String title) {
    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
        child: Row(
          children: [
            PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                onTap: _close,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(color: AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.sm)),
                  child: const Icon(Icons.chevron_left_rounded, size: 20, color: AppDesignTokens.inkSubtle),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppDesignTokens.ink),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                widget.mode == TagEditorMode.add ? '为作品添加本地标签' : '为作品移除已有标签',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 12.5, color: AppDesignTokens.inkMuted),
              ),
            ),
            const SizedBox(width: 12),
            PressScale(
              child: Material(
                color: AppDesignTokens.accentDeep,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: _close,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 22, vertical: 9),
                    child: Text('保存', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 设置还没加载出来时的等待页：同样套设计稿的页头与页底，避免先闪一帧系统 AppBar。
  Widget _loadingScaffold(BuildContext context, String title) {
    return Scaffold(
      backgroundColor: AppDesignTokens.pageBackground,
      body: Column(
        children: [
          _header(context, title),
          const Expanded(
            child: Center(child: CircularProgressIndicator(color: AppDesignTokens.accentDeep)),
          ),
        ],
      ),
    );
  }
}
