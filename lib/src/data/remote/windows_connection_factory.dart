import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'address_ranker.dart';

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
  static const builtInHosts = <String, List<String>>{
    'hanime1.me': builtInAddresses,
    'hanime1.com': builtInAddresses,
    'hanimeone.me': builtInAddresses,
    'www.getchu.com': ['210.155.150.145', '210.155.150.166'],
    'vdownload.hembed.com': imageCdnAddresses,
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

  Future<ConnectionTask<Socket>> call(Uri uri, String? proxyHost, int? proxyPort) async {
    if (proxyHost != null) return Socket.startConnect(proxyHost, proxyPort ?? uri.port);
    final port = uri.hasPort ? uri.port : (uri.isScheme('https') ? 443 : 80);
    final builtIn = useBuiltInHosts ? builtInHosts[uri.host] : null;
    if (builtIn != null) {
      // 后台预热探测：只有「没有数据」或「数据已过期」的 host 才会真的发起，
      // 而且不 await——本次请求仍按当前已知的排序走，不会因为探测而变慢。
      unawaited(AddressRanker.instance.warmUp(builtInHosts, allowBadCertificate: hanimeHosts.contains));
      return _connect(uri, [...builtIn, uri.host], port);
    }
    if (!useDoh) return _startConnect(uri.host, port);
    try {
      final addresses = await _DohResolver(
        preset: dohPreset,
        customUrl: dohCustomUrl,
        bootstrapIps: dohBootstrapIps,
        timeout: _timeout,
      ).resolve(uri.host);
      if (addresses.isNotEmpty) return _connect(uri, [...addresses, uri.host], port);
    } catch (_) {}
    return _connect(uri, [uri.host], port);
  }

  Future<ConnectionTask<Socket>> _connect(Uri uri, List<String> addresses, int port) async {
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
        if (address == uri.host) return _startConnect(uri.host, port);
        // 逐个候选探测用短超时：候选里只要有一个黑洞地址，长超时就会让整次请求
        // 卡满设置里的秒数（默认 10s）才轮到下一个——实测内置列表里就踩过这种坑。
        plain = await Socket.connect(address, port, timeout: AddressRanker.probeTimeout);
        final secure = await SecureSocket.secure(
          plain,
          host: uri.host,
          onBadCertificate: allowBadCertificate ? (_) => true : null,
        );
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
