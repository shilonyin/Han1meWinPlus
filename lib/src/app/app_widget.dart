import 'dart:async';

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';

import '../../l10n/app_localizations.dart';
import '../core/app_scroll_behavior.dart';
import '../core/m3e_theme_bridge.dart';
import '../core/platform_service.dart';
import '../core/settings.dart';
import '../features/auth/app_lock_gate.dart';
import '../features/navigation/exit_coordinator.dart';
import '../features/settings/settings_controller.dart';
import '../features/window/app_title_bar.dart';
import 'app_backdrop.dart';
import 'app_router.dart';
import 'app_theme.dart';
import 'startup_effects.dart';

class Han1meApp extends ConsumerStatefulWidget {
  const Han1meApp({super.key, this.initialLink});

  /// scheme 唤起带来的链接，交给启动流程在首页栈就绪后跳转。
  final Uri? initialLink;

  @override
  ConsumerState<Han1meApp> createState() => _Han1meAppState();
}

class _Han1meAppState extends ConsumerState<Han1meApp> {
  late final AppExitCoordinator _exitCoordinator;
  late final AppRouter _appRouter;

  /// 系统是否关掉了「透明效果」。默认 false：读之前先按最完整的玻璃建起来，
  /// 读到了再降档，避免启动瞬间闪一次实心。
  bool _reduceTransparency = false;

  @override
  void initState() {
    super.initState();
    _exitCoordinator = AppExitCoordinator();
    _appRouter = AppRouter(_exitCoordinator);
    unawaited(_loadTransparencyPreference());
  }

  /// 只在启动读一次：这个开关和窗口材质、系统标题栏一样属于系统层设置，
  /// 改了要重启应用才生效，没必要挂监听。
  Future<void> _loadTransparencyPreference() async {
    if (!await PlatformService.windowsTransparencyDisabled() || !mounted) return;
    setState(() => _reduceTransparency = true);
  }

  @override
  void dispose() {
    _appRouter.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).value ?? AppSettings();
    return DynamicColorBuilder(
      builder: (lightDynamic, darkDynamic) => MaterialApp.router(
        onGenerateTitle: (context) => AppLocalizations.of(context)!.appTitle,
        debugShowCheckedModeBanner: false,
        routerConfig: _appRouter.router,
        // 两层玻璃基础设施，服务两套实现，互不干扰：
        //
        // 1. `GlassHost`（g1455）：它把屏下内容录成**一张**共享的降采样图，
        //    所有 g1455 玻璃各取自己那一格，且只在内容变化时重录。用它必须
        //    在 navigator 之上，否则对话框/弹层里的玻璃找不到它（会 debug 报错）。
        // 2. `BackdropGroup`（引擎自带）：服务我们自己那些用原生
        //    `BackdropFilter` 的面板 —— 让它们共享一次背景采样。
        //
        // 迁完 g1455 之后 `BackdropGroup` 可以撤掉。
        builder: (context, child) => GlassHost(
          // 内容是可滚动列表与封面图 → 声明为富背景，标签按最坏情况挑色。
          richBackdrop: true,
          minLabelContrast: kTextContrastAA,
          // 系统关掉了「透明效果」就整屏落到 opaque 那一档：g1455 的 policy 会为此
          // 返回 GlassTier.opaque 并带上 reduceTransparency 这个理由 —— 它整档都不读
          // 背景，所以这时连那一次全屏捕获也省掉了。
          tier: GlassTierPolicy(reduceTransparency: _reduceTransparency).choose(),
          // 玻璃背后的平均底色：深浅主题差别很大，按当前亮度给。
          backdrop: Theme.of(context).brightness == Brightness.dark
              ? const Color(0xFF131118)
              : const Color(0xFFF9F8FC),
          child: BackdropGroup(
            child: M3EThemeBridge(
              child: AppBackdrop(
                // AMOLED 要的是纯黑省电，铺渐变就白搭了；深色下也只在非 AMOLED 时启用。
                enabled: !(settings.amoledMode && Theme.of(context).brightness == Brightness.dark),
                // 开着窗口材质时把画布让出一部分，让 Mica / 亚克力的系统半透明透上来；
                // 纯色模式则铺满，否则背景又变回一片没有色调的灰白。
                opacity: settings.windowBackdrop == WindowBackdrop.none ? 1 : .78,
                child: AppWindowFrame(
                  child: AppStartupEffects(
                    navigatorKey: _appRouter.navigatorKey,
                    exitCoordinator: _exitCoordinator,
                    initialLink: widget.initialLink,
                    child: MediaQuery(
                      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(settings.textScale)),
                      child: AppLockGate(child: child ?? const SizedBox.shrink()),
                    ),
                  ),
                ),
              ),
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
        // 主题切换必须瞬时生效：整套配色在深/浅之间插值时，页面、卡片、文字会一起
        // 变成发灰的中间色（看起来像蒙了一层），用户点侧栏的主题按钮时就会看到
        // 「底色切换异常」。
        // 注意：`themeAnimationDuration` 的**默认值是 200ms**（kThemeAnimationDuration），
        // 所以「不写这个参数」并不等于关掉动画 —— 必须显式给 Duration.zero。
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
