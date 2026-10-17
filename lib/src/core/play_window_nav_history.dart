import 'package:flutter/foundation.dart';

/// 播放窗口里「我点开过哪些视频」的顺序记录。
///
/// 顶部栏那两个箭头翻的是**这个窗口内的打开顺序**，不是全局观看历史。
/// 场景：正在看 A，点开 B 播放，看完想回 A —— 左箭头就该回到 A。
/// 用观看历史做不到这件事：历史只在播满时长后才写，同一部片子的多条记录
/// 还会按「看过的时间」重新排队，和「我刚才点开的顺序」是两回事。
///
/// 只活在播放窗口进程内：窗口关掉就没了，重新打开从当前视频重新开始记。
/// 这与「刚才点开的」这个语义一致 —— 跨启动的顺序不叫「刚才」。
class PlayWindowNavEntry {
  const PlayWindowNavEntry({required this.videoCode, required this.title});

  final String videoCode;
  final String title;
}

class PlayWindowNavHistory {
  PlayWindowNavHistory._();

  static final PlayWindowNavHistory instance = PlayWindowNavHistory._();

  final List<PlayWindowNavEntry> _entries = [];
  int _index = -1;

  /// 通过箭头跳转时记下目标，[record] 见到它就不再新增一条。
  ///
  /// 箭头最终也是 pushReplacement 到新页面，新页面照样会调 [record]。
  /// 不区分的话，回退一次就会在栈尾追加一条，越退越长。
  String? _pendingTarget;

  /// 当前可翻的条目（调试与测试用）。
  @visibleForTesting
  List<PlayWindowNavEntry> get entries => List.unmodifiable(_entries);

  @visibleForTesting
  int get index => _index;

  PlayWindowNavEntry? get previous => _index > 0 ? _entries[_index - 1] : null;

  PlayWindowNavEntry? get next =>
      _index >= 0 && _index < _entries.length - 1 ? _entries[_index + 1] : null;

  bool get canGoPrevious => previous != null;
  bool get canGoNext => next != null;

  /// 记录一次「打开」。
  ///
  /// 同一个视频重复调用（重建、刷新详情）只更新标题，不会多出一条。
  void record(PlayWindowNavEntry entry) {
    if (entry.videoCode.isEmpty) return;

    // 箭头跳转：index 在 [goTo] 里已经移好，这里只同步标题。
    if (_pendingTarget == entry.videoCode) {
      _pendingTarget = null;
      if (_index >= 0 && _index < _entries.length) {
        _entries[_index] = entry;
      }
      return;
    }

    if (_index >= 0 && _entries[_index].videoCode == entry.videoCode) {
      _entries[_index] = entry;
      return;
    }

    // 从中间点开了新视频：丢掉原来的「前进」部分，和浏览器一致。
    if (_index < _entries.length - 1) {
      _entries.removeRange(_index + 1, _entries.length);
    }
    _entries.add(entry);
    _index = _entries.length - 1;
  }

  /// 箭头跳转前调用：把游标移到目标条目。
  ///
  /// 目标必须是栈里已有的条目；越界返回 false，调用方不该发起跳转。
  bool goTo(PlayWindowNavEntry target) {
    final at = _entries.indexWhere(
      (entry) => entry.videoCode == target.videoCode,
    );
    if (at < 0) return false;
    _index = at;
    _pendingTarget = target.videoCode;
    return true;
  }

  /// 只清状态，不重建实例（测试与「整窗重置」用）。
  @visibleForTesting
  void reset() {
    _entries.clear();
    _index = -1;
    _pendingTarget = null;
  }
}
