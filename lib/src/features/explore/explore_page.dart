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
import '../search/search_suggestions.dart';
import '../shared/underline_tab_strip.dart';
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

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  var _sectionIndex = 0;
  var _searchPanelOpen = false;
  var _searchFocused = false;
  final _searchController = TextEditingController();
  final _searchFocus = FocusNode();
  final _searchFieldKey = GlobalKey();
  final _topBarKey = GlobalKey();
  final _bodyStackKey = GlobalKey();

  @override
  void initState() {
    super.initState();
    _searchFocus.addListener(_onSearchFocusChange);
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onSearchFocusChange);
    _searchController.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// 输入框失焦（例如点了侧栏或快捷键）时也收起搜索态。
  void _onSearchFocusChange() {
    if (_searchFocus.hasFocus || !_searchFocused) return;
    setState(() {
      _searchFocused = false;
      _searchPanelOpen = false;
    });
  }

  /// 点搜索框：左侧的分类与快捷页签淡出，输入框滑到中间变宽，同时铺开建议面板。
  void _openSearch() {
    setState(() {
      _searchFocused = true;
      _searchPanelOpen = true;
    });
    _searchFocus.requestFocus();
  }

  void _closeSearch() {
    _searchFocus.unfocus();
    setState(() {
      _searchFocused = false;
      _searchPanelOpen = false;
    });
  }

  void _submitSearch(String value) {
    final text = value.trim();
    _searchController.text = text;
    _closeSearch();
    context.push('/search', extra: SearchRouteRequest(initialQuery: SearchQuery(text: text)));
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(homeSectionsProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final drawerMode = settings?.useNavigationDrawer ?? false;
    final l10n = AppLocalizations.of(context)!;
    final tabs = settings?.useHomeCategoryTabs == true;
    final categories = feed.valueOrNull == null ? const <_FeedCategory>[] : _feedCategories(feed.value!);
    final sections = [for (final category in categories) category.section];
    final index = sections.isEmpty ? 0 : _sectionIndex.clamp(0, sections.length - 1).toInt();
    final showPicker = tabs && sections.isNotEmpty;
    // 顶栏右侧的快捷分类（在「界面布局 → 首页快捷分类」里自定义内容与排序）。
    final quick = tabs ? _quickCategories(categories, settings?.homeQuickCategories ?? const <String>[]) : const <({int index, String label})>[];
    // 已经作为快捷分类显示在右侧的分类，不再重复出现在左侧下拉菜单里。
    final quickIndexes = <int>{for (final item in quick) item.index};
    final pickerIndexes = <int>[for (var i = 0; i < sections.length; i++) if (!quickIndexes.contains(i)) i];
    final screenWidth = MediaQuery.sizeOf(context).width;
    final idleSearchWidth = screenWidth >= 1180 ? 260.0 : (screenWidth >= 940 ? 180.0 : 132.0);
    final showDrawerButton = drawerMode && !permanentNavigationDrawer(context);
    return Scaffold(
      // 顶栏自己画在 body 的 Stack 里（不用 Scaffold.appBar）：这样搜索框与下方的建议面板
      // 处在同一个坐标系里，面板能跟搜索框严格对齐。
      body: Stack(
        key: _bodyStackKey,
        children: [
          Column(
            children: [
              Material(
                color: Theme.of(context).appBarTheme.backgroundColor ?? Theme.of(context).colorScheme.surface,
                child: SizedBox(
                  height: 56,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        if (showDrawerButton) SizedBox(width: 52, child: IconButton(onPressed: openAppDrawer, icon: const Icon(Icons.menu))),
                        Expanded(
                          child: Stack(
                            key: _topBarKey,
                            children: [
                    // 左侧标题（分类下拉 + 快捷分类）：聚焦搜索时淡出并让位。
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      right: idleSearchWidth + 8 + 100,
                      child: IgnorePointer(
                        ignoring: _searchFocused,
                        child: AnimatedOpacity(
                          duration: const Duration(milliseconds: 160),
                          opacity: _searchFocused ? 0 : 1,
                          child: showPicker
                              ? Row(
                                  children: [
                                    if (pickerIndexes.isNotEmpty) _CategorySelector(sections: sections, indexes: pickerIndexes, index: index, onSelected: (value) => setState(() => _sectionIndex = value)),
                                    if (pickerIndexes.isNotEmpty && quick.isNotEmpty) ...[
                                      const SizedBox(width: 8),
                                      const SizedBox(height: 22, child: VerticalDivider(width: 1)),
                                      const SizedBox(width: 8),
                                    ],
                                    if (quick.isNotEmpty)
                                      Expanded(
                                        child: UnderlineTabStrip(
                                          labels: [for (final item in quick) item.label],
                                          index: quick.indexWhere((item) => item.index == index),
                                          onSelected: (value) => setState(() => _sectionIndex = quick[value].index),
                                        ),
                                      ),
                                  ],
                                )
                              : null,
                        ),
                      ),
                    ),
                    // 搜索框 + 右侧图标：平时贴右边，聚焦后搜索框滑到中间并变宽。
                    AnimatedAlign(
                      duration: const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      alignment: _searchFocused ? Alignment.center : Alignment.centerRight,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TweenAnimationBuilder<double>(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            tween: Tween<double>(begin: idleSearchWidth, end: _searchFocused ? 520 : idleSearchWidth),
                            builder: (context, width, child) => SizedBox(key: _searchFieldKey, width: width, height: 56, child: child),
                            child: _HomeSearchField(
                              controller: _searchController,
                              focusNode: _searchFocus,
                              focused: _searchFocused,
                              onTap: _openSearch,
                              onSubmitted: _submitSearch,
                              onClear: () {
                                _searchController.clear();
                                _closeSearch();
                              },
                            ),
                          ),
                          // 聚焦时右侧图标淡出并收窄为 0，搜索框才能真正落在正中间。
                          AnimatedSize(
                            duration: const Duration(milliseconds: 220),
                            curve: Curves.easeOutCubic,
                            alignment: Alignment.centerRight,
                            child: AnimatedOpacity(
                              duration: const Duration(milliseconds: 160),
                              opacity: _searchFocused ? 0 : 1,
                              child: IgnorePointer(
                                ignoring: _searchFocused,
                                child: SizedBox(
                                  width: _searchFocused ? 0 : null,
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(onPressed: () => context.push('/previews/${_currentPreviewMonth()}'), icon: const Icon(Icons.live_tv_outlined)),
                                      IconButton(tooltip: l10n.mine, onPressed: () => context.push('/mine'), icon: const Icon(Icons.account_circle_outlined)),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    Expanded(
      child: feed.when(
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
        data: (value) => _HomeFeedBody(featured: value.featured, sections: sections, index: index, single: showPicker),
      ),
    ),
  ],
),
          // 点搜索框展开的建议面板：底部铺一层透明遮罩，点它或点一条建议都会收起。
          IgnorePointer(
            ignoring: !_searchPanelOpen,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 170),
              opacity: _searchPanelOpen ? 1 : 0,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _closeSearch,
                child: const SizedBox.expand(),
              ),
            ),
          ),
          _buildSearchPanel(context),
        ],
      ),
    );
  }

  /// 建议面板按搜索框的实际位置摆放（宽度、水平位置都与搜索框一致），
  /// 这样不管左侧是否有侧栏、窗口多宽，面板都和上方的搜索框对齐。
  Widget _buildSearchPanel(BuildContext context) {
    final barBox = _topBarKey.currentContext?.findRenderObject() as RenderBox?;
    final stackBox = _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    // 搜索框是顶栏内居中的，顶栏宽度在动画期间不变，所以用顶栏几何来定位面板最稳。
    var width = (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 520.0);
    var left = 0.0;
    if (barBox != null && barBox.hasSize && stackBox != null && stackBox.hasSize) {
      width = width.clamp(240.0, barBox.size.width);
      final barLeft = barBox.localToGlobal(Offset.zero).dx;
      final stackLeft = stackBox.localToGlobal(Offset.zero).dx;
      left = (barLeft - stackLeft + (barBox.size.width - width) / 2).clamp(0.0, (stackBox.size.width - width).clamp(0.0, double.infinity));
    }
    return Positioned(
      left: left,
      top: 62,
      width: width,
      child: IgnorePointer(
        ignoring: !_searchPanelOpen,
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          offset: _searchPanelOpen ? Offset.zero : const Offset(0, -0.03),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 170),
            opacity: _searchPanelOpen ? 1 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [BoxShadow(color: Color(0x55000000), blurRadius: 20, offset: Offset(0, 8))],
              ),
              child: SearchSuggestions(
                width: width,
                onSelected: (query) {
                  _closeSearch();
                  context.push('/search', extra: SearchRouteRequest(initialQuery: query));
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<_FeedCategory> _feedCategories(HomeFeed feed) {
    final settings = ref.watch(settingsProvider).valueOrNull;
    final catalog = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final subscribed = ref.watch(libraryProvider).valueOrNull?.artists.map((artist) => artist.name.toLowerCase()).toSet() ?? <String>{};
    return feed.sections
        .map((section) => _FeedCategory(
              rawTitle: section.title,
              section: HomeSection(
                title: localizedHomeSectionTitle(section, catalog, locale),
                videos: section.videos.where((video) => _visible(video, settings, subscribed)).toList(),
                moreUrl: section.moreUrl,
                isFeatured: section.isFeatured,
              ),
            ))
        .where((category) => category.section.videos.isNotEmpty)
        .toList();
  }

  /// 顶栏快捷分类：优先按设置里保存的顺序（存的是站点原始分类名），未设置时取前 6 个。
  List<({int index, String label})> _quickCategories(List<_FeedCategory> categories, List<String> configured) {
    if (categories.isEmpty) return const [];
    if (configured.isEmpty) {
      return [for (var i = 0; i < categories.length && i < 6; i++) (index: i, label: categories[i].section.title)];
    }
    final result = <({int index, String label})>[];
    for (final raw in configured) {
      final index = categories.indexWhere((category) => category.rawTitle == raw);
      if (index >= 0 && !result.any((item) => item.index == index)) result.add((index: index, label: categories[index].section.title));
    }
    return result;
  }
}

/// 首页分类：`rawTitle` 是站点原始名（用于持久化与本地化查找），`section` 是本地化后的展示数据。
class _FeedCategory {
  const _FeedCategory({required this.rawTitle, required this.section});

  final String rawTitle;
  final HomeSection section;
}

class _HomeFeedBody extends ConsumerWidget {
  const _HomeFeedBody({required this.featured, required this.sections, required this.index, required this.single});

  final VideoCard? featured;
  final List<HomeSection> sections;
  final int index;

  /// Category tabs are off: every section is stacked with its own header.
  final bool single;

  @override
  Widget build(BuildContext context, WidgetRef ref) => M3EPullToRefreshIndicator(
        onRefresh: () => ref.read(homeSectionsProvider.notifier).refresh(),
        child: _HomeScroll(
          featured: featured,
          sections: single && sections.isNotEmpty ? [sections[index]] : sections,
          showHeader: !single,
        ),
      );
}

/// 顶栏里的搜索框：点击后左侧的分类与快捷页签淡出、它自己滑到中间变宽，回车直接进搜索页。
class _HomeSearchField extends StatelessWidget {
  const _HomeSearchField({required this.controller, required this.focusNode, required this.focused, required this.onTap, required this.onSubmitted, required this.onClear});

  final TextEditingController controller;
  final FocusNode focusNode;
  final bool focused;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final border = OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide.none);
    return Align(
      alignment: Alignment.center,
      child: SizedBox(
        height: 36,
        width: double.infinity,
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onTap: onTap,
          onSubmitted: onSubmitted,
          style: theme.textTheme.bodySmall,
          decoration: InputDecoration(
            hintText: l10n.searchHint,
            isDense: true,
            filled: true,
            fillColor: focused ? theme.colorScheme.surfaceContainerHigh : theme.colorScheme.surfaceContainerHighest,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14),
            border: border,
            enabledBorder: border,
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(17), borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: .7))),
            suffixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : IconButton(visualDensity: VisualDensity.compact, iconSize: 16, onPressed: onClear, icon: const Icon(Icons.close)),
                ),
                IconButton(visualDensity: VisualDensity.compact, iconSize: 18, onPressed: () => onSubmitted(controller.text), icon: const Icon(Icons.search)),
                const SizedBox(width: 4),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Collapsed category picker: the current section name plus a chevron that
/// opens the full list, mirroring the reference app's header.
class _CategorySelector extends StatefulWidget {
  const _CategorySelector({required this.sections, required this.indexes, required this.index, required this.onSelected});

  final List<HomeSection> sections;

  /// 下拉菜单里可选的分类下标（已作为快捷分类显示在右侧的会被排除）。
  final List<int> indexes;
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
    return MenuAnchor(
      controller: _controller,
      alignmentOffset: const Offset(0, 6),
      menuChildren: [
        for (final index in widget.indexes)
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
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
    );
  }
}

/// 把站点的分类名换成当前语言下的名字（找不到就用原名）。首页顶栏与「首页快捷分类」
/// 设置页都用它，保证两处显示一致。
String localizedHomeSectionTitle(HomeSection section, SearchOptionCatalog? catalog, String locale) {
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
