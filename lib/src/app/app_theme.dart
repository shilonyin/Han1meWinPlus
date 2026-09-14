import 'package:flutter/material.dart';

import '../core/settings.dart';

ThemeData appTheme(ColorScheme? dynamicScheme, Color seedColor, {Brightness brightness = Brightness.light, bool amoled = false, bool useSystemFont = false}) {
  var scheme = dynamicScheme ?? ColorScheme.fromSeed(seedColor: seedColor, brightness: brightness);
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
    // 默认用内置 MiSans；系统字体开关打开时交回平台默认字体。
    // fallback 用于 MiSans 没有的字符（emoji、生僻字）与彩色 emoji。
    fontFamily: useSystemFont ? null : 'MiSans',
    fontFamilyFallback: useSystemFont ? null : const ['Microsoft YaHei UI', 'Segoe UI Emoji', 'Segoe UI Symbol'],
    scaffoldBackgroundColor: amoled ? Colors.black : null,
    canvasColor: amoled ? Colors.black : null,
    // M3 tints the app bar with the primary colour once content scrolls under
    // it, which stands out badly against the flat/AMOLED surfaces this app uses.
    // Keep the bar the same colour as the page.
    appBarTheme: AppBarTheme(backgroundColor: scheme.surface, surfaceTintColor: Colors.transparent, scrolledUnderElevation: 0),
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
        AppThemeColor.custom => Color(int.parse('ff$customColor', radix: 16)),
      };
}
