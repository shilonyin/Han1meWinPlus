import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../../data/local/library_repository.dart';
import '../../core/settings.dart';
import '../settings/settings_controller.dart';
import '../shared/video_card.dart';
import 'explore_controller.dart';

const _maxContentWidth = 1440.0;
const _gridPadding = 16.0;
const _gridSpacing = 10.0;

/// Column count of the home waterfall. Cards end up roughly 240-320 logical
/// pixels wide, which is the density the reference app's poster wall uses.
int homeWaterfallColumns(double width) {
  if (width >= 1500) return 6;
  if (width >= 1180) return 5;
  if (width >= 880) return 4;
  if (width >= 600) return 3;
  return 2;
}

double homeWaterfallCardWidth(double width, int columns) => (width - _gridPadding * 2 - _gridSpacing * (columns - 1)) / columns;

class ExplorePage extends ConsumerWidget {
  const ExplorePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections = ref.watch(homeSectionsProvider);
    final drawerMode = ref.watch(settingsProvider).valueOrNull?.useNavigationDrawer ?? false;
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: AppBar(
        leading: drawerMode && !permanentNavigationDrawer(context) ? IconButton(onPressed: openAppDrawer, icon: const Icon(Icons.menu)) : null,
        actions: [
          IconButton(onPressed: () => context.push('/search', extra: SearchRouteRequest()), icon: const Icon(Icons.search)),
          IconButton(onPressed: () => context.push('/previews/${_currentPreviewMonth()}'), icon: const Icon(Icons.live_tv_outlined)),
          IconButton(tooltip: l10n.mine, onPressed: () => context.push('/mine'), icon: const Icon(Icons.account_circle_outlined)),
        ],
      ),
      body: sections.when(
        skipLoadingOnReload: true,
        skipLoadingOnRefresh: true,
        loading: () => const Center(child: M3EContainedLoadingIndicator()),
        error: (error, _) => _ErrorView(
          error: error,
          onRetry: () => ref.read(homeSectionsProvider.notifier).refresh(),
          onCloudflareVerified: () async {
            final url = error is CloudflareChallengeException ? error.url : null;
            if (await context.push<bool>('/cloudflare', extra: url) == true) {
              await Future<void>.delayed(const Duration(milliseconds: 250));
              await ref.read(homeSectionsProvider.notifier).refresh();
            }
          },
        ),
        data: (feed) => _HomeFeedBody(feed: feed),
      ),
    );
  }
}

class _HomeFeedBody extends ConsumerStatefulWidget {
  const _HomeFeedBody({required this.feed});
  final HomeFeed feed;

  @override
  ConsumerState<_HomeFeedBody> createState() => _HomeFeedBodyState();
}

class _HomeFeedBodyState extends ConsumerState<_HomeFeedBody> {
  var _sectionIndex = 0;

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final subscribed = ref.watch(libraryProvider).valueOrNull?.artists.map((artist) => artist.name.toLowerCase()).toSet() ?? <String>{};
    final sections = widget.feed.sections
        .map((section) => HomeSection(
              title: _localizedSectionTitle(section, catalog, locale),
              videos: section.videos.where((video) => _visible(video, settings, subscribed)).toList(),
              moreUrl: section.moreUrl,
              isFeatured: section.isFeatured,
            ))
        .where((section) => section.videos.isNotEmpty)
        .toList();
    Future<void> refresh() => ref.read(homeSectionsProvider.notifier).refresh();
    if (settings?.useHomeCategoryTabs != true || sections.isEmpty) return M3EPullToRefreshIndicator(onRefresh: refresh, child: _HomeScroll(featured: widget.feed.featured, sections: sections));
    // Categories are picked from a title + chevron menu instead of a tab strip,
    // so only the selected section is built and the grid gets the full height.
    final index = _sectionIndex.clamp(0, sections.length - 1).toInt();
    return Column(children: [
      _CategorySelector(sections: sections, index: index, onSelected: (value) => setState(() => _sectionIndex = value)),
      Expanded(
        child: M3EPullToRefreshIndicator(
          onRefresh: refresh,
          child: _HomeScroll(featured: widget.feed.featured, sections: [sections[index]], showHeader: false),
        ),
      ),
    ]);
  }
}

