import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/local/json_store.dart';
import 'package:han1me_win_plus/src/data/remote/address_ranker.dart';

/// 内存版存储，避免测试写真实的应用数据目录。
class _MemoryStore extends JsonStore {
  final Map<String, Map<String, dynamic>> files = {};

  @override
  Future<Map<String, dynamic>> read(String fileName) async => files[fileName] ?? {};

  @override
  Future<void> write(String fileName, Map<String, dynamic> value) async => files[fileName] = value;
}

void main() {
  const host = 'hanime1.com';
  const ipv4Fast = '104.18.0.1';
  const ipv4Slow = '104.19.0.1';
  const ipv6 = '2606:4700:3030::6815:746';
  const addresses = [ipv4Slow, ipv4Fast, ipv6];

  test('没有探测数据时保持 IPv4 优先的原顺序', () {
    final ranker = AddressRanker(_MemoryStore());
    expect(ranker.order(host, addresses), addresses);
  });

  test('有实测数据时按延迟升序，已知失败的沉到最后', () {
    final ranker = AddressRanker(_MemoryStore());
    ranker.recordSuccess(host, ipv4Slow, const Duration(milliseconds: 320));
    ranker.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 180));
    ranker.recordFailure(host, ipv6);
    expect(ranker.order(host, addresses), [ipv4Fast, ipv4Slow, ipv6]);
  });

  test('没有数据的地址排在已知地址之后，且不会盖过失败的顺序', () {
    final ranker = AddressRanker(_MemoryStore());
    ranker.recordSuccess(host, ipv4Slow, const Duration(milliseconds: 320));
    expect(ranker.order(host, addresses), [ipv4Slow, ipv4Fast, ipv6]);
  });

  test('成功后清掉失败标记，失败后清掉延迟记录', () {
    final ranker = AddressRanker(_MemoryStore());
    ranker.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 180));
    ranker.recordFailure(host, ipv4Fast);
    expect(ranker.rankedFor(host).containsKey(ipv4Fast), isFalse);
    expect(ranker.failedFor(host).contains(ipv4Fast), isTrue);
    ranker.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 90));
    expect(ranker.failedFor(host).contains(ipv4Fast), isFalse);
    expect(ranker.rankedFor(host)[ipv4Fast], 90);
  });

  test('域名兜底项不参与排序也不会被记录', () {
    final ranker = AddressRanker(_MemoryStore());
    ranker.recordFailure(host, host);
    expect(ranker.failedFor(host), isEmpty);
    expect(ranker.order(host, [...addresses, host]).last, host);
  });

  // 全部内置地址都被标记失败时，兜底项曾经会冒到第一位：它会先去做系统 DNS（本机对
  // hanime 域名的解析被污染，连不上），于是每次请求都烧满 20s 连接超时、一个内置 IP 都
  // 轮不到，整站页面都加载不出来。兜底项必须永远在所有字面地址之后。
  test('所有内置地址都失败时，域名兜底项仍然排在最后', () {
    final ranker = AddressRanker(_MemoryStore());
    for (final address in addresses) {
      ranker.recordFailure(host, address);
    }
    final ordered = ranker.order(host, [...addresses, host]);

    expect(ordered.last, host);
    expect(ordered.take(addresses.length), addresses);
  });

  test('关掉优先后回到列表原顺序，且不再记录结果', () {
    final ranker = AddressRanker(_MemoryStore())..enabled = false;
    ranker.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 90));
    ranker.recordFailure(host, ipv6);
    expect(ranker.rankedFor(host), isEmpty);
    expect(ranker.order(host, addresses), addresses);
  });

  test('结果落盘后重新载入仍然生效', () async {
    final store = _MemoryStore();
    final first = AddressRanker(store);
    first.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 180));
    first.recordFailure(host, ipv4Slow);
    await first.save();

    final second = AddressRanker(store);
    await second.ensureLoaded();
    expect(second.rankedFor(host)[ipv4Fast], 180);
    expect(second.failedFor(host).contains(ipv4Slow), isTrue);
    // 已知失败的要沉到「没有数据」的地址之后。
    expect(second.order(host, addresses), [ipv4Fast, ipv6, ipv4Slow]);
  });

  test('清空结果后回到原顺序', () async {
    final ranker = AddressRanker(_MemoryStore());
    ranker.recordSuccess(host, ipv4Fast, const Duration(milliseconds: 180));
    ranker.recordFailure(host, ipv6);
    await ranker.clear();
    expect(ranker.rankedFor(host), isEmpty);
    expect(ranker.failedFor(host), isEmpty);
    expect(ranker.order(host, addresses), addresses);
  });
}
