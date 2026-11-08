import 'package:flutter/material.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../core/app_radius.dart';
import '../../core/app_design_tokens.dart';
import '../../../l10n/app_localizations.dart';

import '../../data/local/library_repository.dart';
import '../../data/local/watch_repository.dart';
import '../../core/app_shell.dart';
import '../../data/han1me_repository.dart';
import '../../domain/models/library.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../shared/press_scale.dart';
import '../shared/hover_zoom.dart';
import '../shared/video_card.dart';
import '../shared/app_image_cache.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';
import '../video/play_window.dart';
import 'remote_library_controller.dart';
import '../../core/app_dialog.dart';
import '../shared/app_top_bar.dart';

/// 选中角标：白色对勾垫在一个半透明黑圆上。
///
/// 对勾是直接压在封面上的，封面亮的时候纯白图标会整片消失——垫一层深色圆底，
/// 无论封面深浅都能读出来。
class _SelectionCheck extends StatelessWidget {
  const _SelectionCheck();

  @override
  Widget build(BuildContext context) => const DecoratedBox(
    decoration: BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
    child: Padding(padding: EdgeInsets.all(2), child: Icon(Symbols.check_circle_rounded, color: Colors.white)),
  );
}

class LibraryPage extends ConsumerStatefulWidget {
  const LibraryPage({super.key, this.initialTab = 0});

  final int initialTab;

  @override
  ConsumerState<LibraryPage> createState() => _LibraryPageState();
}

class _LibraryPageState extends ConsumerState<LibraryPage> {
  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).valueOrNull;
    if (account?.id != null) return _RemoteLibrary(initialTab: widget.initialTab);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppTopBar(leading: Navigator.of(context).canPop() || permanentNavigationDrawer(context) ? null : PressScale(child: IconButton(tooltip: l10n.navigationDrawer, onPressed: openAppDrawer, icon: const Icon(Symbols.menu_rounded))), title: Text(_tabTitle(l10n, widget.initialTab)), actions: widget.initialTab == 4 ? [PressScale(child: IconButton(tooltip: l10n.statistics, onPressed: () => context.push('/stats'), icon: const Icon(Symbols.bar_chart_rounded)))] : null),
      body: LibraryTabView(index: widget.initialTab),
    );
  }
}

/// 单个清单页签的内容（清单页与「我的」页共用）：自己取数据，因此可以直接嵌进别的页面。
class LibraryTabView extends ConsumerStatefulWidget {
  const LibraryTabView({super.key, required this.index});

  /// 0 稍后观看 / 1 喜欢的影片 / 2 播放清单 / 3 我的订阅 / 4 观看历史。
  final int index;

  @override
  ConsumerState<LibraryTabView> createState() => _LibraryTabViewState();
}

class _LibraryTabViewState extends ConsumerState<LibraryTabView> {
  /// 订阅页里选中的作者（本地订阅用）。
  String? _artistId;

  @override
  Widget build(BuildContext context) {
    final account = ref.watch(accountProvider).valueOrNull;
    final l10n = AppLocalizations.of(context)!;
    if (account?.id != null) {
      return ref.watch(remoteLibraryProvider).when(
            loading: () => const Center(child: M3EContainedLoadingIndicator()),
            error: (error, stackTrace) => Center(child: PressScale(child: FilledButton(onPressed: () => ref.invalidate(remoteLibraryProvider), child: Text(l10n.reload)))),
            data: (library) => _remoteTabContent(context, library, widget.index, account?.csrfToken),
          );
    }
    return ref.watch(libraryProvider).when(
          loading: () => const Center(child: M3EContainedLoadingIndicator()),
          error: (error, stackTrace) => Center(child: Text('$error')),
          data: (library) => _localTabContent(context, library, widget.index, _artistId, (artist) => setState(() => _artistId = artist)),
        );
  }
}

Widget _localTabContent(BuildContext context, LibraryState library, int index, String? artistId, ValueChanged<String?> onSelectedArtist) {
  final l10n = AppLocalizations.of(context)!;
  return switch (index) {
    0 => _SelectableVideos(videos: library.watchLater, emptyMessage: l10n.noWatchLater, remover: (ref, ids) => ref.read(libraryProvider.notifier).removeWatchLater(ids)),
    1 => _SelectableVideos(videos: library.favorites, emptyMessage: l10n.noFavoriteVideos, remover: (ref, ids) => ref.read(libraryProvider.notifier).removeFavorites(ids)),
    2 => _LocalPlaylists(playlists: library.playlists),
    3 => _LocalSubscriptions(artists: library.artists, videos: library.subscriptionVideos, selectedArtist: artistId, onSelected: onSelectedArtist),
    _ => const _LocalHistory(),
  };
}

class _RemoteLibrary extends ConsumerWidget {
  const _RemoteLibrary({required this.initialTab});

  final int initialTab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppTopBar(leading: permanentNavigationDrawer(context) ? null : PressScale(child: IconButton(tooltip: l10n.navigationDrawer, onPressed: openAppDrawer, icon: const Icon(Symbols.menu_rounded))), title: Text(_tabTitle(l10n, initialTab))),
      body: LibraryTabView(index: initialTab),
    );
  }
}

