import 'dart:async';
import 'dart:io';

import '../local/json_store.dart';

/// 单个候选地址的探测结果。
class AddressProbe {
  const AddressProbe({required this.address, required this.ok, this.milliseconds});

  final String address;
  final bool ok;

  /// 建连 + TLS 握手的耗时；[ok] 为假时是 null。
  final int? milliseconds;
}

/// 候选地址的「延迟探测 + 自动选优」。
///
/// 内置地址列表是照某一次实测写死的（见 `WindowsConnectionFactory.builtInHosts`），但节点
/// 质量会随时间和网络环境漂移：有的地址是黑洞（要烧满超时才轮到下一个），有的光是 TLS
/// 握手就要 1.5s（实测图片 CDN 的两段节点就有 0.31s 与 1.6s 之差）。以前只能按列表顺序
/// 硬试 —— 一次请求可能白等好几秒，而且连接失败什么也学不到，下次还从同一个坏节点开始。
///
/// 这里做三件事：
/// 1. [probe] 并发探测每个候选地址的真实握手耗时，快的排前面；
/// 2. 结果落盘，[_ttl] 内不重复探测，重启后直接复用；
/// 3. [recordSuccess] / [recordFailure] 把真实请求的结果反哺进排序，坏节点自动沉底。
///
/// 探测永远在后台跑，不阻塞真实请求；没有数据时 [order] 保持调用方给的顺序（IPv4 优先），
/// 也就是与改动前完全一致的行为。
class AddressRanker {
  AddressRanker([JsonStore? store]) : _store = store ?? JsonStore();

  /// 全局实例：连接工厂在同步路径上要用 [order]，拿不到依赖注入，只能走单例。
  static final AddressRanker instance = AddressRanker();

  static const _fileName = 'address_latency.json';

  /// 与连接工厂里候选地址的超时保持一致：坏节点不该让整次请求卡满设置里的秒数。
  static const probeTimeout = Duration(seconds: 4);
  static const _defaultPort = 443;
  static const _concurrency = 6;

  /// 落盘结果的有效期。过期只在后台重测，仍会先用旧结果排序，不阻塞请求。
  static const _ttl = Duration(hours: 6);

  /// 真实请求的反馈攒一会儿再落盘，避免每次连接都写文件。
  static const _saveDebounce = Duration(seconds: 3);

  final JsonStore _store;

  /// 关掉后不重排、不预热探测（对应设置项 `useAddressRanking`）。
  bool enabled = true;

  final _ranked = <String, Map<String, int>>{};
  final _failed = <String, Set<String>>{};
  final _probedAt = <String, DateTime>{};
  final _inFlight = <String>{};
  Future<void>? _loading;
  Timer? _saveTimer;

