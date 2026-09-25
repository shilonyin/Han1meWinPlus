import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:share_plus/share_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/video_player_shutdown.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/download_repository.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/download.dart';
import '../../domain/models/library.dart';
import '../../domain/models/video.dart';
import '../../domain/series_name.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import 'download_picker_sheet.dart';
import 'video_controller.dart';

/// 一个操作项（图标 / 文案 / 回调），悬浮工具条和侧栏操作排都用它
class _VideoAction {
  const _VideoAction(this.icon, this.label, this.onPressed);

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
}

/// 播放页侧栏里的操作排（图标在上、文案在下一排平铺）
class VideoActionRow extends ConsumerWidget {
  const VideoActionRow({super.key, required this.video});

  final VideoDetail video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
      child: Row(
        children: [
          for (final action in _videoActions(context, ref, video))
            Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: action.onPressed,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(action.icon, size: 18, color: action.onPressed == null ? theme.colorScheme.outline : theme.colorScheme.onSurface),
                      const SizedBox(height: 4),
                      Text(action.label, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class VideoActionBar extends ConsumerWidget {
  const VideoActionBar({super.key, required this.video, this.vertical = false});

  final VideoDetail video;
  final bool vertical;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actions = [for (final action in _videoActions(context, ref, video)) IconButton(tooltip: action.label, icon: Icon(action.icon), onPressed: action.onPressed)];
    return vertical
        ? M3EVerticalFloatingToolbar(expanded: true, content: Column(mainAxisSize: MainAxisSize.min, children: actions))
        : M3EHorizontalFloatingToolbar(expanded: true, content: Row(mainAxisSize: MainAxisSize.min, children: actions));
  }
}

/// 收藏 / 稍后看 / 下载 / 分享这几个操作
List<_VideoAction> _videoActions(BuildContext context, WidgetRef ref, VideoDetail video) {
  final library = ref.watch(libraryProvider).value ?? const LibraryState();
  final account = ref.watch(accountProvider).valueOrNull;
  final remote = account == null ? null : ref.watch(remoteLibraryProvider).valueOrNull;
  final inWatchLater = (remote?.watchLater ?? library.watchLater).any((item) => item.videoCode == video.id);
  final persistedFavorite = (remote?.favorites ?? library.favorites).any((item) => item.videoCode == video.id);
  final inFavorites = ref.watch(favoriteOverrideProvider(video.id)) ?? persistedFavorite;
  final l10n = AppLocalizations.of(context)!;
  return [
    _VideoAction(inWatchLater ? Icons.playlist_add_check : Icons.playlist_add, l10n.addToPlaylist, () => account == null ? _pickLocalPlaylist(context, ref, video, library) : _pickPlaylist(context, ref, video, video.csrfToken ?? remote?.csrfToken ?? account.csrfToken, remote)),
    _VideoAction(inFavorites ? Icons.favorite : Icons.favorite_border, l10n.favorite, () => _toggleFavorite(ref, video, account == null ? null : video.csrfToken ?? account.csrfToken, account == null ? null : video.currentUserId ?? account.id, !inFavorites)),
    _VideoAction(Icons.download_outlined, l10n.download, video.sources.any((item) => !_isStreamPlaylist(item)) ? () => _showDownloadPicker(context, ref, video) : null),
    _VideoAction(Icons.share_outlined, l10n.share, () => Share.share('${video.title} (${video.id})', subject: video.title)),
  ];
}

Future<void> _toggleFavorite(WidgetRef ref, VideoDetail video, String? token, String? userId, bool enabled) async {
  ref.read(favoriteOverrideProvider(video.id).notifier).state = enabled;
  try {
    if (token == null || userId == null) {
      await ref.read(libraryProvider.notifier).setFavorite(video, enabled);
      return;
    }
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).setFavorite(settings.resolvedBaseUrl, token, userId, video.id, enabled);
    ref.invalidate(remoteLibraryProvider);
  } catch (_) {
    ref.read(favoriteOverrideProvider(video.id).notifier).state = !enabled;
  }
}

Future<void> _pickLocalPlaylist(BuildContext context, WidgetRef ref, VideoDetail video, LibraryState library) async {
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(AppLocalizations.of(context)!.addToPlaylist)),
          ListTile(leading: const Icon(Icons.watch_later_outlined), title: Text(AppLocalizations.of(context)!.watchLater), onTap: () => Navigator.pop(context, '__watch_later__')),
          ...library.playlists.map((item) => ListTile(leading: const Icon(Icons.playlist_play), title: Text(item.title), subtitle: Text(AppLocalizations.of(context)!.videoCount(item.count)), onTap: () => Navigator.pop(context, item.id))),
          ListTile(leading: const Icon(Icons.add), title: Text(AppLocalizations.of(context)!.newPlaylist), onTap: () => Navigator.pop(context, '__create__')),
        ],
      ),
    ),
  );
  if (selected == null) return;
  final controller = ref.read(libraryProvider.notifier);
  if (selected == '__watch_later__') {
    await controller.setWatchLater(video, true);
    return;
  }
  if (selected != '__create__') {
    await controller.saveToPlaylist(video, selected);
    return;
  }
  final result = await showDialog<String>(context: context, builder: (_) => const _PlaylistNameDialog());
  if (result?.isEmpty != false) return;
  await controller.createPlaylist(video, result!);
}

