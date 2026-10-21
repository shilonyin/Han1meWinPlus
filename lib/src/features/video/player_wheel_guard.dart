import 'dart:ui';

import 'package:flutter/foundation.dart';

/// 播放器里「滚轮不该调音量」的区域表。
///
/// 播放器最外层挂着一个 `Listener`，滚轮直接改音量。可播放器的弹层（选集、
/// 清晰度……）是 `MenuAnchor` 插进 Navigator Overlay 的，不在播放器子树里，
/// 两者只能靠 `PointerSignalResolver` 抢同一个滚轮事件：谁先 `register` 谁生效，
/// 输的那个连 respond 都收不到。
///
/// 靠抢是不可靠的。面板里的 `Scrollable` 一滚到顶就不再注册滚轮
/// （`scrollable.dart` 里 `targetScrollOffset != position.pixels` 才 register），
/// 而播放器那个 `Listener` 还老实待在 hit test 路径上，于是音量被改、面板
/// 纹丝不动。用户看到的就是「鼠标明明在选集面板里滚，音量却在变」。
///
/// 所以这里不比谁快，改成按区域禁掉：面板把自己占据的屏幕矩形登记进来，
/// 播放器收到滚轮先看指针落没落在禁区里，在就一步都不做，事件全交给面板。
class PlayerWheelGuard extends ChangeNotifier {
  PlayerWheelGuard._();

  static final PlayerWheelGuard instance = PlayerWheelGuard._();

  /// 需要吞掉滚轮的区域（只有内容会滚动的面板才登记）。
  final Map<Object, Rect> _wheelRegions = <Object, Rect>{};

  /// 当前开着的弹层（所有面板都登记，不看会不会滚）。
  final Set<Object> _openPanels = <Object>{};

  /// 当前是否有弹层开着。
  ///
  /// 播放器拿它决定「控制条还该不该跟着计时器隐藏」：弹层是从控制条上的
  /// 按钮开出来的，控制条一隐藏，按钮所在的 `MenuAnchor` 跟着从树里消失，
  /// 面板就被一并关掉了。所以只要有面板在，控制条必须钉住。
  bool get hasRegions => _openPanels.isNotEmpty;

  /// 上报 / 刷新 [owner] 占据的屏幕矩形（全局坐标，逻辑像素）。
  ///
  /// [blocksWheel] 为 false 时只登记「这个面板开着」，不拦滚轮 —— 音量、倍速
  /// 这类不滚的面板，滚轮依旧是调音量的。
  ///
  /// 只在「有 / 没有」发生翻转时通知 —— 这个方法每个已排版的帧都会被调用，
  /// 每次都通知会让监听方每帧 setState，自己把自己递进无限重建。
  void update(Object owner, Rect region, {bool blocksWheel = true}) {
    final wasEmpty = _openPanels.isEmpty;
    _openPanels.add(owner);
    if (blocksWheel) {
      _wheelRegions[owner] = region;
    } else {
      _wheelRegions.remove(owner);
    }
    if (wasEmpty && _openPanels.isNotEmpty) notifyListeners();
  }

  void remove(Object owner) {
    final removed = _openPanels.remove(owner);
    _wheelRegions.remove(owner);
    if (removed && _openPanels.isEmpty) notifyListeners();
  }

  /// [globalPosition] 是否落在某个需要吞滚轮的禁区里。
  bool blocks(Offset globalPosition) {
    for (final region in _wheelRegions.values) {
      if (region.contains(globalPosition)) return true;
    }
    return false;
  }
}
