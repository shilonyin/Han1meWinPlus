// 回归测试：DoH 与「内置 Hosts」是互补关系，不是二选一。
//
// 背景：`WindowsConnectionFactory.call` 原先的判断顺序是「有内置地址就直接返回」，
// 而 `hanime1.me` / `hanime1.com` / `hanimeone.me` 全都在 `builtInHosts` 里 ——
// 于是设置里**开了 DoH 也对主站不生效**，DoH 只对没有内置列表的域名起作用。
//
// 改法是把两者的结果合成一个候选池交给 `AddressRanker` 排序：内置列表是照某次实测
// 写死的 anycast IP（快，但站点换 IP 段后会过期），DoH 拿的是当下真实解析（能跟着
// 站点走，但需要 bootstrap IP 才能在 DNS 被污染的网络里起来）。合起来才能互相兜底。
//
// `mergeCandidates` 就是这个合并逻辑，抽成纯函数以便直接断言顺序与去重。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/data/remote/windows_connection_factory.dart';

void main() {
  const host = 'hanime1.me';
  const builtIn = ['172.64.229.154', '104.19.0.1'];
  const resolved = ['104.18.0.1', '172.64.229.154'];

  group('候选池合并', () {
    test('内置在前、DoH 在后，域名兜底项恒定排最后', () {
      final merged = WindowsConnectionFactory.mergeCandidates(builtIn: builtIn, resolved: resolved, host: host);
      expect(merged.last, host);
      expect(merged.take(merged.length - 1), containsAll([...builtIn, '104.18.0.1']));
    });

    // DoH 解析出来往往就是那批 Cloudflare anycast IP，和内置列表高度重叠。
    // 不去重的话 `_connect` 会把同一个坏地址重复烧好几遍超时。
    test('内置与 DoH 重叠的地址只保留一份', () {
      final merged = WindowsConnectionFactory.mergeCandidates(builtIn: builtIn, resolved: resolved, host: host);
      final withoutFallback = merged.where((address) => address != host).toList();
      expect(withoutFallback.toSet().length, withoutFallback.length);
      // '172.64.229.154' 两边都有，只该出现一次。
      expect(withoutFallback.where((address) => address == '172.64.229.154').length, 1);
    });

    test('只有内置时不额外塞东西，只是补上域名兜底项', () {
      expect(
        WindowsConnectionFactory.mergeCandidates(builtIn: builtIn, resolved: const [], host: host),
        [...builtIn, host],
      );
    });

    test('只有 DoH 时同样保留域名兜底项（DoH 结果也可能全不可用）', () {
      expect(
        WindowsConnectionFactory.mergeCandidates(builtIn: const [], resolved: const ['104.18.0.1'], host: host),
        ['104.18.0.1', host],
      );
    });

    test('两者都空时只剩域名兜底项（退回系统解析，与改动前一致）', () {
      expect(WindowsConnectionFactory.mergeCandidates(builtIn: const [], resolved: const [], host: host), [host]);
    });

    // 传入的列表里若混进了域名本身（调用方可能把 host 拼在候选里），
    // 不能让它在 IP 中间出现 —— 否则 `_connect` 会提前走系统解析、浪费掉后面的真实 IP。
    test('入参里混进域名时，域名仍只在最后出现一次', () {
      final merged = WindowsConnectionFactory.mergeCandidates(builtIn: [...builtIn, host], resolved: const [host], host: host);
      expect(merged.last, host);
      expect(merged.where((address) => address == host).length, 1);
    });

    // 顺序稳定性：候选池会喂给 `AddressRanker`，顺序变了排序结果就会变，
    // 这条守着「内置优先」这个刻意设计。
    test('内置地址的相对顺序保持不变', () {
      final merged = WindowsConnectionFactory.mergeCandidates(
        builtIn: const ['104.19.0.1', '104.16.0.1', '104.18.0.1'],
        resolved: const ['188.114.96.1'],
        host: host,
      );
      expect(merged, ['104.19.0.1', '104.16.0.1', '104.18.0.1', '188.114.96.1', host]);
    });
  });

  group('内置表与主机名', () {
    // 这几个域名有内置列表 —— 正是原先「DoH 走不到」的那批，回归时必须覆盖到。
    test('hanime 站群确实在内置表里（DoH 协同的前提）', () {
      for (final name in ['hanime1.me', 'hanime1.com', 'hanimeone.me']) {
        expect(WindowsConnectionFactory.builtInHosts.containsKey(name), isTrue, reason: name);
      }
    });

    test('hanimeHosts 覆盖内置表里的站群条目', () {
      expect(WindowsConnectionFactory.hanimeHosts, containsAll(['hanime1.me', 'hanime1.com', 'hanimeone.me']));
    });
  });
}