Widget _remoteTabContent(BuildContext context, RemoteLibrary library, int index, String? accountToken) {
  final l10n = AppLocalizations.of(context)!;
  return switch (index) {
    0 => _SelectableVideos(
        videos: library.watchLater,
        emptyMessage: l10n.noWatchLater,
        remover: (ref, ids) async {
          final account = ref.read(accountProvider).valueOrNull;
          final userId = account?.id;
          final token = library.csrfToken ?? accountToken;
          if (userId == null || token == null) return;
          final settings = await ref.read(settingsProvider.future);
          final repository = ref.read(han1meRepositoryProvider);
          for (final id in ids) {
            await repository.saveToPlaylist(settings.resolvedBaseUrl, token, 'save', id, false);
          }
          ref.invalidate(remoteLibraryProvider);
        },
      ),
    1 => _SelectableVideos(
        videos: library.favorites,
        emptyMessage: l10n.noFavoriteVideos,
        remover: (ref, ids) async {
          final account = ref.read(accountProvider).valueOrNull;
          final userId = account?.id;
          final token = library.csrfToken ?? accountToken;
          if (userId == null || token == null) return;
          final settings = await ref.read(settingsProvider.future);
          final repository = ref.read(han1meRepositoryProvider);
          for (final id in ids) {
            await repository.setFavorite(settings.resolvedBaseUrl, token, userId, id, false);
          }
          ref.invalidate(remoteLibraryProvider);
        },
      ),
    2 => _Playlists(playlists: library.playlists, token: library.csrfToken ?? accountToken),
    3 => _RemoteSubscriptions(artists: library.subscriptionArtists, videos: library.subscriptions),
    _ => _RemoteHistory(videos: library.history, token: accountToken ?? library.csrfToken),
  };
}

String _tabTitle(AppLocalizations l10n, int index) => switch (index) {
  0 => l10n.watchLater,
  1 => l10n.favoriteVideos,
  2 => l10n.playlists,
  3 => l10n.subscriptions,
  _ => l10n.watchHistory,
};

class _LocalHistory extends ConsumerStatefulWidget {
  const _LocalHistory();

  @override
  ConsumerState<_LocalHistory> createState() => _LocalHistoryState();
}

class _LocalHistoryState extends ConsumerState<_LocalHistory> {
  final _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final all = ref.watch(watchProvider).valueOrNull?.histories ?? const [];
    // 新的在前；搜索时按标题过滤。
    var items = all.reversed.toList(growable: false);
    if (_keyword.trim().isNotEmpty) {
      items = items.where((item) => item.title.toLowerCase().contains(_keyword.trim().toLowerCase())).toList(growable: false);
    }
    String dateKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
    final now = DateTime.now();
    final todayKey = dateKey(now);
    final yesterdayKey = dateKey(now.subtract(const Duration(days: 1)));
    final groups = <String, List<WatchHistory>>{};
    for (final item in items) {
      final key = item.date == todayKey ? '今天' : (item.date == yesterdayKey ? '昨天' : item.date);
      groups.putIfAbsent(key, () => <WatchHistory>[]).add(item);
    }
    String fmtDuration(int ms) {
      final total = (ms / 1000).round();
      final m = total ~/ 60;
      final s = total % 60;
      return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    String fmtSize(int ms) {
      // 站点历史不带文件大小，按观看时长估个约数（每分钟约 8 MB）—— 只作展示提示。
      final mb = (ms / 60000 * 8).round();
      return mb >= 1024 ? '${(mb / 1024).toStringAsFixed(1)} GB' : '$mb MB';
    }
    return Column(
      children: [
        // 顶部工具条：标题 + 计数 + 搜索框 + 清空 + 齿轮。
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 8),
          child: Row(
            children: [
              const Text('观看历史', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
              const SizedBox(width: 10),
              Text('共 ${all.length} 条 · 最近 30 天', style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
              const Spacer(),
              SizedBox(
                width: 260,
                height: 34,
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _keyword = v),
                  style: const TextStyle(fontSize: 13, color: AppDesignTokens.ink),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '在历史中搜索',
                    hintStyle: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
                    filled: true,
                    fillColor: AppDesignTokens.fieldFill,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    prefixIcon: const Icon(Symbols.search_rounded, size: 16, color: AppDesignTokens.inkMuted),
                    prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              PressScale(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  onTap: all.isEmpty
                      ? null
                      : () => ref.read(watchProvider.notifier).deleteHistories({for (final h in all) h.id}),
                  child: Container(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(color: AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.sm)),
                    child: const Text('清空', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              PressScale(child: IconButton(tooltip: l10n.settings, visualDensity: VisualDensity.compact, onPressed: () => context.push('/settings'), icon: const Icon(Symbols.settings_rounded, size: 20))),
            ],
          ),
        ),
        Expanded(
          child: items.isEmpty
              ? Center(child: Text(l10n.noWatchHistory, style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted)))
              : ListView(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  children: [
                    for (final entry in groups.entries) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(2, 14, 2, 8),
                        child: Row(
                          children: [
                            Text(entry.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                            const SizedBox(width: 8),
                            Text('${entry.value.length} 条', style: const TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMuted)),
                          ],
                        ),
                      ),
                      for (final item in entry.value)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _HistoryRow(
                            item: item,
                            duration: fmtDuration(item.watchedMs),
                            sizeLabel: fmtSize(item.watchedMs),
                            onDelete: () => ref.read(watchProvider.notifier).deleteHistories({item.id}),
                            onOpen: () => context.push('/video/${item.videoCode}'),
                          ),
                        ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }
}

/// 单条历史记录行：白底圆角14，缩略图 + 进度条 + 标题/集数 + 进度胶囊/大小 + 播放圆钮。
class _HistoryRow extends StatelessWidget {
  const _HistoryRow({required this.item, required this.duration, required this.sizeLabel, required this.onDelete, required this.onOpen});

  final WatchHistory item;
  final String duration;
  final String sizeLabel;
  final VoidCallback onDelete;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.md)),
      padding: const EdgeInsets.all(10),
      child: PressScale(child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onOpen,
        child: Row(
          children: [
            // 缩略图 + 底部进度条（这里用一条占位进度，真实进度在播放页维护）。
            ClipRRect(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              child: SizedBox(
                width: 96,
                height: 54,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    const ColoredBox(color: Color(0xFF3D3540)),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: SizedBox(
                        height: 3,
                        child: Row(children: const [
                          Expanded(flex: 62, child: ColoredBox(color: AppDesignTokens.accent)),
                          Expanded(flex: 38, child: ColoredBox(color: Color(0x59000000))),
                        ]),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                  const SizedBox(height: 5),
                  Text('$duration · ${item.date}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11.5, color: AppDesignTokens.inkSubtle)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(color: AppDesignTokens.accent.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(AppRadius.sm)),
              child: const Text('已看过', style: TextStyle(fontSize: 10.5, color: AppDesignTokens.accentDeep)),
            ),
            const SizedBox(width: 12),
            SizedBox(width: 60, child: Text(sizeLabel, style: const TextStyle(fontSize: 11.5, color: AppDesignTokens.inkMuted))),
            const SizedBox(width: 8),
            PressScale(
              child: InkWell(
                borderRadius: BorderRadius.circular(AppRadius.lg),
                onTap: onOpen,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: AppDesignTokens.accentDeep, shape: BoxShape.circle),
                  child: const Icon(Symbols.play_arrow_rounded, size: 18, color: Colors.white),
                ),
              ),
            ),
            IconButton(
              tooltip: AppLocalizations.of(context)!.delete,
              onPressed: onDelete,
              icon: const Icon(Symbols.close_rounded, size: 16, color: AppDesignTokens.inkMuted),
            ),
          ],
        ),
      )),
    );
  }
}

class _RemoteSubscriptions extends StatefulWidget {
  const _RemoteSubscriptions({required this.artists, required this.videos});

