import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../app/app_router.dart' show searchRouteBuilder;
import '../../app/app_theme.dart';
import '../../core/app_scroll_behavior.dart';
import '../../core/m3e_theme_bridge.dart';
import '../../core/route_observer.dart';
import '../../core/settings.dart';
import '../../core/window_chrome.dart';
import '../../data/local/cached_video_lookup.dart';
import '../../domain/models/video.dart';
import '../cache/cache_page.dart';
import '../settings/cloudflare_page.dart';
import '../settings/settings_controller.dart';
import '../window/app_title_bar.dart';
import '../window/play_window_title_bar.dart';
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
          builder: (context, state) => PlayWindowVideo(
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
            // 播放窗口用自己那条标题栏（回到主界面 / 上下集 / 居中标题 / 置顶 /
            // 画中画 / 窗口按钮）。主窗口那条只放 logo 与窗口按钮，在这里不够用。
            titleBar: PlayWindowTitleBar(onHome: revealMainWindow),
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

/// 播放窗口查缓存用的实现；测试会替换它以避免真的读磁盘。
///
/// 默认就是 [loadCachedVideoDetail]（纯只读，见 cached_video_lookup.dart）。
@visibleForTesting
Future<VideoDetail?> Function(String videoCode) cachedVideoLookup =
    loadCachedVideoDetail;

/// 命中/未命中后真正要建的播放页；测试替换它以便只观察 PlayWindowVideo 的状态机。
///
/// 默认就是 [VideoPage]。测试不去渲染真实的 VideoPage，是因为它会拉起一串网络
/// provider，在测试拆解时留下「provider 已被销毁」的噪音，反而看不清这里的时序。
@visibleForTesting
Widget Function({
  required String id,
  required VideoDetail? localVideo,
  VoidCallback? onBack,
  VoidCallback? onHome,
})
playWindowPageBuilder = _defaultPlayWindowPage;

Widget _defaultPlayWindowPage({
  required String id,
  required VideoDetail? localVideo,
  VoidCallback? onBack,
  VoidCallback? onHome,
}) => VideoPage(
  id: id,
  localVideo: localVideo,
  onBack: onBack,
  onHome: onHome,
  // 让播放页把标题 / 上下集登记给窗口顶部栏，并隐去自带的播放器顶部条。
  inPlayWindow: true,
);

/// 播放窗口里那条 `/video/:id` 路由的落地：先查一次本地缓存，再决定播哪个源。
///
/// 为什么要有这一层：缓存页的「播放」以前是在主窗口内 push `VideoPage`（见
/// cache_format.dart 的 openCachedVideo），于是「从缓存播」和「从列表播」是两种
/// 完全不同的行为——前者不开独立窗口。现在缓存页也走 launchPlayWindow，但
/// 跨进程传不了 `VideoDetail` 对象（本地路径就在它里面），所以由播放窗口进程
/// 自己按 id 读一次缓存（[cachedVideoLookup]，纯只读、不起下载）。
///
/// 关键点：查询结束前**不创建任何 `VideoPage`**。如果先按网络源建一个、查完再换成
/// 缓存源，播放器就会被建两次——那正是这轮一直在修的「加载出来又重来一遍」。
/// 所以这里先显示黑色加载态，等结果定了再一次性建页面。
@visibleForTesting
class PlayWindowVideo extends StatefulWidget {
  const PlayWindowVideo({
    required this.id,
    this.onBack,
    this.onHome,
    super.key,
  });

  final String id;
  final VoidCallback? onBack;
  final VoidCallback? onHome;

  @override
  State<PlayWindowVideo> createState() => _PlayWindowVideoState();
}

class _PlayWindowVideoState extends State<PlayWindowVideo> {
  /// 查询完之前保持 null；`_resolved` 为真后它才是最终值（可能是 null = 无缓存）。
  VideoDetail? _cached;
  var _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    VideoDetail? cached;
    try {
      cached = await cachedVideoLookup(widget.id);
    } catch (_) {
      // 读缓存出的任何问题都回退网络播放，绝不能因此打不开视频。
      cached = null;
    }
    if (!mounted) return;
    setState(() {
      _cached = cached;
      _resolved = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_resolved) {
      // 读一个本地 JSON 而已，通常几毫秒；这里只要不闪一下网络播放页就行。
      return const ColoredBox(
        color: Color(0xFF000000),
        child: Center(child: M3EContainedLoadingIndicator()),
      );
    }
    return playWindowPageBuilder(
      id: widget.id,
      localVideo: _cached,
      onBack: widget.onBack,
      onHome: widget.onHome,
    );
  }
}