/// Collapsed category picker: the current section name plus a chevron that
/// opens the full list, mirroring the reference app's header.
class _CategorySelector extends StatefulWidget {
  const _CategorySelector({required this.sections, required this.index, required this.onSelected});

  final List<HomeSection> sections;
  final int index;
  final ValueChanged<int> onSelected;

  @override
  State<_CategorySelector> createState() => _CategorySelectorState();
}

class _CategorySelectorState extends State<_CategorySelector> {
  final _controller = MenuController();

  @override
  Widget build(BuildContext context) {
    final section = widget.sections[widget.index];
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 2),
      child: Row(
        children: [
          MenuAnchor(
            controller: _controller,
            alignmentOffset: const Offset(0, 6),
            menuChildren: [
              for (var index = 0; index < widget.sections.length; index++)
                MenuItemButton(
                  onPressed: () {
                    _controller.close();
                    if (index != widget.index) widget.onSelected(index);
                  },
                  leadingIcon: Icon(index == widget.index ? Icons.check : Icons.label_outline, size: 18),
                  child: Text(widget.sections[index].title),
                ),
            ],
            builder: (context, controller, child) => InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: () => controller.isOpen ? controller.close() : controller.open(),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(section.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(width: 4),
                    const Icon(Icons.keyboard_arrow_down),
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

String _localizedSectionTitle(HomeSection section, SearchOptionCatalog? catalog, String locale) {
  if (catalog == null) return section.title;
  final uri = Uri.tryParse(section.moreUrl ?? '');
  final genre = uri?.queryParameters['genre'];
  final sort = uri?.queryParameters['sort'];
  return (genre == null ? null : catalog.genres.localize(genre, locale)) ??
      (sort == null ? null : catalog.sorts.localize(sort, locale)) ??
      catalog.genres.localize(section.title, locale) ??
      catalog.sorts.localize(section.title, locale) ??
      section.title;
}

/// Home rows are pre-filtered, and the pages loaded while scrolling have to go
/// through the same recommendation filters.
bool _visible(VideoCard video, AppSettings? settings, Set<String> subscribed) {
  if (settings == null) return true;
  final subscribedAuthor = video.artist != null && subscribed.contains(video.artist!.toLowerCase());
  if (!(settings.exemptSubscribedAuthors && subscribedAuthor)) {
    if (settings.blockedVideoTitleKeywords.any((keyword) => video.title.toLowerCase().contains(keyword.toLowerCase()))) return false;
    if (settings.blockedAuthors.any((author) => (video.artist ?? '').toLowerCase().contains(author.toLowerCase()))) return false;
    if (_durationSeconds(video.duration) < settings.minimumVideoDurationSeconds || _viewsCount(video.views) < settings.minimumVideoViews) return false;
  }
  return true;
}

int _durationSeconds(String? text) => (text?.split(':').map(int.tryParse).toList() ?? const <int?>[]).fold<int>(0, (total, unit) => unit == null ? total : total * 60 + unit);
int _viewsCount(String? text) => int.tryParse(RegExp(r'[\d,.]+').firstMatch(text ?? '')?.group(0)?.replaceAll(',', '') ?? '') ?? 0;

class _HomeScroll extends StatelessWidget {
  const _HomeScroll({this.featured, required this.sections, this.showHeader = true});
  final VideoCard? featured;
  final List<HomeSection> sections;
  final bool showHeader;

  @override
  Widget build(BuildContext context) => CustomScrollView(physics: const AlwaysScrollableScrollPhysics(), cacheExtent: 720, slivers: [
    if (featured != null) SliverToBoxAdapter(child: RepaintBoundary(child: _MaxWidth(child: _FeaturedVideo(video: featured!)))),
    for (final section in sections) _HomeSection(section: section, showHeader: showHeader),
    SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
  ]);
}

class _HomeSection extends ConsumerStatefulWidget {
  const _HomeSection({required this.section, this.showHeader = true});

  final HomeSection section;
  final bool showHeader;

  @override
  ConsumerState<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends ConsumerState<_HomeSection> {
  String _prefetchKey = '';
  late List<VideoCard> _videos = widget.section.videos;
  var _page = 1;
  int? _totalPages;
  var _loading = false;

  /// Unknown until the first extra page comes back, so the first probe always
  /// gets a chance to ask for it.
  bool get _hasMore => widget.section.moreUrl != null && (_totalPages == null || _page < _totalPages!);

  @override
  void didUpdateWidget(_HomeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilds the section objects on every build, so identity is
    // taken from the "more" link and the first card instead of the object.
    final changed = oldWidget.section.moreUrl != widget.section.moreUrl || oldWidget.section.videos.firstOrNull?.id != widget.section.videos.firstOrNull?.id;
    if (changed) {
      _videos = widget.section.videos;
      _page = 1;
      _totalPages = null;
      _schedulePrefetch();
    }
  }

  void _schedulePrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_prefetch());
    });
  }

  double get _viewportWidth => MediaQuery.sizeOf(context).width.clamp(0.0, _maxContentWidth).toDouble();

  /// The home page only ships the first page of each row, so the rest is pulled
  /// from the same search the row's "more" link points at.
  Future<void> _loadMore() async {
    final moreUrl = widget.section.moreUrl;
    if (_loading || !_hasMore || moreUrl == null) return;
    _loading = true;
    try {
      final settings = await ref.read(settingsProvider.future);
      final query = SearchQuery.fromUri(moreUrl);
      final result = await ref.read(han1meRepositoryProvider).search(
            baseUrl: settings.homeBaseUrl,
            query: query.text,
            genre: query.genre,
            sort: query.sort,
            date: query.date,
            duration: query.duration,
            tags: query.tags,
            broad: query.broad,
            type: query.type,
            page: _page + 1,
          );
      if (!mounted) return;
      final subscribed = ref.read(libraryProvider).valueOrNull?.artists.map((artist) => artist.name.toLowerCase()).toSet() ?? <String>{};
      final current = ref.read(settingsProvider).valueOrNull;
      final known = _videos.map((video) => video.id).toSet();
      final extra = result.items.where((video) => !known.contains(video.id) && _visible(video, current, subscribed)).toList();
      debugPrint('[home] ${widget.section.title}: page ${result.page}/${result.totalPages}, +${extra.length}');
      setState(() {
        _videos = [..._videos, ...extra];
        _page = result.page;
        _totalPages = result.totalPages;
      });
    } catch (error) {
      debugPrint('[home] load more failed: $error');
    } finally {
      _loading = false;
    }
  }

  Future<void> _prefetch() async {
    if (!mounted) return;
    final context = this.context;
    final width = _viewportWidth;
    final columns = homeWaterfallColumns(width);
    final cacheWidth = videoCardCacheWidth(homeWaterfallCardWidth(width, columns), MediaQuery.devicePixelRatioOf(context));
    for (final video in _videos.take(columns * 2)) {
      if (video.coverUrl.isNotEmpty) {
        unawaited(precacheImage(CachedNetworkImageProvider(video.coverUrl, maxWidth: cacheWidth), context).catchError((_) {}));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = _viewportWidth;
    final columns = homeWaterfallColumns(width);
    final prefetchKey = '${_videos.length}-$columns';
    if (prefetchKey != _prefetchKey) {
      _prefetchKey = prefetchKey;
      _schedulePrefetch();
    }
    final hasMore = _hasMore;
    return SliverMainAxisGroup(
      slivers: [
        if (widget.showHeader) SliverToBoxAdapter(child: _MaxWidth(child: _SectionHeader(section: widget.section))),
        SliverConstrainedCrossAxis(
          maxExtent: _maxContentWidth,
          sliver: SliverPadding(
            padding: const EdgeInsets.fromLTRB(_gridPadding, 0, _gridPadding, 20),
            sliver: SliverMasonryGrid.count(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: _gridSpacing,
              childCount: _videos.length,
              itemBuilder: (context, index) => index == _videos.length - 1 && hasMore
                  ? _LoadMoreProbe(onProbe: _loadMore, child: VideoCardTile(video: _videos[index], horizontal: true))
                  : VideoCardTile(video: _videos[index], horizontal: true),
            ),
          ),
        ),
        if (hasMore && _loading)
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(bottom: 24),
              child: Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))),
            ),
          ),
      ],
    );
  }
}

