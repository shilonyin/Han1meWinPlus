import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_design_tokens.dart';
import '../../core/cast_receiver.dart';
import '../../core/app_radius.dart';
import '../../core/app_responsive.dart';
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
  ConsumerState<NetworkSettingsPage> createState() =>
      _NetworkSettingsPageState();
}

class _NetworkSettingsPageState extends ConsumerState<NetworkSettingsPage> {
  /// 「站点可用性诊断」直接在这块右侧内容区里切换显示，而不是 push 一个全屏页：
  /// 设置是「左分类 + 右内容」的两栏结构，push 会把左侧分类栏整个盖住，
  /// 退出后还得重新点一次分类才能回到这里。
  var _showDiagnostics = false;
  var _showSiteGroups = false;

  @override
  Widget build(BuildContext context) {
    if (_showDiagnostics) {
      return SettingsSubPageScope(
        onBack: () => setState(() => _showDiagnostics = false),
        child: const SiteDiagnosticsPage(),
      );
    }
    if (_showSiteGroups) {
      return SettingsSubPageScope(
        onBack: () => setState(() => _showSiteGroups = false),
        child: const SiteGroupsPage(),
      );
    }
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) {
      return const Scaffold(
        body: Center(child: M3EContainedLoadingIndicator()),
      );
    }
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: embeddedInSettingsPanes(context)
          ? null
          : AppBar(title: Text(l10n.networkSettings)),
      body: ListView(
        children: [
          // 设计稿顶部的网络状态横幅：绿底 + 「网络正常」+ 当前代理说明，右侧是大号延迟。
          // 它回答的是「我现在能不能连上」这件事，而下面那些开关都是「怎么连」——
          // 放在最上面，进页面第一眼就知道状态。
          _NetworkStatusBanner(settings: settings),
          // 设计稿把这一页整理成两块：
          // ① 顶部状态横幅（能不能连上）；
          // ② 「代理」卡：代理模式三段按钮 + 当前代理说明 + 内置 Hosts + DoH + 地址延迟排序 + 连接测试。
          // 站点选择 / 镜像 / 投屏接收端这些本应用自己的项放在下面单独一张卡，
          // 不塞进设计稿那张「代理」卡里 —— 那张卡讲的是「怎么连外网」。
          // ① 代理模式：设计稿里这是**独立的一张卡**（y223~354），
          // 和下面的「内置 Hosts / DoH / 连接测试」那张卡之间隔 24。
          // 原来把两者塞进同一张卡，代理模式那一段就和下面几行粘在一起，
          // 分不出「选一种连法」和「连法的细节开关」是两层东西。
          SettingsCardList(
            children: [
              // 代理模式：设计稿是三个等宽分段按钮（直连 / 跟随系统 / 自定义），
              // 点一下立即切换并把当前那一档染成粉底白字。原来是一个弹窗入口，
              // 想换模式得多点两次，也看不出当前选的是哪档。
              _ProxyModeSegments(
                settings: settings,
                // 设计稿这行写的是「HTTPS_PROXY 环境变量 · 系统代理 127.0.0.1:7897」，
                // 也就是把**实际在用**的代理地址显出来。
                hint: switch (settings.proxyMode) {
                  'direct' => '直连 · 不使用代理与环境变量',
                  'custom' =>
                    settings.customProxy.isEmpty
                        ? '自定义代理 · 未设置'
                        : '自定义代理 · ${settings.customProxy}',
                  _ => '跟随系统 · 读取 HTTPS_PROXY 环境变量与系统代理',
                },
                onChanged: (mode) => controller.saveChanges(
                  (current) => current.copyWith(proxyMode: mode),
                ),
              ),
              if (settings.proxyMode == 'custom')
                SettingsCardItem(
                  title: l10n.proxy,
                  subtitle: _proxySummary(l10n, settings),
                  onTap: () =>
                      _showProxySettings(context, settings, controller),
                ),
            ],
          ),
          // ② 连接细节：卡片间距 24 —— `SettingsSection` 自带
          // `fromLTRB(39, 0, 29, 16)`，底部已有 16，这里再补 8。
          SettingsCardList(
            padding: const EdgeInsets.only(top: 8),
            children: [
              SettingsCardItem(
                title: l10n.useBuiltInHosts,
                subtitle:
                    settings.useBuiltInHosts && settings.proxyMode != 'direct'
                    ? '${l10n.useBuiltInHostsDescription}\n${l10n.proxyDirectOnlyHint}'
                    : l10n.useBuiltInHostsDescription,
                trailing: Switch(
                  value: settings.useBuiltInHosts,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(useBuiltInHosts: value),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.doh,
                subtitle: _dohSummary(l10n, settings),
                // 行本身可点：DoH 除了开关还有预设 / 自定义地址 / 引导 IP / 超时这几项，
                // 都收在那个弹层里。开关只控制启用与否，细项点这一行进设置。
                onTap: () => _showDohSettings(context, settings, controller),
                trailing: Switch(
                  value: settings.useDoh,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(useDoh: value),
                  ),
                ),
              ),
              SettingsCardItem(
                // 设计稿这一行叫「连接测试」（副标题「测试与 hanime1.com 的连通性，
                // 进入诊断」），不是「站点可用性诊断」。后者是我们自己起的长名字，
                // 和设计稿并排一看就是两回事；而且「连接测试」更符合用户点它时的预期
                // （跑一次测试，不是打开一个诊断面板）。
                title: '连接测试',
                subtitle: '测试与 ${_siteHost(settings)} 的连通性，进入诊断',
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _showDiagnostics = true),
              ),
            ],
          ),
          // 站点与镜像：本应用特有的站点切换，设计稿没有画，但功能上必须保留。
          SettingsCardList(
            title: '站点',
            children: [
              SettingsCardItem(
                title: l10n.site,
                subtitle: settings.comicMode
                    ? 'https://hanimeone.me'
                    : settings.baseUrl,
                onTap: () => showSitePicker(
                  context,
                  ref,
                  settings,
                  onManageGroups: () => setState(() => _showSiteGroups = true),
                ),
              ),
              SettingsCardItem(
                title: l10n.customMirrorSite,
                subtitle: _mirrorSummary(l10n, settings),
                onTap: () =>
                    _showMirrorSettings(context, ref, settings, controller),
              ),
            ],
          ),
          if (CastReceiver.isSupported)
            // 分组标题用分类名「投屏」，条目才是「投屏接收端」—— 和本页其他分组
            // （标题是分类、条目是具体项）一致。此前这里两者共用 dlnaReceiver，
            // 因为该条目掉出了卡片分支、连分组标题一起没渲染，重复才没显形。
            SettingsCardList(
              title: l10n.castToDevice,
              children: [
                ValueListenableBuilder<bool>(
                  valueListenable: CastReceiver.instance.running,
                  builder: (context, running, _) => SettingsCardItem(
                    title: l10n.dlnaReceiver,
                    subtitle: running
                        ? '${l10n.dlnaReceiverRunning}\n${CastReceiver.instance.location}'
                        : l10n.dlnaReceiverDescription,
                    leading: const Icon(Symbols.cast_connected_rounded),
                    trailing: Switch(
                      value: settings.dlnaReceiverEnabled,
                      onChanged: (value) => controller.saveChanges(
                        (current) =>
                            current.copyWith(dlnaReceiverEnabled: value),
                      ),
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  /// 副标题：当前在用的镜像 + 还存了几个候选。只显示地址的话，用户看不出自己
  /// 其实还存着别的镜像可以随时切。
  String _mirrorSummary(AppLocalizations l10n, AppSettings settings) {
    final count = settings.customMirrorSites.length;
    if (!settings.mirrorActive) {
      return count == 0
          ? l10n.customMirrorSiteHint
          : '${l10n.customMirrorSites} ($count)';
    }
    return count <= 1
        ? settings.customMirrorSite
        : '${settings.customMirrorSite} (+${count - 1})';
  }

  String _dohSummary(AppLocalizations l10n, AppSettings settings) =>
      !settings.useDoh
      ? l10n.dohDisabled
      : settings.dohPreset == 'custom'
      ? settings.dohCustomUrl.ifEmpty(l10n.custom)
      : _dohPresets[settings.dohPreset]!;

  Future<void> _showMirrorSettings(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
    SettingsController controller,
  ) async {
    final result = await showAppDialog<_MirrorSettings>(
      context: context,
      builder: (_) => _MirrorSettingsDialog(settings: settings),
    );
    if (result == null) return;
    final unchanged =
        result.enabled == settings.useCustomMirrorSite &&
        result.activeUrl == settings.customMirrorSite &&
        result.appendPath == settings.appendCustomMirrorPath &&
        listEquals(result.urls, settings.customMirrorSites);
    if (unchanged) return;
    await controller.saveChanges(
      (current) => current.copyWith(
        useCustomMirrorSite: result.enabled,
        customMirrorSite: result.activeUrl,
        customMirrorSites: result.urls,
        appendCustomMirrorPath: result.appendPath,
      ),
    );
    ref.invalidate(accountProvider);
    resetHomeFeed(ref);
  }

  Future<void> _showDohSettings(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) async {
    final result = await showAppDialog<_DohSettings>(
      context: context,
      builder: (_) => _DohSettingsDialog(settings: settings),
    );
    if (result != null) {
      await controller.saveChanges(
        (current) => current.copyWith(
          useDoh: result.enabled,
          dohPreset: result.preset,
          dohCustomUrl: result.customUrl,
          dohBootstrapIps: result.bootstrapIps,
          dohTimeoutSeconds: result.timeoutSeconds,
        ),
      );
    }
  }

  /// 当前站点的**主机名**（去掉协议与路径），用于「测试与 xxx 的连通性」这类文案。
  /// 解析失败时退回设计稿里的示例主机名，不至于在界面上留一段空白。
  String _siteHost(AppSettings settings) {
    final raw = settings.comicMode ? 'https://hanimeone.me' : settings.baseUrl;
    return Uri.tryParse(raw)?.host ?? 'hanime1.com';
  }

  String _proxySummary(AppLocalizations l10n, AppSettings settings) =>
      switch (settings.proxyMode) {
        'direct' => l10n.proxyDirect,
        'custom' =>
          settings.customProxy.isEmpty
              ? l10n.proxyCustom
              : '${l10n.proxyCustom} · ${settings.customProxy}',
        _ => l10n.proxySystem,
      };

  /// 代理模式会影响三套网络栈：Dart 的 HttpClient（图片/页面/评论）、mpv（视频）
  /// 与 WebView2（登录、Cloudflare 挑战），所以保存后要把三者都刷新一遍，
  /// 否则只有其中一部分跟随新设置。
  Future<void> _showProxySettings(
    BuildContext context,
    AppSettings settings,
    SettingsController controller,
  ) async {
    final result = await showAppDialog<_ProxySettings>(
      context: context,
      builder: (_) => _ProxySettingsDialog(settings: settings),
    );
    if (result == null) return;
    await controller.saveChanges(
      (current) =>
          current.copyWith(proxyMode: result.mode, customProxy: result.custom),
    );
    await ConfiguredMediaKitVideoPlayer.refreshHttpProxy();
    // WebView 环境的代理参数只在创建时下发，且已创建的实例也改不了，
    // 只能重建（下次进入登录页/CF 页时自然生效）。
    ref.invalidate(webViewEnvironmentProvider);
  }
}

const _dohPresets = {
  'alidns': 'AliDNS',
  'dnspod': 'DNSPod',
  'cloudflare': 'Cloudflare',
};

/// 设计稿的「代理模式」三段按钮：直连 / 跟随系统 / 自定义，等宽并排。
///
/// 选中的那一档是实心强调粉 + 白字，未选是浅灰底 + 灰字 —— 一眼能看出当前用的是哪档。
/// 原来这一项是个弹窗入口（点开、选、确定），多两步操作，而且列表行里也看不出
/// 「三档里我选的是哪个」。
class _ProxyModeSegments extends StatelessWidget {
  const _ProxyModeSegments({
    required this.settings,
    required this.onChanged,
    required this.hint,
  });

  final AppSettings settings;
  final ValueChanged<String> onChanged;

  /// 胶囊下方那行灰字：当前代理是怎么来的、指向哪里。
  final String hint;

  /// (值, 文案) —— 与 `AppSettings.proxyMode` 的取值一致。
  static const _modes = [
    ('direct', '直连'),
    ('system', '跟随系统'),
    ('custom', '自定义'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      // 上、下留白交给 `_SplitListGroup` 统一处理（卡片首行/末行各补一段），
      // 这里只留左右 16。
      //
      // 原来这段自带 `fromLTRB(16, 16, 16, 14)`，而卡片首尾补偿又加了一次，
      // 于是代理模式卡的留白变成 29/28 —— 比同一个页面里其他几张卡的
      // 15/15 明显松一头。留白只该有一个来源。
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        // 用 `start`（不是 `stretch`）：`stretch` 会给子级「紧宽度」约束，
        // 下面那个 `Row(mainAxisSize: min)` 就被拉成整行宽，三颗胶囊反而铺满。
        // `start` 下子级按自身宽度布局，胶囊能保持 72/96 的自然宽度。
        // 标题本来就要左对齐，也正好。
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // 「代理模式」是卡内的第一行标题（设计稿：13 号粗体墨色，
          // 与下面其他行的标题同字号），不是分组小标题。原来给 14 号 w500，
          // 比下面「内置 Hosts」那行还轻，层级是反的。
          const Text(
            '代理模式',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.ink,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 17),
          // 三个**独立胶囊**，不是撑满整行的分段控件。
          //
          // 设计稿（`7396_v6_network.png`）里它们各约 72×30、左对齐排开，
          // 右边留出一大片空白；我们之前用 `Expanded` 让三格平分整行，
          // 每个胶囊宽到 250+ —— 一眼看去像一条通栏的 tab 条。
          //
          // 这里用 `Row(mainAxisSize.min)` 而不是 `Wrap`：`Wrap` 在收缩约束下
          // 会把三颗「折行」成一列竖排（实测就是这样），而 Row 只会溢出、
          // 不会竖排 —— 三颗胶囊加起来的宽度远小于卡片宽度，不会溢出。
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final (value, label) in _modes) ...[
                // 胶囊间距 10：设计稿（`7396_v6_network.png`）三颗胶囊的
                // 空隙实测 9~12（圆角处按像素算会差 1~2），取中间值。
                if (value != _modes.first.$1) const SizedBox(width: 10),
                PressScale(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(AppRadius.lg),
                    onTap: () => onChanged(value),
                    child: Container(
                      // 高度 34：设计稿（`7396_v6_network.png`）实测三颗胶囊
                      // y272~305（含 1px 投影，实体 32~34）。原来的 30 偏矮，
                      // 和卡片的松紧配起来像一条细长的按钮带。
                      //
                      // 宽度随文字（设计稿「直连」72、「跟随系统」98、「自定义」72），
                      // 用水平内边距 22 把胶囊撑开：13 号字「直连」约 26 宽，
                      // 加 22×2 = 70，落在设计稿的 72 上。
                      height: 34,
                      padding: const EdgeInsets.symmetric(horizontal: 22),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        // 选中：实心主题色 + 白字；未选：浅灰底 + 灰字。
                        // 设计稿未选的两颗是**浅灰实心**（#EDEDF2），
                        // 不是透明 —— 透明的话在白卡上看不出按钮的边界。
                        color: settings.proxyMode == value
                            ? AppDesignTokens.accentOf(context)
                            : AppDesignTokens.fieldFill,
                        borderRadius: BorderRadius.circular(AppRadius.lg),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(
                          // 13 号：设计稿胶囊内的字比卡片标题（13）同号、
                          // 比提示行（11）大一档。原来给 12，整排胶囊看着比标题小一号。
                          fontSize: 13,
                          fontWeight: settings.proxyMode == value
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: settings.proxyMode == value
                              ? Colors.white
                              : AppDesignTokens.inkSubtle,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          // 胶囊下方那行灰字（设计稿：「HTTPS_PROXY 环境变量 · 系统代理 127.0.0.1:7897」）。
          // 它告诉用户「当前实际在用哪一个代理」，比只高亮一颗按钮信息量更大 ——
          // 尤其是「跟随系统」这一档，光看按钮根本不知道系统代理指到哪。
          //
          // 间距 22：设计稿胶囊底 302 → 提示顶 324。提示是 11 号字，行盒
          // 上方还有约 3 的余量，所以 SizedBox 给 19 实测落在 22。
          const SizedBox(height: 19),
          Text(
            hint,
            style: const TextStyle(
              fontSize: 11,
              color: AppDesignTokens.inkMuted,
            ),
          ),
        ],
      ),
    );
  }
}

/// 设计稿顶部的网络状态横幅（`网络正常` + 当前代理说明 + 右侧大号延迟）。
///
/// 延迟是真测的：进页面时向当前站点发一次 HEAD 请求，量「发起到收到响应头」的耗时。
/// 不显示编造的示例值 —— 连不上就显示「连接失败」，这正是用户要首先知道的事。
class _NetworkStatusBanner extends StatefulWidget {
  const _NetworkStatusBanner({required this.settings});

  final AppSettings settings;

  @override
  State<_NetworkStatusBanner> createState() => _NetworkStatusBannerState();
}

class _NetworkStatusBannerState extends State<_NetworkStatusBanner> {
  /// 延迟（毫秒）。null 表示正在测，-1 表示失败。
  int? _latency;

  @override
  void initState() {
    super.initState();
    unawaited(_measure());
  }

  Future<void> _measure() async {
    final watch = Stopwatch()..start();
    try {
      final client = HttpClient()
        ..connectionTimeout = const Duration(seconds: 8);
      try {
        final request = await client.headUrl(
          Uri.parse(widget.settings.baseUrl),
        );
        final response = await request.close();
        await response.drain<void>();
        if (mounted) setState(() => _latency = watch.elapsedMilliseconds);
      } finally {
        client.close(force: true);
      }
    } catch (_) {
      if (mounted) setState(() => _latency = -1);
    }
  }

  /// 当前代理的说明文字：与「代理模式」那一行用的是同一套语义。
  String get _modeLabel => switch (widget.settings.proxyMode) {
    'direct' => '直连',
    'custom' => '自定义代理',
    _ => '跟随系统',
  };

  @override
  Widget build(BuildContext context) {
    final latency = _latency;
    final ok = latency != null && latency >= 0;
    final failed = latency == -1;
    // 设计稿用柔和的绿底表示正常；失败换成柔和的粉底，保持同一套浅色底的做法。
    final background = failed
        ? const Color(0xFFFDEEF2)
        : const Color(0xFFEDF7F0);
    final accent = failed
        ? AppDesignTokens.accentOf(context)
        : const Color(0xFF2E7D4F);
    return Container(
      // 与白卡 / 其他横幅统一：左边 39、右边 29（`SettingsSection` 的默认值）。
      // 原来写 12/12，横幅比卡片左右各宽出一截，右边缘直接贴到窗口上。
      margin: const EdgeInsets.fromLTRB(39, 0, 29, 12),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        color: accent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      failed ? '网络异常' : (ok ? '网络正常' : '正在检测…'),
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: accent,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  '当前代理：$_modeLabel · 内置 Hosts ${widget.settings.useBuiltInHosts ? '已启用' : '未启用'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppDesignTokens.inkSubtle,
                  ),
                ),
              ],
            ),
          ),
          if (ok)
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '$latency ms',
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    color: accent,
                  ),
                ),
                const Text(
                  '延迟',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppDesignTokens.inkMuted,
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _ProxySettings {
  const _ProxySettings({required this.mode, required this.custom});
  final String mode;
  final String custom;
}

class _ProxySettingsDialog extends StatefulWidget {
  const _ProxySettingsDialog({required this.settings});
  final AppSettings settings;
  @override
  State<_ProxySettingsDialog> createState() => _ProxySettingsDialogState();
}

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
        ProxyAddressStatus.valid => (
          l10n.proxyCurrent(WindowsProxy.rule(_custom.text) ?? 'DIRECT'),
          theme.colorScheme.onSurfaceVariant,
        ),
        // 填错了最终也走直连，用错误色和「当前生效：直连」把后果说清楚。
        _ => (l10n.proxyCurrentDirect, theme.colorScheme.error),
      },
      _ => (l10n.proxyDescription, theme.colorScheme.onSurfaceVariant),
    };
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(color: tone, height: 1.4),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      ('system', l10n.proxySystem),
      ('direct', l10n.proxyDirect),
      ('custom', l10n.proxyCustom),
    ];
    final custom = _mode == 'custom';
    return AlertDialog(
      title: Text(l10n.proxy),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.proxyDescription,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
            const SizedBox(height: 4),
            for (final option in options)
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(option.$2),
                trailing: _mode == option.$1
                    ? const Icon(Symbols.check_rounded)
                    : null,
                onTap: () => setState(() => _mode = option.$1),
              ),
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
          ],
        ),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: !_canSave
                ? null
                : () => Navigator.pop(
                    context,
                    _ProxySettings(mode: _mode, custom: _custom.text.trim()),
                  ),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

