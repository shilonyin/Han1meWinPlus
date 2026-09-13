import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:liquid_glass_widgets/liquid_glass_widgets.dart';

import 'src/app.dart';
import 'src/core/media_player_initializer.dart';
import 'src/core/playback_speed_policy.dart';
import 'src/core/settings.dart';
import 'src/core/shader_service.dart';
import 'src/data/local/json_store.dart';
import 'src/data/local/update_installer.dart';
import 'src/features/settings/settings_controller.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final loadedSettings = await SettingsStore(JsonStore()).load();
  // 玻璃包的着色器预热在 Windows(Skia) 上是运行时编译，驱动着色器缓存未命中时
  // 可耗时数十秒。绝不能 await 它再 runApp：否则这段时间窗口一片空白、首帧完全
  // 出不来，看起来就像网络卡死。桌面宽度走 NavigationRail、并不渲染玻璃组件，
  // 首帧不需要它；组件自身也会按需懒加载，所以放到后台预热即可。
  unawaited(LiquidGlassWidgets.initialize().catchError((Object _) {}));
  await PlaybackSpeedPolicy.initialize();
  final settings = PlaybackSpeedPolicy.isHarmonyOs && loadedSettings.playerEngine != PlayerEngine.libMpv
      ? loadedSettings.copyWith(playerEngine: PlayerEngine.libMpv)
      : loadedSettings;
  if (!identical(settings, loadedSettings)) await SettingsStore(JsonStore()).save(settings);
  MediaPlayerInitializer.bootstrap(settings);
  runApp(
    LiquidGlassWidgets.wrap(
      child: ProviderScope(
        overrides: [settingsProvider.overrideWith(() => SettingsController(settings))],
        child: const Han1meApp(),
      ),
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
