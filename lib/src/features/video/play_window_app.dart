import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_router.dart' show searchRouteBuilder;
import '../../app/app_theme.dart';
import '../../core/app_scroll_behavior.dart';
import '../../core/m3e_theme_bridge.dart';
import '../../core/route_observer.dart';
import '../../core/settings.dart';
import '../../core/window_chrome.dart';
import '../cache/cache_page.dart';
import '../settings/cloudflare_page.dart';
import '../settings/settings_controller.dart';
import '../window/app_title_bar.dart';
import 'play_window.dart';
import 'tag_editor_page.dart';
import 'video_page.dart';

/// 独立播放窗口（多进程多窗口）的宿主 App，是 [Han1meApp] 的精简版。
///
/// 主题、本地化、应用内标题栏与主窗口共用同一套（改主题两边的播放页自动一致），
/// 但只挂播放页可达的路由，也不引入 AppStartupEffects——托盘、全局热键、更新
/// 检查、DLNA 这些主窗口专属的启动效果在一个播放进程里只会添乱（比如抢注册
/// 全局热键、弹出第二个托盘图标）。
///
/// 注意：播放窗口与主窗口是两个进程，共用同一份 setting.json / 本地仓库文件，
/// 同时写设置时后写的一方胜出；正常使用（主窗口改设置、播放窗口只读）没有冲突。
class PlayWindowApp extends ConsumerStatefulWidget {
  const PlayWindowApp({super.key, required this.videoId});

  final String videoId;

  @override
  ConsumerState<PlayWindowApp> createState() => _PlayWindowAppState();
}

class _PlayWindowAppState extends ConsumerState<PlayWindowApp> {
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      observers: [routeObserver],
      initialLocation: '/video/${widget.videoId}',
      routes: [
        // 播放页：独立窗口里「返回」就是关掉这个窗口，「回主页」则唤起主窗口
        //（无参启动时 runner 会激活已运行的主窗口，没运行就冷启动一个）。
        GoRoute(
          path: '/video/:id',
          builder: (context, state) => VideoPage(
            id: state.pathParameters['id']!,
            onBack: WindowChrome.close,
            onHome: revealMainWindow,
          ),
        ),
        // 换集 / 相关推荐在窗口内导航，不开新窗口（b 站行为一致）。
        GoRoute(path: '/video/:id/tags/:mode', builder: (context, state) => TagEditorPage(videoId: state.pathParameters['id']!, mode: state.pathParameters['mode'] == 'remove' ? TagEditorMode.remove : TagEditorMode.add)),
        // 视频加载遇到 Cloudflare 质询时的过验页。
        GoRoute(path: '/cloudflare', builder: (context, state) => CloudflarePage(initialUrl: state.extra as String?)),
        // 播放器菜单里的「下载管理」。
        GoRoute(path: '/downloads', builder: (context, state) => const CachePage()),
        // 简介里的作者 / 标签会 push 搜索页。
        GoRoute(path: '/search', builder: searchRouteBuilder),
      ],
    );
  }

  @override
  void dispose() {
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings();
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        debugShowCheckedModeBanner: false,
        routerConfig: _router,
        builder: (context, child) => M3EThemeBridge(
          child: AppWindowFrame(
            child: MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.textScale)),
              child: child ?? const SizedBox.shrink(),
            ),
          ),
        ),
        scrollBehavior: const AppScrollBehavior(),
        locale: switch (settings.language) {
          AppLanguage.system => null,
          AppLanguage.simplifiedChinese => const Locale('zh'),
          AppLanguage.traditionalChinese => const Locale('zh', 'TW'),
          AppLanguage.english => const Locale('en'),
        },
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        themeMode: settings.materialThemeMode,
        // 与主窗口一致：主题切换必须瞬时生效（Han1meApp 里对默认 200ms 动画的说明）。
        themeAnimationDuration: Duration.zero,
        theme: appTheme(settings.useMonetColors ? lightDynamic : null, settings.themeColor.seedColor(settings.customThemeColor), useSystemFont: settings.useSystemFont, variant: settings.themeColor.schemeVariant, neutralSurfaces: settings.themeColor.neutralSurfaces, backdrop: settings.windowBackdrop),
        darkTheme: appTheme(
          settings.useMonetColors ? darkDynamic : null,
          settings.themeColor.seedColor(settings.customThemeColor),
          brightness: Brightness.dark,
          amoled: settings.amoledMode,
          useSystemFont: settings.useSystemFont,
          variant: settings.themeColor.schemeVariant,
          neutralSurfaces: settings.themeColor.neutralSurfaces,
          backdrop: settings.windowBackdrop,
        ),
      ),
    );
  }
}
