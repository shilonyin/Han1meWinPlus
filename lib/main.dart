import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';

import 'src/app.dart';
import 'src/core/app_notifications.dart';
import 'src/core/deep_link.dart';
import 'src/core/media_player_initializer.dart';
import 'src/core/playback_speed_policy.dart';
import 'src/core/runtime_visual_guard.dart';
import 'src/core/settings.dart';
import 'src/core/shader_service.dart';
import 'src/core/window_chrome.dart';
import 'src/data/local/json_store.dart';
import 'src/data/local/update_installer.dart';
import 'src/features/glass_demo/glass_demo_app.dart';
import 'src/features/settings/settings_controller.dart';
import 'src/features/video/play_window.dart';
import 'src/features/video/play_window_app.dart';

Future<void> main(List<String> args) async {
  final startupWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // 独立播放窗口（多进程多窗口）：`--play-window --video=<id>` 启动的进程只渲染
  // 播放页，不进主应用的启动流程（托盘 / 热键 / 更新检查都不参与）。
  // 注意这不是 desktop_multi_window 的多引擎方案——那套与手写 runner 不兼容
  //（副窗口一创建主窗口引擎就假死，见 windows/runner/main.cpp 的 NOTE）；
  // 这里每个播放窗口是独立进程，各有各的引擎与消息循环，互不影响。
  final playWindow = PlayWindowArgs.fromArguments(args);
  if (playWindow != null) {
    await _runPlayWindow(playWindow);
    return;
  }
  // 临时验证入口：`--glass-demo` 只跑 g1455 的独立验证页，主应用一行都不走。
  // 放在这里是因为 `GlassHost.precache()` 必须在 runApp 之前 await —— 见
  // `glass_demo_app.dart` 里的说明。验证完可以整块删掉。
  if (args.contains('--glass-demo')) {
    await GlassHost.precache();
    runApp(const GlassDemoApp());
    return;
  }
  // `han1me://` scheme 唤起时系统把链接放进命令行参数（runner 已转交 Dart）。
  final initialLink = DeepLink.fromArguments(args);
  // 列表页图片数量多（首页 + 搜索 + 库 + 预告），默认的 100MB / 1000 张容易被挤掉，
  // 被淘汰的图再滚回来就要重新解码甚至重新下载。桌面端内存宽裕，放宽一倍以上。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 300 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  final loadedSettings = await SettingsStore(JsonStore()).load();
  // Toast 通知要在 runApp 之前初始化（Windows 侧要建开始菜单快捷方式）。
  AppNotifications.enabled = loadedSettings.notificationsEnabled;
  await AppNotifications.ensureInitialized();
  // The runner shows the window before the engine is up, so the title bar style
  // has to be applied from here. Doing it before runApp keeps the change on the
  // splash screen instead of on the first painted frame.
  debugPrint('[startup] system title bar: ${loadedSettings.useSystemTitleBar}');
  await WindowChrome.setUseSystemTitleBar(loadedSettings.useSystemTitleBar);
  debugPrint('[startup] engine+settings: ${startupWatch.elapsedMilliseconds}ms');
  await PlaybackSpeedPolicy.initialize();
  final settings = PlaybackSpeedPolicy.isHarmonyOs && loadedSettings.playerEngine != PlayerEngine.libMpv
      ? loadedSettings.copyWith(playerEngine: PlayerEngine.libMpv)
      : loadedSettings;
  if (!identical(settings, loadedSettings)) await SettingsStore(JsonStore()).save(settings);
  // mpv 的 libmpv-2.dll 会在 MediaKit.ensureInitialized() 里被同步 LoadLibrary 加载，
  // 冷启动（磁盘读取 + 杀软扫描）可能耗数百毫秒。首屏 ExplorePage 用不到播放器，
  // 所以把播放器初始化整体挪到首帧之后再执行，缩短启动图停留时间。
  // 真正打开视频时才创建 Player()，那时 DLL 早已加载完毕，不存在竞态。
  // 运行时视觉守卫：订阅全局帧回调，持续掉帧时把玻璃折射永久降到低成本路径。
  // 在主窗口的启动流程里装（独立播放窗口不装）—— 玻璃面板只出现在主窗口，
  // 播放窗口那套 chrome 不参与本预算。
  RuntimeVisualGuard.instance.install();
  WidgetsBinding.instance.addPostFrameCallback((_) {
    debugPrint('[startup] first-frame done: ${startupWatch.elapsedMilliseconds}ms');
    MediaPlayerInitializer.bootstrap(settings);
  });
  runApp(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => SettingsController(settings))],
      child: Han1meApp(initialLink: initialLink),
    ),
  );
  unawaited(_postLaunch());
}

Future<void> _postLaunch() async {
  try {
    await Future.wait([
      ShaderService.copyToStorage(),
      UpdateInstaller(Dio()).removeStaleUpdate(),
    ]);
  } catch (_) {}
}

/// 独立播放窗口的启动流程：只加载设置（主题 / 播放器参数跟主窗口共用同一份
/// setting.json）、应用标题栏偏好、首帧后初始化播放内核，然后跑精简的
/// [PlayWindowApp]。通知、深链、更新清理这些主窗口专属的启动步骤全部跳过。
Future<void> _runPlayWindow(PlayWindowArgs args) async {
  final settings = await SettingsStore(JsonStore()).load();
  await WindowChrome.setUseSystemTitleBar(settings.useSystemTitleBar);
  WidgetsBinding.instance.addPostFrameCallback((_) => MediaPlayerInitializer.bootstrap(settings));
  runApp(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => SettingsController(settings))],
      child: PlayWindowApp(videoId: args.videoId),
    ),
  );
}
