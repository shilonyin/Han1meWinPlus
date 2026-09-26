import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../core/app_scroll_behavior.dart';
import '../core/m3e_theme_bridge.dart';
import '../core/settings.dart';
import '../features/auth/app_lock_gate.dart';
import '../features/navigation/exit_coordinator.dart';
import '../features/settings/settings_controller.dart';
import '../features/window/app_title_bar.dart';
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

  @override
  void initState() {
    super.initState();
    _exitCoordinator = AppExitCoordinator();
    _appRouter = AppRouter(_exitCoordinator);
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
        builder: (context, child) => M3EThemeBridge(
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
