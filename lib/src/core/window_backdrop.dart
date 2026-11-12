import 'dart:io';

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

  /// 初始化只做一次的**共享 Future**。
  ///
  /// 原来用 `_initialized` 布尔量判断：两次 `apply` 并发进来时，两个都看到
  /// `_initialized == false`，于是都去 `await Window.initialize()` —— 而它内部的
  /// Completer 只能完成一次，第二次就抛 `Bad state: Future already completed`
  /// （日志里每次启动都有这一行）。
  ///
  /// 改成缓存 Future：只有第一个调用真正初始化，其余直接等同一个 Future。
  /// 失败时把缓存清掉，下一次还能重试（与原来「失败不记为已应用」的语义一致）。
  static Future<void>? _initFuture;

  /// 应用材质；返回是否真的下发成功。
  ///
  /// 调用方据此决定要不要记住这次结果：窗口刚创建时 `Window.initialize` 可能失败，
  /// 若把失败也当成「已应用」记下来，之后主题切换就再也不会重试，界面会一直停在
  /// 错误的材质深浅上。
  static Future<bool> apply(
    WindowBackdrop backdrop, {
    required bool dark,
  }) async {
    if (!isSupported) return false;
    try {
      // 并发调用共享同一次初始化，避免 Completer 被重复完成。
      await (_initFuture ??= Window.initialize().catchError((Object error) {
        // 初始化失败就把缓存清掉：下一次触发还会重试，而不是永远停在这里。
        _initFuture = null;
        throw error;
      }));
      switch (backdrop) {
        case WindowBackdrop.none:
          await Window.setEffect(effect: WindowEffect.disabled);
        case WindowBackdrop.mica:
          // 先关一次再重设：某些 Windows build 上 DWM 收到「同一种材质、只换 dark」
          // 时不会重绘，切主题后窗口背景仍停在旧深浅（看起来像「主题没生效」）。
          // 先 disabled 再 mica 能强制重建材质，深/浅就会真正跟过去。
          await Window.setEffect(effect: WindowEffect.disabled);
          await Window.setEffect(effect: WindowEffect.mica, dark: dark);
        case WindowBackdrop.acrylic:
          // Acrylic 需要一层底色，深色下压暗一点，否则浅色主题的文字会看不清。
          // 同 mica：先关再设，避免只换 dark 时不重绘。
          await Window.setEffect(effect: WindowEffect.disabled);
          await Window.setEffect(
            effect: WindowEffect.acrylic,
            color: dark ? const Color(0xcc101114) : const Color(0xccf7f7fb),
            dark: dark,
          );
      }
      return true;
    } catch (error) {
      debugPrint('[backdrop] setEffect failed: $error');
      return false;
    }
  }
}

/// 真正把材质下发给系统的那一次调用。测试会替换它，免得在单元测试里真的去碰 DWM。
@visibleForTesting
Future<bool> Function(WindowBackdrop backdrop, {required bool dark})
windowBackdropApplier = WindowBackdropEffect.apply;

/// 窗口材质的下发器：把「目标材质」串行地交给 [windowBackdropApplier]。
///
/// 为什么要串行：`Window.setEffect` 是异步的，连点主题按钮时会有多次请求并发
/// 交错，最终落到窗口上的可能是先发的那次（材质深浅就和主题对不上了）。这里每次
/// 只发一个，发完再看有没有更新的目标；旧的中间态直接跳过，只保证收敛到最后那个。
///
/// 失败不会被记成「已应用」，下一次触发还会重试——而不是永远停在错误的材质上。
///
/// 一个窗口一个实例。主窗口与每个独立播放窗口都是**各自独立的进程**、各自的顶层
/// 窗口，所以每个进程各持一个即可，互不影响。
class WindowBackdropController {
  (WindowBackdrop, bool)? _applied;
  (WindowBackdrop, bool)? _pending;
  var _draining = false;

  /// 请求把窗口材质切到 [backdrop]，深浅由 [dark] 决定。
  ///
  /// 与上次**成功**下发的组合相同时直接返回，不再打扰系统。
  Future<void> request(WindowBackdrop backdrop, {required bool dark}) async {
    if (!WindowBackdropEffect.isSupported) return;
    final target = (backdrop, dark);
    if (_applied == target) return;
    _pending = target;
    await _drain();
  }

  /// 串行消费待下发的请求，直到追上最后一次选择。
  Future<void> _drain() async {
    if (_draining) return;
    _draining = true;
    try {
      while (true) {
        final target = _pending;
        if (target == null || target == _applied) return;
        _pending = null;
        if (await windowBackdropApplier(target.$1, dark: target.$2)) {
          _applied = target;
        }
      }
    } finally {
      _draining = false;
    }
  }
}
