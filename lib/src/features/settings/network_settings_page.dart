import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/cast_receiver.dart';
import '../../core/app_radius.dart';
import '../../core/settings.dart';
import '../../core/configured_media_kit_video_player.dart';
import '../../data/remote/han1me_http_client.dart';
import '../../data/remote/webview_environment.dart';
import '../../data/remote/windows_connection_factory.dart';
import '../../data/remote/windows_proxy.dart';
import '../../data/remote/jav/jav_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../account/account_controller.dart';
import '../explore/explore_controller.dart';
import '../shared/press_scale.dart';
import 'selection_settings_pages.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';
import 'site_diagnostics_page.dart';
import 'site_groups_page.dart';
import 'settings_pane_scope.dart';
import '../../core/app_dialog.dart';

class NetworkSettingsPage extends ConsumerStatefulWidget {
  const NetworkSettingsPage({super.key});

  @override
  ConsumerState<NetworkSettingsPage> createState() => _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends ConsumerState<NetworkSettingsPage> {
  /// 「站点可用性诊断」直接在这块右侧内容区里切换显示，而不是 push 一个全屏页：
  /// 设置是「左分类 + 右内容」的两栏结构，push 会把左侧分类栏整个盖住，
  /// 退出后还得重新点一次分类才能回到这里。
  var _showDiagnostics = false;
  var _showSiteGroups = false;

  @override
  Widget build(BuildContext context) {
    if (_showDiagnostics) return SettingsSubPageScope(onBack: () => setState(() => _showDiagnostics = false), child: const SiteDiagnosticsPage());
    if (_showSiteGroups) return SettingsSubPageScope(onBack: () => setState(() => _showSiteGroups = false), child: const SiteGroupsPage());
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(appBar: embeddedInSettingsPanes(context) ? null : AppBar(title: Text(l10n.networkSettings)), body: ListView(children: [
       SettingsCardList(title: l10n.general, children: [
        SettingsCardItem(title: l10n.site, subtitle: settings.comicMode ? 'https://hanimeone.me' : settings.baseUrl, leading: const Icon(Symbols.language_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => showSitePicker(context, ref, settings, onManageGroups: () => setState(() => _showSiteGroups = true))),
       SettingsCardItem(title: l10n.customMirrorSite, subtitle: _mirrorSummary(l10n, settings), leading: const Icon(Symbols.link_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => _showMirrorSettings(context, ref, settings, controller)),
       SettingsCardItem(title: l10n.useBuiltInHosts, subtitle: settings.useBuiltInHosts && settings.proxyMode != 'direct' ? '${l10n.useBuiltInHostsDescription}\n${l10n.proxyDirectOnlyHint}' : l10n.useBuiltInHostsDescription, leading: const Icon(Symbols.dns_rounded), trailing: Switch(value: settings.useBuiltInHosts, onChanged: (value) => controller.saveChanges((current) => current.copyWith(useBuiltInHosts: value)))),        SettingsCardItem(title: l10n.siteDiagnostics, subtitle: l10n.siteDiagnosticsDescription, leading: const Icon(Symbols.network_check_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => setState(() => _showDiagnostics = true)),       SettingsCardItem(title: l10n.proxy, subtitle: _proxySummary(l10n, settings), leading: const Icon(Symbols.vpn_lock_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => _showProxySettings(context, settings, controller)),
       SettingsCardItem(title: l10n.doh, subtitle: _dohSummary(l10n, settings), leading: const Icon(Symbols.security_rounded), trailing: const Icon(Symbols.chevron_right_rounded), onTap: () => _showDohSettings(context, settings, controller)),
      ]),
      if (CastReceiver.isSupported)
        // 分组标题用分类名「投屏」，条目才是「投屏接收端」—— 和本页其他分组
        // （标题是分类、条目是具体项）一致。此前这里两者共用 dlnaReceiver，
        // 因为该条目掉出了卡片分支、连分组标题一起没渲染，重复才没显形。
        SettingsCardList(title: l10n.castToDevice, children: [
          ValueListenableBuilder<bool>(
            valueListenable: CastReceiver.instance.running,
            builder: (context, running, _) => SettingsCardItem(
              title: l10n.dlnaReceiver,
              subtitle: running ? '${l10n.dlnaReceiverRunning}\n${CastReceiver.instance.location}' : l10n.dlnaReceiverDescription,
              leading: const Icon(Symbols.cast_connected_rounded),
              trailing: Switch(value: settings.dlnaReceiverEnabled, onChanged: (value) => controller.saveChanges((current) => current.copyWith(dlnaReceiverEnabled: value))),
            ),
          ),
        ]),
    ]));
  }

  /// 副标题：当前在用的镜像 + 还存了几个候选。只显示地址的话，用户看不出自己
  /// 其实还存着别的镜像可以随时切。
  String _mirrorSummary(AppLocalizations l10n, AppSettings settings) {
    final count = settings.customMirrorSites.length;
    if (!settings.mirrorActive) {
      return count == 0 ? l10n.customMirrorSiteHint : '${l10n.customMirrorSites} ($count)';
    }
    return count <= 1 ? settings.customMirrorSite : '${settings.customMirrorSite} (+${count - 1})';
  }

  String _dohSummary(AppLocalizations l10n, AppSettings settings) => !settings.useDoh ? l10n.dohDisabled : settings.dohPreset == 'custom' ? settings.dohCustomUrl.ifEmpty(l10n.custom) : _dohPresets[settings.dohPreset]!;

  Future<void> _showMirrorSettings(BuildContext context, WidgetRef ref, AppSettings settings, SettingsController controller) async {
    final result = await showAppDialog<_MirrorSettings>(context: context, builder: (_) => _MirrorSettingsDialog(settings: settings));
    if (result == null) return;
    final unchanged = result.enabled == settings.useCustomMirrorSite &&
        result.activeUrl == settings.customMirrorSite &&
        result.appendPath == settings.appendCustomMirrorPath &&
        listEquals(result.urls, settings.customMirrorSites);
    if (unchanged) return;
    await controller.saveChanges((current) => current.copyWith(useCustomMirrorSite: result.enabled, customMirrorSite: result.activeUrl, customMirrorSites: result.urls, appendCustomMirrorPath: result.appendPath));
    ref.invalidate(accountProvider);
    resetHomeFeed(ref);
  }

  Future<void> _showDohSettings(BuildContext context, AppSettings settings, SettingsController controller) async {
    final result = await showAppDialog<_DohSettings>(context: context, builder: (_) => _DohSettingsDialog(settings: settings));
    if (result != null) await controller.saveChanges((current) => current.copyWith(useDoh: result.enabled, dohPreset: result.preset, dohCustomUrl: result.customUrl, dohBootstrapIps: result.bootstrapIps, dohTimeoutSeconds: result.timeoutSeconds));
  }

  String _proxySummary(AppLocalizations l10n, AppSettings settings) => switch (settings.proxyMode) {
        'direct' => l10n.proxyDirect,
        'custom' => settings.customProxy.isEmpty ? l10n.proxyCustom : '${l10n.proxyCustom} · ${settings.customProxy}',
        _ => l10n.proxySystem,
      };

  /// 代理模式会影响三套网络栈：Dart 的 HttpClient（图片/页面/评论）、mpv（视频）
  /// 与 WebView2（登录、Cloudflare 挑战），所以保存后要把三者都刷新一遍，
  /// 否则只有其中一部分跟随新设置。
  Future<void> _showProxySettings(BuildContext context, AppSettings settings, SettingsController controller) async {
    final result = await showAppDialog<_ProxySettings>(context: context, builder: (_) => _ProxySettingsDialog(settings: settings));
    if (result == null) return;
    await controller.saveChanges((current) => current.copyWith(proxyMode: result.mode, customProxy: result.custom));
    await ConfiguredMediaKitVideoPlayer.refreshHttpProxy();
    // WebView 环境的代理参数只在创建时下发，且已创建的实例也改不了，
    // 只能重建（下次进入登录页/CF 页时自然生效）。
    ref.invalidate(webViewEnvironmentProvider);
  }

}

const _dohPresets = {'alidns': 'AliDNS', 'dnspod': 'DNSPod', 'cloudflare': 'Cloudflare'};

class _ProxySettings { const _ProxySettings({required this.mode, required this.custom}); final String mode; final String custom; }

class _ProxySettingsDialog extends StatefulWidget { const _ProxySettingsDialog({required this.settings}); final AppSettings settings; @override State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState(); }

class _ProxySettingsDialogState extends State<_ProxySettingsDialog> {
  late var _mode = widget.settings.proxyMode;
  late final _custom = TextEditingController(text: widget.settings.customProxy);

  @override
  void initState() {
    super.initState();
    // 地址是边打边校验的，所以要监听输入。
    _custom.addListener(_onChanged);
  }

  void _onChanged() => setState(() {});

  @override
  void dispose() {
    _custom.removeListener(_onChanged);
    _custom.dispose();
    super.dispose();
  }

  /// 当前输入框里地址的校验结果；只有手动模式才需要校验。
  ProxyAddressStatus get _status => WindowsProxy.validate(_custom.text);

  bool get _canSave => _mode != 'custom' || _status == ProxyAddressStatus.valid;

  String? _errorText(AppLocalizations l10n) => switch (_status) {
        ProxyAddressStatus.empty => l10n.proxyAddressEmpty,
        ProxyAddressStatus.missingHostOrPort => l10n.proxyAddressMissingPort,
        ProxyAddressStatus.unsupportedScheme => l10n.proxyAddressUnsupportedScheme,
        ProxyAddressStatus.socksUnsupported => l10n.proxyAddressSocksUnsupported,
        ProxyAddressStatus.valid => null,
      };

  /// 把「当前会实际生效什么」摊开给用户看。
  ///
  /// 展示的是 Dart 侧的规则（界面、图片、评论走的那条路）。「跟随系统」模式下
  /// 系统代理要异步读注册表才能知道，弹窗里同步展示不了，所以只说明来源；
  /// 站点诊断页那栏已经有解析后的实际值。
  Widget _currentStatus(BuildContext context, AppLocalizations l10n) {
    final theme = Theme.of(context);
    final (text, tone) = switch (_mode) {
      'direct' => (l10n.proxyCurrentDirect, theme.colorScheme.onSurfaceVariant),
      'custom' => switch (_status) {
          ProxyAddressStatus.valid => (l10n.proxyCurrent(WindowsProxy.rule(_custom.text) ?? 'DIRECT'), theme.colorScheme.onSurfaceVariant),
          // 填错了最终也走直连，用错误色和「当前生效：直连」把后果说清楚。
          _ => (l10n.proxyCurrentDirect, theme.colorScheme.error),
        },
      _ => (l10n.proxyDescription, theme.colorScheme.onSurfaceVariant),
    };
    return Text(text, style: theme.textTheme.bodySmall?.copyWith(color: tone, height: 1.4));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = [('system', l10n.proxySystem), ('direct', l10n.proxyDirect), ('custom', l10n.proxyCustom)];
    final custom = _mode == 'custom';
    return AlertDialog(title: Text(l10n.proxy), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(l10n.proxyDescription, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
      const SizedBox(height: 4),
      for (final option in options) ListTile(contentPadding: EdgeInsets.zero, dense: true, title: Text(option.$2), trailing: _mode == option.$1 ? const Icon(Symbols.check_rounded) : null, onTap: () => setState(() => _mode = option.$1)),
      const SizedBox(height: 8),
      TextField(
        controller: _custom,
        enabled: custom,
        keyboardType: TextInputType.url,
        decoration: InputDecoration(
          labelText: l10n.proxyCustomAddress,
          helperText: l10n.proxyCustomAddressHint,
          // 只在手动模式下报错：其它模式里这个框是灰的，报错会让人以为选错了。
          errorText: custom ? _errorText(l10n) : null,
        ),
      ),
      const SizedBox(height: 4),
      _currentStatus(context, l10n),
    ])), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: !_canSave ? null : () => Navigator.pop(context, _ProxySettings(mode: _mode, custom: _custom.text.trim())), child: Text(l10n.save)))]);
  }
}

