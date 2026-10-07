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
import '../features/shared/glass/glass_tuning.dart';
import '../features/window/app_title_bar.dart';
import 'app_backdrop.dart';
import 'app_page_colors.dart';
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

  /// 系统是否开着「高对比度」。和上面同理，默认 false —— 先按最常见的情形建起来，
  /// 读到了再改，免得启动瞬间闪一次重描边。
  bool _systemHighContrast = false;

  @override
  void initState() {
    super.initState();
    _exitCoordinator = AppExitCoordinator();
    _appRouter = AppRouter(_exitCoordinator);
    unawaited(_loadTransparencyPreference());
    unawaited(_loadHighContrastPreference());
  }

  /// 只在启动读一次：这个开关和窗口材质、系统标题栏一样属于系统层设置，
  /// 改了要重启应用才生效，没必要挂监听。
  Future<void> _loadTransparencyPreference() async {
    if (!await PlatformService.windowsTransparencyDisabled() || !mounted) return;
    setState(() => _reduceTransparency = true);
  }

  /// 同理只读一次。**必须由我们读**：g1455 的 `highContrast` 传 null 表示去读
  /// `MediaQuery.highContrastOf`，而引擎只在 iOS 与 Android 34+ 上设置它，
  /// Windows 上恒为 false —— 交给它，「跟随系统」这一档就永远跟不出来。
  Future<void> _loadHighContrastPreference() async {
    if (!await PlatformService.windowsHighContrastEnabled() || !mounted) return;
    setState(() => _systemHighContrast = true);
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
          // 触摸玻璃时表面起的波纹（设置里四档，关闭档给 null）。声明在 host 上是因为
          // g1455 把它定义成"这一屏的默认值"：所有没被可点区域铺满的玻璃都会形变，
          // 而铺满的那些（设置项整行都是 InkWell）本来就不会触发 —— hit 恒为 true。
          ripple: glassRippleFor(settings.glassRipple),
          // 边缘对比度。**必须由我们传值**：null 会让 g1455 去读
          // `MediaQuery.highContrastOf`，而引擎只在 iOS 与 Android 34+ 上设置它，
          // Windows 上恒为 false —— 「跟随系统」就永远跟不出来。读注册表的活见
          // `_loadHighContrastPreference`。
          highContrast: glassHighContrastFor(
            settings.glassContrast,
            systemHighContrast: _systemHighContrast,
          ),
          // 层级由设置里的档位决定；系统关掉了「透明效果」时那一档优先 —— g1455 的
          // policy 会为此返回 GlassTier.opaque 并带上 reduceTransparency 这个理由，
          // 它整档都不读背景，所以这时连那一次全屏捕获也省掉了。
          tier: glassTierChoice(
            mode: settings.glassTier,
            reduceTransparency: _reduceTransparency,
          ),
          // 玻璃背后的平均底色：直接取页面底色（`AppPageColors`，即 g1455 演示站的
          // 两个主题底色）。它同时决定「不透明档拿什么填色」和「玻璃上的文字挑黑还是白」，
          // 所以必须和 `AppBackdrop` 真正画出来的那一层同源 —— 两处各写一个值，
          // 就会出现「按 A 色挑文字、实际画在 B 色上」这类判定与实际不符的问题。
          backdrop: AppPageColors.of(Theme.of(context).brightness),
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
