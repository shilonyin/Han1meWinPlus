// 回归测试：窗口材质的深浅必须由「实际生效的主题」推导，而不是读 Theme.of(context)。
//
// 背景（用户报的「主题色异常」）：开启 AMOLED 后点击主题模式切换，最左侧侧栏与顶部
// 标题栏整片发灰，正常应是第三张图那种浅粉白。
//
// 根因：startup_effects 的 _applyWindowBackdrop 在 settingsProvider 的回调里同步读
// Theme.of(context)。provider 回调早于 widget 重建，那时 Theme 还是切换前的亮度——
// 从深色切回浅色时把 Mica 留在了深色上；浅色主题的表面是半透明的（app_theme 的
// transparent 分支），盖在深色材质上就整片发灰。标题栏与侧栏最明显，因为它们是
// 半透明表面、底下直接就是材质。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

void main() {
  group('effectiveBrightness 由设置与系统亮度推导，不依赖重建时序', () {
    test('浅色：无论系统什么亮度都是 light', () {
      const settings = AppSettings(themeMode: AppThemeMode.light);
      expect(
        settings.effectiveBrightness(Brightness.dark),
        Brightness.light,
      );
      expect(
        settings.effectiveBrightness(Brightness.light),
        Brightness.light,
      );
    });

    test('深色：无论系统什么亮度都是 dark', () {
      const settings = AppSettings(themeMode: AppThemeMode.dark);
      expect(settings.effectiveBrightness(Brightness.light), Brightness.dark);
      expect(settings.effectiveBrightness(Brightness.dark), Brightness.dark);
    });

    test('跟随系统：跟系统亮度走', () {
      const settings = AppSettings(themeMode: AppThemeMode.system);
      expect(settings.effectiveBrightness(Brightness.light), Brightness.light);
      expect(settings.effectiveBrightness(Brightness.dark), Brightness.dark);
    });

    test('与 materialThemeMode 一一对应（同一份设置不能给出两种结论）', () {
      for (final mode in AppThemeMode.values) {
        final settings = AppSettings(themeMode: mode);
        final fromThemeMode = switch (settings.materialThemeMode) {
          ThemeMode.light => Brightness.light,
          ThemeMode.dark => Brightness.dark,
          // system 交给系统亮度
          ThemeMode.system => Brightness.dark,
        };
        expect(
          settings.effectiveBrightness(Brightness.dark),
          fromThemeMode,
          reason: 'themeMode=${mode.name}',
        );
      }
    });
  });

  group('AMOLED 只作用于深色主题', () {
    // app_theme 里 amoled 只传给 darkTheme；浅色主题下开 AMOLED 不该改变任何颜色。
    // 侧栏曾用裸的 amoledMode 判断，浅色下会把底色换成 4% 白——开了窗口材质时
    // 几乎全透明，直接透出材质，看着就是「侧栏发灰、和内容区不是一套」。
    test('浅色主题下 amoled 开关不改变明暗推导', () {
      const off = AppSettings(themeMode: AppThemeMode.light);
      const on = AppSettings(themeMode: AppThemeMode.light, amoledMode: true);
      expect(
        on.effectiveBrightness(Brightness.light),
        off.effectiveBrightness(Brightness.light),
      );
      expect(on.effectiveBrightness(Brightness.light), Brightness.light);
    });

    test('深色主题 + AMOLED 仍是 dark（材质要给系统下深色）', () {
      const settings = AppSettings(
        themeMode: AppThemeMode.dark,
        amoledMode: true,
      );
      expect(settings.effectiveBrightness(Brightness.light), Brightness.dark);
    });
  });
}