/// Sits on the last card of a row and asks for the next page once it is built,
/// which happens as soon as the end of the row scrolls into the cache area.
class _LoadMoreProbe extends StatefulWidget {
  const _LoadMoreProbe({required this.onProbe, required this.child});

  final Future<void> Function() onProbe;
  final Widget child;

  @override
  State<_LoadMoreProbe> createState() => _LoadMoreProbeState();
}

class _LoadMoreProbeState extends State<_LoadMoreProbe> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.onProbe());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class _MaxWidth extends StatelessWidget {
  const _MaxWidth({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: _maxContentWidth), child: child),
      );
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.section});

  final HomeSection section;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        child: Text(section.title, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
      );
}

String _currentPreviewMonth() {
  final now = DateTime.now();
  return '${now.year}${now.month.toString().padLeft(2, '0')}';
}

class _FeaturedVideo extends StatelessWidget {
  const _FeaturedVideo({required this.video});
  final VideoCard video;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final desktop = constraints.maxWidth >= 700;
          return Padding(
            padding: EdgeInsets.fromLTRB(desktop ? 24 : 16, 4, desktop ? 24 : 16, 16),
            child: desktop
                ? SizedBox(
                    width: double.infinity,
                    height: 320,
                    child: _FeaturedVideoSurface(video: video),
                  )
                : AspectRatio(
                    aspectRatio: 16 / 8,
                    child: _FeaturedVideoSurface(video: video),
                  ),
          );
        },
      );
}

