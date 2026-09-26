import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_acrylic/flutter_acrylic.dart';

import 'settings.dart';

/// 窗口背景材质（Mica / Acrylic）。
///
/// 只在 Windows 上启用：Mica 是 Win11 的材质，Acrylic 在 Win10 1803+ 可用，
/// 而本仓库只维护 Windows，别的平台一律保持默认背景。
///
/// 材质本身由系统画在窗口底下，所以还要让界面表面半透明才看得见——
/// 那一半在 [appTheme] 里做（传 `backdrop` 参数）。
class WindowBackdropEffect {
  WindowBackdropEffect._();

  static bool get isSupported => Platform.isWindows;

  static bool _initialized = false;

  static Future<void> apply(WindowBackdrop backdrop, {required bool dark}) async {
    if (!isSupported) return;
    try {
      if (!_initialized) {
        await Window.initialize();
        _initialized = true;
      }
      switch (backdrop) {
        case WindowBackdrop.none:
          await Window.setEffect(effect: WindowEffect.disabled);
        case WindowBackdrop.mica:
          await Window.setEffect(effect: WindowEffect.mica, dark: dark);
        case WindowBackdrop.acrylic:
          // Acrylic 需要一层底色，深色下压暗一点，否则浅色主题的文字会看不清。
          await Window.setEffect(effect: WindowEffect.acrylic, color: dark ? const Color(0xcc101114) : const Color(0xccf7f7fb), dark: dark);
      }
    } catch (error) {
      debugPrint('[backdrop] setEffect failed: $error');
    }
  }
}
