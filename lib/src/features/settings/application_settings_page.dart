import 'dart:async';

import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/cache_cleaner.dart';
import '../../core/platform_service.dart';
import '../../data/local/video_meta_cache.dart';
import '../auth/app_lock_controller.dart';
import '../shared/app_toast.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';

class ApplicationSettingsPage extends ConsumerStatefulWidget {
  const ApplicationSettingsPage({super.key});

  @override
  ConsumerState<ApplicationSettingsPage> createState() => _ApplicationSettingsPageState();
}

class _ApplicationSettingsPageState extends ConsumerState<ApplicationSettingsPage> {
  int? _cacheSize;

  @override
  void initState() {
    super.initState();
    unawaited(_loadCacheSize());
  }

  Future<void> _loadCacheSize() async {
    final size = await CacheCleaner.size();
    if (mounted) setState(() => _cacheSize = size);
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final cacheSize = _cacheSize;
    return Scaffold(appBar: AppBar(title: Text(l10n.applicationSettings)), body: ListView(children: [
       SettingsCardList(children: [
          SettingsCardItem(title: l10n.appLock, subtitle: l10n.appLockDescription, leading: const Icon(Icons.lock_outline), trailing: Switch(value: settings.appLockEnabled, onChanged: (value) async { if (!value || await PlatformService.authenticate()) { if (value) ref.read(appLockProvider.notifier).markUnlocked(); await controller.saveChanges((current) => current.copyWith(appLockEnabled: value)); } })),
          SettingsCardItem(title: l10n.backupSettings, subtitle: l10n.backupSettingsDescription, leading: const Icon(Icons.backup_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => context.push('/settings/application/backup')),
         SettingsCardItem(title: l10n.emergencyExit, subtitle: l10n.emergencyExitDescription, leading: const Icon(Icons.warning_amber_outlined), trailing: Switch(value: settings.emergencyExitEnabled, onChanged: (value) async { await PlatformService.setEmergencyExit(value); await controller.saveChanges((current) => current.copyWith(emergencyExitEnabled: value)); })),
          SettingsCardItem(title: l10n.hideFromRecents, subtitle: l10n.hideFromRecentsDescription, leading: const Icon(Icons.visibility_off_outlined), trailing: Switch(value: settings.hideFromRecents, onChanged: (value) async { await PlatformService.setHideFromRecents(value); await controller.saveChanges((current) => current.copyWith(hideFromRecents: value)); })),
          SettingsCardItem(title: l10n.openAppLinkSettings, subtitle: l10n.openAppLinkSettingsDescription, leading: const Icon(Icons.open_in_new_outlined), trailing: const Icon(Icons.chevron_right), onTap: PlatformService.openAppLinksSettings),
          SettingsCardItem(title: l10n.clearCache, subtitle: cacheSize == null ? l10n.clearCacheDescription : l10n.cacheUsage(CacheCleaner.formatSize(cacheSize)), leading: const Icon(Icons.cleaning_services_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => unawaited(_clearCache())),
       ]),
    ]));
  }

  /// 清缓存：封面图的磁盘/内存缓存 + 列表卡片补全用的元数据缓存。
  Future<void> _clearCache() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.clearCache),
        content: Text(l10n.clearCacheDescription),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.clear)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    final freed = await CacheCleaner.size();
    await CacheCleaner.clearImages();
    await ref.read(videoMetaCacheProvider).clear();
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();
    if (!mounted) return;
    await _loadCacheSize();
    if (!mounted) return;
    showAppToast(context, l10n.cacheCleared(CacheCleaner.formatSize(freed)));
  }
}