  final List<SubscribedArtist> artists;
  final List<FollowingVideo> videos;

  @override
  State<_RemoteSubscriptions> createState() => _RemoteSubscriptionsState();
}

class _RemoteSubscriptionsState extends State<_RemoteSubscriptions> {
  String? _artist;
  String _filter = 'all';

  @override
  Widget build(BuildContext context) {
    final selected = widget.artists.any((artist) => artist.name == _artist) ? _artist : null;
    return _SubscriptionsLayout(
      artists: widget.artists,
      updatesOf: (artist) => widget.videos.where((video) => video.artistName == artist.name).toList(growable: false),
      selectedKey: selected,
      keyOf: (artist) => artist.name,
      onSelected: (key) => setState(() => _artist = key),
      filter: _filter,
      onFilterChanged: (value) => setState(() => _filter = value),
      emptyMessage: AppLocalizations.of(context)!.noSubscriptionVideos,
    );
  }
}

class _LocalSubscriptions extends StatelessWidget {
  const _LocalSubscriptions({required this.artists, required this.videos, required this.selectedArtist, required this.onSelected});

  final List<SubscribedArtist> artists;
  final Map<String, List<FollowingVideo>> videos;
  final String? selectedArtist;
  final ValueChanged<String?> onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    if (artists.isEmpty) return Center(child: Text(l10n.noSubscriptionVideos));
    return _SubscriptionsLayout(
      artists: artists,
      updatesOf: (artist) => videos[artist.id] ?? const <FollowingVideo>[],
      selectedKey: selectedArtist,
      keyOf: (artist) => artist.id,
      onSelected: onSelected,
      filter: 'all',
      onFilterChanged: (_) {},
      emptyMessage: l10n.noSubscriptionVideos,
    );
  }
}

/// 关注页统一样式骨架：页头工具条 + 筛选胶囊 + 作者卡片网格。
///
/// 本地 / 远程两种数据源共用同一套视觉，只把「作者 → 作品」的取法抽成回调。
class _SubscriptionsLayout extends StatefulWidget {
  const _SubscriptionsLayout({
    required this.artists,
    required this.updatesOf,
    required this.selectedKey,
    required this.keyOf,
    required this.onSelected,
    required this.filter,
    required this.onFilterChanged,
    required this.emptyMessage,
  });

  final List<SubscribedArtist> artists;
  final List<FollowingVideo> Function(SubscribedArtist artist) updatesOf;
  final String? selectedKey;
  final String Function(SubscribedArtist artist) keyOf;
  final ValueChanged<String?> onSelected;
  final String filter;
  final ValueChanged<String> onFilterChanged;
  final String emptyMessage;

  @override
  State<_SubscriptionsLayout> createState() => _SubscriptionsLayoutState();
}

