import 'dart:async';
import 'dart:io';

import '../local/json_store.dart';

/// 单个候选地址的探测结果。
class AddressProbe {
  const AddressProbe({
    required this.address,
    required this.ok,
    this.milliseconds,
    this.kilobytesPerSecond,
    this.note,
  });

  final String address;
  final bool ok;

  /// 建连 + TLS 握手的耗时；[ok] 为假时是 null。
  final int? milliseconds;

  /// 握手后实际拉取响应体的吞吐（KB/s）。
  ///
  /// 只在显式测速时测量（见 [AddressRanker.probe] 的 `measureBandwidth`）：光是
  /// 握手快不代表下载快，实测同一批节点里有握手 0.3s 但整页要 4s 的。为 null
  /// 表示这次没测（后台预热）或没测出有效值。
  final int? kilobytesPerSecond;

  /// 探测过程中的补充说明（例如握手成功但 HTTP 层被拒），供诊断页原样展示。
  final String? note;
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

  /// 握手耗时差在这个范围内视为打平，改用吞吐决定先后。
  static const _latencyTieMs = 120;

  /// 吞吐只在响应体够大时才算。Cloudflare 边缘对我们的 `GET /` 只回一个 178 字节的
  /// 301 跳转，178B/1.1s 会算成 0 KB/s —— 页面上看着像「这个节点完全没有带宽」，
  /// 其实只是没有东西可下。样本小于这个值就当作测不出，不写进排序表。
  static const _minBandwidthBytes = 4096;

  /// HTTP 换行；测吞吐时要手写请求行，拼接时用它。
  static const _crlf = '\r\n';

  final JsonStore _store;

  /// 关掉后不重排、不预热探测（对应设置项 `useAddressRanking`）。
  bool enabled = true;

  final _ranked = <String, Map<String, int>>{};

