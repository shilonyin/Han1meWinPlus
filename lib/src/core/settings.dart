import 'dart:io';

import 'package:flutter/material.dart';

import '../data/local/json_store.dart';
import 'platform_paths.dart';
import 'player_hotkey_registry.dart';
import 'video_decoders.dart';

enum AppThemeMode { system, light, dark }

enum AppThemeColor {
  rose,
  blue,
  teal,
  amber,
  green,
  orange,
  indigo,
  pink,
  purple,
  white,
  custom,
}

enum AppLanguage { system, simplifiedChinese, traditionalChinese, english }

enum PlayerEngine { exoPlayer, avPlayer, libMpv }

enum VideoRenderer { auto, gpu, gpuNext, mediacodecEmbed }

enum VideoView { platformView, surfaceView }

/// 超分辨率方案。`efficiency` / `quality` 是 Anime4K 的两个档位。
/// 序列化按枚举名保存，所以已有的值不能改名或删除，新方案只能往后追加。
///
/// 注：曾评估过 ArtCNN（与 Anime4K 同类的模型放大），但它是纯计算着色器实现，
/// 而本应用默认的 libmpv 渲染链路走 ANGLE（OpenGL ES 3.0，`compute shaders=0`），
/// 计算着色器 pass 会被直接丢弃，实测编译失败，因此未收录。
enum SuperResolutionMode { off, efficiency, quality, natural }

enum VideoAspectRatio { auto, crop, stretch, ratio4x3 }

/// libmpv 的 `gpu-api`：`auto` 由 mpv 自选（Windows 上通常落到 ANGLE / OpenGL ES），
/// `vulkan` / `d3d11` 走原生后端——**只有这两条链路支持 compute shader**，
/// ArtCNN 这类纯计算着色器的超分辨率模型才可能跑起来。
///
/// 序列化按枚举名保存，新值只能往后追加。
enum MpvGpuApi { auto, vulkan, d3d11 }

/// 窗口背景材质：`none` 保持纯色（现状），`mica` 走 Win11 Mica，`acrylic` 走 Win10 的亚克力。
/// 序列化按枚举名保存，新值只能往后追加。
enum WindowBackdrop { none, mica, acrylic }

/// 玻璃用哪块料（g1455 的 `GlassFinish`）。
///
/// 这五档不是我们编的：它们是 g1455 按真机材质**校准过**的常数，名字也照抄包的。
/// 名字必须照抄 —— 包里的损伤表按材质名索引，换个名字只会拿到拒绝而不是数字。
/// 我们从不自己拼 finish，只在这五个里挑一个。
/// - `regular` 常规：包按明暗挑 `.regular` 的那一支（深色下即 `regularDark`）
/// - `dark`    深色：钉死用深色那支
/// - `light`   浅色：钉死用浅色那支
/// - `clear`   超透：不模糊，只有一层很淡的底 + 亮边
/// - `frosted` 磨砂：纯模糊不折射
///
/// 换料**不碰** tint —— 染哪一色是「玻璃染色」那一栏的事。原来挂在磨砂档上的
/// 「磨砂不透明度」滑条已经删掉：它只对磨砂档有效，而演示站那边磨砂就是磨砂，
/// 浓度是材质自己定的。
///
/// 序列化按枚举名保存，新值只能往后追加。
enum GlassMaterial { regular, dark, light, clear, frosted }

/// 一组命名的设置，演示站叫 Preset。
///
/// **不落盘**：它不是独立状态，而是「当前这几项凑起来正好等于哪一档」，所以每次都由
/// 实际设置反推（见 `glass_tuning.dart` 的 `glassPresetFor`）。手改了任意一项就变成
/// 自定义，改回去预设又回来 —— 演示站就是这么做的。
///
/// 序列化按枚举名保存，新值只能往后追加。
enum GlassPresetKind { ultra, high, medium, low }

/// 玻璃本身的染色（g1455 的 `GlassFinish.tint`）。
///
/// **和「配色方案」是两件事**：配色方案给的是 primary 这类强调色，管按钮、选中态、
/// 背景画布的光晕；这一项管的是玻璃**那块料自己**偏什么色。原来所有玻璃都吃包默认的
/// 中性 tint，所以玻璃永远是灰的。
///
/// `neutral` 时**不动**材质自己的 tint —— g1455 那两个 `.regular` 的 tint 是按真机
/// 材质校准过的（`regularDark` 是 `rgba(29,29,32,0.693)`），我们没理由拿自己的表面色
/// 去替掉它。只有选了带色的两档才换掉 RGB、保留材质自己的 alpha。
///
/// 具体色值是我们的取舍：演示站的 Tint 那三档拿不到（站点是 Flutter web，HTML 只是
/// 静态大纲）。序列化按枚举名保存，新值只能往后追加。
enum GlassTintKind { neutral, indigo, rose }

/// 触摸玻璃时表面起的波纹（g1455 的 `GlassRipple`）。
///
/// g1455 的原话是「viscosity 是多数应用唯一需要的旋钮：**0 是水**，会一圈圈荡开；
/// **1 是蜂蜜**，只有一坨慢慢鼓起来」。所以四档只改 viscosity，其余参数
/// （amplitude / speed / width / press / pressRadius / light）保持包的默认值 ——
/// 那是作者"按眼睛定的、没有参照可量"的一组数，我们没有更好的依据去动它。
/// `jelly` 取包自己的默认 0.6，也正是 g1455 演示页的默认档。
///
/// **默认关闭**：g1455 把它标成 opt-in（iOS 对触摸的回应是光与缩放，从不形变材质），
/// 打开后所有没被可点区域铺满的玻璃都会开始形变，这个变化不该在用户没要求时发生。
/// 序列化按枚举名保存，新值只能往后追加。
enum GlassRippleKind { off, water, jelly, honey }

/// 玻璃的渲染层级（g1455 的 `GlassTier`）。
///
/// 这个维度是**整屏级**的，不是每块玻璃一个：三个档位分别决定"要不要读背景"，
/// 而捕获全屏的那一次是共享的，所以档位只能整屏选。
/// - `glass`       玻璃：读背景 —— 折射、模糊、亮边都在（也是波纹能画出来的唯一档）
/// - `translucent` 半透：同样的形状与亮边，但**完全不读背景**，省掉那次全屏捕获
/// - `opaque`      不透明：纯填充，背后什么都不透
///
/// 演示站还有一档 `auto`（交给包自己判），我们没有搬：它判出来的结果和 `glass` 一样
/// （`GlassTierChoice.byDefault` 就是 `GlassTier.full`），多一档只是多一次解释。
/// 系统「减少透明度」仍然**优先于**这里的任何一档 —— 那是可访问性地板，不是偏好，
/// 见 `glass_tuning.dart` 的 `glassTierChoice`。
///
/// 序列化按枚举名保存，新值只能往后追加。
enum GlassRendering { glass, translucent, opaque }

