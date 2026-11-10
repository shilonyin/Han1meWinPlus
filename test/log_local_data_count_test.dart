import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/features/settings/log_local_data_card.dart';

void main() {
  group('countFromDecoded', () {
    test('顶层数组直接数长度', () {
      expect(countFromDecoded([1, 2, 3, 4, 5], null), 5);
    });

    test('顶层 Map 数键数', () {
      expect(countFromDecoded({'a': 1, 'b': 2, 'c': 3}, null), 3);
    });

    test('countKey 取嵌套数组长度，而不是顶层键数', () {
      // watch_store.json 的真实形状：两个顶层键，25 条 histories。
      // 之前写错文件名 + 数顶层，得到 0 / 2，都不是观看历史条数。
      final store = {
        'continueItems': [
          {'videoCode': 'A'},
        ],
        'histories': List.generate(25, (i) => {'id': '$i'}),
      };
      expect(countFromDecoded(store, 'histories'), 25);
      expect(countFromDecoded(store, null), 2);
    });

    test('countKey 指向的键不存在或不是数组时返回 0', () {
      expect(countFromDecoded({'continueItems': []}, 'histories'), 0);
      expect(countFromDecoded({'histories': 'oops'}, 'histories'), 0);
    });

    test('形状非法时返回 0，不抛', () {
      expect(countFromDecoded(null, null), 0);
      expect(countFromDecoded(42, null), 0);
      expect(countFromDecoded('text', 'histories'), 0);
    });
  });
}
