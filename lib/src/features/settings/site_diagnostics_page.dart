import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../shared/glass/glass_panel.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/remote/address_ranker.dart';
import '../../data/remote/han1me_http_client.dart';
import '../../data/remote/network_diagnostics.dart';
import '../../data/remote/windows_connection_factory.dart';
import '../../data/remote/windows_http_overrides.dart';
import '../account/account_controller.dart';
import '../shared/press_scale.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';

/// 候选地址分组：Hanime1 的三个域名共用同一批 Cloudflare 边缘地址（同一个 List 常量），
/// 合成一组展示，免得同一个地址列表在页面上重复三遍。
///
/// 后五个 AV 源也列出来：其中只有 xHamster 有实测可用的内置地址，其余四个的
/// Cloudflare 边缘地址在直连下要么超时要么被按 IP 拒绝。列出来是为了让用户看清
/// 「这一组为什么没有候选」，否则页面只显示三组，会让人以为项目不支持这些站点。
const _addressHosts = <String>[
  'hanime1.com',
  'vdownload.hembed.com',
  'www.getchu.com',
  'zh.xhamster.com',
  'missav.ai',
  'jable.tv',
  'supjav.com',
  'kissjav.li',
];

String _addressGroupLabel(AppLocalizations l10n, String host) => switch (host) {
      'vdownload.hembed.com' => l10n.addressGroupImageCdn,
      'www.getchu.com' => l10n.addressGroupGetchu,
      'zh.xhamster.com' || 'missav.ai' || 'jable.tv' || 'supjav.com' || 'kissjav.li' => l10n.addressGroupJav,
      _ => l10n.addressGroupSite,
    };

/// 站点可用性诊断：DNS → 连接 → 证书 → 站点结构 → 登录，外加内置候选地址的实测延迟。
///
/// 所有请求都走 [Han1meHttpClient]，所以用的是当前真实生效的网络设置（代理模式、内置
/// Hosts、DoH）—— 结论与真实加载路径一致，这是这一页存在的意义。
class SiteDiagnosticsPage extends ConsumerStatefulWidget {
  const SiteDiagnosticsPage({super.key});

  @override
  ConsumerState<SiteDiagnosticsPage> createState() => _SiteDiagnosticsPageState();
}