Future<void> _pickPlaylist(BuildContext context, WidgetRef ref, VideoDetail video, String? token, RemoteLibrary? library) async {
  if (token == null) return;
  final selected = await showModalBottomSheet<String>(
    context: context,
    showDragHandle: true,
    builder: (context) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          ListTile(title: Text(AppLocalizations.of(context)!.addToPlaylist)),
          ListTile(leading: const Icon(Icons.watch_later_outlined), title: Text(AppLocalizations.of(context)!.watchLater), onTap: () => Navigator.pop(context, 'save')),
          ...(library?.playlists ?? const <Playlist>[]).map((item) => ListTile(leading: const Icon(Icons.playlist_play), title: Text(item.title), subtitle: Text(AppLocalizations.of(context)!.videoCount(item.count)), onTap: () => Navigator.pop(context, item.id))),
          ListTile(leading: const Icon(Icons.add), title: Text(AppLocalizations.of(context)!.newPlaylist), onTap: () => Navigator.pop(context, '__create__')),
        ],
      ),
    ),
  );
  if (selected == null) return;
  final settings = await ref.read(settingsProvider.future);
  if (selected == '__create__') {
    final result = await showDialog<(String, String)>(context: context, builder: (_) => const _PlaylistEditorDialog());
    if (result == null || result.$1.isEmpty) return;
    await ref.read(han1meRepositoryProvider).createPlaylist(settings.resolvedBaseUrl, token, video.id, result.$1, result.$2);
  } else {
    await ref.read(han1meRepositoryProvider).saveToPlaylist(settings.resolvedBaseUrl, token, selected, video.id, true);
  }
  ref.invalidate(remoteLibraryProvider);
}

/// HLS/播放列表源不能当成普通文件下载（那只会存到一个清单），下载入口只对渐进式片源开放。
bool _isStreamPlaylist(VideoSource source) => (source.type ?? '').toLowerCase().contains('mpegurl') || source.url.contains('.m3u8');