class _SubscriptionsLayoutState extends State<_SubscriptionsLayout> {
  final _search = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final allArtists = widget.artists;
    final updateCount = allArtists.where((artist) => widget.updatesOf(artist).isNotEmpty).length;
    final keyword = _keyword.trim().toLowerCase();
    var shown = allArtists;
    if (widget.selectedKey != null) {
      shown = shown.where((artist) => widget.keyOf(artist) == widget.selectedKey).toList(growable: false);
    }
    if (widget.filter == 'updated') {
      shown = shown.where((artist) => widget.updatesOf(artist).isNotEmpty).toList(growable: false);
    }
    if (keyword.isNotEmpty) {
      shown = shown.where((artist) => artist.name.toLowerCase().contains(keyword)).toList(growable: false);
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _SubscriptionHeader(
          total: allArtists.length,
          updated: updateCount,
          search: _search,
          onSearchChanged: (value) => setState(() => _keyword = value),
        ),
        _SubscriptionFilters(
          filter: widget.filter,
          total: allArtists.length,
          updated: updateCount,
          onChanged: widget.onFilterChanged,
        ),
        Expanded(
          child: shown.isEmpty
              ? Center(child: Text(widget.emptyMessage, style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted)))
              : GridView.builder(
                  padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 4, mainAxisSpacing: 16, crossAxisSpacing: 16, mainAxisExtent: 196),
                  itemCount: shown.length,
                  itemBuilder: (context, index) {
                    final artist = shown[index];
                    return _FollowingArtistCard(
                      artist: artist,
                      updates: widget.updatesOf(artist),
                      onTap: () => context.push('/author/${Uri.encodeComponent(artist.name)}'),
                      onToggle: () => widget.onSelected(widget.keyOf(artist) == widget.selectedKey ? null : widget.keyOf(artist)),
                      onLongPress: () {
                        final url = Uri(path: '/search', queryParameters: {'query': artist.name}).toString();
                        context.push(url, extra: SearchRouteRequest(initialUrl: url));
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }
}

/// 关注页页头：标题 + 计数 + 搜索框 + 排序胶囊。
class _SubscriptionHeader extends StatelessWidget {
  const _SubscriptionHeader({required this.total, required this.updated, required this.search, required this.onSearchChanged});

  final int total;
  final int updated;
  final TextEditingController search;
  final ValueChanged<String> onSearchChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 12),
      child: Row(
        children: [
          const Text('关注', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
          const SizedBox(width: 10),
          Text('$total 位作者 · $updated 位有更新', style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted)),
          const Spacer(),
          SizedBox(
            width: 220,
            height: 34,
            child: TextField(
              controller: search,
              onChanged: onSearchChanged,
              style: const TextStyle(fontSize: 13, color: AppDesignTokens.ink),
              decoration: InputDecoration(
                isDense: true,
                hintText: '搜索作者',
                hintStyle: const TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
                filled: true,
                fillColor: AppDesignTokens.fieldFill,
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                prefixIcon: const Icon(Symbols.search_rounded, size: 16, color: AppDesignTokens.inkMuted),
                prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
                enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(AppRadius.sm), borderSide: BorderSide.none),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 34,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.sm), border: Border.all(color: AppDesignTokens.stroke)),
            child: const Row(
              children: [
                Text('最近更新', style: TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle)),
                SizedBox(width: 4),
                Icon(Symbols.keyboard_arrow_down_rounded, size: 16, color: AppDesignTokens.inkSubtle),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 关注页筛选胶囊：全部 / 有更新 / 最近收藏。
class _SubscriptionFilters extends StatelessWidget {
  const _SubscriptionFilters({required this.filter, required this.total, required this.updated, required this.onChanged});

  final String filter;
  final int total;
  final int updated;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
      child: Row(
        children: [
          _FilterChip(label: '全部 $total', selected: filter == 'all', onTap: () => onChanged('all')),
          const SizedBox(width: 8),
          _FilterChip(label: '有更新 $updated', selected: filter == 'updated', onTap: () => onChanged('updated')),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return PressScale(
      child: InkWell(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(color: selected ? AppDesignTokens.accentDeep : AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.sm)),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: selected ? FontWeight.w700 : FontWeight.w500, color: selected ? Colors.white : AppDesignTokens.inkSubtle)),
        ),
      ),
    );
  }
}

/// 关注页作者卡片：上方淡粉头像区 + 白底信息区 + 状态胶囊。
class _FollowingArtistCard extends StatelessWidget {
  const _FollowingArtistCard({required this.artist, required this.updates, required this.onTap, required this.onToggle, required this.onLongPress});

  final SubscribedArtist artist;
  final List<FollowingVideo> updates;
  final VoidCallback onTap;
  final VoidCallback onToggle;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final hasAvatar = artist.avatarUrl?.isNotEmpty == true;
    final hasUpdates = updates.isNotEmpty;
    return PressScale(
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.lg), border: Border.all(color: AppDesignTokens.divider)),
          clipBehavior: Clip.antiAlias,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                height: 72,
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFFFBEDF2), Color(0xFFF6F1F4)])),
                alignment: Alignment.center,
                child: CircleAvatar(
                  radius: 24,
                  backgroundColor: AppDesignTokens.surface,
                  backgroundImage: hasAvatar ? appNetworkImage(artist.avatarUrl!) : null,
                  child: hasAvatar ? null : Text(artist.name.isNotEmpty ? artist.name.characters.first : '?', style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: AppDesignTokens.accent)),
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 12, 10, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                      const SizedBox(height: 4),
                      Text(_subtitle(artist, updates), maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppDesignTokens.inkMuted)),
                      const Spacer(),
                      GestureDetector(
                        onTap: onToggle,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                          decoration: BoxDecoration(color: hasUpdates ? AppDesignTokens.accentDeep : AppDesignTokens.fieldFill, borderRadius: BorderRadius.circular(AppRadius.md)),
                          child: Text(
                            hasUpdates ? '${updates.length} 部新作' : '已关注',
                            style: TextStyle(fontSize: 11, fontWeight: hasUpdates ? FontWeight.w600 : FontWeight.w500, color: hasUpdates ? Colors.white : AppDesignTokens.inkSubtle),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _subtitle(SubscribedArtist artist, List<FollowingVideo> updates) {
    final genre = artist.genre?.trim();
    if (genre != null && genre.isNotEmpty) return '${updates.length} 作品 · $genre';
    return '${updates.length} 作品';
  }
}

class _LocalPlaylists extends StatelessWidget {
  const _LocalPlaylists({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) => _LocalPlaylistList(playlists: playlists);
}

class _LocalPlaylistList extends StatelessWidget {
  const _LocalPlaylistList({required this.playlists});

  final List<Playlist> playlists;

  @override
  Widget build(BuildContext context) {
    if (playlists.isEmpty) {
      return Center(
        child: Text(
          AppLocalizations.of(context)!.noPlaylists,
          style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted),
        ),
      );
    }
    return GridView.builder(
      padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
      itemCount: playlists.length,
      // 白卡留呼吸：行/列间距比旧版(10)略松，卡片高度多给一行标题 + 元数据。
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: 1.32,
      ),
      itemBuilder: (context, index) => _LocalPlaylistCard(playlist: playlists[index]),
    );
  }
}

