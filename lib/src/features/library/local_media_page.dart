import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/local_media_scanner.dart';
import '../../data/local/local_media_repository.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_sub_page.dart';
import '../video/video_page.dart';

/// 本地媒体库：扫描用户指定的目录，把里面的视频列出来直接播放。
///
/// 与在线视频是两条独立的来源——本地文件没有封面 / 作者 / 标签，
/// 列表只显示文件名解析出的标题，点开后走同一个播放页（传 localVideo）。
class LocalMediaPage extends ConsumerStatefulWidget {
  const LocalMediaPage({super.key});

  @override
  ConsumerState<LocalMediaPage> createState() => _LocalMediaPageState();
}

class _LocalMediaPageState extends ConsumerState<LocalMediaPage> {
  var _scanning = false;

  Future<void> _pickDirectory() async {
    final l10n = AppLocalizations.of(context)!;
    final selected = await FilePicker.platform.getDirectoryPath(dialogTitle: l10n.localMediaDirectory);
    if (selected == null) return;
    await _rescan(selected);
  }

  Future<void> _rescan(String directory) async {
    final controller = ref.read(settingsProvider.notifier);
    setState(() => _scanning = true);
    try {
      if (directory.isNotEmpty) await controller.saveChanges((current) => current.copyWith(localMediaDirectory: directory));
      await ref.read(localMediaRepositoryProvider).rescan(directory);
      await ref.read(localMediaRepositoryProvider).watchDirectory(directory);
      ref.invalidate(localMediaProvider);
    } finally {
      if (mounted) setState(() => _scanning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final settings = ref.watch(settingsProvider).valueOrNull;
    final directory = settings?.localMediaDirectory ?? '';
    final entries = ref.watch(localMediaProvider).valueOrNull ?? const [];
    return Scaffold(
      appBar: AppBar(leading: settingsSubPageBack(context), title: Text(l10n.localMedia)),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(directory.isEmpty ? l10n.localMediaHint : directory, style: Theme.of(context).textTheme.bodySmall),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Wrap(spacing: 8, children: [
              FilledButton.icon(onPressed: _scanning ? null : _pickDirectory, icon: const Icon(Icons.folder_open_outlined), label: Text(l10n.localMediaPickDirectory)),
              OutlinedButton.icon(onPressed: _scanning || directory.isEmpty ? null : () => _rescan(directory), icon: const Icon(Icons.refresh), label: Text(l10n.localMediaRescan)),
            ]),
          ),
          if (_scanning) const Padding(padding: EdgeInsets.all(24), child: Center(child: M3EContainedLoadingIndicator())),
          if (!_scanning && entries.isEmpty)
            Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l10n.localMediaEmpty)))
          else
            ...entries.map((entry) => ListTile(
                  leading: const Icon(Icons.movie_outlined),
                  title: Text(entry.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                  subtitle: Text(entry.path, maxLines: 1, overflow: TextOverflow.ellipsis),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => VideoPage(id: entry.id, localVideo: entry.toVideoDetail()))),
                )),
        ],
      ),
    );
  }
}
