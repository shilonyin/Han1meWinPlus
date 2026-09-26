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

ThemeData appTheme(ColorScheme? dynamicScheme, Color seedColor, {Brightness brightness = Brightness.light, bool amoled = false, bool useSystemFont = false, DynamicSchemeVariant variant = DynamicSchemeVariant.tonalSpot, bool neutralSurfaces = false, WindowBackdrop backdrop = WindowBackdrop.none}) {
  var scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness, dynamicSchemeVariant: variant);
  if (neutralSurfaces) scheme = _neutralSurfaces(scheme, brightness);
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
    scheme = scheme.copyWith(
      surface: Colors.black,
      surfaceContainerLowest: Colors.black,
      surfaceContainerLow: Colors.black,
      surfaceContainer: Colors.black,
      surfaceContainerHigh: Colors.black,
      surfaceContainerHighest: Colors.black,
    );
  }
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    // 默认用内置 HarmonyOS Sans SC（可变字体，单文件自带 9 档字重）；
    // 系统字体开关打开时交回平台默认字体。
    // fallback 用于该字体没有的字符（emoji、生僻字）与彩色 emoji。
    fontFamily: useSystemFont ? null : 'HarmonyOS Sans SC',
    fontFamilyFallback: useSystemFont ? null : const ['Microsoft YaHei UI', 'Segoe UI Emoji', 'Segoe UI Symbol'],
    scaffoldBackgroundColor: amoled ? Colors.black : null,
    canvasColor: amoled ? Colors.black : null,
    // M3 tints the app bar with the primary colour once content scrolls under
    // it, which stands out badly against the flat/AMOLED surfaces this app uses.
    // Keep the bar the same colour as the page.
    // 开了窗口材质时标题栏也留空，让壁纸色一路透上来。
    appBarTheme: AppBarTheme(backgroundColor: transparent ? Colors.transparent : scheme.surface, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
    pageTransitionsTheme: _pageTransitionsTheme,
    // 贴底的通栏 SnackBar 在这个布局里显得很重，改成半透明浮动圆角。
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.92),
      contentTextStyle: TextStyle(color: scheme.onSurface),
      actionTextColor: scheme.primary,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
    ),
    sliderTheme: const SliderThemeData(year2023: false),
  );
}

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
        AppThemeColor.purple => const Color(0xff6d3f90),
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
  bool get neutralSurfaces => this == AppThemeColor.white;

  /// 色板上那个圆的颜色：白色主题画白底（它的粉只体现在高亮色上）。
  Color swatchColor(String customColor) => this == AppThemeColor.white ? const Color(0xffffffff) : seedColor(customColor);
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
