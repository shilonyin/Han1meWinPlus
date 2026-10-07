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
          // 整屏只穿一种材质，**必须在这里也声明一次**。
          //
          // `GlassHost.finish` 是"这一屏所有没自己报材质的玻璃都穿的那件"：开关、
          // 滑条这些控件不报材质，就穿它；而 `GlassPanel` 是**逐面**报自己那件
          // （设置里的「材质」+「玻璃染色」）。两边不一致时 g1455 会把这一屏判成
          // "mixed"（`glass_host.dart:1746-1755` 按 finish 的 name 与 sigma 比较）。
          // 给同一个值（同一个 `glassFinishFor`、同一个 brightness）让两边一致，
          // 演示站也是这么做的（`finish: _settings.finishIn(...)` 挂 host 上）。
          //
          // 对齐这条**没有**修掉滚动时的灰块（对齐前后都在设置页复现了）；留着是
          // 因为它本来就是对的：host 的 finish 既是兜底，也是图集格子与预算算的键。
          finish: glassFinishFor(
            material: settings.glassMaterial,
            tint: settings.glassTint,
            brightness: Theme.of(context).brightness,
          ),
          // 图集上限：**桌面窗口必须自己声明**（不声明就是 4096）。
          //
          // g1455 把一屏所有玻璃录进**一张**图集，图集放不下就一步步加深除数
          // （画质换尺寸）；到 `GlassHost.maxTextureSide` 这个上限还放不下，
          // 这一帧就**什么都不发布**，各块玻璃只能继续用上一帧的图集 —— 而各块
          // 已经按新位置去取了，于是卡片上出现"硬边、位置错"的灰块。
          //
          // 这条上限在包里是**规格下限、不是实测值**（`hardware.dart:138-176`）：
          // 未识别的硬件（Windows 就是这一类，读不到任何 GPU 事实）取
          // `GlassHardware.unmeasured` = **4096**，而 4096 是 GLES 3.0 的下限。
          // 文档原话（`glass_host.dart:705-714`）："Worth declaring on a large
          // screen … A host that knows its device reports 16384 and says so keeps
          // the quality the floor of 4096 would have spent."
          //
          // 我们确实知道：Windows 走 ANGLE/D3D11，D3D11 feature level 11_0 就
          // 保证 16384（Windows 10 起没有更低的档），**用例正是文档点名的那个**
          // —— 桌面上的一叠宽卡片。声明真值总比拿规格下限当上限好。
          //
          // 这条也**没有**修掉滚动时的灰块：改成 16384 前后都在设置页复现了，
          // 所以那个灰块不是"图集放不下"。
          maxTextureSide: 16384,
          // 真正的病根：`GlassContentDeclaration` 管的是"屏下内容没变就可以一直
          // 沿用旧代理图"。
          //
          // 默认 `declared` —— 层监视器说这一帧没变，就**无限期**留用上一张图。
          // 而它认不认得出"变了"全押在包内那张**图层类型白名单**上
          // （`proxy_layer_watch.dart`），文档自己就写着这是仅剩的风险点：
          // "What is left of the risk lives in one table of layer types"
          // （`glass_host.dart:632-634`）。我们的设置页是滚轮驱动的长列表，一旦
          // 它判成"没变"，代理就停在旧内容上 —— 玻璃按**新**位置取样、取到的是
          // 旧图，卡片里于是浮出上一帧 UI 的硬边矩形。磨砂 / 超透的 tint alpha
          // 只有 .22，背景占 78%，一眼就看见；标准材质 alpha .718 把它盖住了，
          // 所以只有这两档露馅。
          //
          // 文档给这种情形的处方正是这个值：`undeclared` 是"给那些包认为自己读错的
          // 宿主"用的（`glass_host.dart:636-639`），代价是每帧重录。
          //
          // 实测（设置页、材质 = 磨砂、滚轮 5 格 × 每格 3 帧连拍，判据是采样区里
          // 140..205 的像素数，干净帧 ≈1330）：加它之前 15 帧有 9 帧带灰块，加它
          // 之后 2–3 帧。**没有归零** —— 剩下的那些是捕获天生滞后一帧（post-frame
          // 里录、同一帧里取），结构性的，站在应用这层改不掉。
          content: GlassContentDeclaration.undeclared,
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
            rendering: settings.glassRendering,
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
