import 'dart:async';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'src/app.dart';
import 'src/core/app_notifications.dart';
import 'src/core/deep_link.dart';
import 'src/core/floating_window.dart';
import 'src/core/media_player_initializer.dart';
import 'src/core/playback_speed_policy.dart';
import 'src/core/settings.dart';
import 'src/core/shader_service.dart';
import 'src/core/window_chrome.dart';
import 'src/data/local/json_store.dart';
import 'src/data/local/update_installer.dart';
import 'src/features/settings/settings_controller.dart';
import 'src/features/window/floating_window_app.dart';

Future<void> main(List<String> args) async {
  final startupWatch = Stopwatch()..start();
  WidgetsFlutterBinding.ensureInitialized();
  // `han1me://` scheme 唤起时系统把链接放进命令行参数（runner 已转交 Dart）。
  final initialLink = DeepLink.fromArguments(args);
  // 列表页图片数量多（首页 + 搜索 + 库 + 预告），默认的 100MB / 1000 张容易被挤掉，
  // 被淘汰的图再滚回来就要重新解码甚至重新下载。桌面端内存宽裕，放宽一倍以上。
  PaintingBinding.instance.imageCache.maximumSizeBytes = 300 << 20;
  PaintingBinding.instance.imageCache.maximumSize = 2000;
  // 悬浮窗是独立进程内的一套新引擎，靠窗口 arguments 区分；命中就走副窗口分支，
  // 不去加载主窗口那套启动流程（更新检查、托盘等）。
  final floatingVideoId = await _floatingVideoId();
  if (floatingVideoId != null) {
    await _runFloatingWindow(floatingVideoId);
    return;
  }
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

/// 读当前窗口的 arguments，判断自己是不是被弹出来的悬浮窗。
Future<String?> _floatingVideoId() async {
  try {
    final controller = await WindowController.fromCurrentEngine();
    return FloatingWindow.videoIdFromArguments(controller.arguments);
  } catch (_) {
    // 插件不可用时（比如单窗口调试）就当作主窗口。
    return null;
  }
}

Future<void> _runFloatingWindow(String videoId) async {
  final settings = await SettingsStore(JsonStore()).load();
  MediaPlayerInitializer.bootstrap(settings);
  runApp(
    ProviderScope(
      overrides: [settingsProvider.overrideWith(() => SettingsController(settings))],
      child: FloatingWindowApp(videoId: videoId),
    ),
  );
}

Future<void> _postLaunch() async {
  try {
    await Future.wait([
      ShaderService.copyToStorage(),
      UpdateInstaller(Dio()).removeStaleUpdate(),
    ]);
  } catch (_) {}
}
