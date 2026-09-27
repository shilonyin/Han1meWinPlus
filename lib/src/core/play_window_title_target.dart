import 'package:flutter/foundation.dart';

/// 播放窗口顶部栏要从「当前播放页」拿的三样东西：标题、是否有上一集 / 下一集。
///
/// 为什么需要这层：顶部栏挂在窗口级（PlayWindowApp 的 AppWindowFrame 里），而
/// 标题和上下集能力属于播放页内部（VideoDetail 与它的 playlist）。两者不在同一棵
/// 子树上，直接传参要穿过 VideoPage -> _DetailBody -> VideoPageBody 好几层。
///
/// 沿用 PlaybackHotkeyTarget 那套做法：播放页 initState 登记、dispose 注销，
/// 只暴露必要的信息（标题字符串与两个无参回调），不把 VideoDetail 泄漏到全局。
///
/// 只有独立播放窗口的顶部栏会读它；主窗口用的是 AppTitleBar（不读）。
class PlayWindowTitleTarget {
  PlayWindowTitleTarget._();

  /// 当前视频标题，显示在顶部栏正中。
  static final ValueNotifier<String> title = ValueNotifier('');

  /// 有没有上一集 / 下一集，决定两个箭头是否可点。
  static final ValueNotifier<bool> hasPrevious = ValueNotifier(false);
  static final ValueNotifier<bool> hasNext = ValueNotifier(false);

  /// 换成上一集 / 下一集（没有时由注册方自己决定不响应）。
  static VoidCallback? previousEpisode;
  static VoidCallback? nextEpisode;

  /// 当前登记者的身份。
  ///
  /// 播放页之间会用 `pushReplacement` 互跳（下一集 / 换集），Flutter 里旧路由的
  /// dispose 发生在新页面 initState **之后**——如果 clear() 无条件清空，旧页面退出时
  /// 会把新页面刚登记的标题一起擦掉（顶部栏变空白）。所以记录所有者，
  /// 只有「登记它的那个页面」才有权清空。这与 WindowChrome.immersivePage 用计数
  /// 处理同一类时序问题是同一个原因。
  static Object? _owner;

  /// 播放页登记 / 更新自己的信息。[owner] 传该页面的 State 实例。
  static void register({
    required Object owner,
    required String title,
    required bool hasPrevious,
    required bool hasNext,
    VoidCallback? onPrevious,
    VoidCallback? onNext,
  }) {
    _owner = owner;
    PlayWindowTitleTarget.title.value = title;
    PlayWindowTitleTarget.hasPrevious.value = hasPrevious;
    PlayWindowTitleTarget.hasNext.value = hasNext;
    previousEpisode = onPrevious;
    nextEpisode = onNext;
  }

  /// 注销。只有当前所有者能清空（见 [_owner] 的说明）。
  static void clear(Object owner) {
    if (!identical(_owner, owner)) return;
    _owner = null;
    title.value = '';
    hasPrevious.value = false;
    hasNext.value = false;
    previousEpisode = null;
    nextEpisode = null;
  }

  /// 无条件清空；仅测试与「整窗重置」用。
  @visibleForTesting
  static void reset() {
    _owner = null;
    title.value = '';
    hasPrevious.value = false;
    hasNext.value = false;
    previousEpisode = null;
    nextEpisode = null;
  }
}
