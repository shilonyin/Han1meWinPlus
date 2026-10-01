import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import '../core/settings.dart';

/// 页面跳转过渡：淡入 + 极小的上浮。
///
/// 桌面端默认用的是 `ZoomPageTransitionsBuilder`（整页从 0.85 缩放进场），切换时
/// 大块内容“弹”一下，和这个以卡片/列表为主、配色平滑的界面不搭；这里改成以淡入为主、
/// 位移只做点缀，和主题切换（320ms easeInOut）的平滑感保持一致。
class _AppPageTransitionsBuilder extends PageTransitionsBuilder {
  const _AppPageTransitionsBuilder();

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
    final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
    return FadeTransition(
      opacity: curve,
      child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, 0.015), end: Offset.zero).animate(curve), child: child),
    );
  }
}

/// 只替换桌面平台的过渡：Android 保持 PredictiveBack、iOS/macOS 保持 Cupertino（含边缘返回手势），
/// 都跟 Flutter 自带默认值一致，避免影响移动端。
const _pageTransitionsTheme = PageTransitionsTheme(
  builders: {
    TargetPlatform.android: PredictiveBackPageTransitionsBuilder(),
    TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.fuchsia: ZoomPageTransitionsBuilder(),
    TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
    TargetPlatform.linux: _AppPageTransitionsBuilder(),
    TargetPlatform.windows: _AppPageTransitionsBuilder(),
  },
);

/// 开启窗口材质后界面要"透"：系统材质画在窗口底下，表面不透明就全被盖住。
///
/// 透明度按 M3 的海拔层次递进——越靠前的容器越不透明，材质只在最底层明显，
/// 这样层级关系还能看出来，不至于整片糊成一团。
const double _surfaceAlpha = .70;
const double _surfaceContainerLowestAlpha = .55;
const double _surfaceContainerLowAlpha = .62;
const double _surfaceContainerAlpha = .70;
const double _surfaceContainerHighAlpha = .78;
const double _surfaceContainerHighestAlpha = .86;

/// 全局图标轴：把 Material Symbols 统一到「线性描边 + 常规字重」。
///
/// 这四条是 `material_symbols_icons` 暴露的可变字体轴，只有 Material Symbols 字体会读，
/// Material 内置图标（MD3 组件内部的下拉箭头、SnackBar 关闭钮等）会忽略——两者共存无冲突。
///
/// - `fill: 0` 线性描边（选中/激活态在调用处显式给 `fill: 1`）
/// - `weight: 400` 与正文的常规字重对齐
/// - `opticalSize: 48` 与界面里图标的主流字号一致
/// - 深色下细线条会发糊，把 `grade` 压到 -25 提清晰度（浅色保持 0）
IconThemeData _iconTheme(Brightness brightness) => IconThemeData(
  fill: 0,
  weight: 400,
  grade: brightness == Brightness.dark ? -25 : 0,
  opticalSize: 48,
);