/// 玻璃边缘的对比度（g1455 的 `highContrast`）。
///
/// 打开后每块玻璃的描边改成**不透明**的高对比细线，半透明本身不变 ——
/// 这正是 Apple 自己的"提高对比度"开关对它家玻璃做的事：看得清边界，但材质不消失。
/// 给看不清边界的人用，和"把透明度关掉"（`GlassRendering.opaque`）是两件事。
enum GlassContrast { auto, increased }

extension PlayerEngineX on PlayerEngine {
  static List<PlayerEngine> get available {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS)
      return const [PlayerEngine.libMpv];
    if (Platform.isIOS)
      return const [PlayerEngine.avPlayer, PlayerEngine.libMpv];
    if (Platform.isAndroid)
      return const [PlayerEngine.exoPlayer, PlayerEngine.libMpv];
    return const [PlayerEngine.libMpv];
  }

  static PlayerEngine get defaultEngine => PlayerEngine.libMpv;
}

extension VideoRendererX on VideoRenderer {
  String? get mpvValue => switch (this) {
    VideoRenderer.auto => null,
    VideoRenderer.gpu => 'gpu',
    VideoRenderer.gpuNext => 'gpu-next',
    VideoRenderer.mediacodecEmbed => 'mediacodec_embed',
  };
}

const defaultDownloadPath = '';

class AppSettings {
  const AppSettings({
    this.themeMode = AppThemeMode.dark,
    this.baseUrl = 'https://hanime1.com',
    this.preferredQuality = 720,
    this.resumePlayback = true,
    this.autoPlayOnOpen = true,
    this.keyframesEnabled = true,
    this.language = AppLanguage.system,
    this.playerEngine = PlayerEngine.libMpv,
    this.hardwareAcceleration = true,
    this.hardwareDecoder = defaultHardwareDecoder,
    this.videoRenderer = VideoRenderer.auto,
    this.videoView = VideoView.platformView,
    this.customParameters = const [],
    this.superResolutionMode = SuperResolutionMode.off,
    this.autoUpdate = true,
    this.useUpdateMirror = true,
    this.themeColor = AppThemeColor.white,
    this.customThemeColor = '62539F',
    this.useMonetColors = false,
    this.amoledMode = false,
    this.textScale = 1,
    this.downloadSpeedLimitMbps = 0,
    this.concurrentDownloads = 2,
    this.autoGroupDownloads = true,
    this.groupNameFromSeries = false,
    this.groupNameTraditional = false,
    this.downloadPath = defaultDownloadPath,
    this.defaultPlaybackSpeed = 1,
    this.playbackVolume = 1,
    this.longPressPlaybackSpeed = 2,
    this.playerControlsTimeoutSeconds = 4,
    this.seekSensitivity = .35,
    this.appLockEnabled = false,
    this.emergencyExitEnabled = false,
    this.hideFromRecents = false,
    this.commentsEnabled = true,
    this.blockedCommentKeywords = const [],
    this.comicMode = false,
    this.previewSource = 'auto',
    this.videoBaseUrl = 'https://hanime1.com',
    this.useBuiltInHosts = false,
    this.useCustomMirrorSite = false,
    this.customMirrorSite = '',
    this.appendCustomMirrorPath = true,
    this.useAddressRanking = true,
    this.useDoh = false,
    this.dohPreset = 'alidns',
    this.dohCustomUrl = '',
    this.dohBootstrapIps = '',
    this.dohTimeoutSeconds = 10,
    this.proxyMode = 'system',
    this.customProxy = '',
    this.useHorizontalSearchCards = true,
    this.searchCardsPerRow = 2,
    this.useCompactSearchCards = true,
    this.expandHomeVideoCards = false,
    this.useNavigationDrawer = true,
    this.useSystemFont = false,
    this.useSystemTitleBar = true,
    this.openVideoInWindow = true,
    this.minimizeToTray = false,
    this.globalHotkeysEnabled = true,
    this.hotkeyBindings = const {},
    this.hotkeyDefaultsMigrated = false,
    this.windowBackdrop = WindowBackdrop.none,
    this.glassSurfaceEnabled = false,
    this.glassMaterial = GlassMaterial.regular,
    this.glassTint = GlassTintKind.neutral,
    this.glassRipple = GlassRippleKind.off,
    this.glassRendering = GlassRendering.glass,
    this.glassContrast = GlassContrast.auto,
    this.notificationsEnabled = true,
    this.gpuApi = MpvGpuApi.auto,
    this.localMediaDirectory = '',
    this.dlnaReceiverEnabled = false,
    this.useHomeCategoryTabs = false,
    this.homeQuickCategories = const <String>[],
    this.blockedVideoTitleKeywords = const [],
    this.blockedAuthors = const [],
    this.blockedVideoTags = const [],
    this.minimumVideoDurationSeconds = 0,
    this.minimumVideoViews = 0,
    this.exemptSubscribedAuthors = true,
    this.applyRecommendationFiltersToRelated = true,
    this.applyRecommendationFiltersToSearch = true,
    this.blockedCommentUsers = const [],
    this.incognitoPlayback = false,
    this.autoPlayNext = false,
    this.loopPlayback = false,
    this.autoPictureInPicture = false,
    this.videoAspectRatio = VideoAspectRatio.auto,
    this.skipSeconds = 80,
    this.webDavEnabled = false,
    this.webDavHistorySync = false,
    this.webDavFavoriteSync = false,
    this.webDavUrl = '',
    this.webDavUsername = '',
    this.webDavPassword = '',
  });

  final AppThemeMode themeMode;
  final String baseUrl;
  final int preferredQuality;
  final bool resumePlayback;
  final bool autoPlayOnOpen;
  final bool keyframesEnabled;
  final AppLanguage language;
  final PlayerEngine playerEngine;
  final bool hardwareAcceleration;

  /// 传给 mpv 的 hwdec 值（仅在硬件解码开启时生效）
  final String hardwareDecoder;
  final VideoRenderer videoRenderer;
  final VideoView videoView;
  final List<String> customParameters;
  final SuperResolutionMode superResolutionMode;
  final bool autoUpdate;
  final bool useUpdateMirror;
  final AppThemeColor themeColor;
  final String customThemeColor;
  final bool useMonetColors;
  final bool amoledMode;
  final double textScale;
  final double downloadSpeedLimitMbps;
  final int concurrentDownloads;
  final bool autoGroupDownloads;
  final bool groupNameFromSeries;
  final bool groupNameTraditional;
  final String downloadPath;
  final double defaultPlaybackSpeed;

