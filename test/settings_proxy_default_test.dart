// 代理模式的默认值：不使用代理。
//
// 默认跟随系统代理时，用户在没配代理的机器上也会走一遍系统代理设置，出问题时
// 很难判断是站点不可达还是代理链路的问题；默认直连可以让「能不能通」这件事先
// 落在站点本身上。要用代理的用户自己去网络设置里选。
//
// 这里守两点：① 全新配置与无法识别的值都落到 direct；② **已经存过值的配置要
// 尊重用户的选择**，不能被新默认值覆盖（用户主动选过「跟随系统」就该继续跟随）。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';

void main() {
  test('全新配置（空 JSON）→ 不使用代理', () {
    final settings = AppSettings.fromJson(const {});
    expect(settings.proxyMode, 'direct');
  });

  test('构造函数默认值 → 不使用代理', () {
    expect(const AppSettings().proxyMode, 'direct');
  });

  test('无法识别的值 → 回落到不使用代理', () {
    final settings = AppSettings.fromJson({'proxyMode': 'something-else'});
    expect(settings.proxyMode, 'direct');
  });

  test('已保存的选择被尊重：跟随系统 / 自定义都保持原样', () {
    expect(AppSettings.fromJson({'proxyMode': 'system'}).proxyMode, 'system');
    expect(AppSettings.fromJson({'proxyMode': 'custom'}).proxyMode, 'custom');
  });

  test('往返：保存后重载仍是同一个模式', () {
    for (final mode in ['direct', 'system', 'custom']) {
      final saved = AppSettings.fromJson({'proxyMode': mode}).toJson();
      expect(AppSettings.fromJson(saved).proxyMode, mode);
    }
  });
}
