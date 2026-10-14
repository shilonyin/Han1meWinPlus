import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 跨进程信箱的**唤醒通道**，由 runner 提供（`windows/runner/main.cpp`）。
///
/// 背景：播放窗口投递意图（打开作者页、下载…）是写一个文件到信箱目录，主窗口
/// 每两秒轮询一次取走。写盘那部分不变、仍然是唯一的事实来源；这个通道只负责
/// 「别等了，现在就看一眼」。
///
/// 没有它的时候，用户点完作者头像要等下一次轮询（最坏两秒）主窗口才有反应，
/// 表现出来就是「点了之后卡一两秒才跳」。有它之后延迟是一次消息传递。
///
/// 投递是尽力而为：主窗口不在（已退出 / 还在启动）时通知会落空，那时仍然靠
/// 轮询兜底，所以调用方不需要处理失败。
class MailboxChannel {
  MailboxChannel._();

  static const MethodChannel _channel = MethodChannel('han1me/mailbox');

  /// 主窗口侧收到通知时的回调；播放窗口侧用不到。
  static void Function()? onDrainRequested;

  static bool _bound = false;

  /// 只在 Windows 上有原生实现。
  static bool get isSupported => !kIsWeb && Platform.isWindows;

  /// 绑定主窗口侧的回调。重复调用是安全的（后一次覆盖前一次）。
  ///
  /// 必须在主窗口进程里调用：播放窗口注册的是 `poke` 方法而不是这个回调。
  static void bindMainWindow(void Function() onDrain) {
    if (!isSupported) return;
    onDrainRequested = onDrain;
    if (_bound) return;
    _bound = true;
    _channel.setMethodCallHandler((call) async {
      if (call.method != 'drain') return;
      onDrainRequested?.call();
    });
  }

  /// 播放窗口侧：告诉主窗口「信箱里刚多了一封信」。
  ///
  /// 失败（主窗口没在跑、通道不可用）时静默——轮询会把信取走。
  static Future<void> pokeMainWindow() async {
    if (!isSupported) return;
    try {
      await _channel.invokeMethod<void>('poke');
    } catch (error) {
      debugPrint('[mailbox] poke failed: $error');
    }
  }
}