ThemeData appTheme(ColorScheme? dynamicScheme, Color seedColor, {Brightness brightness = Brightness.light, bool amoled = false, bool useSystemFont = false, DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot, bool neutralSurfaces = false, WindowBackdrop backdrop = WindowBackdrop.none}) {
  var scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness, dynamicSchemeVariant: variant);
  // white 主题是刻意的「白底 + 中性灰」，保持它自己的中性面；
  // 其余主题走 morrow（明隙）式淡染，中性面带上主色倾向。
  if (neutralSurfaces) {
    scheme = _neutralSurfaces(scheme, brightness);
  } else {
    scheme = _tintedSurfaces(scheme, brightness);
  }
  // AMOLED 是纯黑，跟材质叠不出效果，以纯黑为准。
  final transparent = backdrop != WindowBackdrop.none && !amoled;
  if (transparent) {
    scheme = scheme.copyWith(
      surface: scheme.surface.withValues(alpha: _surfaceAlpha),
      surfaceContainerLowest: scheme.surfaceContainerLowest.withValues(alpha: _surfaceContainerLowestAlpha),
      surfaceContainerLow: scheme.surfaceContainerLow.withValues(alpha: _surfaceContainerLowAlpha),
      surfaceContainer: scheme.surfaceContainer.withValues(alpha: _surfaceContainerAlpha),
      surfaceContainerHigh: scheme.surfaceContainerHigh.withValues(alpha: _surfaceContainerHighAlpha),
      surfaceContainerHighest: scheme.surfaceContainerHighest.withValues(alpha: _surfaceContainerHighestAlpha),
    );
  }
  if (amoled) {
    // AMOLED 的语义是「大面积纯黑省电」，但**不能把六层 surface 全压成黑**：
    // 卡片和底色同色之后，设置页整片糊成一块，连分组边界都看不出来（morrow 的
    // 深色恰恰是底色 #181720、卡片 #292634 的明度差）。
    // 这里底色保持纯黑，靠上的容器给一档极暗的主色灰把层次留住——
    // 纯黑仍然占绝大多数面积，省电意图不受影响。
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Color.lerp(Colors.black, scheme.primary, .05)!,
      surfaceContainer: Color.lerp(Colors.black, scheme.primary, .08)!,
      surfaceContainerHigh: Color.lerp(Colors.black, scheme.primary, .12)!,
      surfaceContainerHighest: Color.lerp(Colors.black, scheme.primary, .16)!,
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    iconTheme: _iconTheme(brightness),
    // 默认用内置 HarmonyOS Sans SC（可变字体，单文件自带 9 档字重）；
    // 系统字体开关打开时交回平台默认字体。
    // fallback 用于该字体没有的字符（emoji、生僻字）与彩色 emoji。
    fontFamily: useSystemFont ? null : 'HarmonyOS Sans SC',
    fontFamilyFallback: useSystemFont ? null : const ['Microsoft YaHei UI', 'Segoe UI Emoji', 'Segoe UI Symbol'],
    // 背景画布（AppBackdrop）铺在应用最底层，Scaffold 必须让出底色才能露出渐变。
    // AMOLED 例外：它要的就是纯黑，画布也一并关掉。
    scaffoldBackgroundColor: amoled ? Colors.black : Colors.transparent,
    canvasColor: amoled ? Colors.black : null,
    // M3 tints the app bar with the primary colour once content scrolls under
    // it, which stands out badly against the flat/AMOLED surfaces this app uses.
    // Keep the bar the same colour as the page.
    // 页面背景已经统一交给 AppBackdrop（Scaffold 是透明的），所以 AppBar 也必须透明：
    // 只要它铺自己的底色，顶部就会横出一条和下面内容不同色的实色条。
    // 原来只有"开着窗口材质"时才透明，关掉材质就露馅（用户看到的「右侧顶部出问题」）。
    appBarTheme: AppBarTheme(backgroundColor: Colors.transparent, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    pageTransitionsTheme: _pageTransitionsTheme,
    // 贴底的通栏 SnackBar 在这个布局里显得很重，改成半透明浮动圆角。
    // 它是浮起来的，同样给一层投影 —— 否则在半透明卡片上像贴纸。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      elevation: 4,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: const SliderThemeData(year2023: false),
    // 参考 morrow：卡片一律大圆角、零海拔——层级靠淡染底色和圆角区分，
    // 不靠投影，避免在磨砂/透明窗口上叠出一圈灰边。
    cardTheme: CardThemeData(
      elevation: 0,
      color: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      margin: EdgeInsets.zero,
    ),
    // 浮窗必须自己带投影：遮罩已经是全透明的（见 `showAppDialog`），背景不再变暗，
    // 全靠这层阴影把浮窗从页面上托起来。阴影色用主色偏灰（照 morrow），
    // 压在浅色画布上不会发脏；深色下仍用纯黑。
    dialogTheme: DialogThemeData(
      elevation: 10,
      shadowColor: _dialogShadow(scheme),
      backgroundColor: scheme.surface,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
    ),
    popupMenuTheme: PopupMenuThemeData(
      elevation: 6,
      shadowColor: _dialogShadow(scheme),
      color: scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    // 底部弹层同理：它也是浮起来的，需要自己的投影。
    bottomSheetTheme: BottomSheetThemeData(
      elevation: 8,
      shadowColor: _dialogShadow(scheme),
      surfaceTintColor: Colors.transparent,
    ),
  );
}

/// 浮窗投影的颜色。
Color _dialogShadow(ColorScheme scheme) => scheme.brightness == Brightness.light
    ? Color.lerp(Colors.black, scheme.primary, .45)!
    : Colors.black;

extension AppThemeColorSeed on AppThemeColor {
  Color seedColor(String customColor) => switch (this) {
        AppThemeColor.rose => const Color(0xffb3265a),
        AppThemeColor.blue => const Color(0xff00639b),
        AppThemeColor.teal => const Color(0xff006b5f),
        AppThemeColor.amber => const Color(0xff875400),
        AppThemeColor.green => const Color(0xff386a20),
        AppThemeColor.orange => const Color(0xff9b4400),
        AppThemeColor.indigo => const Color(0xff4a5f9e),
        AppThemeColor.pink => const Color(0xff9c3c66),
        // morrow（明隙）的品牌紫。中性面会朝它插值 8%，整套界面因此带紫调。
        AppThemeColor.purple => const Color(0xff7662ba),
        // 「白色」= 白底 + 一抹品牌粉（参考 bilibili），种子取 b 站粉 #FB7299，
        // 配合 [schemeVariant] 的 fidelity 变体：主色就是这抹粉，中性面保持接近纯白。
        // 注意：**不能拿纯白当种子** —— HCT 色度为 0 时 Material 会回退到色相 192（青），
        // 整套界面会变成青色（`ColorScheme.fromSeed(Color(0xffffffff)).primary` = #006874）。
        AppThemeColor.white => const Color(0xfffb7299),
        AppThemeColor.custom => Color(int.parse('ff$customColor', radix: 16)),
      };

  /// 配色变体：白色主题用 fidelity（主色忠于种子、中性面近白），其余走默认 tonalSpot。
  DynamicSchemeVariant get schemeVariant => this == AppThemeColor.white ? DynamicSchemeVariant.fidelity : DynamicSchemeVariant.tonalSpot;

  /// 是否把中性面换成中性灰（参考 bilibili 的「白底 + 浅灰卡片」）。
  ///
  /// 现在恒为 `false`：白色主题的底不再走「死白 + 灰卡片」，
  /// 而是和其他主题一样走淡染 —— 底色自动带上品牌色的极淡倾向，
  /// 和背景画布连成一片（即"自动沉浸"）。
  /// 真正需要纯中性面的场景（播放页、自绘标题栏）直接给 `appTheme(neutralSurfaces: true)`。
  bool get neutralSurfaces => false;

  /// 色板上那个圆的颜色：白色主题画白底（它的粉只体现在高亮色上）。
  Color swatchColor(String customColor) => this == AppThemeColor.white ? const Color(0xffffffff) : seedColor(customColor);
}

/// morrow（明隙）式淡染中性面。
///
/// `ColorScheme.fromSeed` 给出的中性色是**纯灰**——背景、卡片、文字都不带一点主色，
/// 再配上 M3 默认的 outline 对比度，卡片之间的分隔线显得很硬，整体偏"标准 Material"。
///
/// 这里照 morrow 的做法重组中性面：
/// - 每个中性色朝**强调色插值 8%**，得到带主色倾向的柔和底色（紫主题下就是"紫白"）；
/// - 分隔线压到 7.5%（暗色 13%）不透明度，几乎看不见，改用明度层次分区；
/// - 卡片面比背景亮一档，靠明度差而不是描边区分层级。
///
/// 插值比例与 morrow `Palette.themeTint` 的默认值一致（.08）。
const _tintAmount = .08;

ColorScheme _tintedSurfaces(ColorScheme scheme, Brightness brightness) {
  Color tint(Color base) => Color.lerp(base, scheme.primary, _tintAmount)!;

  if (brightness == Brightness.light) {
    final ink = tint(const Color(0xff302d43));
    return scheme.copyWith(
      // 中性面：从最亮的卡片白到最沉的容器灰，整条链都带一丝主色。
      surface: tint(Colors.white),
      surfaceContainerLowest: tint(const Color(0xfff9f8fc)),
      surfaceContainerLow: tint(const Color(0xfff4f3f9)),
      surfaceContainer: tint(const Color(0xffefeef6)),
      surfaceContainerHigh: tint(const Color(0xffeae9f2)),
      surfaceContainerHighest: tint(const Color(0xffe5e4ef)),
      onSurface: ink,
      onSurfaceVariant: tint(const Color(0xff777184)),
      // 描边整体降一档，真正的分区交给明度差。
      outline: tint(const Color(0xffb0aebe)),
      outlineVariant: ink.withValues(alpha: .075),
      // 次要容器跟中性面同调，避免 M3 默认的灰蓝容器跳出来。
      secondaryContainer: tint(const Color(0xffefeef6)),
      onSecondaryContainer: ink,
      surfaceTint: Colors.transparent,
    );
  }
  final ink = tint(const Color(0xfff0edf8));
  return scheme.copyWith(
    surface: tint(const Color(0xff292634)),
    surfaceContainerLowest: tint(const Color(0xff181720)),
    surfaceContainerLow: tint(const Color(0xff1f1d28)),
    surfaceContainer: tint(const Color(0xff24222e)),
    surfaceContainerHigh: tint(const Color(0xff2a2735)),
    surfaceContainerHighest: tint(const Color(0xff302d3c)),
    onSurface: ink,
    onSurfaceVariant: tint(const Color(0xffb4aec5)),
    outline: tint(const Color(0xff5a5766)),
    outlineVariant: ink.withValues(alpha: .13),
    secondaryContainer: tint(const Color(0xff2a2735)),
    onSecondaryContainer: ink,
    surfaceTint: Colors.transparent,
  );
}

/// 「白底 + 灰卡片 + 品牌色点缀」的中性面（参考 bilibili）。
///
/// fidelity 变体虽然让主色忠于种子，但会把 surface 系列一并染上种子的淡粉；
/// 这里把中性角色换成固定灰阶，只留 primary / secondary 等强调色是品牌色。
ColorScheme _neutralSurfaces(ColorScheme scheme, Brightness brightness) => brightness == Brightness.light
    ? scheme.copyWith(
        surface: const Color(0xffffffff),
        surfaceContainerLowest: const Color(0xffffffff),
        surfaceContainerLow: const Color(0xfff6f7f8),
        surfaceContainer: const Color(0xfff1f2f3),
        surfaceContainerHigh: const Color(0xffecedee),
        surfaceContainerHighest: const Color(0xffe7e8ea),
        onSurface: const Color(0xff18191c),
        onSurfaceVariant: const Color(0xff61666d),
        outline: const Color(0xffc9ccd0),
        outlineVariant: const Color(0xffe3e5e7),
        secondaryContainer: const Color(0xfff1f2f3),
        onSecondaryContainer: const Color(0xff18191c),
      )
    : scheme.copyWith(
        surface: const Color(0xff17181a),
        surfaceContainerLowest: const Color(0xff101113),
        surfaceContainerLow: const Color(0xff1e1f21),
        surfaceContainer: const Color(0xff242527),
        surfaceContainerHigh: const Color(0xff2a2b2e),
        surfaceContainerHighest: const Color(0xff303134),
        onSurface: const Color(0xffe5e7eb),
        onSurfaceVariant: const Color(0xffa2a6ad),
        outline: const Color(0xff5a5d63),
        outlineVariant: const Color(0xff3a3c40),
        secondaryContainer: const Color(0xff2a2b2e),
        onSecondaryContainer: const Color(0xffe5e7eb),
      );