class _LocalPlaylistCard extends StatelessWidget {
  const _LocalPlaylistCard({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) => _PlaylistGridCard(playlist: playlist, onTap: () => showModalBottomSheet<void>(context: context, barrierColor: Colors.transparent, showDragHandle: true, isScrollControlled: true, builder: (context) => _LocalPlaylistItemsSheet(playlist: playlist)));
}

class _Playlists extends ConsumerWidget {
  const _Playlists({required this.playlists, required this.token});
  final List<Playlist> playlists;
  final String? token;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        playlists.isEmpty
            ? Center(
                child: Text(
                  l10n.noPlaylists,
                  style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted),
                ),
              )
            : GridView.builder(
                padding: EdgeInsets.fromLTRB(12, 12, 12, 12 + MediaQuery.paddingOf(context).bottom),
                itemCount: playlists.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, crossAxisSpacing: 12, mainAxisSpacing: 12, childAspectRatio: 1.32),
                itemBuilder: (context, index) => _PlaylistCard(playlist: playlists[index]),
              ),
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: FloatingActionButton(
            tooltip: l10n.newPlaylist,
            onPressed: token == null ? null : () => _createPlaylist(context, ref, token!),
            child: const Icon(Symbols.playlist_add_rounded),
          ),
        ),
      ],
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref, String token) async {
    final result = await showAppDialog<(String, String)>(context: context, builder: (_) => const _CreatePlaylistDialog());
    if (result == null || result.$1.isEmpty) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).createPlaylist(settings.resolvedBaseUrl, token, '', result.$1, result.$2);
    ref.invalidate(remoteLibraryProvider);
  }
}

class _CreatePlaylistDialog extends StatefulWidget {
  const _CreatePlaylistDialog();

  @override
  State<_CreatePlaylistDialog> createState() => _CreatePlaylistDialogState();
}

class _CreatePlaylistDialogState extends State<_CreatePlaylistDialog> {
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
    return AlertDialog(
      title: Text(l10n.newPlaylist),
      content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _title, autofocus: true, decoration: InputDecoration(labelText: l10n.name)), TextField(controller: _description, decoration: InputDecoration(labelText: l10n.description))]),
      actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, (_title.text.trim(), _description.text.trim())), child: Text(l10n.create)))],
    );
  }
}

class _RemoteHistory extends ConsumerStatefulWidget {
  const _RemoteHistory({required this.videos, required this.token});

  final List<FollowingVideo> videos;
  final String? token;

  @override
  ConsumerState<_RemoteHistory> createState() => _RemoteHistoryState();
}

class _RemoteHistoryState extends ConsumerState<_RemoteHistory> {
  final _selected = <String>{};
  var _selectionMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        widget.videos.isEmpty
            ? Center(child: Text(l10n.noWatchHistory))
            : VideoCardGrid(
                videos: widget.videos.map(_videoCard).toList(growable: false),
                cardsPerRow: 4,
                itemBuilder: (context, index, video, horizontal) {
                  final selected = _selected.contains(video.id);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        decoration: selected ? BoxDecoration(border: Border.all(color: Theme.of(context).colorScheme.primary, width: 2), borderRadius: BorderRadius.circular(AppRadius.md)) : const BoxDecoration(),
                        child: VideoCardTile(video: video, horizontal: horizontal, onTap: _selectionMode ? () => _toggle(video.id) : null, onLongPress: () => _startSelection(video.id)),
                      ),
                      if (selected) const Positioned(top: 6, right: 6, child: _SelectionCheck()),
                    ],
                  );
                },
              ),
        Positioned(
          right: 16,
          bottom: 16 + MediaQuery.paddingOf(context).bottom,
          child: FloatingActionButton(tooltip: _selectionMode ? l10n.delete : l10n.select, onPressed: widget.token == null ? null : (_selectionMode ? (_selected.isEmpty ? _exitSelection : _deleteSelected) : _enterSelection), child: Icon(_selectionMode ? Symbols.delete_rounded : Symbols.checklist_rounded)),
        ),
      ],
    );
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  void _enterSelection() => setState(() => _selectionMode = true);
  void _startSelection(String id) => setState(() { _selectionMode = true; _selected.add(id); });
  void _exitSelection() => setState(() { _selectionMode = false; _selected.clear(); });

  Future<void> _deleteSelected() async {
    final token = widget.token;
    if (token == null) return;
    final confirmed = await showAppDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(AppLocalizations.of(context)!.delete), content: Text(AppLocalizations.of(context)!.selectedItems(_selected.length)), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context)!.delete)))]));
    if (confirmed != true) return;
    final settings = await ref.read(settingsProvider.future);
    for (final id in _selected) {
      await ref.read(han1meRepositoryProvider).deleteHistory(settings.resolvedBaseUrl, token, id);
    }
    if (!mounted) return;
    setState(() { _selectionMode = false; _selected.clear(); });
    ref.invalidate(remoteLibraryProvider);
  }
}

