import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/app_radius.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/library_repository.dart';
import '../../domain/models/video.dart';
import '../../../l10n/app_localizations.dart';
import '../account/account_controller.dart';
import '../library/remote_library_controller.dart';
import '../settings/settings_controller.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import '../../core/app_design_tokens.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import 'author_controller.dart';
import '../shared/app_top_bar.dart';

/// 作者页：头部是作者资料（模糊横幅 / 头像 / 名字 / 数字 / 订阅 + 分享），下面分
/// 「主页」（最新 + 热门各一排）与「影片」（全部影片 + 排序 + 页内筛选）两个页签。
///
/// 为什么要有这一页：以前点作者名是「拿作者名去搜索」——落在一个带分类、排序、
/// 标签的搜索页上，看不出这是谁的页面，而且模糊匹配会混进别人的片子。这里换成
/// 作者自己的页面（用户对着同类客户端的作者空间页提出的要求）。
class AuthorPage extends ConsumerStatefulWidget {
  const AuthorPage({super.key, required this.artist});

  final String artist;

  @override
  ConsumerState<AuthorPage> createState() => _AuthorPageState();
}

class _AuthorPageState extends ConsumerState<AuthorPage> {
  /// 每个分区最多摆几张：作者可能有好几百个片子，首页只做「一眼看个大概」。
  static const _sectionLimit = 10;

  /// 头像边长。
  static const _avatarSize = 76.0;

  /// 页签条自己的左右内边距；资料行的外边距跟它共用同一个值，两处才会在同一条竖线上。
  static const _tabStripInset = 10.0;

  /// 订阅状态的本地乐观值：点下去立刻变，请求失败再翻回来。
  bool? _override;

  /// 当前页签：0 = 主页，1 = 影片。
  int _tab = 0;

  /// 「影片」页签的排序：用户上传页自己的三档键 latest/popular/oldest
  /// （见 `author_controller.dart` 的常量）。
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

  /// 已登录时要有 artistId / token / userId 才能调站点的订阅接口；缺一个就禁用
  /// 按钮。未登录时订阅只记在本地库，但本地库要的是一条影片详情，所以那时仍需
  /// [profile]；artistId 可以来自用户上传页（[pageProfile]）。
  bool _canSubscribe(VideoDetail? profile, String artistId) {
    final account = ref.read(accountProvider).valueOrNull;
    if (account == null) return profile != null;
    return artistId.isNotEmpty &&
        (profile?.csrfToken ?? account.csrfToken) != null &&
        (profile?.subscriptionUserId ?? profile?.currentUserId ?? account.id) !=
            null;
  }

  Future<void> _toggleSubscription(VideoDetail? profile, String artistId) async {
    final account = ref.read(accountProvider).valueOrNull;
    final enabled = !(_override ?? _persisted());
    setState(() => _override = enabled);
    try {
      if (account == null) {
        // 未登录：只记在本地库里，和详情页作者卡一致。
        await ref
            .read(libraryProvider.notifier)
            .setSubscription(profile!, enabled);
        return;
      }
      final settings = await ref.read(settingsProvider.future);
      await ref
          .read(han1meRepositoryProvider)
          .setSubscription(
            settings.resolvedBaseUrl,
            profile?.csrfToken ?? account.csrfToken!,
            profile?.subscriptionUserId ?? profile?.currentUserId ?? account.id!,
            artistId,
            enabled,
          );
      ref.invalidate(remoteLibraryProvider);
    } catch (_) {
      if (mounted) setState(() => _override = !enabled);
    }
  }

  /// 取第一个非空字符串：头像/名字/用户 id 都有多个来源，按优先级挑。
  String? _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final trimmed = value?.trim() ?? '';
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  /// 「分享」：站点真实的关系页地址是 `/user/<id>/uploaded`。
  ///
  /// 解析出用户 id 之后分享这个地址（和同类客户端一样的作者页地址）；没有 id 时
  /// 只能退回「拿作者名去搜」的地址。
  // ignore: unused_element
  Future<void> _share(String name, String artistId) async {
    final settings = await ref.read(settingsProvider.future);
    final url = artistId.isEmpty
        ? Uri.parse(
            settings.resolvedBaseUrl,
          ).replace(path: '/search', queryParameters: {'query': name}).toString()
        : Uri.parse(
            settings.resolvedBaseUrl,
          ).replace(path: '/user/$artistId/uploaded').toString();
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
      appBar: AppTopBar(title: Text(l10n.author)),
      body: Column(
        children: [
          _header(theme, l10n, card, profile, data, subscribed),
          // 设计稿页签：作品 / 系列 / 简介（原来只有「主页 / 影片」两个）。
          Align(
            alignment: Alignment.centerLeft,
            child: UnderlineTabStrip(
              labels: ['作品', '系列', '简介'],
              index: _tab.clamp(0, 2),
              selectedColor: AppDesignTokens.accent,
              onSelected: (index) => setState(() => _tab = index),
              padding: const EdgeInsets.symmetric(horizontal: _tabStripInset),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: _tab == 1
                ? _seriesTab(theme, l10n, data)
                : _tab == 2
                    ? _aboutTab(theme, l10n, profile, data)
                    : _videosTab(theme, l10n, async, data, request),
          ),
        ],
      ),
    );
  }

