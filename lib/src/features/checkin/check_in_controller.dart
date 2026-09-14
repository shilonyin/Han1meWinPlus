import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/local/check_in_repository.dart';
import '../../domain/models/check_in.dart';

/// 「冲了么」页面的状态：显示中的月份 + 全部记录 + 由记录派生的统计。
class CheckInState {
  const CheckInState({required this.month, required this.records});

  /// 日历当前显示的月份（当月 1 号）。
  final DateTime month;

  final List<CheckInRecord> records;

  String get monthKey => checkInMonthKey(month);

  int countFor(String dateKey) => records.where((record) => record.date == dateKey).length;

  int get todayCount => countFor(checkInDateKey(DateTime.now()));

  /// 本月有记录的天数
  int get monthDays => records.where((record) => record.date.startsWith(monthKey)).map((record) => record.date).toSet().length;

  /// 本月记录总条数
  int get monthTotal => records.where((record) => record.date.startsWith(monthKey)).length;

  /// 本月最长连续打卡天数
  int get bestStreak {
    final days = records.where((record) => record.date.startsWith(monthKey)).map((record) => record.date).toSet().map(DateTime.parse).toList()..sort();
    var best = 0;
    var streak = 0;
    DateTime? previous;
    for (final day in days) {
      streak = previous != null && day.difference(previous).inDays == 1 ? streak + 1 : 1;
      if (streak > best) best = streak;
      previous = day;
    }
    return best;
  }
}

final checkInProvider = AsyncNotifierProvider<CheckInController, CheckInState>(CheckInController.new);

class CheckInController extends AsyncNotifier<CheckInState> {
  final _repository = CheckInRepository();

  @override
  Future<CheckInState> build() async => CheckInState(month: _monthStart(DateTime.now()), records: await _repository.load());

  /// 打卡（今天一条，类型由界面选择）。
  Future<void> checkIn(String type) => _add(checkInDateKey(DateTime.now()), type);

  /// 补记某一天。
  Future<void> addFor(DateTime date, String type) => _add(checkInDateKey(date), type);

  Future<void> _add(String date, String type) async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.countFor(date) >= maxCheckInsPerDay) return;
    state = AsyncData(CheckInState(month: current.month, records: await _repository.add(CheckInRecord(date: date, time: checkInTimeValue(DateTime.now()), type: type))));
  }

  /// 清空某一天（默认清空今天）。
  Future<void> clearDate(DateTime date) async {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(CheckInState(month: current.month, records: await _repository.clearDate(checkInDateKey(date))));
  }

  void previousMonth() => _shiftMonth(-1);

  void nextMonth() => _shiftMonth(1);

  void _shiftMonth(int delta) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(CheckInState(month: DateTime(current.month.year, current.month.month + delta), records: current.records));
  }

  static DateTime _monthStart(DateTime date) => DateTime(date.year, date.month);
}
