import 'package:flutter/foundation.dart';

/// 全局热键要作用在「当前正在播放的那个实例」上，而播放器实例是播放页里的
/// 局部状态（页面内 ValueNotifier），热键模块拿不到它。
///
/// 所以用一张全局回调登记表做桥接：播放页 initState 注册、dispose 注销。
/// 回调都是无参的 void，避免把控制器实体泄漏到全局。
class PlaybackHotkeyTarget {
  PlaybackHotkeyTarget._();

  /// 播放 / 暂停切换。
  static void Function()? togglePlay;

  /// 当前是否正在播放。
  ///
  /// 画中画小窗的中央按钮要据此在「播放」与「暂停」两个图标之间切；那个按钮挂在
  /// 窗口级浮层上（[AppWindowFrame]），拿不到播放页里的 controller，所以由播放页
  /// 把状态同步到这里。

  /// 上一集（没有上一集时由注册方自己决定不响应）。
  static void Function()? previousEpisode;

  /// 下一集。
  static void Function()? nextEpisode;

  /// 见 [togglePlay] 上方说明。
  static final ValueNotifier<bool> isPlaying = ValueNotifier(false);

  static void clear() {
    togglePlay = null;
    previousEpisode = null;
    nextEpisode = null;
    isPlaying.value = false;
  }
}