  /// host → 地址 → 实测吞吐（KB/s）。只有显式测速会写这里，后台预热不测。
  final _throughput = <String, Map<String, int>>{};
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
        final throughput = value['kbps'];
        if (throughput is Map) {
          _throughput[host] = {
            for (final item in throughput.entries)
              if ((item.value as num).toInt() > 0) item.key.toString(): (item.value as num).toInt(),
          };
        }
        final failed = value['failed'];
        if (failed is List) _failed[host] = failed.map((item) => item.toString()).toSet();
      }
    } catch (_) {
      // 缓存读不出来就当没有，探测结果本来就是可以随时重建的。
    }
  }

  /// 并发探测 [addresses] 并把结果并进排序表。UI 的「重新测速」与 [warmUp] 都走这里。
  ///
  /// [measureBandwidth] 为真时会额外握手后真的拉一小段响应体，把吞吐一并测出来。
  /// 只给界面上的显式测速用：后台预热只关心「哪个节点先连上」，多拉 32KB 会让
  /// 预热从几百毫秒变成几秒。
  Future<List<AddressProbe>> probe(
    String host,
    List<String> addresses, {
    int port = _defaultPort,
    bool allowBadCertificate = false,
    bool measureBandwidth = false,
  }) async {
    final targets = addresses.where(_isLiteralAddress).toList(growable: false);
    if (targets.isEmpty) return const [];
    final results = <AddressProbe>[];
    var cursor = 0;
    Future<void> worker() async {
      while (cursor < targets.length) {
        final address = targets[cursor++];
        results.add(await _probeOne(host, address, port, allowBadCertificate, measureBandwidth: measureBandwidth));
      }
    }

    await Future.wait(List.generate(_concurrency.clamp(1, targets.length), (_) => worker()));
    final rank = _ranked[host] ??= {};
    final failed = _failed[host] ??= {};
    final speed = _throughput[host] ??= {};
    for (final result in results) {
      if (result.ok) {
        rank[result.address] = result.milliseconds!;
        failed.remove(result.address);
        final kbps = result.kilobytesPerSecond;
        // 这次没测吞吐（预热）时不覆盖旧值；测了但拿不到就说明确实取不到，清掉。
        if (kbps != null) {
          speed[result.address] = kbps;
        } else if (measureBandwidth) {
          speed.remove(result.address);
        }
      } else {
        rank.remove(result.address);
        failed.add(result.address);
        speed.remove(result.address);
      }
    }
    _probedAt[host] = DateTime.now();
    _scheduleSave();
    return results;
  }

  Future<AddressProbe> _probeOne(
    String host,
    String address,
    int port,
    bool allowBadCertificate, {
    bool measureBandwidth = false,
  }) async {
    final stopwatch = Stopwatch()..start();
    Socket? plain;
    try {
      plain = await Socket.connect(address, port, timeout: probeTimeout);
      // 保持 SNI = 域名：只按 IP 连上并不代表这个节点能服务该站点（实测过一批只回
      // Cloudflare 1034 的地址），握手带上域名才算真正可用。
      // TLS 握手同样要限时：TCP 连上不等于站点可用，实测 www.getchu.com 的备用地址
      // TCP 100ms 就连上了，握手却卡了 21 秒 —— 不设限它会被当作「可用但很慢」记进
      // 排序表，之后每次请求轮到它都要白等这么久。
      final secure = await SecureSocket.secure(plain, host: host, onBadCertificate: allowBadCertificate ? (_) => true : null).timeout(probeTimeout);
      stopwatch.stop();
      final milliseconds = stopwatch.elapsedMilliseconds;
      if (!measureBandwidth) {
        secure.destroy();
        return AddressProbe(address: address, ok: true, milliseconds: milliseconds);
      }
      final (throughput, note) = await _measureThroughput(secure, host);
      secure.destroy();
      return AddressProbe(address: address, ok: true, milliseconds: milliseconds, kilobytesPerSecond: throughput, note: note);
    } catch (_) {
      plain?.destroy();
      return AddressProbe(address: address, ok: false);
    }
  }

  /// 握手成功后再真的走一次 HTTP，量出「能下载多少」。
  ///
  /// 为什么要多这一步：握手快只说明 TCP/TLS 顺，媒体节点经常是握手 0.3s、拉一个
  /// 几十 KB 的图却要好几秒；只按握手排序列会稳定挑中这种「连得快、传得慢」的节点。
  /// 请求带 `Range` 限死 32KB，避免把整张图/整个页面拉下来。
  ///
  /// 返回 (KB/s, 备注)；拿不到响应体时吞吐为 null，备注说明原因。
  Future<(int?, String?)> _measureThroughput(Socket socket, String host) async {
    const sampleBytes = 32 * 1024;
    final stopwatch = Stopwatch()..start();
    final buffer = <int>[];
    try {
      socket.write(
        'GET / HTTP/1.1$_crlf'
        'Host: $host$_crlf'
        'Range: bytes=0-$sampleBytes$_crlf'
        'Accept: */*$_crlf'
        'Connection: close$_crlf'
        '$_crlf',
      );
      await socket.flush();
      var headerEnd = -1;
      await for (final chunk in socket.timeout(probeTimeout)) {
        buffer.addAll(chunk);
        if (headerEnd < 0) {
          // 响应头只会出现在开头且通常不到 1KB；超过 8KB 还没收完就是异常响应。
          headerEnd = _indexOfHeaderEnd(buffer);
          if (headerEnd < 0 && buffer.length > 8192) return (null, 'headers-too-large');
        }
        if (headerEnd >= 0 && buffer.length - headerEnd >= sampleBytes) break;
      }
      stopwatch.stop();
      if (headerEnd < 0) return (null, 'no-response');
      final status = _statusCodeOf(buffer);
      if (status >= 400) return (null, 'http-$status');
      // 3xx 的响应体是给人看的跳转说明（Cloudflare 边缘对我们的 `GET /` 只回一个
      // 178 字节的 301），拿它算吞吐没有任何意义，还会白等到连接关闭。
      if (status >= 300) return (null, 'redirect');
      final received = buffer.length - headerEnd;
      final elapsed = stopwatch.elapsedMilliseconds;
      if (received <= 0 || elapsed <= 0) return (null, 'empty-body');
      if (received < _minBandwidthBytes) return (null, 'small-body');
      return (((received / 1024) / (elapsed / 1000)).round(), null);
    } catch (_) {
      return (null, 'read-failed');
    }
  }

  /// `\r\n\r\n` 之后就是响应体，返回它的起始下标；没找到返回 -1。
  static int _indexOfHeaderEnd(List<int> bytes) {
    for (var i = 0; i + 3 < bytes.length; i++) {
      if (bytes[i] == 13 && bytes[i + 1] == 10 && bytes[i + 2] == 13 && bytes[i + 3] == 10) return i + 4;
    }
    return -1;
  }

  /// 从状态行 `HTTP/1.1 200 OK` 里取状态码。
  static int _statusCodeOf(List<int> bytes) {
    final end = bytes.indexOf(13);
    if (end < 0) return 0;
    final parts = String.fromCharCodes(bytes.sublist(0, end)).split(' ');
    return parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
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
    final speed = _throughput[host];
    known.sort((a, b) {
      final byLatency = rank![a]!.compareTo(rank[b]!);
      // 握手耗时相差不到 120ms 就算「一样快」——这个差距对观感没影响，而握手快、
      // 传输慢的节点恰恰都落在这个区间里，一律按吞吐决定先后。
      if (byLatency.abs() <= _latencyTieMs) {
        final speedA = speed?[a];
        final speedB = speed?[b];
        if (speedA != null && speedB != null && speedA != speedB) return speedB.compareTo(speedA);
      }
      return byLatency;
    });
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
    _throughput[host]?.remove(address);
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

  /// 某个 host 已知的地址吞吐（KB/s），供 UI 展示。没有测过就是空表。
  Map<String, int> throughputFor(String host) => Map.unmodifiable(_throughput[host] ?? const {});

  /// 某个 host 已知不可用的地址。
  Set<String> failedFor(String host) => Set.unmodifiable(_failed[host] ?? const {});

  /// 丢掉全部结果（UI 的「清除结果」）。
  Future<void> clear() async {
    _ranked.clear();
    _throughput.clear();
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
            'kbps': _throughput[host] ?? const <String, int>{},
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