class _DohSettings {
  const _DohSettings({
    required this.enabled,
    required this.preset,
    required this.customUrl,
    required this.bootstrapIps,
    required this.timeoutSeconds,
  });
  final bool enabled;
  final String preset;
  final String customUrl;
  final String bootstrapIps;
  final int timeoutSeconds;
}

class _DohSettingsDialog extends StatefulWidget {
  const _DohSettingsDialog({required this.settings});
  final AppSettings settings;
  @override
  State<_DohSettingsDialog> createState() => _DohSettingsDialogState();
}

class _DohSettingsDialogState extends State<_DohSettingsDialog> {
  late var _enabled = widget.settings.useDoh;
  late var _preset = widget.settings.dohPreset;
  late final _customUrl = TextEditingController(
    text: widget.settings.dohCustomUrl,
  );
  late final _bootstrapIps = TextEditingController(
    text: widget.settings.dohBootstrapIps,
  );
  late final _timeout = TextEditingController(
    text: widget.settings.dohTimeoutSeconds.toString(),
  );
  var _testing = false;
  String? _testResult;
  bool _testOk = false;
  @override
  void dispose() {
    _customUrl.dispose();
    _bootstrapIps.dispose();
    _timeout.dispose();
    super.dispose();
  }

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
          ? l10n.dohTestOk(
              result.host,
              result.addresses.length,
              result.milliseconds,
            )
          : l10n.dohTestFail(result.error ?? l10n.addressLatencyUnavailable);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(
      title: Text(l10n.dohSettings),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.useDoh),
              value: _enabled,
              onChanged: (value) => setState(() => _enabled = value),
            ),
            DropdownButtonFormField(
              initialValue: _preset,
              decoration: InputDecoration(labelText: l10n.dohPreset),
              items: [
                ..._dohPresets.entries.map(
                  (item) => DropdownMenuItem(
                    value: item.key,
                    child: Text(item.value),
                  ),
                ),
                DropdownMenuItem(value: 'custom', child: Text(l10n.custom)),
              ],
              onChanged: (value) => setState(() => _preset = value!),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _customUrl,
              enabled: _preset == 'custom',
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l10n.dohCustomUrl),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _bootstrapIps,
              decoration: InputDecoration(
                labelText: l10n.dohBootstrapIps,
                helperText: l10n.dohBootstrapIpsDescription,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _timeout,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: l10n.dohTimeoutSeconds,
                helperText: l10n.dohTimeoutSecondsDescription,
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: PressScale(
                child: OutlinedButton.icon(
                  onPressed: _testing ? null : () => _testDoh(l10n),
                  icon: _testing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Symbols.network_check_rounded),
                  label: Text(_testing ? l10n.dohTesting : l10n.dohTest),
                ),
              ),
            ),
            if (_testResult != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  _testResult!,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: _testOk ? null : Theme.of(context).colorScheme.error,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _DohSettings(
                enabled: _enabled,
                preset: _preset,
                customUrl: _customUrl.text.trim(),
                bootstrapIps: _bootstrapIps.text.trim(),
                timeoutSeconds: (int.tryParse(_timeout.text) ?? 10).clamp(
                  1,
                  60,
                ),
              ),
            ),
            child: Text(l10n.save),
          ),
        ),
      ],
    );
  }
}