class _DohSettings { const _DohSettings({required this.enabled, required this.preset, required this.customUrl, required this.bootstrapIps, required this.timeoutSeconds}); final bool enabled; final String preset; final String customUrl; final String bootstrapIps; final int timeoutSeconds; }

class _DohSettingsDialog extends StatefulWidget { const _DohSettingsDialog({required this.settings}); final AppSettings settings; @override State<_DohSettingsDialog> createState() => _DohSettingsDialogState(); }

class _DohSettingsDialogState extends State<_DohSettingsDialog> {
  late var _enabled = widget.settings.useDoh;
  late var _preset = widget.settings.dohPreset;
  late final _customUrl = TextEditingController(text: widget.settings.dohCustomUrl);
  late final _bootstrapIps = TextEditingController(text: widget.settings.dohBootstrapIps);
  late final _timeout = TextEditingController(text: widget.settings.dohTimeoutSeconds.toString());
  var _testing = false;
  String? _testResult;
  bool _testOk = false;
  @override void dispose() { _customUrl.dispose(); _bootstrapIps.dispose(); _timeout.dispose(); super.dispose(); }

  /// 用**当前填的值**真发一次解析，而不是用已保存的配置 —— 这样「改完先测再存」
  /// 的顺序才成立，选错端点在按下保存之前就能看见。
  Future<void> _testDoh(AppLocalizations l10n) async {
    setState(() {
      _testing = true;
      _testResult = null;
    });
    final seconds = (int.tryParse(_timeout.text) ?? 10).clamp(1, 60);
    final result = await WindowsConnectionFactory.probeDohEndpoint(
      preset: _preset,
      customUrl: _customUrl.text.trim(),
      bootstrapIps: _bootstrapIps.text.trim(),
      timeout: Duration(seconds: seconds),
    );
    if (!mounted) return;
    setState(() {
      _testing = false;
      _testOk = result.ok;
      _testResult = result.ok
          ? l10n.dohTestOk(result.host, result.addresses.length, result.milliseconds)
          : l10n.dohTestFail(result.error ?? l10n.addressLatencyUnavailable);
    });
  }
  @override Widget build(BuildContext context) { final l10n = AppLocalizations.of(context)!; return AlertDialog(title: Text(l10n.dohSettings), content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(l10n.useDoh), value: _enabled, onChanged: (value) => setState(() => _enabled = value)), DropdownButtonFormField(initialValue: _preset, decoration: InputDecoration(labelText: l10n.dohPreset), items: [..._dohPresets.entries.map((item) => DropdownMenuItem(value: item.key, child: Text(item.value))), DropdownMenuItem(value: 'custom', child: Text(l10n.custom))], onChanged: (value) => setState(() => _preset = value!)), const SizedBox(height: 12), TextField(controller: _customUrl, enabled: _preset == 'custom', keyboardType: TextInputType.url, decoration: InputDecoration(labelText: l10n.dohCustomUrl)), const SizedBox(height: 12), TextField(controller: _bootstrapIps, decoration: InputDecoration(labelText: l10n.dohBootstrapIps, helperText: l10n.dohBootstrapIpsDescription)), const SizedBox(height: 12), TextField(controller: _timeout, keyboardType: TextInputType.number, decoration: InputDecoration(labelText: l10n.dohTimeoutSeconds, helperText: l10n.dohTimeoutSecondsDescription)), const SizedBox(height: 12), SizedBox(width: double.infinity, child: PressScale(child: OutlinedButton.icon(onPressed: _testing ? null : () => _testDoh(l10n), icon: _testing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Symbols.network_check_rounded), label: Text(_testing ? l10n.dohTesting : l10n.dohTest)))), if (_testResult != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_testResult!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: _testOk ? null : Theme.of(context).colorScheme.error, height: 1.4)))])), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, _DohSettings(enabled: _enabled, preset: _preset, customUrl: _customUrl.text.trim(), bootstrapIps: _bootstrapIps.text.trim(), timeoutSeconds: (int.tryParse(_timeout.text) ?? 10).clamp(1, 60))), child: Text(l10n.save)))]); }
}

