import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/cache_cleaner.dart';
import '../../core/settings.dart';
import '../../core/platform_paths.dart';
import '../../data/local/download_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../library/local_media_page.dart';
import '../shared/app_toast.dart';
import 'backup_settings_page.dart';
import 'settings_controller.dart';
import 'settings_card_list.dart';
import 'settings_sub_page.dart';

/// 「存储」：下载、缓存与备份 —— 磁盘相关的设置都收在这里。
class StorageSettingsPage extends ConsumerStatefulWidget {
  const StorageSettingsPage({super.key});

  @override
  ConsumerState<StorageSettingsPage> createState() => _StorageSettingsPageState();
}

class _StorageSettingsPageState extends ConsumerState<StorageSettingsPage> {
  int? _cacheSize;

  /// 二级页在右侧内容区里切换显示，而不是 push 一个全屏路由（见 [SettingsSubPageScope]）。
  var _showBackup = false;

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
    if (_showBackup) return SettingsSubPageScope(onBack: () => setState(() => _showBackup = false), child: const BackupSettingsPage());
    final settings = ref.watch(settingsProvider).valueOrNull;
    if (settings == null) return const Scaffold(body: Center(child: M3EContainedLoadingIndicator()));
    final controller = ref.read(settingsProvider.notifier);
    final l10n = AppLocalizations.of(context)!;
    final cacheSize = _cacheSize;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.storage)),
      body: ListView(children: [
        SettingsCardList(title: l10n.downloadSettings, children: [
          SettingsCardItem(title: l10n.downloadPath, subtitle: settings.downloadPath, leading: const Icon(Icons.folder_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => _editDownloadPath(context, settings, controller)),
          SettingsCardItem(title: l10n.exportDownloads, subtitle: l10n.exportDownloadsDescription, leading: const Icon(Icons.drive_folder_upload_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => _exportDownloads(context, ref)),
          _SliderTile(icon: Icons.speed_outlined, title: l10n.downloadSpeedLimit, value: settings.downloadSpeedLimitMbps, min: 0, max: 20, divisions: 40, label: settings.downloadSpeedLimitMbps == 0 ? l10n.unlimited : '${settings.downloadSpeedLimitMbps.toStringAsFixed(1)} MB/s', onChanged: (value) => controller.saveChanges((current) => current.copyWith(downloadSpeedLimitMbps: value))),
          _SliderTile(icon: Icons.download_for_offline_outlined, title: l10n.concurrentDownloads, subtitle: l10n.concurrentDownloadsDescription(settings.concurrentDownloads), value: settings.concurrentDownloads.toDouble(), min: 1, max: 5, divisions: 4, label: '${settings.concurrentDownloads}', onChanged: (value) => controller.saveChanges((current) => current.copyWith(concurrentDownloads: value.round()))),
        ]),
        SettingsCardList(title: l10n.localMedia, children: [
          SettingsCardItem(title: l10n.localMediaDirectory, subtitle: settings.localMediaDirectory.isEmpty ? l10n.localMediaHint : settings.localMediaDirectory, leading: const Icon(Icons.movie_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const LocalMediaPage()))),
        ]),
        SettingsCardList(title: l10n.cache, children: [
          SettingsCardItem(title: l10n.clearCache, subtitle: cacheSize == null ? l10n.clearCacheDescription : l10n.cacheUsage(CacheCleaner.formatSize(cacheSize)), leading: const Icon(Icons.cleaning_services_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => unawaited(_clearCache())),
        ]),
        SettingsCardList(title: l10n.backupSettings, children: [
          SettingsCardItem(title: l10n.exportDataBackup, subtitle: l10n.exportDataBackupDescription, leading: const Icon(Icons.archive_outlined), trailing: const Icon(Icons.chevron_right), onTap: () => setState(() => _showBackup = true)),
        ]),
      ]),
    );
  }

  Future<void> _editDownloadPath(BuildContext context, AppSettings settings, SettingsController controller) async {
    if (Platform.isAndroid || Platform.isIOS) {
      final path = await resolveDefaultDownloadPath();
      await controller.saveChanges((current) => current.copyWith(downloadPath: path));
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.privateDownloadPath)));
      return;
    }
    final path = await showDialog<String>(context: context, builder: (_) => _PathDialog(title: AppLocalizations.of(context)!.downloadPath, initialPath: settings.downloadPath));
    if (path == null) return;
    await controller.saveChanges((current) => current.copyWith(downloadPath: path));
  }

  Future<void> _exportDownloads(BuildContext context, WidgetRef ref) async {
    if (Platform.isAndroid) {
      final exported = await ref.read(downloadProvider.notifier).exportCompletedWithPicker();
      if (!exported) return;
    } else {
      final path = await FilePicker.platform.getDirectoryPath(dialogTitle: AppLocalizations.of(context)!.exportDownloads);
      if (path == null || path.isEmpty) return;
      await ref.read(downloadProvider.notifier).exportCompleted(path);
    }
    if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(AppLocalizations.of(context)!.exportCompleted)));
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

class _PathDialog extends StatefulWidget { const _PathDialog({required this.title, required this.initialPath}); final String title; final String initialPath; @override State<_PathDialog> createState() => _PathDialogState(); }
class _PathDialogState extends State<_PathDialog> { late final _controller = TextEditingController(text: widget.initialPath); @override void dispose() { _controller.dispose(); super.dispose(); } Future<void> _browse() async { final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: widget.title, initialDirectory: _controller.text.trim().isEmpty ? null : _controller.text.trim()); if (selected != null) setState(() => _controller.text = selected); } @override Widget build(BuildContext context) { final l10n = AppLocalizations.of(context)!; return AlertDialog(title: Text(widget.title), content: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [Expanded(child: TextField(controller: _controller, autofocus: true, keyboardType: TextInputType.url, decoration: InputDecoration(labelText: l10n.downloadPath, hintText: platformDownloadPathHint(l10n.defaultDownloadPath)))), const SizedBox(width: 8), IconButton(tooltip: l10n.chooseFolder, onPressed: _browse, icon: const Icon(Icons.folder_open_outlined))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, _controller.text.trim()), child: Text(l10n.save))]); } }

class _SliderTile extends SettingsSliderItem {
  _SliderTile({required IconData icon, required String title, String? subtitle, required double value, required double min, required double max, required int divisions, required String label, required ValueChanged<double> onChanged})
      : super(leading: Icon(icon), title: title, subtitle: subtitle, value: value, min: min, max: max, divisions: divisions, label: label, onChanged: onChanged);
}
