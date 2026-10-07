import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/services.dart';

import 'desktop_platform.dart';

class PlatformService {
  static const _channel = MethodChannel('com.liar.han1meplus/platform');
  static bool get isDesktop => isDesktopPlatformService;

  static Future<void> setScreenBrightness(double value) => isDesktop ? Future.value() : _channel.invokeMethod<void>('setScreenBrightness', {'value': value});
  static Future<double> screenBrightness() async => isDesktop ? 1 : await _channel.invokeMethod<double>('screenBrightness') ?? 1;
  static Future<double> volume() async => isDesktop ? 1 : await _channel.invokeMethod<double>('volume') ?? 1;
  static Future<void> setVolume(double value) => isDesktop ? Future.value() : _channel.invokeMethod<void>('setVolume', {'value': value});
  static Future<void> setHideFromRecents(bool value) => isDesktop ? Future.value() : _channel.invokeMethod<void>('setHideFromRecents', {'value': value});
  static Future<void> setEmergencyExit(bool value) => isDesktop ? Future.value() : _channel.invokeMethod<void>('setEmergencyExit', {'value': value});
  static Future<void> minimizeApp() => isDesktop ? Future.value() : _channel.invokeMethod<void>('minimizeApp');
  static Future<bool> enterPictureInPicture() async => !Platform.isAndroid ? false : await _channel.invokeMethod<bool>('enterPictureInPicture') ?? false;
  static Future<bool> isHarmonyOs() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isHarmonyOs') ?? false;
    } on PlatformException {
      return false;
    }
  }
  static Future<String?> androidUpdateAbi() async => !Platform.isAndroid ? null : await _channel.invokeMethod<String>('androidUpdateAbi');
  static Future<void> openAppLinksSettings() => isDesktop ? Future.value() : _channel.invokeMethod<void>('openAppLinksSettings');
  static Future<bool> authenticate() async => isDesktop ? false : await _channel.invokeMethod<bool>('authenticate') ?? false;
  static Future<String?> selectDirectory() async => Platform.isAndroid ? _channel.invokeMethod<String>('selectDirectory') : null;
  static Future<void> exportDirectory(String sourcePath, String destination) => Platform.isAndroid ? _channel.invokeMethod<void>('exportDirectory', {'sourcePath': sourcePath, 'destination': destination}) : Future.value();
  static Future<bool> saveDocument(String name, Uint8List bytes) async => Platform.isAndroid ? await _channel.invokeMethod<bool>('saveDocument', {'name': name, 'bytes': bytes}) ?? false : false;

  /// Windows 的「透明效果」开关（设置 → 个性化 → 颜色）是否被关掉了。
  ///
  /// **为什么应用得自己读**：g1455 有一档 rung 专门等这个信号 —— 用户既然在系统里
  /// 关掉了透明，界面就不该继续透出背景，那是可访问性而不是省性能（它文档里也这么
  /// 说）。而 Flutter 不带这个开关，所以只能由应用读出来传给它。
  ///
  /// **为什么用 reg.exe 而不是原生代码**：Windows 上它就是注册表里一个 DWORD，
  /// 为一件事动 runner 的 C++ 不划算（那边的多窗口处理还是手写的，碰它有风险）。
  /// 只在启动时查一次。
  ///
  /// 读不到（键不存在、reg 调用失败、输出解析不了）一律当「没关」：宁可多一层玻璃，
  /// 也别因为解析失败把整个界面变成实心。
  static Future<bool> windowsTransparencyDisabled() async {
    if (!Platform.isWindows) return false;
    try {
      final ProcessResult result = await Process.run('reg', [
        'query',
        r'HKCU\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize',
        '/v',
        'EnableTransparency',
      ]);
      if (result.exitCode != 0) return false;
      final RegExpMatch? match = RegExp(r'EnableTransparency\s+REG_DWORD\s+0x([0-9a-fA-F]+)').firstMatch(result.stdout.toString());
      return match != null && int.parse(match.group(1)!, radix: 16) == 0;
    } catch (_) {
      return false;
    }
  }

  /// 系统「高对比度」开着吗（Windows）。设置里对比度选「跟随系统」时用它。
  ///
  /// **为什么不能交给 g1455**：`GlassHost.highContrast` 传 null 表示"去读
  /// `MediaQuery.highContrastOf`"，而引擎只在 iOS 与 Android 34+ 上设置那个值 ——
  /// **Windows 上它恒为 false**（包的文档也点名了平台不给的情况，举的是 macOS）。
  /// 所以"跟随系统"这一档在 Windows 上必须由应用自己读，否则它永远跟不出来、
  /// 看起来就像一个坏掉的开关。
  ///
  /// Windows 把它放在 `HKCU\Control Panel\Accessibility\HighContrast` 的 `Flags`
  /// 里，是个**十进制字符串**（不是 DWORD），最低位就是「高对比度已打开」。
  /// 读不到一律当"没开"：宁可少一道描边，也别无故把界面切到高对比观感。
  static Future<bool> windowsHighContrastEnabled() async {
    if (!Platform.isWindows) return false;
    try {
      final ProcessResult result = await Process.run('reg', [
        'query',
        r'HKCU\Control Panel\Accessibility\HighContrast',
        '/v',
        'Flags',
      ]);
      if (result.exitCode != 0) return false;
      final RegExpMatch? match = RegExp(r'Flags\s+REG_SZ\s+(\d+)').firstMatch(result.stdout.toString());
      return match != null && (int.parse(match.group(1)!) & 0x1) == 0x1;
    } catch (_) {
      return false;
    }
  }
}