class _MirrorSettings {
  const _MirrorSettings({required this.enabled, required this.urls, required this.activeUrl, required this.appendPath});

  final bool enabled;
  final List<String> urls;
  final String activeUrl;
  final bool appendPath;
}

/// 镜像站设置：候选列表 + 逐条测速。
///
/// 之前只存一个地址，镜像站一换就得重新去别处找、再手输一遍。现在候选列表常驻，
/// 列表里直接切当前使用的那一个；每一条都能单独测，不用切过去再回主页看有没有
/// 加载出来。
class _MirrorSettingsDialog extends StatefulWidget {
  const _MirrorSettingsDialog({required this.settings});

  final AppSettings settings;

  @override
  State<_MirrorSettingsDialog> createState() => _MirrorSettingsDialogState();
}

class _MirrorSettingsDialogState extends State<_MirrorSettingsDialog> {
  late var _enabled = widget.settings.useCustomMirrorSite;
  late final _urls = <String>[...widget.settings.customMirrorSites];
  late var _active = widget.settings.customMirrorSite;
  late var _appendPath = widget.settings.appendCustomMirrorPath;
  final _input = TextEditingController();

  /// 当前正在测的那一条（同一时刻只测一条，镜像请求本来就慢，并发没意义）。
  String? _probing;
  final _probeResults = <String, String>{};

