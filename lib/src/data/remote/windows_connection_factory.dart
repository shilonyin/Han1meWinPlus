import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'address_ranker.dart';
import 'network_exceptions.dart';

class WindowsConnectionFactory {
  static const hanimeHosts = {'hanime1.me', 'hanime1.com', 'hanimeone.me'};

  /// Cloudflare edge addresses that actually serve [hanimeHosts] with the right
  /// SNI. Verified 2026-09-15 by requesting `/` and `/search` over each address:
  /// `162.159.0.1`, `108.162.192.1` and `172.64.33.1` answer Cloudflare
  /// error 1034 (Direct IP access not allowed) for every path, so they were
  /// removed — dialing them only burned the timeout already before.
  static const builtInAddresses = [
    '172.64.229.154',
    '104.19.0.1',
    '104.18.0.1',
    '104.16.0.1',
    '188.114.96.1',
    '2606:4700:3035::ac43:bb8d',
    '2606:4700:3030::6815:746',
    '2606:4700:3030::6815:714',
  ];

  /// 图片 CDN（CDN77）的优选节点。实测同一张缩略图：`89.187.187.14` 总耗时
  /// 0.95s（TLS 0.31s），而 `143.244.51.58` / `.245` 的 TLS 握手要 1.4-1.6s、
  /// 总耗时 2.5-3.9s。系统 DNS 会同时返回这两段并随机命中，所以固定优先快节点；
  /// 它们连不上时仍会回退到系统解析（`_connect` 里把域名接在最后）。
  static const imageCdnAddresses = ['89.187.187.14', '89.187.187.10', '89.187.187.19'];

  /// host → 实测可用的地址。
  ///
  /// getchu 是日本源站，全站只有 `210.155.150.145` / `.166` 两个地址，而且质量极不稳定：
  /// 2026-09-15 实测 `.166` 直连 0.5s（`.145` 超时），到 09-21 就完全反了过来 —— `.166`
  /// 直接连不上、`.145` 能通但整页要 8.2s，而**走代理只要 1.79s**。所以两个都放进来，
  /// 交给 `AddressRanker` 按实测延迟挑，别再手工判断哪个快（判断一次就过期一次）。
  /// AV 源站点的候选地址。
  ///
  /// 五个内置 AV 源里只有 xHamster 的边缘地址在**直连**下真的能服务
  /// （2026-10-23 实测 `104.16.3.81` → 200 4.8s、`104.16.4.81` → 200 5.9s）。
  /// missav.ai / jable.tv / supjav.com / kissjav.li 的 Cloudflare 地址直连全部
  /// 超时或被按 IP 拒绝（403），必须走代理 —— 往候选池里塞这些地址等于每次都
  /// 先烧掉几个 4 秒超时，所以它们不列地址，请求直接回退到系统解析。
  static const javAddresses = <String, List<String>>{
    'zh.xhamster.com': ['104.16.3.81', '104.16.4.81'],
  };

  static const builtInHosts = <String, List<String>>{
    'hanime1.me': builtInAddresses,
    'hanime1.com': builtInAddresses,
    'hanimeone.me': builtInAddresses,
    'www.getchu.com': ['210.155.150.145', '210.155.150.166'],
    'vdownload.hembed.com': imageCdnAddresses,
    ...javAddresses,
  };

  WindowsConnectionFactory({
    required this.useBuiltInHosts,
    required this.useDoh,
    required this.dohPreset,
    required this.dohCustomUrl,
    required this.dohBootstrapIps,
    required this.dohTimeoutSeconds,
  });

  final bool useBuiltInHosts;
  final bool useDoh;
  final String dohPreset;
  final String dohCustomUrl;
  final String dohBootstrapIps;
  final int dohTimeoutSeconds;

  Duration get _timeout => Duration(seconds: dohTimeoutSeconds);

  /// 域名兜底那一跳的等待上限。
  ///
  /// 比 [AddressRanker.probeTimeout] 宽（要走一次系统 DNS），但比 HttpClient 的
  /// 20s 连接超时窄：候选全挂时用户能早 12 秒看到「这个站点连不上」并直接去改代理。
  static const _hostFallbackTimeout = Duration(seconds: 8);

