import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

/// 老用户强制迁移：旧版 [AppSettings.toJson] 把当时的默认值
/// `globalHotkeysEnabled: false` 全量写进 setting.json，与「用户主动关闭」
/// 无法区分。规则：没有迁移标记（hotkeyDefaultsMigrated）的配置载入时
/// 强制回 true；有标记的配置尊重用户存的选择，不再打扰。
void main() {
  test('老配置（无标记，存着旧默认值 false）→ 强制迁移回 true', () {
    final settings = AppSettings.fromJson({
      'globalHotkeysEnabled': false,
    });
    expect(settings.globalHotkeysEnabled, true);
    expect(settings.hotkeyDefaultsMigrated, true);
  });

  test('老配置缺字段 / 全新配置 → 同样按新默认开启', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.globalHotkeysEnabled, true);
    expect(settings.hotkeyDefaultsMigrated, true);
  });

  test('已迁移配置里用户主动关掉 → 保持 false 不再迁移', () {
    final settings = AppSettings.fromJson({
      'hotkeyDefaultsMigrated': true,
      'globalHotkeysEnabled': false,
    });
    expect(settings.globalHotkeysEnabled, false);
  });

  test('迁移结果落盘后重载不会反复迁移', () {
    final migrated = AppSettings.fromJson({'globalHotkeysEnabled': false});
    // 迁移只改内存；用户之后主动关掉并保存，标记必须跟着落盘。
    final saved = migrated.copyWith(globalHotkeysEnabled: false).toJson();
    expect(saved['hotkeyDefaultsMigrated'], true);
    expect(saved['globalHotkeysEnabled'], false);
    final reloaded = AppSettings.fromJson(saved);
    expect(reloaded.globalHotkeysEnabled, false);
  });
}