  @override
  void initState() {
    super.initState();
    // 老配置里那个单个地址也要出现在候选列表里，否则用户会看到一个空列表却还在用着它。
    if (_active.isNotEmpty && !_urls.contains(_active)) _urls.insert(0, _active);
    if (_active.isEmpty && _urls.isNotEmpty) _active = _urls.first;
  }

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  void _addUrl(AppLocalizations l10n) {
    final url = _normalize(_input.text);
    if (!_validMirrorUrl(url)) {
      setState(() => _probeResults['#input'] = l10n.customMirrorSiteInvalid);
      return;
    }
    setState(() {
      if (!_urls.contains(url)) _urls.add(url);
      _active = url;
      _probeResults.remove('#input');
      _input.clear();
    });
  }

  Future<void> _probe(AppLocalizations l10n, String url) async {
    setState(() {
      _probing = url;
      _probeResults.remove(url);
    });
    final result = await _testMirror(url, l10n);
    if (!mounted) return;
    setState(() {
      _probing = null;
      _probeResults[url] = result;
    });
  }

  Future<String> _testMirror(String homeUrl, AppLocalizations l10n) async {
    final apiBase = _appendPath ? homeUrl : Uri.parse(homeUrl).origin;
    final http = Han1meHttpClient();
    try {
      // AV 视频源是另一套页面结构：这里填它的地址（或它的其它语言站/镜像）时按 AV 源
      // 的方式验证，否则拿 hanime1 的标记去判会误报「主页结构解析失败」。
      final javSite = javSiteFor(homeUrl);
      if (javSite != null) {
        final section = javSite.sections.isEmpty ? '/' : javSite.sections.first.path;
        final result = await JavApi(http).search(javSite, keyword: '', genre: section, page: 1);
        if (result.items.isEmpty) return l10n.customMirrorTestParseFailed;
        return l10n.customMirrorTestJavSuccess(javSite.label, javSite.baseUrl, result.items.length);
      }
      final home = await http.get('$homeUrl/');
      if (home.statusCode >= 400) return l10n.customMirrorTestFailedHttp(home.statusCode, home.url);
      if (home.statusCode == 403 || home.body.contains('cf-chl-')) return l10n.customMirrorTestChallenge;
      if (!home.body.contains('home-rows-wrapper')) return l10n.customMirrorTestParseFailed;
      final search = await http.get('$apiBase/search');
      if (search.statusCode >= 400) return l10n.customMirrorTestPartialSuccess(apiBase, search.statusCode);
      return l10n.customMirrorTestSuccess(home.url, apiBase);
    } catch (error) {
      return l10n.customMirrorTestFailed(error.toString());
    }
  }