  /// 头部资料区：头像 + 名字 + 「@id · N 位订阅者 · M 部影片」+ 订阅/分享。
  ///
  /// 这里**不铺横幅**：站点只给一张方形头像，拉成宽横幅只能靠模糊，出来是一片
  /// 没有信息的色块（用户看过之后要求去掉）。资料直接放在页面底色上，反而干净。
  /// 头部资料卡：白底圆角16 + 顶部一条 7% 品牌粉装饰带，内含 76 圆头像、
  /// 21 Bold 名字、副标题、三栏统计（作品/总播放/关注）与右侧「关注」按钮。
  Widget _header(
    ThemeData theme,
    AppLocalizations l10n,
    VideoCard? card,
    VideoDetail? profile,
    AuthorVideos? data,
    bool subscribed,
  ) {
    final pageProfile = data?.profile;
    final avatar = _firstNonEmpty([
      pageProfile?.avatarUrl,
      card?.coverUrl,
      profile?.artistAvatarUrl,
    ]);
    final name = _firstNonEmpty([pageProfile?.name, card?.title, widget.artist]) ?? widget.artist;
    final artistId = _firstNonEmpty([pageProfile?.artistId, profile?.artistId]) ?? '';
    final videoCount = data?.items.length ?? pageProfile?.videoCount ?? 0;
    final subscriberCount = pageProfile?.subscriberCount;
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(color: AppDesignTokens.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
        child: Stack(
          children: [
            // 顶部 56 高的粉色装饰带（设计稿 profileCardDecor）。
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 56,
              child: ColoredBox(color: AppDesignTokens.accent.withValues(alpha: 0.07)),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _avatar(theme, avatar),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
                              const SizedBox(height: 6),
                              Text(
                                '更新频繁 · 共 $videoCount 部作品',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 12, color: AppDesignTokens.inkSubtle),
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _statColumn('$videoCount', '作品'),
                                  const SizedBox(width: 28),
                                  _statColumn(subscriberCount?.toString() ?? '—', '关注'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      // 关注按钮：粉底白字 108×36 圆角18。
                      PressScale(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.lg),
                          onTap: _canSubscribe(profile, artistId) ? () => _toggleSubscription(profile, artistId) : null,
                          child: Container(
                            width: 108,
                            height: 36,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: subscribed ? AppDesignTokens.fieldFill : AppDesignTokens.accentDeep,
                              borderRadius: BorderRadius.circular(AppRadius.lg),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(subscribed ? Symbols.check_rounded : Symbols.favorite_border_rounded, size: 15, color: subscribed ? AppDesignTokens.inkSubtle : Colors.white),
                                const SizedBox(width: 6),
                                Text(subscribed ? l10n.subscribed : l10n.subscribe, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: subscribed ? AppDesignTokens.inkSubtle : Colors.white)),
                              ],
                            ),
                          ),
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
    );
  }

  Widget _statColumn(String number, String label) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(number, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: AppDesignTokens.ink)),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 10.5, color: AppDesignTokens.inkMuted)),
        ],
      );

  Widget _avatar(ThemeData theme, String? url) => Container(
    width: _avatarSize,
    height: _avatarSize,
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      border: Border.all(color: theme.colorScheme.surface, width: 3),
      image: url == null
          ? null
          : DecorationImage(image: appNetworkImage(url), fit: BoxFit.cover),
    ),
    child: url != null
        ? null
        : Text(
            widget.artist.isEmpty ? '?' : widget.artist.characters.first,
            style: theme.textTheme.headlineMedium,
          ),
  );

  /// 「主页」页签：最新一排 + 热门一排，各最多 [_sectionLimit] 张。
  Widget _homeTab(ThemeData theme, AppLocalizations l10n) {
    final latest = ref.watch(
      authorVideosProvider((artist: widget.artist, sort: authorSortLatest)),
    );
    final hot = ref.watch(
      authorVideosProvider((artist: widget.artist, sort: authorSortPopular)),
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
  /// 「系列」页签：作者的作品按系列聚合时，这里展示系列卡片；暂无聚合数据时
  /// 复用「作品」网格（同一个作者卡片列表），避免空白页。
  Widget _seriesTab(ThemeData theme, AppLocalizations l10n, AuthorVideos? data) {
    return _homeTab(theme, l10n);
  }

  /// 「简介」页签：作者资料里的描述文本（拿不到就给一句占位说明）。
  Widget _aboutTab(ThemeData theme, AppLocalizations l10n, VideoDetail? profile, AuthorVideos? data) {
    final bio = profile?.description;
    if (bio == null || bio.trim().isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('这位作者还没有填写简介', style: TextStyle(fontSize: 13, color: AppDesignTokens.inkMuted)),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Text(bio, style: const TextStyle(fontSize: 13, height: 1.7, color: AppDesignTokens.ink)),
    );
  }

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
                        // 只在输入框里画一个叉，没有 tooltip 时鼠标移上去什么都不提示，
                        // 读屏也只会念"按钮"。补上无障碍文案（用的是通用「清除」）。
                        tooltip: l10n.clear,
                        onPressed: () {
                          _filter.clear();
                          setState(() => _keyword = '');
                        },
                        icon: const Icon(Symbols.close_rounded, size: 18),
                      ),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
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
              _sortChip(l10n.popular, authorSortPopular),
              const SizedBox(width: 8),
              _sortChip(l10n.oldest, authorSortOldest),
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
