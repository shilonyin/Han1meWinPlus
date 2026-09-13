import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/platform_service.dart';
import '../settings/settings_controller.dart';

enum AppLockStatus { unlocking, locked, unlocked }

final appLockProvider = NotifierProvider<AppLockController, AppLockStatus>(AppLockController.new);

class AppLockController extends Notifier<AppLockStatus> {
  var _everUnlocked = false;
  var _authenticating = false;

  @override
  AppLockStatus build() {
    // 桌面端不存在应用锁，必须在这里直接放行。
    //
    // 若把它放在「等 settingsProvider 就绪」之后，AppLockGate 会在设置加载期间
    // 用一层背景色盖住整个界面，看起来就像卡在空白启动页（设置加载里还包含系统
    // 代理查询，系统繁忙时可能要好几秒）。
    if (PlatformService.isDesktop) {
      _everUnlocked = true;
      return AppLockStatus.unlocked;
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return AppLockStatus.unlocking;
    if (_everUnlocked || !settings.appLockEnabled) {
      _everUnlocked = true;
      return AppLockStatus.unlocked;
    }
    return AppLockStatus.locked;
  }

  void markUnlocked() => _everUnlocked = true;

  Future<void> unlock() async {
    if (_authenticating) return;
    _authenticating = true;
    try {
      final ok = await PlatformService.authenticate();
      if (ok) _everUnlocked = true;
      state = ok ? AppLockStatus.unlocked : AppLockStatus.locked;
    } catch (_) {
      state = AppLockStatus.locked;
    } finally {
      _authenticating = false;
    }
  }

  Future<void> retry() => unlock();
}
