import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:collection/collection.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:window_manager/window_manager.dart';

import '../../l10n/app_localizations.dart';
import '../core/app_notifications.dart';
import '../core/cast_receiver.dart';
import '../core/deep_link.dart';
import '../core/global_hotkeys.dart';
import '../core/platform_service.dart';
import '../core/settings.dart';
import '../core/system_tray.dart';
import '../core/video_player_shutdown.dart';
import '../core/window_backdrop.dart';
import '../data/local/update_installer.dart';
import '../data/remote/update_checker.dart';
import '../features/navigation/exit_coordinator.dart';
import '../features/settings/settings_controller.dart';

class AppStartupEffects extends ConsumerStatefulWidget {
  const AppStartupEffects({
    super.key,
    required this.navigatorKey,
    required this.exitCoordinator,
    required this.child,
    this.initialLink,
  });

  final GlobalKey<NavigatorState> navigatorKey;
  final AppExitCoordinator exitCoordinator;
  final Widget child;

  /// 由 `han1me://` scheme 唤起时带来的链接（命令行参数解析得到），null 表示正常启动。
  final Uri? initialLink;

  @override
  ConsumerState<AppStartupEffects> createState() => _AppStartupEffectsState();
}

class _AppStartupEffectsState extends ConsumerState<AppStartupEffects> {
  var _checkedForUpdate = false;
  var _appliedPrivacySettings = false;
  late final AppLifecycleListener _lifecycleListener;