class _PlaylistCard extends ConsumerStatefulWidget {
  const _PlaylistCard({required this.playlist});
  final Playlist playlist;
  @override
  ConsumerState<_PlaylistCard> createState() => _PlaylistCardState();
}

class _PlaylistCardState extends ConsumerState<_PlaylistCard> {
  Future<void> _delete() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(l10n.deletePlaylist), content: Text(l10n.deletePlaylistConfirmation(widget.playlist.title)), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)))]));
    final account = ref.read(accountProvider).valueOrNull;
    if (confirmed != true || account?.csrfToken == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).deletePlaylist(settings.resolvedBaseUrl, account!.csrfToken!, widget.playlist.id);
    ref.invalidate(remoteLibraryProvider);
  }

  @override
  Widget build(BuildContext context) => _PlaylistGridCard(playlist: widget.playlist, onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => _PlaylistItemsPage(playlist: widget.playlist))), onLongPress: _delete);
}

class _PlaylistGridCard extends StatelessWidget {
  const _PlaylistGridCard({required this.playlist, required this.onTap, this.onLongPress});

  final Playlist playlist;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return CardHover(
      builder: (context, hovered) => DecoratedBox(
        // 白底 + 大圆角 + 一圈极细描边，不铺重阴影：卡片靠描边从页面底上立起来，
        // 观感与「稍后看/收藏」的影片网格一致。
        decoration: BoxDecoration(
          color: AppDesignTokens.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppDesignTokens.stroke, width: 1),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          child: Material(
            type: MaterialType.transparency,
            child: PressScale(child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress,
              hoverColor: Colors.transparent,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 封面在卡片内也切圆角，而不是贴着卡片的直角边：白卡 + 圆角封面
                  // 是设计稿里「卡片」的统一做法。
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          width: double.infinity,
                          child: playlist.coverUrl?.isNotEmpty == true
                              ? ZoomOnHover(
                                  hovered: hovered,
                                  child: AppCachedNetworkImage(
                                    imageUrl: playlist.coverUrl!,
                                    fit: BoxFit.cover,
                                    memCacheWidth: 480,
                                    faceFocus: true,
                                    // 封面加载失败（网络/缓存写盘失败）时给个占位图标，
                                    // 别把异常原文画在卡片上。
                                    errorWidget: (context, url, error) => const ColoredBox(
                                      color: AppDesignTokens.fieldFill,
                                      child: Icon(Symbols.playlist_play_rounded, size: 40, color: AppDesignTokens.inkMuted),
                                    ),
                                  ),
                                )
                              : ColoredBox(
                                  color: AppDesignTokens.fieldFill,
                                  child: const Icon(
                                    Symbols.playlist_play_rounded,
                                    size: 40,
                                    color: AppDesignTokens.inkMuted,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 8, 12, 3),
                    child: Text(
                      playlist.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.ink,
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                    child: Text(
                      l10n.videoCount(playlist.count),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: AppDesignTokens.accentDeep,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
    )));
  }
}

class _LocalPlaylistItemsSheet extends StatelessWidget {
  const _LocalPlaylistItemsSheet({required this.playlist});

  final Playlist playlist;

  @override
  Widget build(BuildContext context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .78,
          child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(24, 4, 24, 12), child: Align(alignment: Alignment.centerLeft, child: Text(playlist.title, style: Theme.of(context).textTheme.titleLarge))),
            Expanded(child: playlist.videos.isEmpty ? Center(child: Text(AppLocalizations.of(context)!.playlistEmpty)) : _Videos(videos: playlist.videos, message: AppLocalizations.of(context)!.playlistEmpty)),
          ]),
        ),
      );
}

class _PlaylistItemsPage extends ConsumerStatefulWidget {
  const _PlaylistItemsPage({required this.playlist});

  final Playlist playlist;

  @override
  ConsumerState<_PlaylistItemsPage> createState() => _PlaylistItemsPageState();
}

class _PlaylistItemsPageState extends ConsumerState<_PlaylistItemsPage> {
  var _sort = 'latest';
  var _editing = false;
  final _selectedItems = <String>{};
  late Future<PlaylistDetail> _playlist = _load();