class _MirrorSettings {
  const _MirrorSettings({
    required this.enabled,
    required this.urls,
    required this.activeUrl,
    required this.appendPath,
  });

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
    if (_active.isNotEmpty && !_urls.contains(_active)) {
      _urls.insert(0, _active);
    }
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
        final section = javSite.sections.isEmpty
            ? '/'
            : javSite.sections.first.path;
        final result = await JavApi(
          http,
        ).search(javSite, keyword: '', genre: section, page: 1);
        if (result.items.isEmpty) return l10n.customMirrorTestParseFailed;
        return l10n.customMirrorTestJavSuccess(
          javSite.label,
          javSite.baseUrl,
          result.items.length,
        );
      }
      final home = await http.get('$homeUrl/');
      if (home.statusCode >= 400) {
        return l10n.customMirrorTestFailedHttp(home.statusCode, home.url);
      }
      if (home.statusCode == 403 || home.body.contains('cf-chl-')) {
        return l10n.customMirrorTestChallenge;
      }
      if (!home.body.contains('home-rows-wrapper')) {
        return l10n.customMirrorTestParseFailed;
      }
      final search = await http.get('$apiBase/search');
      if (search.statusCode >= 400) {
        return l10n.customMirrorTestPartialSuccess(apiBase, search.statusCode);
      }
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
    Navigator.pop(
      context,
      _MirrorSettings(
        enabled: _enabled,
        urls: List.unmodifiable(_urls),
        activeUrl: _active,
        appendPath: _appendPath,
      ),
    );
  }

  static String _normalize(String value) =>
      value.trim().replaceAll(RegExp(r'/+$'), '');

  static bool _validMirrorUrl(String url) {
    final uri = Uri.tryParse(url);
    return uri != null &&
        uri.scheme == 'https' &&
        uri.host.isNotEmpty &&
        !uri.hasQuery &&
        !uri.hasFragment;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final inputError = _probeResults['#input'];
    return AlertDialog(
      title: Text(l10n.customMirrorSite),
      // 对话框基准宽随文字缩放，放大后内容不被挤窄，上限取内容区宽保证小窗不溢出。
      content: SizedBox(
        width: AppResponsive.scaled(context, 520).clamp(
          0.0,
          AppResponsive.contentWidthFor(MediaQuery.sizeOf(context).width),
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: Text(l10n.enableCustomMirrorSite),
                value: _enabled,
                onChanged: (value) => setState(() => _enabled = value),
              ),
              if (_enabled) ...[
                Text(l10n.customMirrorSites, style: theme.textTheme.titleSmall),
                const SizedBox(height: 2),
                Text(
                  l10n.customMirrorSitesHint,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 8),
                if (_urls.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      l10n.customMirrorSitesEmpty,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: scheme.outline,
                      ),
                    ),
                  ),
                for (final url in _urls) _mirrorRow(context, l10n, url),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _input,
                        keyboardType: TextInputType.url,
                        decoration: InputDecoration(
                          labelText: l10n.customMirrorSite,
                          helperText: l10n.customMirrorSiteHint,
                          errorText: inputError,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    PressScale(
                      child: IconButton.filledTonal(
                        onPressed: () => _addUrl(l10n),
                        icon: const Icon(Symbols.add_rounded),
                        tooltip: l10n.customMirrorSite,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  l10n.customMirrorApiPathMode,
                  style: theme.textTheme.titleSmall,
                ),
                // 选中值交给 RadioGroup 统一管，子项只报自己的 value —— 这是
                // RadioListTile 上 groupValue/onChanged 被弃用后的官方写法。
                RadioGroup<bool>(
                  groupValue: _appendPath,
                  onChanged: (value) =>
                      setState(() => _appendPath = value ?? false),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: true,
                        title: Text(l10n.customMirrorPathFollowHome),
                        subtitle: Text(l10n.customMirrorPathFollowHomeSummary),
                      ),
                      RadioListTile<bool>(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        value: false,
                        title: Text(l10n.customMirrorPathRoot),
                        subtitle: Text(l10n.customMirrorPathRootSummary),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => _save(l10n),
            child: Text(l10n.save),
          ),
        ),
      ],
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
        color: active
            ? scheme.primaryContainer.withValues(alpha: .35)
            : scheme.surfaceContainerHighest.withValues(alpha: .4),
        borderRadius: BorderRadius.circular(AppRadius.sm),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                active ? Symbols.check_circle_rounded : Symbols.circle_rounded,
                size: 18,
                color: active ? scheme.primary : scheme.outline,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PressScale(
                  child: InkWell(
                    onTap: () => setState(() => _active = url),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          url,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: active ? FontWeight.w600 : null,
                          ),
                        ),
                        if (active)
                          Text(
                            l10n.customMirrorSiteActive,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.primary,
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (probing)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 8),
                  child: SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                PressScale(
                  child: IconButton(
                    onPressed: () => _probe(l10n, url),
                    icon: const Icon(Symbols.network_check_rounded),
                    tooltip: l10n.testConnection,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              PressScale(
                child: IconButton(
                  onPressed: () => setState(() {
                    _urls.remove(url);
                    _probeResults.remove(url);
                    if (_active == url) {
                      _active = _urls.isEmpty ? '' : _urls.first;
                    }
                  }),
                  icon: const Icon(Symbols.delete_outline_rounded),
                  tooltip: l10n.customMirrorSiteRemove,
                  visualDensity: VisualDensity.compact,
                ),
              ),
            ],
          ),
          if (result != null)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 2, bottom: 2),
              child: Text(
                result,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.3,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on String {
  String ifEmpty(String fallback) => isEmpty ? fallback : this;
}