  /// 播放器音量（0–1）。每次新建播放器时恢复这个值，否则每次都回到满音量
  /// （`VideoPlayerController` 的默认值就是 1.0，没人管的话每次都满）。
  final double playbackVolume;
  final double longPressPlaybackSpeed;
  final int playerControlsTimeoutSeconds;
  final double seekSensitivity;
  final bool appLockEnabled;
  final bool emergencyExitEnabled;
  final bool hideFromRecents;
  final bool commentsEnabled;
  final List<String> blockedCommentKeywords;
  final bool comicMode;

  /// 新番预告的数据源：`auto`（默认站点不可用时自动改用 Getchu）、`default`（只用默认站点）、`getchu`。
  final String previewSource;
  final String videoBaseUrl;
  final bool useBuiltInHosts;
  final bool useCustomMirrorSite;
  final String customMirrorSite;
  final bool appendCustomMirrorPath;

  /// 是否按实测延迟自动优选内置候选地址（见 `AddressRanker`）。关闭则回到列表原顺序（IPv4 优先）。
  final bool useAddressRanking;
  final bool useDoh;
  final String dohPreset;
  final String dohCustomUrl;
  final String dohBootstrapIps;
  final int dohTimeoutSeconds;

  /// 代理模式：`system` 跟随系统代理（默认）、`direct` 不使用代理、`custom` 用 [customProxy]。
  ///
  /// 注意：只要走代理，连接工厂就会把请求交给代理，内置 Hosts 与 DoH 都会被绕过；
  /// `direct` 才能用上内置地址（实测内置 IP 直连站点比走代理还快）。
  final String proxyMode;
  final String customProxy;
  final bool useHorizontalSearchCards;
  final int searchCardsPerRow;
  final bool useCompactSearchCards;
  final bool expandHomeVideoCards;
  final bool useNavigationDrawer;
  final bool useSystemFont;
  final bool useSystemTitleBar;

  /// Windows：点击视频封面时弹出独立播放窗口（多进程），而不是在主窗口内跳转播放页。
  /// 仅桌面 Windows 生效；其余平台恒为窗口内播放（见 `openVideo`）。
  final bool openVideoInWindow;

  /// 关闭按钮收进系统托盘而不是退出（托盘菜单负责「显示窗口 / 退出」）。
  final bool minimizeToTray;

  /// 注册系统级热键（窗口未激活时也生效）。默认开启；全局键位统一带 Ctrl+Alt
  /// 修饰，与其它软件的裸键冲突率很低。老配置里的 false 是旧版写死的默认值，
  /// 由 [hotkeyDefaultsMigrated] 一次性迁移回 true，之后尊重用户选择。
  final bool globalHotkeysEnabled;

  /// 快捷键的用户绑定（动作 id → 组合键字符串，见 `PlayerHotkeyRegistry`）。
  /// 只存被改过的动作；空表 = 全部默认键位。应用内快捷键不受
  /// [globalHotkeysEnabled] 开关控制（那是全局热键的总闸）。
  final Map<String, String> hotkeyBindings;

  /// 快捷键默认开启的一次性迁移标记。老版本的 [toJson] 把当时的默认值
  /// `globalHotkeysEnabled: false` 全量写进了 setting.json，无法与「用户主动
  /// 关闭」区分：没有此标记的配置在载入时会被强制置回 true；迁移后用户再
  /// 关掉就是真关（标记随下一次设置保存落盘，不会再被迁移打扰）。
  final bool hotkeyDefaultsMigrated;

  /// 窗口背景材质。默认 `none` 保持纯色，开启后由 [appTheme] 把表面调成半透明让材质透出来。
  final WindowBackdrop windowBackdrop;

  /// 界面是否使用毛玻璃材质（`LiquidGlassSurface`）。默认关闭：它要采样背景，
  /// 在列表密集滚动时比纯色卡片更耗，且需要 Impeller 后端才有折射效果。
  ///
  /// **遗留字段**：玻璃现在已经由 [glassMaterial] 一档直接决定，渲染层不再读它；
  /// 保留只是为了迁移那些比 `glassQuality` 还老的配置（那时只有「开 / 关」）。
  final bool glassSurfaceEnabled;

  /// 玻璃用哪块料（常规 / 深色 / 浅色 / 超透 / 磨砂）。
  final GlassMaterial glassMaterial;

  /// 玻璃本身的染色（中性 / 靛蓝 / 玫瑰）。与「配色方案」不是一回事，见枚举文档。
  final GlassTintKind glassTint;

  /// 触摸玻璃时表面起的波纹（关闭 / 水 / 果冻 / 蜂蜜）。
  final GlassRippleKind glassRipple;

  /// 玻璃的渲染层级（玻璃 / 半透 / 不透明）。整屏级，见枚举文档。
  final GlassRendering glassRendering;

  /// 玻璃边缘的对比度（跟随系统 / 增强）。
  final GlassContrast glassContrast;

  /// 桌面通知（下载完成 / 更新可用）。默认开，可以整体关掉。
  final bool notificationsEnabled;

  /// libmpv 渲染后端。切到 Vulkan / D3D11 才能用上 compute shader（为 ArtCNN 铺路）。
  final MpvGpuApi gpuApi;

  /// 本地媒体库目录：非空时扫描其中的视频并监听增删（见 `LocalMediaRepository`）。
  final String localMediaDirectory;

  /// DLNA 接收端（PC 作投屏目标）：开启后在局域网里广播一个 MediaRenderer。
  /// 默认关——它会常驻监听 1900 端口并起一个本地 HTTP 服务。
  final bool dlnaReceiverEnabled;
  final bool useHomeCategoryTabs;

  /// 顶栏「快捷分类」：存的是**站点原始分类名**（如「最新上市」），与界面语言无关，
  /// 显示时再本地化。为空表示默认取首页前 6 个分类。
  final List<String> homeQuickCategories;
  final List<String> blockedVideoTitleKeywords;
  final List<String> blockedAuthors;
  final List<String> blockedVideoTags;
  final int minimumVideoDurationSeconds;
  final int minimumVideoViews;
  final bool exemptSubscribedAuthors;
  final bool applyRecommendationFiltersToRelated;
  final bool applyRecommendationFiltersToSearch;
  final List<String> blockedCommentUsers;
  final bool incognitoPlayback;
  final bool autoPlayNext;
  final bool loopPlayback;
  final bool autoPictureInPicture;
  final VideoAspectRatio videoAspectRatio;
  final int skipSeconds;
  final bool webDavEnabled;
  final bool webDavHistorySync;
  final bool webDavFavoriteSync;
  final String webDavUrl;
  final String webDavUsername;
  final String webDavPassword;

