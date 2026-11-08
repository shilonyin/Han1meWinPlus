import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../data/local/watch_repository.dart';
import '../../data/local/webdav_sync_service.dart';
import '../../data/local/library_repository.dart';
import '../../core/settings.dart';
import '../shared/press_scale.dart';
import 'settings_card_list.dart';
import 'settings_controller.dart';
import 'settings_sub_page.dart';
import 'settings_pane_scope.dart';
import '../shared/app_top_bar.dart';

class WebDavSettingsPage extends ConsumerStatefulWidget {
  const WebDavSettingsPage({super.key});

  @override
  ConsumerState<WebDavSettingsPage> createState() => _WebDavSettingsPageState();
}

class _WebDavSettingsPageState extends ConsumerState<WebDavSettingsPage> {
  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  var _showConfiguration = false;

  @override
  Widget build(BuildContext context) {
    if (_showConfiguration) {
      return SettingsSubPageScope(
        onBack: () => setState(() => _showConfiguration = false),
        child: const WebDavConfigurationPage(),
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
          : AppBar(
              leading: settingsSubPageBack(context),
              title: Text(l10n.webDavSettings),
            ),
      body: ListView(
        children: [
          // 设计稿顶部的「已连接」状态卡：一眼看出连的是哪台服务器、上次同步什么时候。
          // 没配置时显示「未配置」，引导去填地址 —— 比一个孤零零的开关有用得多。
          _WebDavStatusCard(settings: settings),
          // 这五项的卡不带小标题（页头已经写着「WebDAV 设置」，再加一行「WebDAV」只是重复）。
          SettingsCardList(
            children: [
              SettingsCardItem(
                title: l10n.webDavSync,
                leading: const Icon(Symbols.cloud_sync_rounded),
                trailing: Switch(
                  value: settings.webDavEnabled,
                  onChanged: (value) => controller.saveChanges(
                    (current) => current.copyWith(
                      webDavEnabled: value,
                      webDavHistorySync: value
                          ? current.webDavHistorySync
                          : false,
                      webDavFavoriteSync: value
                          ? current.webDavFavoriteSync
                          : false,
                    ),
                  ),
                ),
              ),
              SettingsCardItem(
                title: l10n.watchHistorySync,
                leading: const Icon(Symbols.history_rounded),
                trailing: Switch(
                  value: settings.webDavHistorySync,
                  onChanged: settings.webDavEnabled
                      ? (value) => controller.saveChanges(
                          (current) =>
                              current.copyWith(webDavHistorySync: value),
                        )
                      : null,
                ),
              ),
              SettingsCardItem(
                title: l10n.favoriteSync,
                leading: const Icon(Symbols.favorite_rounded),
                trailing: Switch(
                  value: settings.webDavFavoriteSync,
                  onChanged: settings.webDavEnabled
                      ? (value) => controller.saveChanges(
                          (current) =>
                              current.copyWith(webDavFavoriteSync: value),
                        )
                      : null,
                ),
              ),
              SettingsCardItem(
                title: l10n.webDavConfiguration,
                leading: const Icon(Symbols.settings_rounded),
                trailing: const Icon(Symbols.chevron_right_rounded),
                onTap: () => setState(() => _showConfiguration = true),
              ),
              SettingsCardItem(
                title: l10n.syncWatchHistoryNow,
                leading: const Icon(Symbols.sync_rounded),
                onTap: () => _sync(context, ref, settings),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _sync(
    BuildContext context,
    WidgetRef ref,
    AppSettings settings,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    if (!settings.webDavEnabled) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(l10n.webDavDisabled)));
      return;
    }
    try {
      final service = WebDavSyncService(Dio());
      final local = await ref.read(watchProvider.future);
      final merged = await service.syncWatchState(settings, local);
      await ref.read(watchProvider.notifier).replace(merged);
      if (settings.webDavFavoriteSync) {
        final local = await ref.read(libraryProvider.future);
        final merged = await service.syncFavorites(settings, local.favorites);
        await ref.read(libraryProvider.notifier).replaceFavorites(merged);
      }
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.syncQueued)));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(l10n.loadFailed(l10n.webDav))));
      }
    }
  }
}

/// 设计稿顶部的 WebDAV 状态卡：已连接 / 未配置 + 服务器地址 + 上次同步说明。
///
/// 状态只看「有没有填地址 + 同步开关是否打开」，不发请求 —— 进设置页时去打一次
/// 服务器既慢又会在离线时卡住；真正验证连通性由「立即同步」负责。
class _WebDavStatusCard extends StatelessWidget {
  const _WebDavStatusCard({required this.settings});

  final AppSettings settings;

  @override
  Widget build(BuildContext context) {
    final configured = settings.webDavUrl.trim().isNotEmpty;
    final connected = configured && settings.webDavEnabled;
    final accent = connected
        ? const Color(0xFF2E7D4F)
        : AppDesignTokens.inkMuted;
    return Container(
      // 与白卡 / 其他横幅统一：左边 39、右边 29（`SettingsSection` 的默认值）。
      margin: const EdgeInsets.fromLTRB(39, 0, 29, 12),
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 18),
      decoration: BoxDecoration(
        color: AppDesignTokens.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
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
                connected
                    ? '已连接 WebDAV'
                    : (configured ? '已配置，同步未开启' : '未配置 WebDAV'),
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: accent,
                ),
              ),
            ],
          ),
          if (configured) ...[
            const SizedBox(height: 6),
            Text(
              settings.webDavUrl,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 12,
                color: AppDesignTokens.inkSubtle,
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            const Text(
              '填写服务器地址、账号与密码后即可跨设备同步',
              style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
            ),
          ],
        ],
      ),
    );
  }
}

class WebDavConfigurationPage extends ConsumerStatefulWidget {
  const WebDavConfigurationPage({super.key});

  @override
  ConsumerState<WebDavConfigurationPage> createState() =>
      _WebDavConfigurationPageState();
}

class _WebDavConfigurationPageState
    extends ConsumerState<WebDavConfigurationPage> {
  late final TextEditingController _url;
  late final TextEditingController _username;
  late final TextEditingController _password;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(settingsProvider).valueOrNull;
    _url = TextEditingController(text: settings?.webDavUrl);
    _username = TextEditingController(text: settings?.webDavUsername);
    _password = TextEditingController(text: settings?.webDavPassword);
  }

  @override
  void dispose() {
    _url.dispose();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppTopBar(
        leading: settingsSubPageBack(context),
        title: Text(l10n.webDavConfiguration),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              decoration: InputDecoration(labelText: l10n.webDavUrl),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _username,
              decoration: InputDecoration(labelText: l10n.username),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _password,
              obscureText: true,
              decoration: InputDecoration(labelText: l10n.password),
            ),
            const Spacer(),
            PressScale(
              child: FilledButton(onPressed: _save, child: Text(l10n.save)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    await ref
        .read(settingsProvider.notifier)
        .saveChanges(
          (current) => current.copyWith(
            webDavUrl: _url.text.trim(),
            webDavUsername: _username.text.trim(),
            webDavPassword: _password.text,
          ),
        );
    if (mounted) Navigator.pop(context);
  }
}
