import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

/// 系统托盘：常驻图标 +「显示窗口 / 退出」菜单。
///
/// 与 [WindowChrome] 一样做成静态门面。开启后（设置 `minimizeToTray`），
/// 关闭按钮——应用内标题栏与系统标题栏走的是同一条 WM_CLOSE 路径——
/// 只把窗口收进托盘而不退出；真正退出走托盘菜单的「退出」。
///
/// 菜单文案在 [setEnabled] 时传入（本地化语言运行中可切换，语言变化时
/// 调用方应携带新文案重新调用，实现上用「销毁重建」最省事）。
class SystemTray with WindowListener {
  SystemTray._();

  static final SystemTray _instance = SystemTray._();

  /// tray_manager 只出桌面实现；与本仓库定位一致，非桌面端一律空操作。
  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 托盘图标要长期存活（Dart 侧对象被回收会连带释放原生句柄、图标消失），所以静态持有。
  static TrayIcon? _trayIcon;

  /// WindowListener 只注册一次，开关托盘不反复增删。
  static bool _listenerBound = false;

  static Future<void> setEnabled(
    bool enabled, {
    required String tooltip,
    required String showLabel,
    required String exitLabel,
  }) async {
    if (!isSupported) return;
    try {
      await windowManager.ensureInitialized();
      if (enabled) {
        // 拦截 WM_CLOSE：两条关闭路径（应用内标题栏按钮 / 系统 X）都只收进托盘。
        await windowManager.setPreventClose(true);
        if (!_listenerBound) {
          windowManager.addListener(_instance);
          _listenerBound = true;
        }
        await _destroy();
        final icon = TrayIcon.create();
        if (icon == null) return;
        _trayIcon = icon;
        icon.icon = ImageAsset.fromAsset('assets/logo.png');
        icon.setTooltip(tooltip);
        // 双击托盘图标直接恢复窗口；单击右键由系统弹出菜单。
        icon.addListener((event) {
          if (event is TrayIconDoubleClickedEvent) restoreWindow();
        });
        final menu = Menu.create();
        if (menu == null) {
          await _destroy();
          return;
        }
        final showItem = MenuItem.createWithLabelAndType(showLabel, MenuItemType.normal);
        if (showItem != null) {
          showItem.addListener((event) {
            if (event is MenuItemClickedEvent) restoreWindow();
          });
          menu.addItem(showItem);
        }
        menu.addSeparator();
        final exitItem = MenuItem.createWithLabelAndType(exitLabel, MenuItemType.normal);
        if (exitItem != null) {
          exitItem.addListener((event) {
            if (event is MenuItemClickedEvent) exitApp();
          });
          menu.addItem(exitItem);
        }
        icon.setContextMenu(menu);
        icon.setVisible(true);
      } else {
        await windowManager.setPreventClose(false);
        if (_listenerBound) {
          windowManager.removeListener(_instance);
          _listenerBound = false;
        }
        await _destroy();
      }
    } catch (error) {
      debugPrint('[tray] setEnabled failed: $error');
    }
  }

  static Future<void> _destroy() async {
    try {
      _trayIcon?.dispose();
    } catch (error) {
      debugPrint('[tray] dispose failed: $error');
    }
    _trayIcon = null;
  }

  /// 双击托盘图标 / 托盘菜单「显示窗口」。
  static Future<void> restoreWindow() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (error) {
      debugPrint('[tray] restore failed: $error');
    }
  }

  /// 托盘菜单「退出」：destroy 绕过 preventClose，是真正的退出路径。
  static Future<void> exitApp() async {
    await _destroy();
    await windowManager.destroy();
  }

  @override
  void onWindowClose() {
    // preventClose 拦下 WM_CLOSE 后回调到这里：托盘模式下关闭即隐藏。
    unawaited(windowManager.hide());
  }
}