  ThemeMode get materialThemeMode => switch (themeMode) {
    AppThemeMode.system => ThemeMode.system,
    AppThemeMode.light => ThemeMode.light,
    AppThemeMode.dark => ThemeMode.dark,
  };

  /// 实际生效的明暗：`system` 跟系统走，其余按用户选择。
  ///
  /// 窗口材质（Mica / Acrylic）要用它，而不是直接读 `Theme.of(context)`：
  /// provider 的回调先于 widget 重建触发，那时 `Theme.of` 还是切换前的旧亮度，
  /// 从深色切到浅色就会把材质留在深色上。这里是纯推导，跟重建时序无关。
  Brightness effectiveBrightness(Brightness platformBrightness) =>
      switch (themeMode) {
        AppThemeMode.system => platformBrightness,
        AppThemeMode.light => Brightness.light,
        AppThemeMode.dark => Brightness.dark,
      };

  /// AMOLED（表面纯黑）**只作用于深色主题**：`appTheme` 里这个开关只传给
  /// darkTheme，浅色主题下它不该改变任何颜色。
  ///
  /// 拿裸的 [amoledMode] 去改颜色就会在浅色主题下出错——侧栏曾据此把底色换成
  /// 4% 白，开着窗口材质时几乎全透明、直接透出材质，看着就是「侧栏发灰、
  /// 和内容区不是一套」。所以判断要带上实际生效的 [brightness]。
  bool amoledApplies(Brightness brightness) =>
      amoledMode && brightness == Brightness.dark;

  bool get mirrorActive => useCustomMirrorSite && customMirrorSite.isNotEmpty;

  String get homeBaseUrl => mirrorActive ? customMirrorSite : baseUrl;

  String get resolvedBaseUrl {
    if (!mirrorActive) return baseUrl;
    return appendCustomMirrorPath
        ? customMirrorSite
        : _rootUrl(customMirrorSite);
  }

  static String _rootUrl(String url) {
    final uri = Uri.parse(url);
    return '${uri.scheme}://${uri.authority}';
  }

