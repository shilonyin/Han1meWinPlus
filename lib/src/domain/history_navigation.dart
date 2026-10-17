import 'models/library.dart';

/// 观看历史里当前视频的前一条 / 后一条。
///
/// 播放窗口顶部栏的两个箭头用它来换片：翻的是「我最近看过什么」这条时间线，
/// 不是当前视频所在的剧集列表。同一部片子的其它集也在历史里，但它们和其它视频
/// 一样按看过的时间排队，没有特殊地位。
class HistoryNeighbours {
  const HistoryNeighbours({this.previous, this.next});

  /// 比当前视频看得更早的那一条。
  final WatchHistory? previous;

  /// 比当前视频看得更晚的那一条。
  final WatchHistory? next;

  bool get hasPrevious => previous != null;
  bool get hasNext => next != null;
}

/// 在 [history] 里找 [videoCode] 的前后条。
///
/// 几条口径：
///
/// - **当前视频锚在它最近一次出现的位置**。每次开播都会 append 一条新记录（见
///   `WatchController.addTime`），所以同一部片子可能占多条；用最早那条会把箭头
///   定位到一个早就过去的时刻。但**其它视频的旧记录照样保留**——否则「先看 a、
///   再看 b、又看 a」这种顺序里，b 的下一条就找不到 a 了。
/// - **前后跳过自己的重复记录**。同一部片子连看两遍（中间没看别的）时，它的
///   「上一条」不该还是自己。
/// - **按 createdAt 升序排**。`histories` 是 append 出来的，正常已经有序，但
///   WebDAV 同步合并后的顺序不保证，排序不依赖输入顺序。
/// - **当前视频不在历史里时，把最新一条当作它的上一条**。刚从首页点开、还没
///   看够时长（`_watchThresholdMs`）时它确实还没被记下。早先这里让两个箭头都
///   置灰，结果是「点开任何新视频，箭头都是灰的」——功能看起来根本没做。改成
///   锚在最新位置之后：此时上一条是「我上次看的」，下一条没有（还没看新的）。
HistoryNeighbours historyNeighbours(
  List<WatchHistory> history,
  String videoCode,
) {
  if (history.isEmpty || videoCode.isEmpty) return const HistoryNeighbours();

  final ordered = history
      .where((entry) => entry.videoCode.isNotEmpty)
      .toList(growable: false)
    ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  if (ordered.isEmpty) return const HistoryNeighbours();

  var anchor = -1;
  for (var i = ordered.length - 1; i >= 0; i--) {
    if (ordered[i].videoCode == videoCode) {
      anchor = i;
      break;
    }
  }
  if (anchor < 0) {
    // 不在历史里：当前视频视为排在最新一条之后。
    return HistoryNeighbours(previous: ordered.last, next: null);
  }

  WatchHistory? previous;
  for (var i = anchor - 1; i >= 0; i--) {
    if (ordered[i].videoCode != videoCode) {
      previous = ordered[i];
      break;
    }
  }

  WatchHistory? next;
  for (var i = anchor + 1; i < ordered.length; i++) {
    if (ordered[i].videoCode != videoCode) {
      next = ordered[i];
      break;
    }
  }

  return HistoryNeighbours(previous: previous, next: next);
}
