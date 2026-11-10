import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../shared/press_scale.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../../l10n/app_localizations.dart';
import '../../data/remote/address_ranker.dart';
import '../../data/remote/han1me_http_client.dart';
import '../../data/remote/network_diagnostics.dart';
import '../../data/remote/windows_connection_factory.dart';
import '../../data/remote/windows_http_overrides.dart';
import '../account/account_controller.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';
import '../shared/app_top_bar.dart';

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

/// 站点诊断：DNS → 连接 → 证书 → 站点结构 → 登录，外加内置候选地址的实测延迟。
///
/// 所有请求都走 [Han1meHttpClient]，所以用的是当前真实生效的网络设置（代理模式、内置
/// Hosts、DoH）—— 结论与真实加载路径一致，这是这一页存在的意义。
///
/// 视觉按 `p_diagnostics.png` 重做：页底 #F4F4F7、白卡圆角 16 带浅描边；
/// 文字只用 [AppDesignTokens] 的三层灰（ink / inkSubtle / inkMuted）；
/// 状态绿保留原有语义色。检测与网络逻辑完全未动。
class SiteDiagnosticsPage extends ConsumerStatefulWidget {
  const SiteDiagnosticsPage({super.key});

  @override
  ConsumerState<SiteDiagnosticsPage> createState() =>
      _SiteDiagnosticsPageState();
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
    final rule = settings == null
        ? 'DIRECT'
        : await WindowsHttpOverrides.resolveRule(
            mode: settings.proxyMode,
            custom: settings.customProxy,
          );
    setState(() {
      _running = true;
      _proxyActive = rule.toUpperCase().contains('PROXY');
      _siteUrl = settings?.resolvedBaseUrl ?? '';
      _accountName = account?.name ?? '';
    });
    final results = await NetworkDiagnostics(
      http: Han1meHttpClient(),
      siteUrl: _siteUrl,
      hasAccount: account != null,
    ).runAll();
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
      final addresses =
          WindowsConnectionFactory.builtInHosts[host] ?? const <String>[];
      // 探测是**直连**的（裸 TCP + TLS 握手），不走代理：内置地址本来就只在直连时才有
      // 意义。用真实 SNI 是因为「能连上」不等于「这个节点能服务该域名」。
      // 顺带测吞吐：只测握手会被「握手很快、传文件很慢」的节点骗过去，而这一列
      // 本来就是给用户判断「这个地址到底能不能用」看的。
      final probes = await AddressRanker.instance.probe(
        host,
        addresses,
        allowBadCertificate: WindowsConnectionFactory.hanimeHosts.contains(
          host,
        ),
        measureBandwidth: addresses.isNotEmpty,
      );
      if (!mounted) return;
      setState(() => _measured[host] = probes);
    }
    if (!mounted) return;
    setState(() => _probing = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    // 设计稿是浅色稿：#F4F4F7 页底 + 白卡。这里不复用主题面色，
    // 否则换了主题色后这一页会偏离设计稿。
    return Theme(
      data: theme.copyWith(
        scaffoldBackgroundColor: AppDesignTokens.pageBackground,
        appBarTheme: theme.appBarTheme.copyWith(
          backgroundColor: AppDesignTokens.pageBackground,
          surfaceTintColor: Colors.transparent,
          foregroundColor: AppDesignTokens.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
        ),
      ),
      child: Scaffold(
        // 设计稿（`18999_v6_diagnostics.png`）的页头是一整段：
        //   标题「站点诊断」 + 右侧灰字「DNS · 连接 · 证书 · 站点结构 · 登录」
        //   下面两行小字说明，同一行的最右侧是「开始诊断」主按钮。
        //
        // 原来把按钮挂在 AppBar 的 actions 里、说明单独占一整行 ——
        // 按钮跑到标题右上方，和说明隔了一整屏，既不紧凑也不像设计稿。
        appBar: AppTopBar(
          leading: settingsSubPageBack(context),
          title: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                l10n.siteDiagnostics,
                style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(width: 18),
              // 「DNS · 连接 · 证书 · 站点结构 · 登录」——设计稿用它一屏讲清
              // 这一页会查哪五件事，比一整句「检测当前站点的……」更易扫读。
              Flexible(
                child: Text(
                  'DNS · 连接 · 证书 · 站点结构 · 登录',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w400,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(28, 8, 28, 28),
          children: [
            // 说明与按钮**同一行**：左边两行小字（说明 + 「检测在本机实时进行」），
            // 右边「开始诊断」。设计稿里按钮和这段说明齐平，而不是浮在标题行。
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '依次检测 DNS 解析、网络连接、证书、站点结构与登录状态',
                        style: const TextStyle(
                          fontSize: 12.5,
                          height: 1.6,
                          color: AppDesignTokens.inkSubtle,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '检测在本机实时进行，不会上传任何数据',
                        style: const TextStyle(
                          fontSize: 11.5,
                          height: 1.5,
                          color: AppDesignTokens.inkMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 24),
                _runButton(l10n),
              ],
            ),
            // 说明到卡片的间距 24：设计稿说明底行 y168、首卡顶边 y200（含文字行盒余量）。
            const SizedBox(height: 24),
            // 「诊断结果」卡**常驻**。
            //
            // 原来它只在 `_results` 有值、也就是检测跑完之后才出现，于是进页面的
            // 第一秒是一整块空白，卡片位置还会往下跳一截（先没有、跑完突然插进来）。
            // 设计稿（`18999_v6_diagnostics.png`）画的是**结果状态**，但那五行的
            // 位置是固定的 —— 没结果时用同样的五行占位（灰色圆点 + 标题，
            // 详情留空），跑完再把状态与说明填进去，版面从头到尾不跳。
            _sectionCard(title: '诊断结果', children: _diagnosticRows(l10n)),
            // 卡片间距 21：设计稿（`18999_v6_diagnostics.png`）第一张卡底边
            // y526、第二张卡顶边 y547。原来给 16，两卡贴得比设计稿紧。
            const SizedBox(height: 21),
            _addressSection(context, l10n),
          ],
        ),
      ),
    );
  }

  /// 「诊断结果」里的五行。
  ///
  /// 已出结果时按 `_results` 渲染。
  /// 还没跑（或正在跑）时按 [DiagnosticKind] 的固定顺序给出占位行。
  /// 占位行与真实行同高，所以卡片高度在检测前后完全一致，不会「等一下突然长出来」。
  List<Widget> _diagnosticRows(AppLocalizations l10n) {
    final results = _results;
    final widgets = <Widget>[];
    for (var i = 0; i < DiagnosticKind.values.length; i++) {
      if (i > 0) widgets.add(_rowDivider());
      final kind = DiagnosticKind.values[i];
      final result = results?.firstWhere(
        (r) => r.kind == kind,
        orElse: () =>
            DiagnosticResult(kind: kind, status: DiagnosticStatus.skipped),
      );
      widgets.add(_diagnosticRow(context, l10n, result, kind: kind));
    }
    return widgets;
  }

  /// 页头右侧的「开始诊断」主按钮：实心 accentDeep 胶囊 34 高（设计稿）。
  Widget _runButton(AppLocalizations l10n) {
    return SizedBox(
      height: 34,
      child: PressScale(
        child: FilledButton.icon(
          onPressed: _running ? null : _runAll,
          style: FilledButton.styleFrom(
            backgroundColor: AppDesignTokens.accentDeep,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppDesignTokens.accentDeep.withValues(
              alpha: .45,
            ),
            disabledForegroundColor: Colors.white.withValues(alpha: .85),
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.lg),
            ),
            textStyle: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
          icon: _running
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Icon(Symbols.refresh_rounded, size: 16),
          label: Text(l10n.diagnose),
        ),
      ),
    );
  }

  /// 状态色：正常用绿色（与错误色区分开，光靠主题色表达不出「健康」），异常用 error。
  Color _okColor(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? const Color(0xFF6BD08A)
      : const Color(0xFF2E7D32);

  (IconData, Color) _statusVisual(
    BuildContext context,
    DiagnosticStatus status,
  ) => switch (status) {
    DiagnosticStatus.ok => (Symbols.check_rounded, _okColor(context)),
    DiagnosticStatus.fail => (
      Symbols.close_rounded,
      Theme.of(context).colorScheme.error,
    ),
    DiagnosticStatus.skipped => (
      Symbols.remove_rounded,
      AppDesignTokens.inkMuted,
    ),
  };

  String _statusText(AppLocalizations l10n, DiagnosticStatus status) =>
      switch (status) {
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
      DiagnosticKind.dns =>
        result.status == DiagnosticStatus.ok
            ? l10n.diagnosticDnsOk(
                Uri.tryParse(_siteUrl)?.host ?? _siteUrl,
                result.addresses.take(2).join(' / '),
              )
            : l10n.diagnosticDnsFail(Uri.tryParse(_siteUrl)?.host ?? _siteUrl),
      DiagnosticKind.connectivity =>
        result.status == DiagnosticStatus.ok
            ? l10n.diagnosticHttpOk(code ?? 0)
            : code != null
            ? l10n.diagnosticHttpFail(code)
            : l10n.diagnosticError(error),
      DiagnosticKind.certificate => switch (result.status) {
        DiagnosticStatus.ok => l10n.diagnosticCertificateOk(
          result.issuer ?? '',
        ),
        DiagnosticStatus.skipped => l10n.diagnosticCertificateNone,
        _ => l10n.diagnosticError(error),
      },
      DiagnosticKind.site =>
        result.status == DiagnosticStatus.ok
            ? l10n.diagnosticSiteOk(_siteUrl)
            : error == 'structure'
            ? l10n.diagnosticSiteStructure
            : error.isNotEmpty
            ? l10n.diagnosticError(error)
            : l10n.diagnosticSiteFail(code ?? 0),
      DiagnosticKind.login =>
        result.status == DiagnosticStatus.ok
            ? l10n.diagnosticLoginSaved(_accountName)
            : l10n.diagnosticLoginSkipped,
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

  /// 白色卡片：surface 底 + 16 圆角 + 极浅描边（设计稿的卡片靠描边和页底分开）。
  Widget _whiteCard({required Widget child}) {
    return Container(
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppDesignTokens.stroke),
      ),
      child: child,
    );
  }

  /// 带标题的分区卡片（「诊断结果」「地址实测延迟」）。
  Widget _sectionCard({String? title, required List<Widget> children}) {
    return _whiteCard(
      child: Padding(
        padding: EdgeInsets.fromLTRB(24, title == null ? 8 : 20, 24, 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (title != null) ...[
              Text(
                title,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: AppDesignTokens.ink,
                ),
              ),
              const SizedBox(height: 6),
            ],
            ...children,
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _rowDivider() => FractionallySizedBox(
    alignment: Alignment.centerLeft,
    child: Container(height: 1, color: AppDesignTokens.divider),
  );

  /// 诊断结果的一行：状态图标 + 标题/详情 + 右侧状态文字。
  /// 与设计稿一致，所有行铺在同一张白卡里，不再各自一张卡。
  ///
  /// [result] 为 null 表示**还没出结果**：只有一行灰色的「标题」，
  /// 图标与右侧状态都留白。行高与真实行一致（见下面的 50），
  /// 所以检测跑完后卡片不会跳动。
  Widget _diagnosticRow(
    BuildContext context,
    AppLocalizations l10n,
    DiagnosticResult? result, {
    required DiagnosticKind kind,
  }) {
    final (icon, color) = result == null
        ? (Symbols.radio_button_unchecked_rounded, AppDesignTokens.inkMuted)
        : _statusVisual(context, result.status);
    final measurement = result?.latencyMs == null
        ? null
        : '${result!.latencyMs} ms';
    final detail = result == null ? '' : _detail(l10n, result);
    final suggestion = result == null ? null : _suggestion(l10n, result);
    return Padding(
      // 行高 **50**：设计稿（`18999_v6_diagnostics.png`）的分隔线实测
      // 314 / 364 / 414 / 464 —— 严格等差 50。
      // 标题行盒 18 + 间距 4 + 详情 18 = 40，上下各补 4 落在 50。
      // 原来给 13（行高 62），5 行下来比设计稿多占一整行。
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(icon, size: 21, color: color),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _title(l10n, kind),
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: result == null
                        ? AppDesignTokens.inkMuted
                        : AppDesignTokens.ink,
                  ),
                ),
                if (detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      // 延迟放在**最后**（设计稿是 `hanime1.com → 203.0.113.42 · 12ms`），
                      // 而不是挂在最前面。一行以域名/状态开头更好扫读，耗时是补充信息。
                      measurement == null ? detail : '$detail · $measurement',
                      style: const TextStyle(
                        fontSize: 12.5,
                        height: 1.4,
                        color: AppDesignTokens.inkMuted,
                      ),
                    ),
                  ),
                if (suggestion != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Theme.of(
                          context,
                        ).colorScheme.errorContainer.withValues(alpha: .45),
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                      ),
                      child: Text(
                        '${l10n.suggestionLabel}：$suggestion',
                        style: TextStyle(
                          fontSize: 12,
                          height: 1.4,
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Padding(
            padding: const EdgeInsets.only(top: 1),
            // 还没出结果时右侧留空：设计稿那一列是状态文字，
            // 在「未检测」阶段写「未检测」反而像一条失败结论。
            child: result == null
                ? const SizedBox.shrink()
                : Text(
                    _statusText(l10n, result.status),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: color,
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  /// 地址实测延迟分区：设计稿（`18999_v6_diagnostics.png`）是一张
  /// **两列网格表** —— 每个域名一行「域名 …… 延迟」，左列四个、右列四个，
  /// 中间有 1px 竖分隔线。
  ///
  /// 原来做成「按站点分块、逐条列出每个候选 IP、带优选图标与状态文字」，
  /// 一块就有三四行、八块下来整页要滚三屏，和设计稿那种一眼扫完的表
  /// 完全是两回事。这里改成表格：**一个域名一行**，延迟按档着色，
  /// 贴边信息（优选地址、未能测速的原因）收进 tooltip，不再占版面。
  Widget _addressSection(BuildContext context, AppLocalizations l10n) {
    // 每个域名的最佳延迟：优先用实测，没有就退回 ranker 里缓存的值。
    int? bestFor(String host) {
      final measured = _measured[host] ?? const <AddressProbe>[];
      final ranked = AddressRanker.instance.rankedFor(host);
      final values = <int>[
        for (final probe in measured)
          if (probe.ok && probe.milliseconds != null) probe.milliseconds!,
        ...ranked.values,
      ];
      return values.isEmpty ? null : values.reduce((a, b) => a < b ? a : b);
    }

    final rows = <(String, int?)>[
      // **所有**域名都列出来，包括没有内置候选地址的那几个
      // （missav / jable / supjav / kissjav）—— 设计稿
      // （`18999_v6_diagnostics.png`）就是 8 个域名铺成两列八行，
      // 没有数据的照样占一行、延迟显示 `--`。
      // 原来按「有没有内置地址」过滤，八行只剩四行，下半张卡空一半。
      for (final host in _addressHosts) (host, bestFor(host)),
    ];
    // 按延迟升序：设计稿左列是 42/58/126/88、右列 210/156/182/168，
    // 并不是排好序的 —— 但它显然按「快 → 慢」铺满了第一列再铺第二列。
    final sorted = [...rows]
      ..sort((a, b) {
        if (a.$2 == null) return 1;
        if (b.$2 == null) return -1;
        return a.$2!.compareTo(b.$2!);
      });
    final half = (sorted.length + 1) ~/ 2;
    final left = sorted.take(half).toList();
    final right = sorted.skip(half).toList();

    return _whiteCard(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '地址实测延迟',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.ink,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              '直连状态下各候选地址的握手延迟',
              style: TextStyle(
                fontSize: 12.5,
                height: 1.5,
                color: AppDesignTokens.inkMuted,
              ),
            ),
            if (_proxyActive)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  l10n.addressLatencyProxyNotice,
                  style: const TextStyle(
                    fontSize: 12,
                    height: 1.5,
                    color: AppDesignTokens.inkSubtle,
                  ),
                ),
              ),
            const SizedBox(height: 14),
            LayoutBuilder(
              builder: (context, constraints) {
                // 两列：中间留 24 的沟，再各占一半。
                // 窄窗口（< 760）退回单列，否则域名和延迟会挤在一起。
                final twoColumn = constraints.maxWidth >= 760;
                if (!twoColumn) {
                  return Column(
                    children: [
                      for (final row in sorted)
                        _addressRow(context, row.$1, row.$2),
                    ],
                  );
                }
                return Row(
                  // 用 `start`（不是 `stretch`）：`stretch` 会把两列各自撑成
                  // 整块高度，白卡被撑破、分隔线跑到卡片外（实测）。
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final row in left)
                            _addressRow(context, row.$1, row.$2),
                        ],
                      ),
                    ),
                    // 1px 竖分隔线。高度写成「右侧行数 × 44」：
                    // 设计稿里它贯穿整张表（4 行 × 44 = 176）。
                    Container(
                      width: 1,
                      height: (right.length * 44).toDouble(),
                      margin: const EdgeInsets.symmetric(horizontal: 24),
                      color: AppDesignTokens.divider,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final row in right)
                            _addressRow(context, row.$1, row.$2),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
            if (_probing)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  /// 表格里的一行：`域名 ……………… 延迟`。
  ///
  /// 延迟按档着色（设计稿就是这么做的）：60 以内绿、150 以内橙、更慢红。
  /// 没测到的显示灰色 `--`，不用「未能测速」四个字，一行里不塞句子。
  Widget _addressRow(BuildContext context, String host, int? ms) {
    final color = ms == null
        ? AppDesignTokens.inkMuted
        : ms <= 60
        ? _okColor(context)
        : ms <= 150
        ? const Color(0xFFC77700)
        : Theme.of(context).colorScheme.error;
    return SizedBox(
      // 行高 44：设计稿（`18999_v6_diagnostics.png`）的 4 行是
      // y621/665/709/753，严格等差 44。
      height: 44,
      child: Row(
        children: [
          Expanded(
            child: Text(
              host,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: AppDesignTokens.ink),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            ms == null ? '--' : '$ms ms',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}
