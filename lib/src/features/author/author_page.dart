import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/video.dart';
import '../../../l10n/app_localizations.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import 'author_controller.dart';

/// 作者页：头部是作者资料（模糊横幅 / 头像 / 名字 / 数字 / 订阅 + 分享），下面分
/// 「主页」（最新 + 热门各一排）与「影片」（全部影片 + 排序 + 页内筛选）两个页签。
///
/// 为什么要有这一页：以前点作者名是「拿作者名去搜索」——落在一个带分类、排序、
/// 标签的搜索页上，看不出这是谁的页面，而且模糊匹配会混进别人的片子。这里换成
/// 作者自己的页面（用户对着 B 站的空间页提出的要求）。
class AuthorPage extends ConsumerStatefulWidget {
  const AuthorPage({super.key, required this.artist});

  final String artist;

  @override
  ConsumerState<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends ConsumerState<AuthorPage> {
  /// 每个分区最多摆几张：作者可能有好几百个片子，首页只做「一眼看个大概」。
  static const _sectionLimit = 10;

  /// 订阅状态的本地乐观值：点下去立刻变，请求失败再翻回来。
  bool? _override;

  /// 当前页签：0 = 主页，1 = 影片。
  int _tab = 0;

  /// 「影片」页签的排序（站点排序键，见 `assets/search_options/sort_option.json`）。
  String _sort = authorSortLatest;

  /// 页内筛选框：只在已经取回来的影片里过滤，不再打站点（站点搜索是关键字搜索，
  /// 拿它做「作者内搜索」会顺带把别人的片子搜出来，又要再筛一遍）。
  final _filter = TextEditingController();
  String _keyword = '';

  @override
  void dispose() {
    _filter.dispose();
    super.dispose();
  }

  bool _persisted() {
    final account = ref.watch(accountProvider).valueOrNull;
    final remote = account == null
        ? null
        : ref.watch(remoteLibraryProvider).valueOrNull;
    final library = ref.watch(libraryProvider).value ?? const LibraryState();
    final expected = widget.artist.trim().toLowerCase();
    return (remote?.subscriptionArtists ?? library.artists).any(
      (item) => item.name.trim().toLowerCase() == expected,
    );
  }

  /// 已登录时要有 artistId / token / userId 才能调站点的订阅接口；缺一个就只能
  /// 禁用按钮 —— 点了没反应比按钮灰着更让人困惑。
  bool _canSubscribe(VideoDetail profile) {
    final account = ref.read(accountProvider).valueOrNull;
    if (account == null) return true;
    return profile.artistId != null &&
        (profile.csrfToken ?? account.csrfToken) != null &&
        (profile.subscriptionUserId ?? profile.currentUserId ?? account.id) !=
            null;
  }

  Future<void> _toggleSubscription(VideoDetail profile) async {
    final account = ref.read(accountProvider).valueOrNull;
    final enabled = !(_override ?? _persisted());
    setState(() => _override = enabled);
    try {
      if (account == null) {
        // 未登录：只记在本地库里，和详情页作者卡一致。
        await ref
            .read(libraryProvider.notifier)
            .setSubscription(profile, enabled);
        return;
      }
      final settings = await ref.read(settingsProvider.future);
      await ref
          .read(han1meRepositoryProvider)
          .setSubscription(
            settings.resolvedBaseUrl,
            profile.csrfToken ?? account.csrfToken!,
            profile.subscriptionUserId ?? profile.currentUserId ?? account.id!,
            profile.artistId!,
            enabled,
          );
      ref.invalidate(remoteLibraryProvider);
    } catch (_) {
      if (mounted) setState(() => _override = !enabled);
    }
  }

  /// 「分享」：站点没有作者页地址，能分享的就是「拿作者名去搜」这个地址。
  Future<void> _share(String name) async {
    final settings = await ref.read(settingsProvider.future);
    final url = Uri.parse(
      settings.resolvedBaseUrl,
    ).replace(path: '/search', queryParameters: {'query': name}).toString();
    await Clipboard.setData(ClipboardData(text: url));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(url)));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final request = (artist: widget.artist, sort: _sort);
    final async = ref.watch(authorVideosProvider(request));
    final data = async.valueOrNull;
    final firstId = data == null || data.items.isEmpty
        ? ''
        : data.items.first.id;
    final profile = ref.watch(authorProfileProvider(firstId)).valueOrNull;
    final card = ref.watch(authorCardProvider(widget.artist)).valueOrNull;
    final subscribed = _override ?? _persisted();
    return Scaffold(
      appBar: AppBar(title: Text(l10n.author)),
      body: Column(
        children: [
          _banner(theme, l10n, card, profile, data, subscribed),
          UnderlineTabStrip(
            labels: [l10n.home, l10n.videoSection],
            index: _tab,
            onSelected: (index) => setState(() => _tab = index),
            padding: const EdgeInsets.symmetric(horizontal: 14),
          ),
          const Divider(height: 1),
          Expanded(
            child: _tab == 0
                ? _homeTab(theme, l10n)
                : _videosTab(theme, l10n, async, data, request),
          ),
        ],
      ),
    );
  }

  /// 头部横幅：作者头像放大、高斯模糊铺满，再压一层到页面底色的渐变 —— 下沿融进
  /// 背景，名字与数字在任何一张头像上都能读清。头像本身不模糊，放在横幅之上。
  Widget _banner(
    ThemeData theme,
    AppLocalizations l10n,
    VideoCard? card,
    VideoDetail? profile,
    AuthorVideos? data,
    bool subscribed,
  ) {
    final scheme = theme.colorScheme;
    final avatar = (card?.coverUrl.isNotEmpty ?? false)
        ? card!.coverUrl
        : profile?.artistAvatarUrl;
    final hasAvatar = avatar != null && avatar.isNotEmpty;
    final name = (card?.title.trim().isNotEmpty ?? false)
        ? card!.title.trim()
        : widget.artist;
    final artistId = profile?.artistId;
    final cardCount = (card?.artist ?? '').trim();
    final videoCount = data == null ? '' : l10n.videoCount(data.items.length);
    // 站点只在搜索页的作者卡上给出作者级别的数字，这里与自己的影片数并排显示，
    // 重复时不重复写（作者卡给的常常就是影片数）。
    final stats = [
      if (artistId != null && artistId.isNotEmpty) '@$artistId',
      if (cardCount.isNotEmpty && cardCount != videoCount) cardCount,
      if (videoCount.isNotEmpty) videoCount,
    ].join(' · ');
    return SizedBox(
      height: 156,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (hasAvatar)
            ImageFiltered(
              imageFilter: ImageFilter.blur(
                sigmaX: 30,
                sigmaY: 30,
                tileMode: TileMode.clamp,
              ),
              child: Image(image: appNetworkImage(avatar), fit: BoxFit.cover),
            )
          else
            ColoredBox(color: scheme.surfaceContainerHighest),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                // 只用「透明 → 页面底色」两档，不在调用点自创 surface 不透明度
                // （`test/surface_token_guard_test.dart` 守着这条规则）。
                colors: [Colors.transparent, scheme.surface],
                stops: const [.35, 1],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _avatar(theme, hasAvatar ? avatar : null),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        stats,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          PressScale(
                            child: FilledButton.tonal(
                              onPressed: profile != null && _canSubscribe(profile)
                                  ? () => _toggleSubscription(profile)
                                  : null,
                              child: Text(
                                subscribed ? l10n.subscribed : l10n.subscribe,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          PressScale(
                            child: OutlinedButton.icon(
                              onPressed: () => _share(name),
                              icon: const Icon(Symbols.share_rounded, size: 16),
                              label: Text(l10n.share),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatar(ThemeData theme, String? url) => Container(
    width: 76,
    height: 76,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: theme.colorScheme.surface, width: 3),
      image: url == null
          ? null
          : DecorationImage(image: appNetworkImage(url), fit: BoxFit.cover),
    ),
    child: url != null
        ? null
        : Text(
            widget.artist.isEmpty ? '?' : widget.artist.characters.first,
            style: theme.textTheme.headlineSmall,
          ),
  );

  /// 「主页」页签：最新一排 + 热门一排，各最多 [_sectionLimit] 张。
  Widget _homeTab(ThemeData theme, AppLocalizations l10n) {
    final latest = ref.watch(
      authorVideosProvider((artist: widget.artist, sort: authorSortLatest)),
    );
    final hot = ref.watch(
      authorVideosProvider((artist: widget.artist, sort: authorSortHot)),
    );
    final latestItems = latest.valueOrNull?.items ?? const <VideoCard>[];
    final hotItems = hot.valueOrNull?.items ?? const <VideoCard>[];
    if (latestItems.isEmpty && hotItems.isEmpty) {
      return _stateView(theme, l10n, latest);
    }
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        _section(theme, l10n.latest, latest, latestItems),
        _section(theme, l10n.popular, hot, hotItems),
      ],
    );
  }

  Widget _section(
    ThemeData theme,
    String title,
    AsyncValue<AuthorVideos> async,
    List<VideoCard> items,
  ) {
    final shown = items.take(_sectionLimit).toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        if (shown.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
            child: async.isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Text(
                    '—',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
          )
        else
          _grid(theme, shown, scrollable: false),
      ],
    );
  }

  /// 「影片」页签：页内筛选 + 排序 + 全部影片。
  Widget _videosTab(
    ThemeData theme,
    AppLocalizations l10n,
    AsyncValue<AuthorVideos> async,
    AuthorVideos? data,
    AuthorRequest request,
  ) {
    final keyword = _keyword.trim().toLowerCase();
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _filter,
            onChanged: (value) => setState(() => _keyword = value),
            decoration: InputDecoration(
              isDense: true,
              hintText: l10n.searchHint,
              prefixIcon: const Icon(Symbols.search_rounded, size: 18),
              suffixIcon: _keyword.isEmpty
                  ? null
                  : PressScale(
                      child: IconButton(
                        onPressed: () {
                          _filter.clear();
                          setState(() => _keyword = '');
                        },
                        icon: const Icon(Symbols.close_rounded, size: 18),
                      ),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(22),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          child: Row(
            children: [
              _sortChip(l10n.latest, authorSortLatest),
              const SizedBox(width: 8),
              _sortChip(l10n.popular, authorSortHot),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: async.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, _) => _errorView(theme, l10n, error, request),
            data: (value) {
              final items = keyword.isEmpty
                  ? value.items
                  : value.items
                        .where(
                          (video) =>
                              video.title.toLowerCase().contains(keyword),
                        )
                        .toList(growable: false);
              if (items.isEmpty) {
                return Center(
                  child: Text(
                    l10n.noSearchResults,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                );
              }
              return _grid(theme, items, scrollable: true);
            },
          ),
        ),
        if (keyword.isEmpty && data != null && data.hasMore)
          _moreBar(l10n, request, data),
      ],
    );
  }

  Widget _sortChip(String label, String sort) => PressScale(
    child: ChoiceChip(
      label: Text(label),
      selected: _sort == sort,
      showCheckmark: false,
      onSelected: (_) => setState(() => _sort = sort),
    ),
  );

  /// [scrollable] 为 false 时网格按内容撑高、自己不滚动：主页页签要把两排塞进
  /// 一个 ListView 里（`VideoCardGrid` 是 GridView，不 shrinkWrap 就没法嵌）。
  Widget _grid(ThemeData theme, List<VideoCard> items, {required bool scrollable}) => VideoCardGrid(
    videos: items,
    horizontal: true,
    bottomPadding: scrollable ? 16 : 0,
    shrinkWrap: !scrollable,
    physics: scrollable ? null : const NeverScrollableScrollPhysics(),
    // 作者页的卡片也要带上传日期：列表页不给日期，`autoFetchMeta` 会先读本地
    // 缓存（同步、零请求），缓存没有才去详情页补一次。
    itemBuilder: (context, index, video, horizontal) => VideoCardTile(
      video: video,
      horizontal: horizontal,
      autoFetchMeta: true,
    ),
  );

  Widget _stateView(
    ThemeData theme,
    AppLocalizations l10n,
    AsyncValue<AuthorVideos> async,
  ) => async.when(
    loading: () => const Center(child: CircularProgressIndicator()),
    error: (error, _) =>
        _errorView(theme, l10n, error, (artist: widget.artist, sort: _sort)),
    data: (_) => Center(
      child: Text(
        l10n.noSearchResults,
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    ),
  );

  Widget _errorView(
    ThemeData theme,
    AppLocalizations l10n,
    Object error,
    AuthorRequest request,
  ) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          l10n.loadFailed('$error'),
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium,
        ),
        const SizedBox(height: 12),
        PressScale(
          child: FilledButton.tonal(
            onPressed: () => ref.invalidate(authorVideosProvider(request)),
            child: Text(l10n.retry),
          ),
        ),
      ],
    ),
  );

  /// 「查看更多」：站点是分页的，网格本身不能滚动到底自动续（见 `VideoCardGrid`），
  /// 所以把入口放在页面底部。
  Widget _moreBar(
    AppLocalizations l10n,
    AuthorRequest request,
    AuthorVideos data,
  ) => SafeArea(
    top: false,
    child: Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Center(
        child: PressScale(
          child: FilledButton.tonalIcon(
            onPressed: data.loadingMore
                ? null
                : () =>
                      ref.read(authorVideosProvider(request).notifier).loadMore(),
            icon: data.loadingMore
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Symbols.expand_more_rounded),
            label: Text(l10n.more),
          ),
        ),
      ),
    ),
  );
}