  void _save(AppLocalizations l10n) {
    if (_enabled && !_validMirrorUrl(_active)) {
      setState(() => _probeResults['#input'] = l10n.customMirrorSiteInvalid);
      return;
    }
    Navigator.pop(context, _MirrorSettings(enabled: _enabled, urls: List.unmodifiable(_urls), activeUrl: _active, appendPath: _appendPath));
  }

  static String _normalize(String value) => value.trim().replaceAll(RegExp(r'/+$'), '');

  static bool _validMirrorUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null && uri.scheme == 'https' && uri.host.isNotEmpty && !uri.hasQuery && !uri.hasFragment;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inputError = _probeResults['#input'];
    return AlertDialog(
      title: Text(l10n.customMirrorSite),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            SwitchListTile.adaptive(contentPadding: EdgeInsets.zero, title: Text(l10n.enableCustomMirrorSite), value: _enabled, onChanged: (value) => setState(() => _enabled = value)),
            if (_enabled) ...[
              Text(l10n.customMirrorSites, style: theme.textTheme.titleSmall),
              const SizedBox(height: 2),
              Text(l10n.customMirrorSitesHint, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.4)),
              const SizedBox(height: 8),
              if (_urls.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Text(l10n.customMirrorSitesEmpty, style: theme.textTheme.bodySmall?.copyWith(color: scheme.outline))),
              for (final url in _urls)
                _mirrorRow(context, l10n, url),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: TextField(controller: _input, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: l10n.customMirrorSite, helperText: l10n.customMirrorSiteHint, errorText: inputError))),
                const SizedBox(width: 8),
                PressScale(child: IconButton.filledTonal(onPressed: () => _addUrl(l10n), icon: const Icon(Symbols.add_rounded), tooltip: l10n.customMirrorSite)),
              ]),
              const SizedBox(height: 12),
              Text(l10n.customMirrorApiPathMode, style: theme.textTheme.titleSmall),
              // 选中值交给 RadioGroup 统一管，子项只报自己的 value —— 这是
              // RadioListTile 上 groupValue/onChanged 被弃用后的官方写法。
              RadioGroup<bool>(
                groupValue: _appendPath,
                onChanged: (value) => setState(() => _appendPath = value ?? false),
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  RadioListTile<bool>(contentPadding: EdgeInsets.zero, dense: true, value: true, title: Text(l10n.customMirrorPathFollowHome), subtitle: Text(l10n.customMirrorPathFollowHomeSummary)),
                  RadioListTile<bool>(contentPadding: EdgeInsets.zero, dense: true, value: false, title: Text(l10n.customMirrorPathRoot), subtitle: Text(l10n.customMirrorPathRootSummary)),
                ]),
              ),
            ],
          ]),
        ),
      ),
      actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: () => _save(l10n), child: Text(l10n.save)))],
    );
  }

  /// 候选列表里的一行：选中标记 + 地址 + 单条测速 + 删除。
  Widget _mirrorRow(BuildContext context, AppLocalizations l10n, String url) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final active = url == _active;
    final probing = _probing == url;
    final result = _probeResults[url];
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 6, 4, 6),
      decoration: BoxDecoration(
        color: active ? scheme.primaryContainer.withValues(alpha: .35) : scheme.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(active ? Symbols.check_circle_rounded : Symbols.circle_rounded, size: 18, color: active ? scheme.primary : scheme.outline),
          const SizedBox(width: 8),
          Expanded(
            child: PressScale(
              child: InkWell(
                onTap: () => setState(() => _active = url),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(url, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: active ? FontWeight.w600 : null)),
                  if (active) Text(l10n.customMirrorSiteActive, style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary)),
                ]),
              ),
            ),
          ),
          if (probing) const Padding(padding: EdgeInsets.symmetric(horizontal: 8), child: SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)))
          else PressScale(child: IconButton(onPressed: () => _probe(l10n, url), icon: const Icon(Symbols.network_check_rounded), tooltip: l10n.testConnection, visualDensity: VisualDensity.compact)),
          PressScale(child: IconButton(onPressed: () => setState(() { _urls.remove(url); _probeResults.remove(url); if (_active == url) _active = _urls.isEmpty ? '' : _urls.first; }), icon: const Icon(Symbols.delete_outline_rounded), tooltip: l10n.customMirrorSiteRemove, visualDensity: VisualDensity.compact)),
        ]),
        if (result != null) Padding(padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2), child: Text(result, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.3))),
      ]),
    );
  }
}

extension on String { String ifEmpty(String fallback) => isEmpty ? fallback : this; }