  /// 从磁盘载入上次的结果。幂等，可以放心在热路径上调用。
  Future<void> ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    try {
      final json = await _store.read(_fileName);
      final hosts = json['hosts'];
      if (hosts is! Map) return;
      for (final entry in hosts.entries) {
        final value = entry.value;
        if (value is! Map) continue;
        final host = entry.key.toString();
        final probedAt = DateTime.tryParse(value['at']?.toString() ?? '');
        if (probedAt != null) _probedAt[host] = probedAt;
        final milliseconds = value['ms'];
        if (milliseconds is Map) _ranked[host] = {for (final item in milliseconds.entries) item.key.toString(): (item.value as num).toInt()};
        final failed = value['failed'];
        if (failed is List) _failed[host] = failed.map((item) => item.toString()).toSet();
      }
    } catch (_) {
      // 缓存读不出来就当没有，探测结果本来就是可以随时重建的。
    }
  }

  /// 并发探测 [addresses] 并把结果并进排序表。UI 的「重新测速」与 [warmUp] 都走这里。
  Future<List<AddressProbe>> probe(String host, List<String> addresses, {int port = _defaultPort, bool allowBadCertificate = false}) async {
    final targets = addresses.where(_isLiteralAddress).toList(growable: false);
    if (targets.isEmpty) return const [];
    final results = <AddressProbe>[];
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length) {
        final address = targets[cursor++];
        results.add(await _probeOne(host, address, port, allowBadCertificate));
      }
    }

    await Future.wait(List.generate(_concurrency.clamp(1, targets.length), (_) => worker()));
    final rank = _ranked[host] ??= {};
    final failed = _failed[host] ??= {};
    for (final result in results) {
      if (result.ok) {
        rank[result.address] = result.milliseconds!;
        failed.remove(result.address);
      } else {
        rank.remove(result.address);
        failed.add(result.address);
      }
    }
    _probedAt[host] = DateTime.now();
    _scheduleSave();
    return results;
  }

  Future<AddressProbe> _probeOne(String host, String address, int port, bool allowBadCertificate) async {
    final stopwatch = Stopwatch()..start();
    Socket? plain;
    try {
      plain = await Socket.connect(address, port, timeout: probeTimeout);
      // 保持 SNI = 域名：只按 IP 连上并不代表这个节点能服务该站点（实测过一批只回
      // Cloudflare 1034 的地址），握手带上域名才算真正可用。
      final secure = await SecureSocket.secure(plain, host: host, onBadCertificate: allowBadCertificate ? (_) => true : null);
      stopwatch.stop();
      final milliseconds = stopwatch.elapsedMilliseconds;
      secure.destroy();
      return AddressProbe(address: address, ok: true, milliseconds: milliseconds);
    } catch (_) {
      plain?.destroy();
      return AddressProbe(address: address, ok: false);
    }
  }

  /// 按已知延迟重排候选地址：快的在前，没数据的保持原顺序，已知不可用的沉到最后。
  ///
  /// 非字面地址（主机名，也就是系统 DNS 兜底）**永远排在所有字面地址之后**。它一旦排到
  /// 前面就会先走系统 DNS，而本机/某些网络对 hanime 域名的解析是被污染的（实测
  /// `hanime1.com` 解到 `31.13.87.19`，连接一直挂到超时），于是每次请求都在这里烧满
  /// Dart `HttpClient` 的 20s 连接超时，内置 IP 一个都轮不到 —— 表现就是整站页面都加载
  /// 不出来。主机名兜底的原意是「内置地址都连不上时才用它」，位置必须体现这一点。
  List<String> order(String host, List<String> addresses) {
    final ordered = _ipv4First(addresses);
    final literals = ordered.where(_isLiteralAddress).toList(growable: false);
    final hostnames = ordered.where((address) => !_isLiteralAddress(address)).toList(growable: false);
    final fallback = [...literals, ...hostnames];
    if (!enabled) return fallback;
    final rank = _ranked[host];
    final failed = _failed[host];
    if ((rank == null || rank.isEmpty) && (failed == null || failed.isEmpty)) return fallback;
    final known = <String>[];
    final unknown = <String>[];
    final dead = <String>[];
    for (final address in literals) {
      if (failed?.contains(address) ?? false) {
        dead.add(address);
      } else if (rank?[address] != null) {
        known.add(address);
      } else {
        unknown.add(address);
      }
    }
    known.sort((a, b) => rank![a]!.compareTo(rank[b]!));
    return [...known, ...unknown, ...dead, ...hostnames];
  }

  /// 连接成功：用真实耗时刷新这个地址的延迟（比后台探测更贴近当前时刻）。
  void recordSuccess(String host, String address, Duration elapsed) {
    if (!enabled || !_isLiteralAddress(address)) return;
    (_ranked[host] ??= {})[address] = elapsed.inMilliseconds;
    _failed[host]?.remove(address);
    _scheduleSave();
  }

  /// 连接失败：把地址沉到候选末尾，这样同一个坏节点不会每次都重新烧一遍超时。
  void recordFailure(String host, String address) {
    if (!enabled || !_isLiteralAddress(address)) return;
    (_failed[host] ??= {}).add(address);
    _ranked[host]?.remove(address);
    _scheduleSave();
  }

  /// 后台预热：只对「没有数据」或「数据已过期」的 host 发起探测，同一 host 不会并发探测两次。
  Future<void> warmUp(Map<String, List<String>> hosts, {int port = _defaultPort, bool Function(String host)? allowBadCertificate}) async {
    await ensureLoaded();
    if (!enabled) return;
    final now = DateTime.now();
    for (final entry in hosts.entries) {
      if (_inFlight.contains(entry.key)) continue;
      final probedAt = _probedAt[entry.key];
      if (probedAt != null && now.difference(probedAt) < _ttl) continue;
      _inFlight.add(entry.key);
      unawaited(probe(entry.key, entry.value, port: port, allowBadCertificate: allowBadCertificate?.call(entry.key) ?? false).whenComplete(() => _inFlight.remove(entry.key)));
    }
  }

  /// 上次探测时间（UI 用来显示「x 分钟前测过」）。
  DateTime? lastProbedAt(String host) => _probedAt[host];

  /// 某个 host 已知的地址延迟（毫秒），供 UI 展示。
  Map<String, int> rankedFor(String host) => Map.unmodifiable(_ranked[host] ?? const {});

  /// 某个 host 已知不可用的地址。
  Set<String> failedFor(String host) => Set.unmodifiable(_failed[host] ?? const {});

  /// 丢掉全部结果（UI 的「清除结果」）。
  Future<void> clear() async {
    _ranked.clear();
    _failed.clear();
    _probedAt.clear();
    _inFlight.clear();
    await save();
  }

  Future<void> save() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    await _store.write(_fileName, {
      'hosts': {
        for (final host in {..._ranked.keys, ..._failed.keys, ..._probedAt.keys})
          host: {
            'at': (_probedAt[host] ?? DateTime.now()).toIso8601String(),
            'ms': _ranked[host] ?? const <String, int>{},
            'failed': (_failed[host] ?? const <String>{}).toList(),
          },
      },
    });
  }

  void _scheduleSave() {
    _saveTimer?.cancel();
    _saveTimer = Timer(_saveDebounce, () => unawaited(save()));
  }

  static bool _isLiteralAddress(String value) => InternetAddress.tryParse(value) != null;

  /// IPv4 优先：有些网络上 IPv6 是黑洞（连接会一直挂到超时），而且 IPv6 边缘不保证服务所有站点。
  static List<String> _ipv4First(List<String> addresses) => [
        ...addresses.where((address) => InternetAddress.tryParse(address)?.type == InternetAddressType.IPv4),
        ...addresses.where((address) => InternetAddress.tryParse(address)?.type != InternetAddressType.IPv4),
      ];
}
