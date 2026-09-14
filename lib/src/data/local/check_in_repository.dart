import '../../domain/models/check_in.dart';
import 'json_store.dart';

/// 打卡记录的本地存储（`check_in_records.json`）。
///
/// 复用 [JsonStore]，与追番、更新缓存等一致；写入失败（磁盘/权限）由调用方处理，
/// 这里只保证「返回最新的完整列表」这一件事。
class CheckInRepository {
  CheckInRepository([JsonStore? store]) : _store = store ?? JsonStore();

  final JsonStore _store;
  static const _fileName = 'check_in_records.json';

  Future<List<CheckInRecord>> load() async {
    final json = await _store.read(_fileName);
    final raw = (json['records'] as List?) ?? const [];
    return raw.whereType<Map>().map((item) => CheckInRecord.fromJson(Map<String, dynamic>.from(item))).whereType<CheckInRecord>().toList();
  }

  Future<List<CheckInRecord>> save(List<CheckInRecord> records) async {
    await _store.write(_fileName, {'records': records.map((record) => record.toJson()).toList()});
    return records;
  }

  /// 追加一条记录并按时间排序（同日内按时间先后排列）。
  Future<List<CheckInRecord>> add(CheckInRecord record) async {
    final records = [...await load(), record];
    records.sort((a, b) => '${a.date} ${a.time}'.compareTo('${b.date} ${b.time}'));
    return save(records);
  }

  /// 清空某一天的全部记录。
  Future<List<CheckInRecord>> clearDate(String date) async {
    final records = (await load()).where((record) => record.date != date).toList();
    return save(records);
  }
}
