import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';

/// Windows Toast 通知。
///
/// 只做「应用外可感知」的提醒：下载完成、更新可用。应用在前台时界面里本来就有
/// 对应提示，所以更新那条只在窗口未聚焦时才弹（见 `startup_effects`）。
///
/// 文案由 UI 层注入（[NotificationTexts]）：数据层（下载仓库）触发通知时
/// 没有 context，拿不到本地化实例。
class AppNotifications {
  AppNotifications._();

  static bool get isSupported => Platform.isWindows || Platform.isMacOS || Platform.isLinux;

  static bool enabled = true;
  static NotificationTexts? texts;

  static bool _setupDone = false;

  static Future<void> ensureInitialized() async {
    if (!isSupported || _setupDone) return;
    try {
      await localNotifier.setup(appName: 'Han1meWinPlus', shortcutPolicy: ShortcutPolicy.requireCreate);
      _setupDone = true;
    } catch (error) {
      debugPrint('[notify] setup failed: $error');
    }
  }

  static Future<void> show({required String title, required String body, VoidCallback? onClick}) async {
    if (!isSupported || !enabled) return;
    await ensureInitialized();
    try {
      final notification = LocalNotification(title: title, body: body);
      // 点击通知先把窗口唤回来：通知本身不带路由信息，跳转交给界面自己处理。
      notification.onClick = () {
        onClick?.call();
        unawaited(_bringWindowUp());
      };
      await notification.show();
    } catch (error) {
      debugPrint('[notify] show failed: $error');
    }
  }

  static Future<void> downloadFinished(String title) => show(
        title: texts?.downloadComplete ?? '下载完成',
        body: title,
      );

  static Future<void> updateAvailable(String version) => show(
        title: texts?.updateAvailable ?? '发现新版本',
        body: version,
      );

  static Future<void> _bringWindowUp() async {
    try {
      await windowManager.show();
      await windowManager.focus();
    } catch (error) {
      debugPrint('[notify] bring window up failed: $error');
    }
  }
}

/// 通知文案：从 UI 层取好本地化字符串后注入，避免数据层依赖 context。
class NotificationTexts {
  const NotificationTexts({required this.downloadComplete, required this.updateAvailable});

  final String downloadComplete;
  final String updateAvailable;
}