class _FeaturedVideoSurface extends StatelessWidget {
  const _FeaturedVideoSurface({required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context) => Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: video.id.isEmpty ? null : () => context.push('/video/${video.id}'),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: video.coverUrl,
                fit: BoxFit.cover,
                memCacheWidth: 960,
                fadeInDuration: Duration.zero,
                errorWidget: (_, __, ___) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
              ),
              DecoratedBox(
                decoration: const BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, Colors.black87])),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(AppLocalizations.of(context)!.featured, style: Theme.of(context).textTheme.labelLarge?.copyWith(color: Colors.white70)),
                    const SizedBox(height: 4),
                    Text(video.title, maxLines: 2, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                    if (video.artist != null) Text(video.artist!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white70)),
                  ]),
                ),
              ),
            ],
          ),
        ),
      );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.error, required this.onRetry, required this.onCloudflareVerified});
  final Object error;
  final VoidCallback onRetry;
  final Future<void> Function() onCloudflareVerified;
  @override
  Widget build(BuildContext context) => Center(child: Padding(
    padding: const EdgeInsets.all(24),
    child: Column(mainAxisSize: MainAxisSize.min, children: [Text('$error', textAlign: TextAlign.center), const SizedBox(height: 12), FilledButton(onPressed: onRetry, child: Text(AppLocalizations.of(context)!.retry)), if ('$error'.contains('Cloudflare')) TextButton(onPressed: onCloudflareVerified, child: Text(AppLocalizations.of(context)!.completeCloudflareVerification))]),
  ));
}
