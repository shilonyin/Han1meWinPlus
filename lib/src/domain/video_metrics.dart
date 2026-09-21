/// 影片卡片上「时长 / 播放量」的解析。
///
/// 这两个函数刻意返回 `int?`：**取不到就返回 null（未知），而不是 0**。
/// 推荐过滤里有「最短时长」「最少播放量」两条规则，如果把「站点没给这个字段」当成 0，
/// 就会把整页卡片全部滤掉 —— AV 源的卡片本来就不带时长与播放量，表现就是
/// 「AV 站点搜索永远没有结果」。同理 hanime1 的播放量是 `17.2万次` 这种写法，
/// 直接 `int.tryParse` 也拿不到数字。
library;

/// `12:34` → 754；`1:02:03` → 3723。格式不认识或没有数据时返回 null。
int? videoDurationSeconds(String? duration) {
  if (duration == null || duration.isEmpty) return null;
  final parts = duration.split(':').map(int.tryParse).toList(growable: false);
  if (parts.isEmpty || parts.any((part) => part == null)) return null;
  return parts.fold<int>(0, (total, part) => total * 60 + part!);
}

/// `1,234` → 1234；`17.2万次` → 172000；`1.2K` → 1200。取不到数字时返回 null。
int? videoViews(String? views) {
  if (views == null || views.isEmpty) return null;
  final match = RegExp(r'([\d,.]+)\s*([万亿wWkK]?)').firstMatch(views);
  if (match == null) return null;
  final value = double.tryParse(match.group(1)!.replaceAll(',', ''));
  if (value == null) return null;
  final unit = match.group(2) ?? '';
  final multiplier = switch (unit) {
    '万' || 'w' || 'W' => 10000,
    '亿' => 100000000,
    'k' || 'K' => 1000,
    _ => 1,
  };
  return (value * multiplier).round();
}