  Map<String, dynamic> toJson() => {
    'themeMode': themeMode.name,
    'baseUrl': baseUrl,
    'preferredQuality': preferredQuality,
    'resumePlayback': resumePlayback,
    'autoPlayOnOpen': autoPlayOnOpen,
    'keyframesEnabled': keyframesEnabled,
    'language': language.name,
    'playerEngine': playerEngine.name,
    'hardwareAcceleration': hardwareAcceleration,
    'hardwareDecoder': hardwareDecoder,
    'videoRenderer': videoRenderer.name,
    'videoView': videoView.name,
    'customParameters': customParameters,
    'superResolutionMode': superResolutionMode.name,
    'autoUpdate': autoUpdate,
    'useUpdateMirror': useUpdateMirror,
    'themeColor': themeColor.name,
    'customThemeColor': customThemeColor,
    'useMonetColors': useMonetColors,
    'amoledMode': amoledMode,
    'textScale': textScale,
    'downloadSpeedLimitMbps': downloadSpeedLimitMbps,
    'concurrentDownloads': concurrentDownloads,
    'autoGroupDownloads': autoGroupDownloads,
    'groupNameFromSeries': groupNameFromSeries,
    'groupNameTraditional': groupNameTraditional,
    'downloadPath': downloadPath,
    'defaultPlaybackSpeed': defaultPlaybackSpeed,
    'playbackVolume': playbackVolume,
    'longPressPlaybackSpeed': longPressPlaybackSpeed,
    'playerControlsTimeoutSeconds': playerControlsTimeoutSeconds,
    'seekSensitivity': seekSensitivity,
    'appLockEnabled': appLockEnabled,
    'emergencyExitEnabled': emergencyExitEnabled,
    'hideFromRecents': hideFromRecents,
    'commentsEnabled': commentsEnabled,
    'blockedCommentKeywords': blockedCommentKeywords,
    'comicMode': comicMode,
    'previewSource': previewSource,
    'videoBaseUrl': videoBaseUrl,
    'useBuiltInHosts': useBuiltInHosts,
    'useCustomMirrorSite': useCustomMirrorSite,
    'customMirrorSite': customMirrorSite,
    'appendCustomMirrorPath': appendCustomMirrorPath,
    'useAddressRanking': useAddressRanking,
    'useDoh': useDoh,
    'dohPreset': dohPreset,
    'dohCustomUrl': dohCustomUrl,
    'dohBootstrapIps': dohBootstrapIps,
    'dohTimeoutSeconds': dohTimeoutSeconds,
    'proxyMode': proxyMode,
    'customProxy': customProxy,
    'useHorizontalSearchCards': useHorizontalSearchCards,
    'searchCardsPerRow': searchCardsPerRow,
    'useCompactSearchCards': useCompactSearchCards,
    'expandHomeVideoCards': expandHomeVideoCards,
    'useNavigationDrawer': useNavigationDrawer,
    'useSystemFont': useSystemFont,
    'useSystemTitleBar': useSystemTitleBar,
    'openVideoInWindow': openVideoInWindow,
    'minimizeToTray': minimizeToTray,
    'globalHotkeysEnabled': globalHotkeysEnabled,
    'hotkeyBindings': hotkeyBindings,
    'hotkeyDefaultsMigrated': hotkeyDefaultsMigrated,
    'windowBackdrop': windowBackdrop.name,
    'glassSurfaceEnabled': glassSurfaceEnabled,
    'glassMaterial': glassMaterial.name,
    'glassTint': glassTint.name,
    'glassRipple': glassRipple.name,
    'glassRendering': glassRendering.name,
    'glassContrast': glassContrast.name,
    'notificationsEnabled': notificationsEnabled,
    'gpuApi': gpuApi.name,
    'localMediaDirectory': localMediaDirectory,
    'dlnaReceiverEnabled': dlnaReceiverEnabled,
    'useHomeCategoryTabs': useHomeCategoryTabs,
    'homeQuickCategories': homeQuickCategories,
    'blockedVideoTitleKeywords': blockedVideoTitleKeywords,
    'blockedAuthors': blockedAuthors,
    'blockedVideoTags': blockedVideoTags,
    'minimumVideoDurationSeconds': minimumVideoDurationSeconds,
    'minimumVideoViews': minimumVideoViews,
    'exemptSubscribedAuthors': exemptSubscribedAuthors,
    'applyRecommendationFiltersToRelated': applyRecommendationFiltersToRelated,
    'applyRecommendationFiltersToSearch': applyRecommendationFiltersToSearch,
    'blockedCommentUsers': blockedCommentUsers,
    'incognitoPlayback': incognitoPlayback,
    'autoPlayNext': autoPlayNext,
    'loopPlayback': loopPlayback,
    'autoPictureInPicture': autoPictureInPicture,
    'videoAspectRatio': videoAspectRatio.name,
    'skipSeconds': skipSeconds,
    'webDavEnabled': webDavEnabled,
    'webDavHistorySync': webDavHistorySync,
    'webDavFavoriteSync': webDavFavoriteSync,
    'webDavUrl': webDavUrl,
    'webDavUsername': webDavUsername,
    'webDavPassword': webDavPassword,
  };

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
    themeMode: _themeMode(json['themeMode'] as String?),
    baseUrl: json['baseUrl'] as String? ?? 'https://hanime1.com',
    preferredQuality: json['preferredQuality'] as int? ?? 720,
    resumePlayback: json['resumePlayback'] as bool? ?? true,
    autoPlayOnOpen: json['autoPlayOnOpen'] as bool? ?? true,
    keyframesEnabled: json['keyframesEnabled'] as bool? ?? true,
    language: _language(json['language'] as String?),
    playerEngine: _playerEngine(json['playerEngine'] as String?),
    hardwareAcceleration: json['hardwareAcceleration'] as bool? ?? true,
    hardwareDecoder: knownHardwareDecoder(json['hardwareDecoder'] as String?),
    videoRenderer:
        _enumByName(VideoRenderer.values, json['videoRenderer'] as String?) ??
        VideoRenderer.auto,
    videoView:
        _enumByName(VideoView.values, json['videoView'] as String?) ??
        VideoView.platformView,
    customParameters: (json['customParameters'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    superResolutionMode:
        _enumByName(
          SuperResolutionMode.values,
          json['superResolutionMode'] as String?,
        ) ??
        SuperResolutionMode.off,
    autoUpdate: json['autoUpdate'] as bool? ?? true,
    useUpdateMirror: json['useUpdateMirror'] as bool? ?? true,
    themeColor: _themeColor(json['themeColor'] as String?),
    customThemeColor: _hexColor(json['customThemeColor'] as String?),
    useMonetColors: json['useMonetColors'] as bool? ?? false,
    amoledMode: json['amoledMode'] as bool? ?? false,
    textScale: ((json['textScale'] as num?)?.toDouble() ?? 1)
        .clamp(.8, 1.4)
        .toDouble(),
    downloadSpeedLimitMbps:
        (json['downloadSpeedLimitMbps'] as num?)?.toDouble() ?? 0,
    concurrentDownloads:
        (json['concurrentDownloads'] as int? ?? 2).clamp(1, 5),
    autoGroupDownloads: json['autoGroupDownloads'] as bool? ?? true,
    groupNameFromSeries: json['groupNameFromSeries'] as bool? ?? false,
    groupNameTraditional: json['groupNameTraditional'] as bool? ?? false,
    downloadPath: json['downloadPath'] as String? ?? defaultDownloadPath,
    defaultPlaybackSpeed:
        ((json['defaultPlaybackSpeed'] as num?)?.toDouble() ?? 1)
            .clamp(.25, 3)
            .toDouble(),
    playbackVolume: ((json['playbackVolume'] as num?)?.toDouble() ?? 1)
        .clamp(0, 1)
        .toDouble(),
    longPressPlaybackSpeed:
        ((json['longPressPlaybackSpeed'] as num?)?.toDouble() ?? 2)
            .clamp(1, 3)
            .toDouble(),
    playerControlsTimeoutSeconds:
        (json['playerControlsTimeoutSeconds'] as int? ?? 4).clamp(1, 15),
    seekSensitivity: ((json['seekSensitivity'] as num?)?.toDouble() ?? .35)
        .clamp(.1, 1)
        .toDouble(),
    appLockEnabled: json['appLockEnabled'] as bool? ?? false,
    emergencyExitEnabled: json['emergencyExitEnabled'] as bool? ?? false,
    hideFromRecents: json['hideFromRecents'] as bool? ?? false,
    commentsEnabled: json['commentsEnabled'] as bool? ?? true,
    blockedCommentKeywords:
        (json['blockedCommentKeywords'] as List? ?? const [])
            .whereType<String>()
            .toList(),
    comicMode: json['comicMode'] as bool? ?? false,
    previewSource: _previewSource(json['previewSource'] as String?),
    videoBaseUrl:
        json['videoBaseUrl'] as String? ??
        (json['baseUrl'] == 'https://hanimeone.me'
            ? 'https://hanime1.com'
            : json['baseUrl'] as String? ?? 'https://hanime1.com'),
    useBuiltInHosts:
        json['useBuiltInHosts'] as bool? ??
        Platform.isWindows || Platform.isLinux || Platform.isMacOS,
    useCustomMirrorSite: json['useCustomMirrorSite'] as bool? ?? false,
    customMirrorSite: _mirrorUrl(json['customMirrorSite'] as String?),
    appendCustomMirrorPath: json['appendCustomMirrorPath'] as bool? ?? true,
    useAddressRanking: json['useAddressRanking'] as bool? ?? true,
    useDoh: json['useDoh'] as bool? ?? false,
    dohPreset: _dohPreset(json['dohPreset'] as String?),
    dohCustomUrl: json['dohCustomUrl'] as String? ?? '',
    dohBootstrapIps: json['dohBootstrapIps'] as String? ?? '',
    dohTimeoutSeconds:
        (json['dohTimeoutSeconds'] as int? ?? 10).clamp(1, 60),
    proxyMode: _proxyMode(json['proxyMode'] as String?),
    customProxy: (json['customProxy'] as String? ?? '').trim(),
    useHorizontalSearchCards: json['useHorizontalSearchCards'] as bool? ?? true,
    searchCardsPerRow:
        (json['searchCardsPerRow'] as int? ?? 2).clamp(1, 3),
    useCompactSearchCards: json['useCompactSearchCards'] as bool? ?? true,
    expandHomeVideoCards: json['expandHomeVideoCards'] as bool? ?? false,
    useNavigationDrawer: json['useNavigationDrawer'] as bool? ?? true,
    useSystemFont: json['useSystemFont'] as bool? ?? false,
    useSystemTitleBar: json['useSystemTitleBar'] as bool? ?? true,
    openVideoInWindow: json['openVideoInWindow'] as bool? ?? true,
    minimizeToTray: json['minimizeToTray'] as bool? ?? false,
    // 老用户强制迁移：见 [hotkeyDefaultsMigrated] 的说明 —— 没有迁移标记的
    // 配置一律视为「从未主动选择过」，全局热键强制回默认开启。
    globalHotkeysEnabled: (json['hotkeyDefaultsMigrated'] as bool? ?? false)
        ? (json['globalHotkeysEnabled'] as bool? ?? true)
        : true,
    hotkeyBindings: PlayerHotkeyRegistry.sanitizeStoredBindings(
      json['hotkeyBindings'] as Map?,
    ),
    hotkeyDefaultsMigrated: true,
    windowBackdrop:
        _enumByName(WindowBackdrop.values, json['windowBackdrop'] as String?) ??
        WindowBackdrop.none,
    glassSurfaceEnabled: json['glassSurfaceEnabled'] as bool? ?? false,
    // 老配置是「开关 + 档位」两个字段，再往后档位从 clear/frosted/liquid 三档换成
    // 直接选材质。两级回退都在这里：能读到 glassMaterial 就用它，否则按老档位名翻。
    glassMaterial:
        _enumByName(GlassMaterial.values, json['glassMaterial'] as String?) ??
        _legacyMaterial(json['glassQuality'] as String?),
    glassTint: _enumByName(GlassTintKind.values, json['glassTint'] as String?) ?? GlassTintKind.neutral,
    glassRipple: _enumByName(GlassRippleKind.values, json['glassRipple'] as String?) ?? GlassRippleKind.off,
    glassRendering:
        _enumByName(GlassRendering.values, json['glassRendering'] as String?) ??
        _legacyRendering(json['glassTier'] as String?),
    glassContrast: _enumByName(GlassContrast.values, json['glassContrast'] as String?) ?? GlassContrast.auto,
    notificationsEnabled: json['notificationsEnabled'] as bool? ?? true,
    gpuApi:
        _enumByName(MpvGpuApi.values, json['gpuApi'] as String?) ??
        MpvGpuApi.auto,
    localMediaDirectory: json['localMediaDirectory'] as String? ?? '',
    dlnaReceiverEnabled: json['dlnaReceiverEnabled'] as bool? ?? false,
    useHomeCategoryTabs: json['useHomeCategoryTabs'] as bool? ?? false,
    homeQuickCategories: ((json['homeQuickCategories'] as List?) ?? const [])
        .whereType<String>()
        .toList(),
    blockedVideoTitleKeywords:
        (json['blockedVideoTitleKeywords'] as List? ?? const [])
            .whereType<String>()
            .toList(),
    blockedAuthors: (json['blockedAuthors'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    blockedVideoTags: (json['blockedVideoTags'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    minimumVideoDurationSeconds:
        (json['minimumVideoDurationSeconds'] as int? ?? 0).clamp(0, 86400),
    minimumVideoViews:
        (json['minimumVideoViews'] as int? ?? 0).clamp(0, 1000000000),
    exemptSubscribedAuthors: json['exemptSubscribedAuthors'] as bool? ?? true,
    applyRecommendationFiltersToRelated:
        json['applyRecommendationFiltersToRelated'] as bool? ?? true,
    applyRecommendationFiltersToSearch:
        json['applyRecommendationFiltersToSearch'] as bool? ?? true,
    blockedCommentUsers: (json['blockedCommentUsers'] as List? ?? const [])
        .whereType<String>()
        .toList(),
    incognitoPlayback: json['incognitoPlayback'] as bool? ?? false,
    autoPlayNext: json['autoPlayNext'] as bool? ?? false,
    loopPlayback: json['loopPlayback'] as bool? ?? false,
    autoPictureInPicture: json['autoPictureInPicture'] as bool? ?? false,
    videoAspectRatio:
        _enumByName(
          VideoAspectRatio.values,
          json['videoAspectRatio'] as String?,
        ) ??
        VideoAspectRatio.auto,
    skipSeconds: (json['skipSeconds'] as int? ?? 80).clamp(1, 3600),
    webDavEnabled: json['webDavEnabled'] as bool? ?? false,
    webDavHistorySync: json['webDavHistorySync'] as bool? ?? false,
    webDavFavoriteSync: json['webDavFavoriteSync'] as bool? ?? false,
    webDavUrl: json['webDavUrl'] as String? ?? '',
    webDavUsername: json['webDavUsername'] as String? ?? '',
    webDavPassword: json['webDavPassword'] as String? ?? '',
  );

  static AppThemeMode _themeMode(String? name) {
    for (final mode in AppThemeMode.values) {
      if (mode.name == name) return mode;
    }
    // 回落的必须是 [AppSettings.themeMode] 的默认值：缺字段（全新安装时 json 就是空的）
    // 或字段非法时都走这里，如果这里回浅色，构造函数的默认值就形同虚设。
    return AppThemeMode.dark;
  }

  static AppThemeColor _themeColor(String? name) =>
      AppThemeColor.values.where((value) => value.name == name).firstOrNull ??
      AppThemeColor.white;

  static AppLanguage _language(String? name) =>
      AppLanguage.values.where((value) => value.name == name).firstOrNull ??
      AppLanguage.system;

  static PlayerEngine _playerEngine(String? name) {
    final parsed = _enumByName(PlayerEngine.values, name);
    if (parsed != null) return parsed;
    return PlayerEngineX.defaultEngine;
  }

  static T? _enumByName<T extends Enum>(List<T> values, String? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }

  /// 老配置里的「质感档位」翻成现在选的材质。
  ///
  /// `liquid` 那档翻到 `regular` 而不是某个更"具体"的材质：液体玻璃本来就是
  /// 按明暗自动挑 `.regular` 的那一支，`regular` 正是同一件事。
  /// `clear` 与 `frosted` 按名字原样留着 —— 它们在包是两块真料（模糊 σ 0 对 8），
  /// 只是页面底色被压平之后看不出差别，所以设置页不再列出来，但老配置不该被改掉。
  static GlassMaterial _legacyMaterial(String? qualityName) {
    switch (qualityName) {
      case 'clear':
        return GlassMaterial.clear;
      case 'frosted':
        return GlassMaterial.frosted;
      // `liquid` 与 `off`（以及比 `glassQuality` 更老、只有开关的配置）都落到 `regular`：
      // 液体玻璃本来就是按明暗自动挑 `.regular` 的那一支，而老配置里的 off 是"不要玻璃"，
      // 现在的模型没有关掉这一档，取最接近的。
      default:
        return GlassMaterial.regular;
    }
  }

  /// 老配置里的「渲染层级」翻成现在的三档（`auto` 判出来就是完整档）。
  static GlassRendering _legacyRendering(String? tierName) => switch (tierName) {
    'cheap' => GlassRendering.translucent,
    'opaque' => GlassRendering.opaque,
    _ => GlassRendering.glass,
  };

  static String _hexColor(String? value) {
    final normalized = value?.replaceFirst('#', '').toUpperCase() ?? '';
    return RegExp(r'^[0-9A-F]{6}$').hasMatch(normalized)
        ? normalized
        : '62539F';
  }

  static String _dohPreset(String? value) => switch (value) {
    'alidns' || 'dnspod' || 'cloudflare' || 'custom' => value!,
    _ => 'alidns',
  };

  static String _proxyMode(String? value) => switch (value) {
    'system' || 'direct' || 'custom' => value!,
    _ => 'system',
  };

  static String _previewSource(String? value) => switch (value) {
    'auto' || 'default' || 'getchu' => value!,
    _ => 'auto',
  };

  static String _mirrorUrl(String? value) {
    final normalized = value?.trim().replaceAll(RegExp(r'/+$'), '') ?? '';
    final uri = Uri.tryParse(normalized);
    if (uri == null ||
        uri.scheme != 'https' ||
        uri.host.isEmpty ||
        uri.hasQuery ||
        uri.hasFragment)
      return '';
    return normalized;
  }

  AppSettings copyWith({
    AppThemeMode? themeMode,
    String? baseUrl,
    int? preferredQuality,
    bool? resumePlayback,
    bool? autoPlayOnOpen,
    bool? keyframesEnabled,
    AppLanguage? language,
    PlayerEngine? playerEngine,
    bool? hardwareAcceleration,
    String? hardwareDecoder,
    VideoRenderer? videoRenderer,
    VideoView? videoView,
    List<String>? customParameters,
    SuperResolutionMode? superResolutionMode,
    bool? autoUpdate,
    bool? useUpdateMirror,
    AppThemeColor? themeColor,
    String? customThemeColor,
    bool? useMonetColors,
    bool? amoledMode,
    double? textScale,
    double? downloadSpeedLimitMbps,
    int? concurrentDownloads,
    bool? autoGroupDownloads,
    bool? groupNameFromSeries,
    bool? groupNameTraditional,
    String? downloadPath,
    double? defaultPlaybackSpeed,
    double? playbackVolume,
    double? longPressPlaybackSpeed,
    int? playerControlsTimeoutSeconds,
    double? seekSensitivity,
    bool? appLockEnabled,
    bool? emergencyExitEnabled,
    bool? hideFromRecents,
    bool? commentsEnabled,
    List<String>? blockedCommentKeywords,
    bool? comicMode,
    String? previewSource,
    String? videoBaseUrl,
    bool? useBuiltInHosts,
    bool? useCustomMirrorSite,
    String? customMirrorSite,
    bool? appendCustomMirrorPath,
    bool? useAddressRanking,
    bool? useDoh,
    String? dohPreset,
    String? dohCustomUrl,
    String? dohBootstrapIps,
    int? dohTimeoutSeconds,
    String? proxyMode,
    String? customProxy,
    bool? useHorizontalSearchCards,
    int? searchCardsPerRow,
    bool? useCompactSearchCards,
    bool? expandHomeVideoCards,
    bool? useNavigationDrawer,
    bool? useSystemFont,
    bool? useSystemTitleBar,
    bool? openVideoInWindow,
    bool? minimizeToTray,
    bool? globalHotkeysEnabled,
    Map<String, String>? hotkeyBindings,
    bool? hotkeyDefaultsMigrated,
    WindowBackdrop? windowBackdrop,
    bool? glassSurfaceEnabled,
    GlassMaterial? glassMaterial,
    GlassTintKind? glassTint,
    GlassRippleKind? glassRipple,
    GlassRendering? glassRendering,
    GlassContrast? glassContrast,
    bool? notificationsEnabled,
    MpvGpuApi? gpuApi,
    String? localMediaDirectory,
    bool? dlnaReceiverEnabled,
    bool? useHomeCategoryTabs,
    List<String>? homeQuickCategories,
    List<String>? blockedVideoTitleKeywords,
    List<String>? blockedAuthors,
    List<String>? blockedVideoTags,
    int? minimumVideoDurationSeconds,
    int? minimumVideoViews,
    bool? exemptSubscribedAuthors,
    bool? applyRecommendationFiltersToRelated,
    bool? applyRecommendationFiltersToSearch,
    List<String>? blockedCommentUsers,
    bool? incognitoPlayback,
    bool? autoPlayNext,
    bool? loopPlayback,
    bool? autoPictureInPicture,
    VideoAspectRatio? videoAspectRatio,
    int? skipSeconds,
    bool? webDavEnabled,
    bool? webDavHistorySync,
    bool? webDavFavoriteSync,
    String? webDavUrl,
    String? webDavUsername,
    String? webDavPassword,
  }) => AppSettings(
    themeMode: themeMode ?? this.themeMode,
    baseUrl: baseUrl ?? this.baseUrl,
    preferredQuality: preferredQuality ?? this.preferredQuality,
    resumePlayback: resumePlayback ?? this.resumePlayback,
    autoPlayOnOpen: autoPlayOnOpen ?? this.autoPlayOnOpen,
    keyframesEnabled: keyframesEnabled ?? this.keyframesEnabled,
    language: language ?? this.language,
    playerEngine: playerEngine ?? this.playerEngine,
    hardwareAcceleration: hardwareAcceleration ?? this.hardwareAcceleration,
    hardwareDecoder: hardwareDecoder ?? this.hardwareDecoder,
    videoRenderer: videoRenderer ?? this.videoRenderer,
    videoView: videoView ?? this.videoView,
    customParameters: customParameters ?? this.customParameters,
    superResolutionMode: superResolutionMode ?? this.superResolutionMode,
    autoUpdate: autoUpdate ?? this.autoUpdate,
    useUpdateMirror: useUpdateMirror ?? this.useUpdateMirror,
    themeColor: themeColor ?? this.themeColor,
    customThemeColor: customThemeColor ?? this.customThemeColor,
    useMonetColors: useMonetColors ?? this.useMonetColors,
    amoledMode: amoledMode ?? this.amoledMode,
    textScale: textScale ?? this.textScale,
    downloadSpeedLimitMbps:
        downloadSpeedLimitMbps ?? this.downloadSpeedLimitMbps,
    concurrentDownloads: concurrentDownloads ?? this.concurrentDownloads,
    autoGroupDownloads: autoGroupDownloads ?? this.autoGroupDownloads,
    groupNameFromSeries: groupNameFromSeries ?? this.groupNameFromSeries,
    groupNameTraditional: groupNameTraditional ?? this.groupNameTraditional,
    downloadPath: downloadPath ?? this.downloadPath,
    defaultPlaybackSpeed: defaultPlaybackSpeed ?? this.defaultPlaybackSpeed,
    playbackVolume: playbackVolume ?? this.playbackVolume,
    longPressPlaybackSpeed:
        longPressPlaybackSpeed ?? this.longPressPlaybackSpeed,
    playerControlsTimeoutSeconds:
        playerControlsTimeoutSeconds ?? this.playerControlsTimeoutSeconds,
    seekSensitivity: seekSensitivity ?? this.seekSensitivity,
    appLockEnabled: appLockEnabled ?? this.appLockEnabled,
    emergencyExitEnabled: emergencyExitEnabled ?? this.emergencyExitEnabled,
    hideFromRecents: hideFromRecents ?? this.hideFromRecents,
    commentsEnabled: commentsEnabled ?? this.commentsEnabled,
    blockedCommentKeywords:
        blockedCommentKeywords ?? this.blockedCommentKeywords,
    comicMode: comicMode ?? this.comicMode,
    previewSource: previewSource ?? this.previewSource,
    videoBaseUrl: videoBaseUrl ?? this.videoBaseUrl,
    useBuiltInHosts: useBuiltInHosts ?? this.useBuiltInHosts,
    useCustomMirrorSite: useCustomMirrorSite ?? this.useCustomMirrorSite,
    customMirrorSite: customMirrorSite ?? this.customMirrorSite,
    appendCustomMirrorPath:
        appendCustomMirrorPath ?? this.appendCustomMirrorPath,
    useAddressRanking: useAddressRanking ?? this.useAddressRanking,
    useDoh: useDoh ?? this.useDoh,
    dohPreset: dohPreset ?? this.dohPreset,
    dohCustomUrl: dohCustomUrl ?? this.dohCustomUrl,
    dohBootstrapIps: dohBootstrapIps ?? this.dohBootstrapIps,
    dohTimeoutSeconds: dohTimeoutSeconds ?? this.dohTimeoutSeconds,
    proxyMode: proxyMode ?? this.proxyMode,
    customProxy: customProxy ?? this.customProxy,
    useHorizontalSearchCards:
        useHorizontalSearchCards ?? this.useHorizontalSearchCards,
    searchCardsPerRow: searchCardsPerRow ?? this.searchCardsPerRow,
    useCompactSearchCards: useCompactSearchCards ?? this.useCompactSearchCards,
    expandHomeVideoCards: expandHomeVideoCards ?? this.expandHomeVideoCards,
    useNavigationDrawer: useNavigationDrawer ?? this.useNavigationDrawer,
    useSystemFont: useSystemFont ?? this.useSystemFont,
    useSystemTitleBar: useSystemTitleBar ?? this.useSystemTitleBar,
    openVideoInWindow: openVideoInWindow ?? this.openVideoInWindow,
    minimizeToTray: minimizeToTray ?? this.minimizeToTray,
    globalHotkeysEnabled: globalHotkeysEnabled ?? this.globalHotkeysEnabled,
    hotkeyBindings: hotkeyBindings ?? this.hotkeyBindings,
    hotkeyDefaultsMigrated:
        hotkeyDefaultsMigrated ?? this.hotkeyDefaultsMigrated,
    windowBackdrop: windowBackdrop ?? this.windowBackdrop,
    glassSurfaceEnabled: glassSurfaceEnabled ?? this.glassSurfaceEnabled,
    glassMaterial: glassMaterial ?? this.glassMaterial,
    glassTint: glassTint ?? this.glassTint,
    glassRipple: glassRipple ?? this.glassRipple,
    glassRendering: glassRendering ?? this.glassRendering,
    glassContrast: glassContrast ?? this.glassContrast,
    notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
    gpuApi: gpuApi ?? this.gpuApi,
    localMediaDirectory: localMediaDirectory ?? this.localMediaDirectory,
    dlnaReceiverEnabled: dlnaReceiverEnabled ?? this.dlnaReceiverEnabled,
    useHomeCategoryTabs: useHomeCategoryTabs ?? this.useHomeCategoryTabs,
    homeQuickCategories: homeQuickCategories ?? this.homeQuickCategories,
    blockedVideoTitleKeywords:
        blockedVideoTitleKeywords ?? this.blockedVideoTitleKeywords,
    blockedAuthors: blockedAuthors ?? this.blockedAuthors,
    blockedVideoTags: blockedVideoTags ?? this.blockedVideoTags,
    minimumVideoDurationSeconds:
        minimumVideoDurationSeconds ?? this.minimumVideoDurationSeconds,
    minimumVideoViews: minimumVideoViews ?? this.minimumVideoViews,
    exemptSubscribedAuthors:
        exemptSubscribedAuthors ?? this.exemptSubscribedAuthors,
    applyRecommendationFiltersToRelated:
        applyRecommendationFiltersToRelated ??
        this.applyRecommendationFiltersToRelated,
    applyRecommendationFiltersToSearch:
        applyRecommendationFiltersToSearch ??
        this.applyRecommendationFiltersToSearch,
    blockedCommentUsers: blockedCommentUsers ?? this.blockedCommentUsers,
    incognitoPlayback: incognitoPlayback ?? this.incognitoPlayback,
    autoPlayNext: autoPlayNext ?? this.autoPlayNext,
    loopPlayback: loopPlayback ?? this.loopPlayback,
    autoPictureInPicture: autoPictureInPicture ?? this.autoPictureInPicture,
    videoAspectRatio: videoAspectRatio ?? this.videoAspectRatio,
    skipSeconds: skipSeconds ?? this.skipSeconds,
    webDavEnabled: webDavEnabled ?? this.webDavEnabled,
    webDavHistorySync: webDavHistorySync ?? this.webDavHistorySync,
    webDavFavoriteSync: webDavFavoriteSync ?? this.webDavFavoriteSync,
    webDavUrl: webDavUrl ?? this.webDavUrl,
    webDavUsername: webDavUsername ?? this.webDavUsername,
    webDavPassword: webDavPassword ?? this.webDavPassword,
  );
}

class SettingsStore {
  SettingsStore(this._store);
  final JsonStore _store;
  static const _fileName = 'setting.json';

  Future<AppSettings> load() async {
    final settings = AppSettings.fromJson(await _store.read(_fileName));
    final downloadPath = await normalizeDownloadPath(settings.downloadPath);
    if (downloadPath == settings.downloadPath) return settings;
    final normalized = settings.copyWith(downloadPath: downloadPath);
    await save(normalized);
    return normalized;
  }

  Future<void> save(AppSettings value) async =>
      _store.write(_fileName, value.toJson());
}
