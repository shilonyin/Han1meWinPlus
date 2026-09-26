import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/foundation.dart';

/// 系统级悬浮窗：把播放页弹成**独立窗口**，可独立置顶、拖动、缩放。
///
/// 每个副窗口跑一套自己的 Flutter 引擎（desktop_multi_window），所以：
/// - 副窗口里播放的是**另一个播放器实例**，跟主窗口各自独立，不共享进度；
/// - 插件要按窗口注册，Windows runner 里已挂 `DesktopMultiWindowSetWindowCreatedCallback`；
/// - 窗口自身的尺寸 / 置顶由副窗口引擎里的 window_manager 设置（见 [FloatingWindowApp]）。
class FloatingWindow {
  FloatingWindow._();

  /// 副窗口的 arguments 前缀：主窗口启动时靠它判断自己是不是被弹出来的那个。
  static const argumentPrefix = 'floating:';

  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  /// 从 arguments 里取出视频 id；不是悬浮窗则返回 null。
  static String? videoIdFromArguments(String? arguments) {
    if (arguments == null || !arguments.startsWith(argumentPrefix)) return null;
    final id = arguments.substring(argumentPrefix.length);
    return id.isEmpty ? null : id;
  }

  static Future<void> open(String videoId) async {
    if (!isSupported || videoId.isEmpty) return;
    try {
      // 先隐藏创建，等副窗口引擎把自己收拾好（尺寸、置顶、无标题栏）再显示，
      // 避免闪一下标准窗口。
      final controller = await WindowController.create(
        WindowConfiguration(hiddenAtLaunch: true, arguments: '$argumentPrefix$videoId'),
      );
      await controller.show();
    } catch (error) {
      debugPrint('[floating] open failed: $error');
    }
  }
}