Future<void> _showDownloadPicker(BuildContext context, WidgetRef ref, VideoDetail video) async {
  final downloadable = video.sources.where((item) => !_isStreamPlaylist(item)).toList(growable: false);
  if (downloadable.isEmpty) return;
  final settings = await ref.read(settingsProvider.future);
  if (!context.mounted) return;
  final groups = ref.read(downloadProvider).valueOrNull?.groups ?? const <DownloadGroup>[];

  // 剧集列表：当前播放的这一集 + playlist 里的其他集（同 id 只留一条）。
  final episodes = <VideoCard>[
    VideoCard(id: video.id, title: video.title, coverUrl: video.coverUrl ?? ''),
    ...video.playlist.where((item) => item.id != video.id && item.id.isNotEmpty),
  ];

  final seriesName = inferSeriesName(video.title);
  final suggested = suggestGroupName(title: video.title, seriesName: seriesName, useSeriesName: settings.groupNameFromSeries);

  // 弹窗本体与遮罩配置都在 showDownloadPickerSheet 里（透明遮罩，
  // 不要改回 showModalBottomSheet —— 那会多出一层铺满中间的底板）。
  final picked = await showDownloadPickerSheet(
    context,
    sources: downloadable,
    episodes: episodes,
    currentId: video.id,
    suggestedGroupName: suggested,
    initialAutoGroup: settings.autoGroupDownloads,
    initialNameFromSeries: settings.groupNameFromSeries,
    initialTraditional: settings.groupNameTraditional,
    groupNames: {for (final group in groups) if (group.id != 'default') group.name},
  );
  if (picked == null) return;
  // 「我的下载」：去看已经下好的东西，不创建任务。
  //
  // 两个要点：
  // 1. 用 **push 而不是 go** —— `go('/cache')` 会把整条路由栈换成缓存分支，
  //    视频页被直接销毁，用户回不去、只能重新点开视频从头播。push 保留当前栈，
  //    返回键就能回到正在看的这一集。
  // 2. 先把播放中的视频**暂停**：视频页仍在栈里、播放器还活着，不暂停就会在
  //    缓存页后台继续出声（用户听到的"没暂停还在播放声音"就是这么来的）。
  if (picked.openDownloads) {
    await VideoPlayerShutdown.pauseAll();
    // 走挂根导航器的 /downloads（不是 shell 分支里的 /cache）：
    // push 进来 + 返回能回到当前这一集，见 app_router.dart 里的说明。
    if (context.mounted) await context.push('/downloads');
    return;
  }

  var groupId = 'default';
  if (picked.groupName.isNotEmpty) {
    groupId = await ref.read(downloadProvider.notifier).resolveAutoGroup(picked.groupName, DownloadGroupSort.defaultOrder);
  }

  // 逐集取详情页拿到真正的下载源：playlist 里只有 id/title，没有片源地址。
  final repository = ref.read(han1meRepositoryProvider);
  final baseUrl = settings.resolvedBaseUrl;
  final wanted = episodes.where((episode) => picked.episodeIds.contains(episode.id)).toList(growable: false);
  var added = 0;
  var failed = 0;
  for (final episode in wanted) {
    try {
      final detail = episode.id == video.id ? video : await repository.video(baseUrl, episode.id);
      // 按用户选的清晰度取源；没有同名清晰度就退回第一个可下载的渐进式源。
      final candidates = detail.sources.where((item) => !_isStreamPlaylist(item)).toList(growable: false);
      if (candidates.isEmpty) {
        failed++;
        continue;
      }
      final match = candidates.where((item) => item.quality == picked.source.quality).firstOrNull ?? candidates.first;
      await ref.read(downloadProvider.notifier).create(detail, match, groupId);
      added++;
    } catch (_) {
      failed++;
    }
  }

  // 同系列的旧任务若还在默认分组，一并归入新组；用户手动分过组的不动。
  if (groupId != 'default') {
    final codes = <String>{...wanted.map((episode) => episode.id), ...video.playlist.map((item) => item.id)};
    await ref.read(downloadProvider.notifier).adoptSeriesTasks(codes, groupId);
  }

  if (!context.mounted) return;
  final l10n = AppLocalizations.of(context)!;
  final message = failed == 0 ? l10n.addedToDownloadQueue : '${l10n.addedToDownloadQueue} · ${l10n.downloadPartialFailed(failed)}';
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(added == 0 ? l10n.downloadPartialFailed(failed) : message)));
}

class _PlaylistNameDialog extends StatefulWidget {
  const _PlaylistNameDialog();

  @override
  State<_PlaylistNameDialog> createState() => _PlaylistNameDialogState();
}

class _PlaylistNameDialogState extends State<_PlaylistNameDialog> {
  final _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(title: Text(l10n.newPlaylist), content: TextField(controller: _title, autofocus: true, decoration: InputDecoration(labelText: l10n.name)), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, _title.text.trim()), child: Text(l10n.create))]);
  }
}

class _PlaylistEditorDialog extends StatefulWidget {
  const _PlaylistEditorDialog();

  @override
  State<_PlaylistEditorDialog> createState() => _PlaylistEditorDialogState();
}

class _PlaylistEditorDialogState extends State<_PlaylistEditorDialog> {
  final _title = TextEditingController();
  final _description = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(title: Text(l10n.newPlaylist), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _title, autofocus: true, decoration: InputDecoration(labelText: l10n.name)), TextField(controller: _description, decoration: InputDecoration(labelText: l10n.description))]), actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel)), FilledButton(onPressed: () => Navigator.pop(context, (_title.text.trim(), _description.text.trim())), child: Text(l10n.create))]);
  }
}