  /// 一次连接总共能花多久。
  ///
  /// 候选表最多 9 项、每项各自 4s 超时，最坏要 36 秒才轮完 —— 比改之前卡满 20s 还糟，
  /// 而且期间界面什么都不说。这里给个总预算：能用的节点在 4s 内就握手完了，轮过三个
  /// 都没好就说明线路本身不通，早点把结论交给界面。
  static const _connectBudget = Duration(seconds: 12);

  Future<ConnectionTask<Socket>> call(Uri uri, String? proxyHost, int? proxyPort) async {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
    final port = uri.hasPort ? uri.port : (uri.isScheme('https') ? 443 : 80);
    final builtIn = useBuiltInHosts ? builtInHosts[uri.host] : null;

    // DoH 与内置 Hosts 是**互补**的，不是二选一：
    // - 内置 Hosts 是照某次实测写死的 anycast IP，快且稳，但站点换边缘/换 IP 段后会过期；
    // - DoH 拿的是**当下**的真实解析结果，能跟着站点走，但它本身要先解析 DoH 服务器，
    //   在 DNS 被污染的网络里需要 bootstrap IP 才起得来。
    // 把两者的结果合成一个候选池交给 `AddressRanker` 按实测延迟排序，谁快用谁：
    // 内置项失效时 DoH 顶上，DoH 拿不到或被污染时内置项兜底。以前是「有内置列表就直接
    // 返回」，导致 hanime 主站（`hanime1.me` 等都在列表里）根本走不到 DoH —— 设置里
    // 开了 DoH 也对它不生效。
    final resolved = useDoh ? await _resolveWithDoh(uri.host) : const <String>[];

    if (builtIn != null) {
      // 后台预热探测：只有「没有数据」或「数据已过期」的 host 才会真的发起，
      // 而且不 await——本次请求仍按当前已知的排序走，不会因为探测而变慢。
      unawaited(AddressRanker.instance.warmUp(builtInHosts, allowBadCertificate: hanimeHosts.contains));
      return _connect(uri, mergeCandidates(builtIn: builtIn, resolved: resolved, host: uri.host), port);
    }
    if (!useDoh) return _startConnect(uri.host, port);
    return _connect(uri, mergeCandidates(builtIn: const [], resolved: resolved, host: uri.host), port);
  }

  /// 把「内置地址」「DoH 解析结果」「域名兜底项」合成一个候选池。
  ///
  /// 顺序是刻意的：[builtIn] 在前保证内置优选节点的优先级，[resolved] 接上让 DoH
  /// 能补上内置列表失效/过期的情况，[host] 永远最后 —— `AddressRanker.order` 也会
  /// 把非字面量地址恒定排在末尾，两边一致，绝不会出现「域名兜底项挡住真实 IP」。
  ///
  /// 去重是必要的：DoH 解析出来的往往就是那几个 Cloudflare anycast IP，和内置列表
  /// 高度重叠；不去重的话 `_connect` 会把同一个坏地址重复烧好几遍超时。
  static List<String> mergeCandidates({required List<String> builtIn, required List<String> resolved, required String host}) {
    final seen = <String>{};
    final merged = <String>[];
    for (final address in [...builtIn, ...resolved]) {
      // 域名兜底项统一在最后单独加，这里先跳过，避免它被提前插进 IP 中间。
      if (address == host) continue;
      if (seen.add(address)) merged.add(address);
    }
    merged.add(host);
    return merged;
  }

  /// 用 DoH 解析 [host]，失败返回空表（调用方会退回内置地址或系统解析）。
  ///
  /// 单独抽出来是因为 `call` 里有两处要用，而且失败必须**静默兜底** —— DoH 不可用
  /// 不该让整个请求失败，退回原来的路径即可。
  Future<List<String>> _resolveWithDoh(String host) async {
    try {
      return await _DohResolver(
        preset: dohPreset,
        customUrl: dohCustomUrl,
        bootstrapIps: dohBootstrapIps,
        timeout: _timeout,
      ).resolve(host);
    } catch (_) {
      return const [];
    }
  }

