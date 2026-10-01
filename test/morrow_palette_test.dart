import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

void main() {
  group('morrow 紫调配色', () {
    test('默认紫色主题的种子是 morrow 品牌紫 #7662ba', () {
      expect(AppThemeColor.purple.seedColor('62539F'), const Color(0xff7662ba));
    });

    test('淡染中性面：中性色朝主色插值，不是纯灰', () {
      final theme = appTheme(null, const Color(0xff7662ba));
      final scheme = theme.colorScheme;

      // 正文色本应是 #302d43，插值后带上紫，不再等于原色。
      expect(scheme.onSurface, isNot(const Color(0xff302d43)));
      // 但必须仍是深色（可读性不能被染色破坏）。
      expect(scheme.onSurface.computeLuminance(), lessThan(0.1));
      // 卡片面比背景亮一档：层级靠明度差区分。
      expect(
        scheme.surface.computeLuminance(),
        greaterThan(scheme.surfaceContainerHighest.computeLuminance()),
      );
    });

    test('分隔线压到 7.5% 不透明度（亮色）/ 13%（暗色）', () {
      final light = appTheme(null, const Color(0xff7662ba)).colorScheme;
      final dark = appTheme(
        null,
        const Color(0xff7662ba),
        brightness: Brightness.dark,
      ).colorScheme;

      expect(light.outlineVariant.a, closeTo(.075, .005));
      expect(dark.outlineVariant.a, closeTo(.13, .005));
    });

    test('暗色中性面同样是紫调深色，而不是纯黑', () {
      final scheme = appTheme(
        null,
        const Color(0xff7662ba),
        brightness: Brightness.dark,
      ).colorScheme;

      expect(scheme.onSurface.computeLuminance(), greaterThan(0.7));
      expect(scheme.surfaceContainerLowest.computeLuminance(), lessThan(0.1));
      // 纯黑会让紫调消失，这里必须带色相。
      expect(scheme.surfaceContainerLowest, isNot(Colors.black));
    });

    test('换主题色时中性面跟着走，不会紫底配蓝强调', () {
      final violet = appTheme(null, const Color(0xff7662ba)).colorScheme;
      final blue = appTheme(null, const Color(0xff00639b)).colorScheme;

      // 同一档中性面在两个种子下必须给出不同结果，说明染色确实跟主色走。
      expect(violet.surface, isNot(blue.surface));
    });

    test('neutralSurfaces: true 时保留纯中性面（播放页 / 自绘标题栏用）', () {
      final scheme = appTheme(
        null,
        AppThemeColor.white.seedColor(''),
        neutralSurfaces: true,
      ).colorScheme;

      expect(scheme.surface, const Color(0xffffffff));
      expect(scheme.surfaceContainerLow, const Color(0xfff6f7f8));
    });

    test('白色主题的底不再死白，自动带品牌色倾向（自动沉浸）', () {
      // 白色主题现在也走淡染：底色朝品牌色插值，和背景画布连成一片。
      final scheme = appTheme(
        null,
        AppThemeColor.white.seedColor(''),
      ).colorScheme;

      expect(scheme.surface, isNot(const Color(0xffffffff)));
      // 但仍要够亮 —— 它是「白底」主题，不能被染成灰。
      // 实测约 0.89（#F6F0F2 那种淡粉白）：比纯白略沉，仍是明显的浅色底。
      expect(scheme.surface.computeLuminance(), greaterThan(.85));
    });

    test('浮窗带投影且不压暗背景（遮罩透明由 showAppDialog 负责）', () {
      final theme = appTheme(null, const Color(0xff7662ba));
      expect(theme.dialogTheme.elevation, greaterThan(0));
      expect(theme.popupMenuTheme.elevation, greaterThan(0));
      expect(theme.bottomSheetTheme.elevation, greaterThan(0));
      // 卡片仍然零海拔：列表里的卡片不该浮起来。
      expect(theme.cardTheme.elevation, 0);
    });

    test('卡片与弹层统一大圆角、零海拔', () {
      final theme = appTheme(null, const Color(0xff7662ba));
      expect(theme.cardTheme.elevation, 0);
      final shape = theme.cardTheme.shape! as RoundedRectangleBorder;
      expect(
        shape.borderRadius,
        BorderRadius.circular(18),
      );
    });

    test('AMOLED 保留卡片层次，不再把六层 surface 全压成黑', () {
      final scheme = appTheme(
        null,
        const Color(0xff7662ba),
        brightness: Brightness.dark,
        amoled: true,
      ).colorScheme;

      // 底色与最低层仍是纯黑 —— AMOLED 的省电语义不变。
      expect(scheme.surface, Colors.black);
      expect(scheme.surfaceContainerLowest, Colors.black);
      // 但靠上的容器必须有明度差，否则卡片和背景同为黑、分组边界消失。
      expect(scheme.surfaceContainerHigh.computeLuminance(), greaterThan(0));
      expect(
        scheme.surfaceContainerHighest.computeLuminance(),
        greaterThan(scheme.surfaceContainerLow.computeLuminance()),
      );
      // 纯黑仍占绝大多数面积：最高层也必须很暗，不能变成普通深灰。
      expect(scheme.surfaceContainerHighest.computeLuminance(), lessThan(.05));
    });

    test('深色中性面不用纯黑，保住卡片与画布的层次', () {
      final scheme = appTheme(
        null,
        const Color(0xff7662ba),
        brightness: Brightness.dark,
      ).colorScheme;

      // morrow 的深色是「底色 #181720 / 卡片 #292634」，两者都明显亮于纯黑。
      expect(scheme.surfaceContainerLowest, isNot(Colors.black));
      expect(scheme.surface.computeLuminance(), greaterThan(0.01));
      expect(
        scheme.surface.computeLuminance(),
        greaterThan(scheme.surfaceContainerLowest.computeLuminance()),
      );
    });
  });
}