class _SiteDiagnosticsPageState extends ConsumerState<SiteDiagnosticsPage> {
  final _measured = <String, List<AddressProbe>>{};
  List<DiagnosticResult>? _results;
  var _running = false;
  var _probing = false;
  var _proxyActive = false;
  var _siteUrl = '';
  var _accountName = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runAll());
  }

  Future<void> _runAll() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    final account = ref.read(accountProvider).valueOrNull;
    // 地址优选那一栏测的是**直连**延迟，而代理模式下内置地址根本不参与请求。不把这件事
    // 说出来，显示的 4 秒就会让人以为「站点很慢」，而真实访问可能是走代理的 1.8 秒。
    final rule = settings == null ? 'DIRECT' : await WindowsHttpOverrides.resolveRule(mode: settings.proxyMode, custom: settings.customProxy);
    setState(() {
      _running = true;
      _proxyActive = rule.toUpperCase().contains('PROXY');
      _siteUrl = settings?.resolvedBaseUrl ?? '';
      _accountName = account?.name ?? '';
    });
    final results = await NetworkDiagnostics(http: Han1meHttpClient(), siteUrl: _siteUrl, hasAccount: account != null).runAll();
    if (!mounted) return;
    setState(() {
      _results = results;
      _running = false;
    });
    // 地址探测要逐个握手（最慢的那个可能贴着超时），单独跑，别把诊断结果一起卡住。
    unawaited(_probeAddresses());
  }

  Future<void> _probeAddresses() async {
    setState(() => _probing = true);
    for (final host in _addressHosts) {
      final addresses = WindowsConnectionFactory.builtInHosts[host] ?? const <String>[];
      // 探测是**直连**的（裸 TCP + TLS 握手），不走代理：内置地址本来就只在直连时才有
      // 意义。用真实 SNI 是因为「能连上」不等于「这个节点能服务该域名」。
      // 顺带测吞吐：只测握手会被「握手很快、传文件很慢」的节点骗过去，而这一列
      // 本来就是给用户判断「这个地址到底能不能用」看的。
      final probes = await AddressRanker.instance.probe(host, addresses, allowBadCertificate: WindowsConnectionFactory.hanimeHosts.contains(host), measureBandwidth: addresses.isNotEmpty);
      if (!mounted) return;
      setState(() => _measured[host] = probes);
    }
    if (!mounted) return;
    setState(() => _probing = false);
  }

  /// 没有内置候选地址的站点。
  ///
  /// 这些站点（missav / jable / supjav / kissjav）的边缘地址在直连下全部连不上，
  /// 只能走系统解析或代理，所以既没有可测速的地址也没有任何指标。以前它们各自
  /// 占一张卡、每张只写一句「没有候选地址」，一屏里四张几乎空白的卡全是同一句话，
  /// 把真正有数据的卡挤到看不见的地方。合并成一张，正文里列一遍域名就够了。
  List<String> get _hostsWithoutCandidates => [
        for (final host in _addressHosts)
          if ((WindowsConnectionFactory.builtInHosts[host] ?? const <String>[]).isEmpty) host,
      ];

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(leading: settingsSubPageBack(context), title: Text(l10n.siteDiagnostics)),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 24), children: [
        Text(l10n.siteDiagnosticsDescription, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
        const SizedBox(height: 12),
        SizedBox(width: double.infinity, child: PressScale(child: FilledButton.icon(
          onPressed: _running ? null : _runAll,
          icon: _running ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Symbols.refresh_rounded),
          label: Text(l10n.diagnose),
        ))),
        const SizedBox(height: 16),
        for (final result in _results ?? const <DiagnosticResult>[]) _diagnosticCard(context, l10n, result),
        const SizedBox(height: 8),
        Text(l10n.addressLatency, style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w600)),
        const SizedBox(height: 4),
        Text(l10n.addressLatencyDescription, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
        if (_proxyActive) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.primaryContainer.withValues(alpha: .35), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Symbols.info_rounded, size: 16, color: scheme.onPrimaryContainer),
              const SizedBox(width: 8),
              Expanded(child: Text(l10n.addressLatencyProxyNotice, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onPrimaryContainer, height: 1.4))),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        for (final host in _addressHosts)
          if ((WindowsConnectionFactory.builtInHosts[host] ?? const <String>[]).isNotEmpty) _addressCard(context, l10n, host),
        if (_hostsWithoutCandidates.isNotEmpty) _noCandidatesCard(context, l10n, _hostsWithoutCandidates),
      ]),
    );
  }

  /// 状态色：正常用绿色（与错误色区分开，光靠主题色表达不出「健康」），异常用 error。
  Color _okColor(BuildContext context) => Theme.of(context).brightness == Brightness.dark ? const Color(0xFF6BD08A) : const Color(0xFF2E7D32);

  (IconData, Color) _statusVisual(BuildContext context, DiagnosticStatus status) => switch (status) {
        DiagnosticStatus.ok => (Symbols.check_rounded, _okColor(context)),
        DiagnosticStatus.fail => (Symbols.close_rounded, Theme.of(context).colorScheme.error),
        DiagnosticStatus.skipped => (Symbols.remove_rounded, Theme.of(context).colorScheme.outline),
      };

  String _statusText(AppLocalizations l10n, DiagnosticStatus status) => switch (status) {
        DiagnosticStatus.ok => l10n.diagnosticOk,
        DiagnosticStatus.fail => l10n.diagnosticFail,
        DiagnosticStatus.skipped => l10n.diagnosticSkipped,
      };

  String _title(AppLocalizations l10n, DiagnosticKind kind) => switch (kind) {
        DiagnosticKind.dns => l10n.diagnosticDns,
        DiagnosticKind.connectivity => l10n.diagnosticConnectivity,
        DiagnosticKind.certificate => l10n.diagnosticCertificate,
        DiagnosticKind.site => l10n.diagnosticSite,
        DiagnosticKind.login => l10n.diagnosticLogin,
      };

  String _detail(AppLocalizations l10n, DiagnosticResult result) {
    final code = result.statusCode;
    final error = result.error ?? '';
    return switch (result.kind) {
      DiagnosticKind.dns => result.status == DiagnosticStatus.ok ? l10n.diagnosticDnsOk(Uri.tryParse(_siteUrl)?.host ?? _siteUrl, result.addresses.take(2).join(' / ')) : l10n.diagnosticDnsFail(Uri.tryParse(_siteUrl)?.host ?? _siteUrl),
      DiagnosticKind.connectivity => result.status == DiagnosticStatus.ok ? l10n.diagnosticHttpOk(code ?? 0) : code != null ? l10n.diagnosticHttpFail(code) : l10n.diagnosticError(error),
      DiagnosticKind.certificate => switch (result.status) {
          DiagnosticStatus.ok => l10n.diagnosticCertificateOk(result.issuer ?? ''),
          DiagnosticStatus.skipped => l10n.diagnosticCertificateNone,
          _ => l10n.diagnosticError(error),
        },
      DiagnosticKind.site => result.status == DiagnosticStatus.ok
          ? l10n.diagnosticSiteOk(_siteUrl)
          : error == 'structure' ? l10n.diagnosticSiteStructure : error.isNotEmpty ? l10n.diagnosticError(error) : l10n.diagnosticSiteFail(code ?? 0),
      DiagnosticKind.login => result.status == DiagnosticStatus.ok ? l10n.diagnosticLoginSaved(_accountName) : l10n.diagnosticLoginSkipped,
    };
  }

  /// 建议只给失败项。403 是最常见的一种（Cloudflare 校验／地区限制），单独给文案。
  String? _suggestion(AppLocalizations l10n, DiagnosticResult result) {
    if (result.status != DiagnosticStatus.fail) return null;
    final code = result.statusCode;
    if (code == 403) return l10n.suggestionCloudflare;
    if (code != null && code >= 500) return l10n.suggestionSite;
    if (result.kind == DiagnosticKind.dns) return l10n.suggestionDns;
    if (result.kind == DiagnosticKind.site) return l10n.suggestionSite;
    return l10n.suggestionTimeout;
  }

  Widget _diagnosticCard(BuildContext context, AppLocalizations l10n, DiagnosticResult result) {
    final (icon, color) = _statusVisual(context, result.status);
    final measurement = result.latencyMs == null ? null : '${result.latencyMs} ms';
    return _card(
      context,
      icon: icon,
      color: color,
      title: _title(l10n, result.kind),
      measurement: measurement,
      status: _statusText(l10n, result.status),
      detail: _detail(l10n, result),
      suggestion: _suggestion(l10n, result),
    );
  }

  Widget _noCandidatesCard(BuildContext context, AppLocalizations l10n, List<String> hosts) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      solidColor: scheme.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(l10n.addressLatencyNoCandidatesTitle, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(hosts.join(' · '), style: textTheme.bodySmall?.copyWith(color: scheme.outline))),
        Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.addressLatencyNoCandidates, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4))),
      ]),
    );
  }

  Widget _addressCard(BuildContext context, AppLocalizations l10n, String host) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final addresses = WindowsConnectionFactory.builtInHosts[host] ?? const <String>[];
    final measured = {for (final probe in _measured[host] ?? const <AddressProbe>[]) probe.address: probe};
    final ranker = AddressRanker.instance;
    final ranked = ranker.rankedFor(host);
    final speed = ranker.throughputFor(host);
    final failed = ranker.failedFor(host);
    final preferred = ranker.enabled ? ranker.order(host, addresses).firstWhere((address) => ranked.containsKey(address) || measured[address]?.ok == true, orElse: () => '') : '';
    final preferredMs = ranked[preferred] ?? measured[preferred]?.milliseconds;
    final fastest = addresses.map((address) => measured[address]?.ok == true ? measured[address]!.milliseconds : ranked[address]).whereType<int>().fold<int?>(null, (best, value) => best == null || value < best ? value : best);

    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          solidColor: scheme.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text(_addressGroupLabel(l10n, host), style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (_probing) const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
          else if (fastest != null) Text('$fastest ms', style: textTheme.bodyMedium?.copyWith(color: _okColor(context), fontWeight: FontWeight.w600)),
        ]),
        Padding(padding: const EdgeInsets.only(top: 4), child: Text(host, style: textTheme.bodySmall?.copyWith(color: scheme.outline))),
        if (addresses.isEmpty)
          Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.addressLatencyNoCandidates, style: textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)))
        else ...[
          if (preferred.isNotEmpty && preferredMs != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(l10n.addressLatencyPreferred(preferred, preferredMs), style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant))),
        ],
        for (final address in addresses) Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Row(children: [
            Icon(address == preferred ? Symbols.bolt_rounded : failed.contains(address) ? Symbols.error_rounded : Symbols.circle_rounded, size: 16, color: address == preferred ? scheme.primary : failed.contains(address) ? scheme.error : scheme.outline),
            const SizedBox(width: 8),
            Expanded(child: Text(address, style: textTheme.bodyMedium)),
            Text(_addressMeasurement(l10n, measured[address], ranked[address], speed[address], failed.contains(address)), style: textTheme.bodyMedium?.copyWith(color: address == preferred ? scheme.primary : scheme.onSurfaceVariant, fontWeight: address == preferred ? FontWeight.w600 : null)),
          ]),
        ),
      ]),
    );
  }

  /// 把 [AddressProbe.note] 翻成给人看的一小段。
  ///
  /// note 是 [AddressRanker] 内部的短代码（`http-403` / `small-body` / `read-failed`…），
  /// 直接显示出来没人看得懂；分不出具体原因时统一说「未能测速」，比空白好。
  String? _probeNote(AppLocalizations l10n, String? note) {
    if (note == null) return null;
    if (note.startsWith('http-')) {
      final code = int.tryParse(note.substring(5));
      if (code != null) return l10n.addressProbeNoteHttp(code);
    }
    return l10n.addressProbeNoteNoBody;
  }

  /// 地址右侧那一小段测量值。
  ///
  /// 吞吐比延迟更能说明「这个地址到底能不能用」：握手 400ms 但只能跑 30 KB/s 的
  /// 节点，页面上比握手 600ms 能跑 800 KB/s 的那个慢得多。测不出吞吐时（握手成功
  /// 但 HTTP 打回 403／读超时）只显示延迟，把原因留给 [AddressProbe.note]。
  String _addressMeasurement(AppLocalizations l10n, AddressProbe? probe, int? rankedMs, int? kbps, bool failed) {
    if (probe?.ok == true) {
      final latency = '${probe!.milliseconds} ms';
      final speed = probe.kilobytesPerSecond ?? kbps;
      if (speed != null) return '$latency · $speed KB/s';
      // 握手成功但没测出吞吐时，把原因带出来。不然这一行只剩一个延迟，看的人
      // 会以为「这个地址只有延迟可看」，而实际情况可能是 HTTP 层被拒了。
      final note = _probeNote(l10n, probe.note);
      return note == null ? latency : '$latency · $note';
    }
    if (probe?.ok == false || (probe == null && failed)) return l10n.addressLatencyUnavailable;
    if (rankedMs != null) {
      final speed = kbps;
      return speed == null ? '$rankedMs ms' : '$rankedMs ms · $speed KB/s';
    }
    return l10n.addressLatencyNotProbed;
  }

  Widget _card(BuildContext context, {required IconData icon, required Color color, required String title, required String? measurement, required String status, required String detail, required String? suggestion}) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return GlassPanel(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
          borderRadius: BorderRadius.circular(AppRadius.lg),
          solidColor: scheme.surfaceContainerLow,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(width: 36, height: 36, alignment: Alignment.center, decoration: BoxDecoration(color: color.withValues(alpha: .14), shape: BoxShape.circle), child: Icon(icon, size: 20, color: color)),
          const SizedBox(width: 12),
          Expanded(child: Text(title, style: textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600))),
          if (measurement != null) ...[Text(measurement, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant)), const SizedBox(width: 10)],
          Text(status, style: textTheme.bodyMedium?.copyWith(color: color, fontWeight: FontWeight.w600)),
        ]),
        if (detail.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 10), child: Text(detail, style: textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant, height: 1.4))),
        if (suggestion != null) Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: scheme.errorContainer.withValues(alpha: .45), borderRadius: BorderRadius.circular(AppRadius.sm)),
            child: Text('${AppLocalizations.of(context)!.suggestionLabel}：$suggestion', style: textTheme.bodySmall?.copyWith(color: scheme.onErrorContainer, height: 1.4)),
          ),
        ),
      ]),
    );
  }
}
