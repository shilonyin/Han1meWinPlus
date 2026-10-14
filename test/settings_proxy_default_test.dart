// 代理模式的默认值：不使用代理。
//
// 默认跟随系统代理时，用户在没配代理的机器上也会走一遍系统代理设置，出问题时
// 很难判断是站点不可达还是代理链路的问题；默认直连可以让「能不能通」这件事先
// 落在站点本身上。要用代理的用户自己去网络设置里选。
//
// 老用户要一起迁移：旧版 [AppSettings.toJson] 全量落盘，所以每个老配置里都存着
// 当时那个默认值 'system'，与「用户主动选的跟随系统」无法区分。规则：没有迁移
// 标记的配置把 'system' 改回 'direct'；'custom' 不受影响（那要求用户填过地址，
// 是明确的主动选择）。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

void main() {
  test('全新配置（空 JSON）→ 不使用代理', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.proxyMode, 'direct');
    expect(settings.proxyDefaultsMigrated, true);
  });

  test('构造函数默认值 → 不使用代理', () {
    expect(const AppSettings().proxyMode, 'direct');
  });

  test('无法识别的值 → 回落到不使用代理', () {
    final settings = AppSettings.fromJson({'proxyMode': 'something-else'});
    expect(settings.proxyMode, 'direct');
  });

  test('老配置（无迁移标记）里存着旧默认值 system → 强制改回 direct', () {
    final settings = AppSettings.fromJson({'proxyMode': 'system'});
    expect(settings.proxyMode, 'direct');
    expect(settings.proxyDefaultsMigrated, true);
  });

  test('老配置里的自定义代理不动（填过地址 = 明确的主动选择）', () {
    final settings = AppSettings.fromJson({
      'proxyMode': 'custom',
      'customProxy': '127.0.0.1:7890',
    });
    expect(settings.proxyMode, 'custom');
    expect(settings.customProxy, '127.0.0.1:7890');
  });

  test('迁移之后用户再选跟随系统 → 尊重选择，不再迁移', () {
    final settings = AppSettings.fromJson({
      'proxyDefaultsMigrated': true,
      'proxyMode': 'system',
    });
    expect(settings.proxyMode, 'system');
  });

  test('迁移结果落盘后重载不会反复迁移', () {
    final migrated = AppSettings.fromJson({'proxyMode': 'system'});
    expect(migrated.proxyMode, 'direct');
    // 用户在设置里主动选回跟随系统并保存。
    final saved = migrated.copyWith(proxyMode: 'system').toJson();
    expect(saved['proxyDefaultsMigrated'], true);
    expect(AppSettings.fromJson(saved).proxyMode, 'system');
  });

  test('往返：保存后重载仍是同一个模式', () {
    for (final mode in ['direct', 'system', 'custom']) {
      final settings = AppSettings(proxyMode: mode, proxyDefaultsMigrated: true);
      expect(AppSettings.fromJson(settings.toJson()).proxyMode, mode);
    }
  });
}
