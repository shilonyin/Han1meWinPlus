/// 每日打卡（「冲了么」）的记录模型。
///
/// 这是纯本地功能，不涉及站点接口：记录写在 `check_in_records.json` 里，
/// 与参考实现（Android 端用 Room）相比只是换了存储层，字段保持一致：
/// 日期、时间、类型。类型用固定 id 存储，界面按语言本地化展示。
class CheckInRecord {
  const CheckInRecord({required this.date, required this.time, required this.type});

  /// `yyyy-MM-dd`
  final String date;

  /// `HH:mm`
  final String time;

  /// [checkInTypeIds] 之一
  final String type;

  Map<String, dynamic> toJson() => {'date': date, 'time': time, 'type': type};

  static CheckInRecord? fromJson(Object? json) {
    if (json is! Map) return null;
    final date = '${json['date'] ?? ''}'.trim();
    if (date.isEmpty) return null;
    final type = '${json['type'] ?? ''}'.trim();
    return CheckInRecord(date: date, time: '${json['time'] ?? ''}'.trim(), type: checkInTypeIds.contains(type) ? type : checkInTypeIds.first);
  }
}

/// 类型 id：与参考实现一一对应（自慰 / 湿梦 / 做爱 / 口交 / 其他）。
const List<String> checkInTypeIds = ['masturbation', 'wetDream', 'sex', 'oral', 'other'];

/// 每天最多打卡次数（参考实现同样取 20）。
const int maxCheckInsPerDay = 20;

String checkInDateKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

String checkInMonthKey(DateTime date) => '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}';

String checkInTimeValue(DateTime time) => '${time.hour.toString().padLeft(2, '0')}:${time.minute.toString().padLeft(2, '0')}';