  Future<ConnectionTask<Socket>> _connect(Uri uri, List<String> addresses, int port) async {
    // 候选全挂时抛 [NetworkUnreachableException] 而不是最后那个 SocketException：
    // 界面据此说清「这个站点的节点全不通」并直接给出改代理的入口（见 app_error.dart）。
    // 其它异常（比如握手期崩了）原样上抛，别拿「网络不通」遮住真正的 bug。
    return NetworkUnreachableException.guard(
      uri.host,
      addresses.length,
      () => _connectCandidates(uri, addresses, port).timeout(_connectBudget),
    );
  }

  Future<ConnectionTask<Socket>> _connectCandidates(Uri uri, List<String> addresses, int port) async {
    final allowBadCertificate = useBuiltInHosts && hanimeHosts.contains(uri.host);
    final ranker = AddressRanker.instance;
    Object? lastError;
    StackTrace? lastStackTrace;
    // 候选顺序来自「延迟探测 + 自动选优」：实测快的排前面、连不上的沉到最后；没有数据时
    // 退回原来的顺序（IPv4 优先——有些网络上 IPv6 是黑洞，连接会一直挂到超时，而且 IPv6
    // 边缘不保证服务所有站点）。依旧不轮换起始下标：轮换只会让请求随机撞上不能服务该站
    // 点的边缘。
    for (final address in ranker.order(uri.host, addresses)) {
      Socket? plain;
      final stopwatch = Stopwatch()..start();
      try {
        // 兜底项（`uri.host` 本身）由 AddressRanker.order 恒定排在候选末尾，所以这里多等
        // 一会儿也不会挡住其他候选。
        //
        // 必须自己 await 出 socket：`SecureSocket.startConnect` 是**延迟连接**，直接返回
        // 的话它的失败发生在 HttpClient 内部，绕过本层 catch —— 界面只能看到一句
        // `HTTP connection timed out after 0:00:20`，既不知道候选全挂也拿不到改代理的入口。
        if (address == uri.host) {
          final task = await _startConnect(uri.host, port);
          try {
            final socket = await task.socket.timeout(_hostFallbackTimeout);
            return ConnectionTask.fromSocket(Future.value(socket), socket.destroy);
          } catch (_) {
            task.cancel();
            rethrow;
          }
        }
        // 逐个候选探测用短超时：候选里只要有一个黑洞地址，长超时就会让整次请求
        // 卡满设置里的秒数（默认 10s）才轮到下一个——实测内置列表里就踩过这种坑。
        plain = await Socket.connect(address, port, timeout: AddressRanker.probeTimeout);
        // 握手也要限时：TCP 连上不代表能服务该站点，而且有的节点握手会卡很久
        // （实测 21 秒）。不设限的话这一次连接就把整条请求拖死，TimeoutException
        // 会走下面的 catch 把该地址记成失败、继续试下一个。
        final secure = await SecureSocket.secure(
          plain,
          host: uri.host,
          onBadCertificate: allowBadCertificate ? (_) => true : null,
        ).timeout(AddressRanker.probeTimeout);
        // 真实耗时比后台探测更贴近当前时刻，直接喂回去当这次的最优证据。
        ranker.recordSuccess(uri.host, address, stopwatch.elapsed);
        return ConnectionTask.fromSocket(Future.value(secure), secure.destroy);
      } catch (error, stackTrace) {
        plain?.destroy();
        // 把坏地址沉底，同一个节点就不必在每次请求里重新烧一遍超时。
        ranker.recordFailure(uri.host, address);
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  Future<ConnectionTask<Socket>> _startConnect(String host, int port) => SecureSocket.startConnect(host, port);

  /// 单独测一个 DoH 端点能不能真的解析出地址。
  ///
  /// 设置里那一栏原来只能「配了就祈祷」：选错端点（比如在 DNS 被污染的网络里选了
  /// 需要 bootstrap 的 Cloudflare）只能等到真正断网时才发现。这里给一个显式入口 ——
  /// 用当前填的 preset／自定义地址／bootstrap IP 真发一次查询，把耗时和地址数返回。
  ///
  /// 探测域名用 `example.com`：它必然有 A 记录，而且不会命中 `resolve` 里按真实站点
  /// 写下的那批缓存。
  static Future<DohProbeResult> probeDohEndpoint({
    required String preset,
    required String customUrl,
    required String bootstrapIps,
    required Duration timeout,
    String host = 'example.com',
  }) async {
    final resolver = _DohResolver(preset: preset, customUrl: customUrl, bootstrapIps: bootstrapIps, timeout: timeout);
    if (resolver._endpoint == null) {
      return DohProbeResult(host: host, addresses: const [], milliseconds: 0, error: 'invalid-endpoint');
    }
    final watch = Stopwatch()..start();
    try {
      final addresses = await resolver.resolve(host).timeout(timeout);
      return DohProbeResult(host: host, addresses: addresses, milliseconds: watch.elapsedMilliseconds);
    } catch (error) {
      return DohProbeResult(host: host, addresses: const [], milliseconds: watch.elapsedMilliseconds, error: error.toString());
    }
  }
}

/// [WindowsConnectionFactory.probeDohEndpoint] 的结果。
class DohProbeResult {
  const DohProbeResult({required this.host, required this.addresses, required this.milliseconds, this.error});

  final String host;
  final List<String> addresses;
  final int milliseconds;

  /// 非 null 表示这次解析失败（端点不可达／被污染／超时）。
  final String? error;

  bool get ok => error == null && addresses.isNotEmpty;
}

class _DohResolver {
  static final _cache = <String, _CachedAddresses>{};

  const _DohResolver({
    required this.preset,
    required this.customUrl,
    required this.bootstrapIps,
    required this.timeout,
  });

  final String preset;
  final String customUrl;
  final String bootstrapIps;
  final Duration timeout;

  Future<List<String>> resolve(String host) async {
    final endpoint = _endpoint;
    if (endpoint == null) return const [];
    final key = '$endpoint:$host';
    final cached = _cache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) return cached.addresses;
    final answers = await Future.wait([_query(endpoint, host, 'A'), _query(endpoint, host, 'AAAA')]);
    final addresses = answers.expand((answer) => answer).toSet().toList(growable: false);
    if (addresses.isNotEmpty) _cache[key] = _CachedAddresses(addresses, DateTime.now().add(const Duration(minutes: 5)));
    return addresses;
  }

  Uri? get _endpoint => switch (preset) {
        'alidns' => Uri.parse('https://dns.alidns.com/dns-query'),
        'dnspod' => Uri.parse('https://doh.pub/dns-query'),
        'cloudflare' => Uri.parse('https://cloudflare-dns.com/dns-query'),
        'custom' => Uri.tryParse(customUrl.trim()),
        _ => null,
      };

  Future<List<String>> _query(Uri endpoint, String host, String type) async {
    final client = HttpClient()..connectionTimeout = timeout;
    final bootstrap = _bootstrapIps;
    if (bootstrap.isNotEmpty) {
      client.connectionFactory = (uri, proxyHost, proxyPort) async {
        if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
        if (uri.host != endpoint.host) return SecureSocket.startConnect(uri.host, uri.port);
        final plain = await Socket.connect(bootstrap.first, uri.port, timeout: timeout);
        try {
          final secure = await SecureSocket.secure(plain, host: uri.host);
          return ConnectionTask.fromSocket(Future.value(secure), secure.destroy);
        } catch (error) {
          plain.destroy();
          rethrow;
        }
      };
    }
    try {
      final request = await client.getUrl(endpoint.replace(queryParameters: {'name': host, 'type': type}));
      request.headers.set(HttpHeaders.acceptHeader, 'application/dns-json');
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) return const [];
      final json = jsonDecode(await utf8.decoder.bind(response).join());
      if (json is! Map) return const [];
      return (json['Answer'] as List? ?? const [])
          .whereType<Map>()
          .map((answer) => answer['data'])
          .whereType<String>()
          .where((address) => InternetAddress.tryParse(address) != null)
          .toList(growable: false);
    } finally {
      client.close(force: true);
    }
  }

  List<String> get _bootstrapIps {
    final values = bootstrapIps.split(RegExp(r'[,;\s]+')).where((value) => InternetAddress.tryParse(value) != null).toList();
    if (values.isNotEmpty) return values;
    return switch (preset) {
      'alidns' => const ['223.5.5.5', '223.6.6.6'],
      'dnspod' => const ['1.12.12.12', '120.53.53.53'],
      'cloudflare' => const ['1.1.1.1', '1.0.0.1'],
      _ => const [],
    };
  }
}

class _CachedAddresses {
  const _CachedAddresses(this.addresses, this.expiresAt);

  final List<String> addresses;
  final DateTime expiresAt;
}