  Future<PlaylistDetail> _load() async {
    final settings = await ref.read(settingsProvider.future);
    return ref.read(han1meRepositoryProvider).playlist(settings.resolvedBaseUrl, widget.playlist.id, _sort);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final account = ref.watch(accountProvider).valueOrNull;
    return Scaffold(
      appBar: AppTopBar(title: Text(widget.playlist.title)),
      body: FutureBuilder<PlaylistDetail>(
        future: _playlist,
        builder: (context, snapshot) {
          if (snapshot.hasError) return Center(child: Text(l10n.loadFailed('${snapshot.error}')));
          if (!snapshot.hasData) return const Center(child: M3EContainedLoadingIndicator());
          final playlist = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            children: [
              if (playlist.playlist.coverUrl?.isNotEmpty == true) ClipRRect(borderRadius: BorderRadius.circular(AppRadius.lg), child: AspectRatio(aspectRatio: 16 / 9, child: AppCachedNetworkImage(imageUrl: playlist.playlist.coverUrl!, fit: BoxFit.cover, memCacheWidth: 960, faceFocus: true, errorWidget: (context, url, error) => const ColoredBox(color: AppDesignTokens.fieldFill, child: Icon(Symbols.playlist_play_rounded, size: 48, color: AppDesignTokens.inkMuted))))),
              const SizedBox(height: 16),
              Text(playlist.playlist.title, style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              if (playlist.author?.isNotEmpty == true) Text(l10n.playlistCreatedBy(playlist.author!), style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 4),
              Text(l10n.playlistStats(playlist.playlist.count, playlist.viewCount ?? 0), style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).colorScheme.outline)),
              if (playlist.description?.isNotEmpty == true) Padding(padding: const EdgeInsets.only(top: 8), child: Text(playlist.description!)),
              const SizedBox(height: 16),
              Row(children: [Expanded(child: PressScale(child: FilledButton.icon(onPressed: playlist.videos.isEmpty ? null : () => openVideo(context, ref, playlist.videos.first.videoCode), icon: const Icon(Symbols.play_arrow_rounded), label: Text(l10n.playAll)))), const SizedBox(width: 8), PressScale(child: IconButton.filledTonal(onPressed: account?.csrfToken == null ? null : () => _edit(playlist), icon: const Icon(Symbols.edit_rounded))), const SizedBox(width: 8), PressScale(child: IconButton.filledTonal(onPressed: () => Share.share('https://hanimeone.me/playlist?list=${playlist.playlist.id}', subject: playlist.playlist.title), icon: const Icon(Symbols.share_rounded)))]),
              const SizedBox(height: 20),
              Row(children: [for (final value in ['latest', 'popular', 'oldest']) Padding(padding: const EdgeInsets.only(right: 8), child: ChoiceChip(label: Text(_sortLabel(l10n, value)), selected: _sort == value, onSelected: _editing ? null : (_) => _changeSort(value))), const Spacer(), PressScale(child: TextButton.icon(onPressed: _editing ? _removeSelected : () => setState(() => _editing = true), icon: Icon(_editing ? Symbols.delete_rounded : Symbols.edit_rounded), label: Text(_editing ? l10n.delete : l10n.edit)))]),
              const SizedBox(height: 4),
              if (playlist.videos.isEmpty) Padding(padding: const EdgeInsets.all(24), child: Center(child: Text(l10n.playlistEmpty))) else _PlaylistVideoGrid(videos: playlist.videos, editing: _editing, selected: _selectedItems, onToggle: _toggleItem),
            ],
          );
        },
      ),
    );
  }

  String _sortLabel(AppLocalizations l10n, String value) => switch (value) {'latest' => l10n.latest, 'popular' => l10n.popular, _ => l10n.oldest};

  void _changeSort(String value) => setState(() { _sort = value; _playlist = _load(); });

  Future<void> _edit(PlaylistDetail playlist) async {
    final result = await showAppDialog<(String, String, bool)>(context: context, builder: (_) => _PlaylistEditDialog(playlist: playlist));
    if (result == null) return;
    final account = ref.read(accountProvider).valueOrNull;
    if (account?.csrfToken == null) return;
    final settings = await ref.read(settingsProvider.future);
    await ref.read(han1meRepositoryProvider).updatePlaylist(settings.resolvedBaseUrl, account!.csrfToken!, playlist.playlist.id, result.$1, result.$2, result.$3);
    if (!mounted) return;
    if (result.$3) {
      Navigator.pop(context);
      ref.invalidate(remoteLibraryProvider);
      return;
    }
    setState(() => _playlist = _load());
    ref.invalidate(remoteLibraryProvider);
  }

  void _toggleItem(FollowingVideo video) {
    final id = video.playlistItemId;
    if (id == null) return;
    setState(() => _selectedItems.contains(id) ? _selectedItems.remove(id) : _selectedItems.add(id));
  }

  Future<void> _removeSelected() async {
    if (_selectedItems.isEmpty) {
      setState(() => _editing = false);
      return;
    }
    final confirmed = await showAppDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(AppLocalizations.of(context)!.delete), content: Text(AppLocalizations.of(context)!.selectedItems(_selectedItems.length)), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(AppLocalizations.of(context)!.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(AppLocalizations.of(context)!.delete)))]));
    final account = ref.read(accountProvider).valueOrNull;
    if (confirmed != true || account?.csrfToken == null) return;
    final settings = await ref.read(settingsProvider.future);
    await Future.wait(_selectedItems.map((id) => ref.read(han1meRepositoryProvider).removePlaylistItem(settings.resolvedBaseUrl, account!.csrfToken!, id)));
    if (mounted) setState(() { _editing = false; _selectedItems.clear(); _playlist = _load(); });
  }
}

class _PlaylistVideoGrid extends StatelessWidget {
  const _PlaylistVideoGrid({required this.videos, required this.editing, required this.selected, required this.onToggle});

