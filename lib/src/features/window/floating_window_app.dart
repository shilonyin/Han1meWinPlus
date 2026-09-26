import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/settings.dart';
import '../../core/window_chrome.dart';
import '../app/app_theme.dart';
import '../settings/settings_controller.dart';
import '../video/video_controller.dart';
import '../video/video_player_panel.dart';

/// 悬浮窗（副窗口）入口。
///
/// 与主窗口是两套引擎，所以自己建一份 ProviderScope 与主题；播放器也是新的实例，
/// 只按视频 id 重新拉详情播放，不与主窗口共享进度。
class FloatingWindowApp extends ConsumerStatefulWidget {
  const FloatingWindowApp({required this.videoId, super.key});

  final String videoId;

  @override
  ConsumerState<FloatingWindowApp> createState() => _FloatingWindowAppState();
}

class _FloatingWindowAppState extends ConsumerState<FloatingWindowApp> {
  static const _initialSize = Size(480, 270);

  @override
  void initState() {
    super.initState();
    _configureWindow();
  }

  /// 副窗口自己的窗口属性：无标题栏（自己画关闭按钮）、小尺寸、常驻最前。
  Future<void> _configureWindow() async {
    if (!WindowChrome.isSupported) return;
    try {
      await windowManager.ensureInitialized();
      const options = WindowOptions(size: _initialSize, minimumWindowSize: Size(320, 180), center: true, titleBarStyle: TitleBarStyle.hidden, skipTaskbar: true, windowButtonVisibility: false);
      await windowManager.waitUntilReadyToShow(options, () async {
        await windowManager.setAlwaysOnTop(true);
        await windowManager.show();
        await windowManager.focus();
      });
    } catch (error) {
      debugPrint('[floating] configure failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const AppSettings();
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      theme: appTheme(null, settings.themeColor.seedColor(settings.customThemeColor), useSystemFont: settings.useSystemFont, variant: settings.themeColor.schemeVariant, neutralSurfaces: settings.themeColor.neutralSurfaces),
      darkTheme: appTheme(null, settings.themeColor.seedColor(settings.customThemeColor), brightness: Brightness.dark, amoled: settings.amoledMode, useSystemFont: settings.useSystemFont, variant: settings.themeColor.schemeVariant, neutralSurfaces: settings.themeColor.neutralSurfaces),
      themeMode: settings.materialThemeMode,
      home: _FloatingPlayerPage(videoId: widget.videoId),
    );
  }
}

class _FloatingPlayerPage extends ConsumerWidget {
  const _FloatingPlayerPage({required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: Colors.black,
      child: ref.watch(videoDetailProvider(videoId)).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => Center(child: Text(l10n.loadFailed('$error'), style: const TextStyle(color: Colors.white))),
            data: (video) => Stack(children: [
              VideoPlayerPanel(video: video, onBack: () => _closeWindow()),
              // 无边框窗口没有关闭按钮，右上角放一个。
              Positioned(
                top: 4,
                right: 4,
                child: IconButton(color: Colors.white, tooltip: l10n.close, visualDensity: VisualDensity.compact, onPressed: _closeWindow, icon: const Icon(Icons.close, size: 18)),
              ),
            ]),
          ),
    );
  }

  /// 关掉悬浮窗：只隐藏自己这个窗口，主窗口不受影响。
  static Future<void> _closeWindow() async {
    try {
      await windowManager.close();
    } catch (_) {}
  }
}