  @override
  void initState() {
    super.initState();
    _lifecycleListener = AppLifecycleListener(
      onExitRequested: _handleExitRequest,
      onStateChange: (state) {
        if (state == AppLifecycleState.paused ||
            state == AppLifecycleState.hidden) {
          unawaited(VideoPlayerShutdown.pauseAllExceptPip());
        }
      },
    );
    ref.listenManual(settingsProvider, (previous, next) {
      final settings = next.valueOrNull;
      if (settings == null) return;
      if (settings.autoUpdate && !_checkedForUpdate) {
        _checkedForUpdate = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _checkForUpdate(settings.useUpdateMirror),
        );
      }
      if (!_appliedPrivacySettings) {
        _appliedPrivacySettings = true;
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          await PlatformService.setHideFromRecents(settings.hideFromRecents);
          await PlatformService.setEmergencyExit(settings.emergencyExitEnabled);
        });
      }
      // 托盘：开关或界面语言变化时重建（菜单文案要跟着语言走）。
      final previousSettings = previous?.valueOrNull;
      if (previousSettings == null ||
          previousSettings.minimizeToTray != settings.minimizeToTray ||
          previousSettings.language != settings.language) {
        _applyTraySettings(settings);
      }
      // 通知开关与文案（文案取自当前语言，语言变了要跟着换）。
      AppNotifications.enabled = settings.notificationsEnabled;
      final l10n = AppLocalizations.of(
        widget.navigatorKey.currentContext ?? context,
      );
      if (l10n != null) {
        AppNotifications.texts = NotificationTexts(
          downloadComplete: l10n.downloadComplete,
          updateAvailable: l10n.updateAvailable,
        );
      }
      // 全局热键：开关或键位表变化时重注册（改键即时生效）。
      if (previousSettings == null ||
          previousSettings.globalHotkeysEnabled !=
              settings.globalHotkeysEnabled ||
          !const DeepCollectionEquality().equals(
            previousSettings.hotkeyBindings,
            settings.hotkeyBindings,
          )) {
        unawaited(
          GlobalHotkeys.setEnabled(
            settings.globalHotkeysEnabled,
            settings.hotkeyBindings,
          ),
        );
      }
      if (previousSettings == null ||
          previousSettings.dlnaReceiverEnabled !=
              settings.dlnaReceiverEnabled) {
        unawaited(
          CastReceiver.instance.setEnabled(settings.dlnaReceiverEnabled),
        );
      }
      // 窗口材质：开关或明暗主题变化时重新应用（Mica / Acrylic 要跟着深浅色走）。
      if (previousSettings == null ||
          previousSettings.windowBackdrop != settings.windowBackdrop ||
          previousSettings.themeMode != settings.themeMode ||
          previousSettings.amoledMode != settings.amoledMode) {
        _applyWindowBackdrop(settings);
      }
    }, fireImmediately: true);
    CastReceiver.instance.incoming.addListener(_onCastIncoming);
    final link = widget.initialLink;
    if (link != null) {
      // 等首页那一栈建好再跳，否则 navigator 还没挂载、push 会被丢掉。
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _openInitialLink(link),
      );
    }
  }

  /// 手机投屏推片：接收端只是把消息转出来，开页面交给路由。
  /// 投屏页已经开着时不再 push（同一页里自己换源）。
  void _onCastIncoming() {
    final item = CastReceiver.instance.incoming.value;
    if (item == null || CastReceiver.instance.pageOpen) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    context.push('/cast', extra: item);
  }

  Future<void> _openInitialLink(Uri link) async {
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (!mounted) return;
    DeepLink.open(link, widget.navigatorKey);
  }

  @override
  void dispose() {
    CastReceiver.instance.incoming.removeListener(_onCastIncoming);
    _lifecycleListener.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;

  /// 托盘菜单文案取自当前本地化，而 [AppLocalizations] 需要 context；
  /// 首帧之前 `navigatorKey.currentContext` 还是空的，所以推到首帧之后再应用。
  void _applyTraySettings(AppSettings settings) {
    if (!SystemTray.isSupported) return;
    final context = widget.navigatorKey.currentContext;
    if (context == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _applyTraySettings(settings);
      });
      return;
    }
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return;
    unawaited(
      SystemTray.setEnabled(
        settings.minimizeToTray,
        tooltip: l10n.appTitle,
        showLabel: l10n.trayShowWindow,
        exitLabel: l10n.trayExit,
      ),
    );
  }

  /// 读取窗口聚焦状态；读不到（非桌面端 / 插件异常）就当作在前台，走界面弹窗。
  Future<bool> _isWindowFocused() async {
    try {
      await windowManager.ensureInitialized();
      return await windowManager.isFocused();
    } catch (_) {
      return true;
    }
  }

  /// 材质的深浅由**实际生效的**主题决定（`system` 模式要跟系统走），
  /// 所以从 context 里读而非直接用 `themeMode`。
  void _applyWindowBackdrop(AppSettings settings) {
    if (!WindowBackdropEffect.isSupported) return;
    final context = widget.navigatorKey.currentContext;
    final dark = context == null
        ? false
        : Theme.of(context).brightness == Brightness.dark;
    unawaited(WindowBackdropEffect.apply(settings.windowBackdrop, dark: dark));
  }

  Future<AppExitResponse> _handleExitRequest() async {
    if (widget.exitCoordinator.consumeBranchBackHandled())
      return AppExitResponse.cancel;
    final context = widget.navigatorKey.currentContext;
    if (context == null) return AppExitResponse.cancel;
    if (!await widget.exitCoordinator.confirmExit(context))
      return AppExitResponse.cancel;
    if (PlatformService.isDesktop) return AppExitResponse.exit;
    await PlatformService.minimizeApp();
    return AppExitResponse.cancel;
  }

  Future<void> _checkForUpdate(bool useUpdateMirror) async {
    final update = await ref.read(updateCheckerProvider).check();
    if (!mounted || update == null) return;
    // 窗口没在前台（比如收在托盘里）时界面弹窗没人看，改用系统通知。
    final focused = await _isWindowFocused();
    if (!focused) {
      await AppNotifications.updateAvailable(update.tagName);
      return;
    }
    final context = widget.navigatorKey.currentContext;
    if (context == null) return;
    final l10n = AppLocalizations.of(context)!;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.newVersionAvailable(update.tagName)),
        content: Text(
          update.downloadUrl.isEmpty
              ? l10n.noInstallableApk
              : update.body.isEmpty
              ? l10n.newVersionReleased
              : update.body,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(l10n.later),
          ),
          FilledButton(
            onPressed: update.downloadUrl.isEmpty
                ? null
                : () async {
                    Navigator.pop(dialogContext);
                    await _installUpdate(
                      context,
                      update.downloadUrl,
                      useUpdateMirror,
                    );
                  },
            child: Text(l10n.updateNow),
          ),
        ],
      ),
    );
  }

  Future<void> _installUpdate(
    BuildContext context,
    String url,
    bool useMirror,
  ) async {
    if (url.isEmpty) return;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _StartupUpdateDownload(url: url, useMirror: useMirror),
    );
  }
}

class _StartupUpdateDownload extends StatefulWidget {
  const _StartupUpdateDownload({required this.url, required this.useMirror});

  final String url;
  final bool useMirror;

  @override
  State<_StartupUpdateDownload> createState() => _StartupUpdateDownloadState();
}

class _StartupUpdateDownloadState extends State<_StartupUpdateDownload> {
  double? _progress;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      await UpdateInstaller(Dio()).downloadAndInstall(widget.url, (value) {
        if (mounted) setState(() => _progress = value);
      }, useMirror: widget.useMirror);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(AppLocalizations.of(context)!.downloadingUpdate),
    content: _error == null
        ? Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              M3ELinearProgressIndicator(value: _progress),
              const SizedBox(height: 12),
              Text(
                _progress == null
                    ? AppLocalizations.of(context)!.connecting
                    : '${(_progress! * 100).toStringAsFixed(0)}%',
              ),
            ],
          )
        : Text(AppLocalizations.of(context)!.updateFailed(_error.toString())),
    actions: _error == null
        ? null
        : [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(AppLocalizations.of(context)!.close),
            ),
          ],
  );
}