  final List<FollowingVideo> videos;
  final bool editing;
  final Set<String> selected;
  final ValueChanged<FollowingVideo> onToggle;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          const spacing = 10.0;
          final cardWidth = (constraints.maxWidth - spacing) / 2;
          final cardHeight = cardWidth * 9 / 16 + 120;
          return GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, mainAxisSpacing: 12, crossAxisSpacing: spacing, mainAxisExtent: cardHeight),
            itemCount: videos.length,
            itemBuilder: (context, index) {
              final video = videos[index];
              final isSelected = selected.contains(video.playlistItemId);
              return Stack(
                fit: StackFit.expand,
                children: [
                  VideoCardTile(video: _videoCard(video), horizontal: true, onTap: editing ? () => onToggle(video) : null),
                  if (editing) Positioned(top: 4, right: 4, child: Checkbox(value: isSelected, onChanged: (value) => onToggle(video))),
                ],
              );
            },
          );
        },
      );
}

class _PlaylistEditDialog extends StatefulWidget {
  const _PlaylistEditDialog({required this.playlist});

  final PlaylistDetail playlist;

  @override
  State<_PlaylistEditDialog> createState() => _PlaylistEditDialogState();
}

class _PlaylistEditDialogState extends State<_PlaylistEditDialog> {
  late final _title = TextEditingController(text: widget.playlist.playlist.title);
  late final _description = TextEditingController(text: widget.playlist.description ?? '');
  var _delete = false;

  @override
  void dispose() { _title.dispose(); _description.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return AlertDialog(title: Text(l10n.edit), content: Column(mainAxisSize: MainAxisSize.min, children: [TextField(controller: _title, decoration: InputDecoration(labelText: l10n.name)), TextField(controller: _description, minLines: 3, maxLines: 5, decoration: InputDecoration(labelText: l10n.description)), CheckboxListTile(contentPadding: EdgeInsets.zero, value: _delete, onChanged: (value) => setState(() => _delete = value ?? false), title: Text(l10n.deletePlaylist))]), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: _title.text.trim().isEmpty ? null : () => Navigator.pop(context, (_title.text.trim(), _description.text.trim(), _delete)), child: Text(l10n.confirm)))]);
  }
}

class _Videos extends StatelessWidget {
  const _Videos({required this.videos, required this.message});

  final List<FollowingVideo> videos;
  final String message;

  @override
  Widget build(BuildContext context) {
    if (videos.isEmpty) return Center(child: Text(message, style: Theme.of(context).textTheme.bodyLarge));
    return VideoCardGrid(videos: videos.map(_videoCard).toList(growable: false), cardsPerRow: 4);
  }
}

class _SelectableVideos extends ConsumerStatefulWidget {
  const _SelectableVideos({required this.videos, required this.emptyMessage, required this.remover});

  final List<FollowingVideo> videos;
  final String emptyMessage;
  final Future<void> Function(WidgetRef ref, Set<String> videoCodes) remover;

  @override
  ConsumerState<_SelectableVideos> createState() => _SelectableVideosState();
}

class _SelectableVideosState extends ConsumerState<_SelectableVideos> {
  final _selected = <String>{};
  var _selectionMode = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Stack(
      children: [
        widget.videos.isEmpty
            ? Center(
                child: Text(
                  widget.emptyMessage,
                  style: const TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted),
                ),
              )
            : VideoCardGrid(
                videos: widget.videos.map(_videoCard).toList(growable: false),
                cardsPerRow: 4,
                itemBuilder: (context, index, video, horizontal) {
                  final selected = _selected.contains(video.id);
                  return Stack(
                    fit: StackFit.expand,
                    children: [
                      DecoratedBox(
                        // 选中态用设计稿主色描一圈（与封面圆角同档），不铺底色。
                        decoration: selected
                            ? BoxDecoration(
                                border: Border.all(color: AppDesignTokens.accent, width: 2),
                                borderRadius: BorderRadius.circular(videoCardRadius),
                              )
                            : const BoxDecoration(),
                        child: VideoCardTile(video: video, horizontal: horizontal, onTap: _selectionMode ? () => _toggle(video.id) : null, onLongPress: () => _startSelection(video.id)),
                      ),
                      if (selected) const Positioned(top: 6, right: 6, child: _SelectionCheck()),
                    ],
                  );
                },
              ),
        Positioned(right: 16, bottom: 16 + MediaQuery.paddingOf(context).bottom, child: FloatingActionButton(tooltip: _selectionMode ? l10n.delete : l10n.select, onPressed: _selectionMode ? (_selected.isEmpty ? _exitSelection : _deleteSelected) : _enterSelection, child: Icon(_selectionMode ? Symbols.delete_rounded : Symbols.checklist_rounded))),
      ],
    );
  }

  void _toggle(String id) => setState(() => _selected.contains(id) ? _selected.remove(id) : _selected.add(id));
  void _enterSelection() => setState(() => _selectionMode = true);
  void _startSelection(String id) => setState(() { _selectionMode = true; _selected.add(id); });
  void _exitSelection() => setState(() { _selectionMode = false; _selected.clear(); });

  Future<void> _deleteSelected() async {
    final l10n = AppLocalizations.of(context)!;
    final confirmed = await showAppDialog<bool>(context: context, builder: (context) => AlertDialog(title: Text(l10n.delete), content: Text(l10n.selectedItems(_selected.length)), actions: [PressScale(child: TextButton(onPressed: () => Navigator.pop(context, false), child: Text(l10n.cancel))), PressScale(child: FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(l10n.delete)))]));
    if (confirmed != true || !mounted) return;
    await widget.remover(ref, _selected);
    if (mounted) setState(() { _selectionMode = false; _selected.clear(); });
  }
}

VideoCard _videoCard(FollowingVideo video) => VideoCard(id: video.videoCode, title: video.title, coverUrl: video.coverUrl ?? '', artist: video.artistName, duration: video.duration, views: video.views, rating: video.rating, uploadTime: video.uploadTime);
