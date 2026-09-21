import 'dart:io';

import 'han1me_http_client.dart';

/// 诊断项。
enum DiagnosticKind { dns, connectivity, certificate, site, login }

/// 一项诊断的状态。
enum DiagnosticStatus { ok, fail, skipped }

/// 一项诊断的**原始测量结果**。
///
/// 这里只负责「测到的事实」：判定文案、建议、状态颜色都放在界面层生成，
/// 免得把 l10n 拖进数据层。判定成败已经在各 `checkXxx` 里按状态码做过一次
/// （只看「连上了」是不够的：服务端返回 403/5xx 时 TCP 连接是通的，内容却拿不到，
/// 若不判 FAIL 就会得出「一切正常」的误导结论）。
class DiagnosticResult {
  const DiagnosticResult({
    required this.kind,
    required this.status,
    this.latencyMs,
    this.statusCode,
    this.addresses = const <String>[],
    this.issuer,
    this.expiresAt,
    this.error,
  });

  final DiagnosticKind kind;
  final DiagnosticStatus status;

  /// 该项检测耗时（毫秒）。
  final int? latencyMs;

  /// HTTP 状态码（连接可用性与站点结构）。
  final int? statusCode;

  /// DNS 解析结果。
  final List<String> addresses;

  /// 证书颁发者与到期时间。
  final String? issuer;
  final DateTime? expiresAt;

  /// 失败原因（异常类型名或简短描述）。
  final String? error;
}

/// 站点可用性诊断：DNS 解析 → 连接可达性 → SSL 证书 → 站点结构 → 登录状态。
///
/// 请求走 [Han1meHttpClient]，因此会自动使用当前生效的网络设置（代理模式、内置
/// Hosts、DoH），诊断结论与真实加载路径一致 —— 这正是这一页的意义。
class NetworkDiagnostics {
  NetworkDiagnostics({required this.http, required this.siteUrl, required this.hasAccount});

  final Han1meHttpClient http;
  final String siteUrl;
  final bool hasAccount;

  String get host => Uri.tryParse(siteUrl)?.host ?? '';

  Future<List<DiagnosticResult>> runAll() async => [
        await checkDns(),
        await checkConnectivity(),
        await checkCertificate(),
        await checkSite(),
        checkLogin(),
      ];

  /// DNS 解析：解析失败说明域名被污染、域名写错，或者本机 DNS 不可用。
  Future<DiagnosticResult> checkDns() async {
    if (host.isEmpty) return const DiagnosticResult(kind: DiagnosticKind.dns, status: DiagnosticStatus.fail, error: 'invalid-url');
    final stopwatch = Stopwatch()..start();
    try {
      final addresses = await InternetAddress.lookup(host);
      return DiagnosticResult(kind: DiagnosticKind.dns, status: DiagnosticStatus.ok, latencyMs: stopwatch.elapsedMilliseconds, addresses: addresses.map((address) => address.address).toList(growable: false));
    } catch (error) {
      return DiagnosticResult(kind: DiagnosticKind.dns, status: DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, error: error.runtimeType.toString());
    }
  }

  /// 连接可达性：2xx/3xx 视为可达（镜像站常把 `/` 跳到 `/enter`），4xx/5xx 一律算失败。
  Future<DiagnosticResult> checkConnectivity() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get('$siteUrl/');
      final code = response.statusCode;
      return DiagnosticResult(kind: DiagnosticKind.connectivity, status: code >= 200 && code < 400 ? DiagnosticStatus.ok : DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, statusCode: code);
    } catch (error) {
      return DiagnosticResult(kind: DiagnosticKind.connectivity, status: DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, error: error.runtimeType.toString());
    }
  }

  /// SSL 证书：从响应里取对端证书，看颁发者与到期时间。
  ///
  /// 不用裸 `SecureSocket` 自行握手——那样会绕过本应用的内置 Hosts/代理设置，测出来的
  /// 东西和真实加载路径不是一回事。
  Future<DiagnosticResult> checkCertificate() async {
    final stopwatch = Stopwatch()..start();
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client.getUrl(Uri.parse('$siteUrl/'));
      final response = await request.close();
      final certificate = response.certificate;
      await response.drain<void>();
      if (certificate == null) return DiagnosticResult(kind: DiagnosticKind.certificate, status: DiagnosticStatus.skipped, latencyMs: stopwatch.elapsedMilliseconds);
      return DiagnosticResult(kind: DiagnosticKind.certificate, status: DiagnosticStatus.ok, latencyMs: stopwatch.elapsedMilliseconds, issuer: certificate.issuer, expiresAt: certificate.endValidity);
    } catch (error) {
      return DiagnosticResult(kind: DiagnosticKind.certificate, status: DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, error: error.runtimeType.toString());
    } finally {
      client.close(force: true);
    }
  }

  /// 站点结构：能拿到 2xx 但页面里没有已知的结构标记，说明站点改版或镜像站已被换成
  /// 别的东西（实测镜像站的 `/` 直接回 500 是常态，所以要按真实首页判断）。
  Future<DiagnosticResult> checkSite() async {
    final stopwatch = Stopwatch()..start();
    try {
      final response = await http.get('$siteUrl/');
      final code = response.statusCode;
      if (code < 200 || code >= 400) return DiagnosticResult(kind: DiagnosticKind.site, status: DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, statusCode: code);
      final known = ['home-rows-wrapper', 'video-item-container', 'horizontal-card', 'search-videos'];
      final matched = known.any(response.body.contains);
      return DiagnosticResult(kind: DiagnosticKind.site, status: matched ? DiagnosticStatus.ok : DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, statusCode: code, error: matched ? null : 'structure');
    } catch (error) {
      return DiagnosticResult(kind: DiagnosticKind.site, status: DiagnosticStatus.fail, latencyMs: stopwatch.elapsedMilliseconds, error: error.runtimeType.toString());
    }
  }

  /// 登录状态：本应用没有「cookie 是否还有效」的轻量探针，所以只区分有没有保存账号。
  DiagnosticResult checkLogin() => hasAccount
      ? const DiagnosticResult(kind: DiagnosticKind.login, status: DiagnosticStatus.ok)
      : const DiagnosticResult(kind: DiagnosticKind.login, status: DiagnosticStatus.skipped);
}
