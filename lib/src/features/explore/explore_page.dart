import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import '../../../l10n/app_localizations.dart';
import '../../core/app_shell.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/video_meta_cache.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../../domain/video_metrics.dart';
import '../../data/local/library_repository.dart';
import '../../core/settings.dart';
import '../settings/settings_controller.dart';
import '../search/search_suggestions.dart';
import '../shared/app_image_cache.dart';
import '../shared/scroll_actions.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import '../video/play_window.dart';
import 'explore_controller.dart';

const _gridPadding = 16.0;
const _gridSpacing = 10.0;

/// 瀑布流卡片的目樇宽度（逻辑像素）。窗口变化时靠它反推列数，
/// 使卡片密度保持在可读的范围内，同时把宽度用满。
const _targetCardWidth = 260.0;

/// 预热一张封面：图片站点偶发 SSL 握手中断，失败时重试一次。
Future<void> precacheCover(String url, int cacheWidth, BuildContext context) async {
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await precacheImage(CachedNetworkImageProvider(url, maxWidth: cacheWidth, cacheManager: appImageCacheManager), context);
      return;
    } catch (_) {
      // 握手/传输失败时重试一次
    }
  }
}

/// Column count of the home waterfall. Cards end up roughly 240-320 logical
/// pixels wide, which is the density the reference app's poster wall uses.
///
/// 列数由窗口宽度反推，宽屏（比如把窗口放到最大）会自动加列把宽度用满，
/// 不再像以前那样在右侧留出一大片空白。
int homeWaterfallColumns(double width) {
  if (width <= 0) return 2;
  final usable = width - _gridPadding * 2;
  final fitting = ((usable + _gridSpacing) / (_targetCardWidth + _gridSpacing)).round();
  return fitting.clamp(2, 16);
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
    final url = Uri(path: '/search', queryParameters: {'query': text}).toString();
    context.push(url, extra: SearchRouteRequest(initialUrl: url));
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(homeSectionsProvider);
    final settings = ref.watch(settingsProvider).valueOrNull;
    final drawerMode = settings?.useNavigationDrawer ?? false;
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
    // 顶栏右侧不再放图标（直播/我的都在侧栏里有入口），把空间让给搜索框。
    final idleSearchWidth = screenWidth >= 1180 ? 380.0 : (screenWidth >= 940 ? 280.0 : 172.0);
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
                    padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
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
                      right: idleSearchWidth + 8,
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
                maxHeight: (MediaQuery.sizeOf(context).height - 100).clamp(240.0, 640.0),
                onSelected: (query) {
                  _closeSearch();
                  final url = query.toUri().toString();
                  context.push(url, extra: SearchRouteRequest(initialUrl: url));
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
    final categories = feed.sections
        .map((section) => _FeedCategory(
              rawTitle: section.title,
              section: HomeSection(
                title: localizedHomeSectionTitle(section, catalog, locale, l10n: AppLocalizations.of(context)),
                videos: section.videos.where((video) => _visible(video, settings, subscribed)).toList(),
                moreUrl: section.moreUrl,
                isFeatured: section.isFeatured,
              ),
            ))
        .toList();
    // AV 源的分区是**按需加载**的：只有第一个分区自带内容，其余的页签要保留下来
    // （被选中时才去抓第一页）。hanime1 那边空分区没有意义，照旧过滤掉。
    if (javSiteFor(settings?.homeBaseUrl) != null) return categories;
    return categories.where((category) => category.section.videos.isNotEmpty).toList();
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
///
/// AV 视频源（missav 等）的分区名是我们自己定的，存成 `jav:new` 这样的文案键，
/// 所以先查这一张表；hanime1 的分类名才需要去 catalog 里翻。
String localizedHomeSectionTitle(HomeSection section, SearchOptionCatalog? catalog, String locale, {AppLocalizations? l10n}) {
  final javLabel = _javSectionTitle(l10n, javSectionKey(section.title));
  if (javLabel != null) return javLabel;
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

String? _javSectionTitle(AppLocalizations? l10n, String? key) => switch (key) {
      'new' => l10n?.javNew,
      'latest' => l10n?.latest,
      'uncensored' => l10n?.javUncensored,
      'subtitles' => l10n?.javSubtitles,
      'hot' => l10n?.javHot,
      'popular' => l10n?.popular,
      'topRated' => l10n?.javTopRated,
      'byCategory' => l10n?.javByCategory,
      'amateur' => l10n?.javAmateur,
      _ => null,
    };

/// Home rows are pre-filtered, and the pages loaded while scrolling have to go
/// through the same recommendation filters.
bool _visible(VideoCard video, AppSettings? settings, Set<String> subscribed) {
  if (settings == null) return true;
  final subscribedAuthor = video.artist != null && subscribed.contains(video.artist!.toLowerCase());
  if (!(settings.exemptSubscribedAuthors && subscribedAuthor)) {
    if (settings.blockedVideoTitleKeywords.any((keyword) => video.title.toLowerCase().contains(keyword.toLowerCase()))) return false;
    if (settings.blockedAuthors.any((author) => (video.artist ?? '').toLowerCase().contains(author.toLowerCase()))) return false;
    if (settings.blockedVideoTags.any((blockedTag) => video.tags.any((tag) => tag.toLowerCase().contains(blockedTag.toLowerCase())))) return false;
    // 站点没给时长/播放量时按「未知」处理，不参与过滤：按 0 判会把 AV 源的卡片整页
    // 滤光（它们本来就不带这些字段），表现是「搜索结果永远为空」。
    final seconds = videoDurationSeconds(video.duration);
    if (seconds != null && seconds < settings.minimumVideoDurationSeconds) return false;
    final views = videoViews(video.views);
    if (views != null && views < settings.minimumVideoViews) return false;
  }
  return true;
}

class _HomeScroll extends ConsumerStatefulWidget {
  const _HomeScroll({this.featured, required this.sections, this.showHeader = true});
  final VideoCard? featured;
  final List<HomeSection> sections;
  final bool showHeader;

  @override
  ConsumerState<_HomeScroll> createState() => _HomeScrollState();
}

class _HomeScrollState extends ConsumerState<_HomeScroll> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _prefetchFeatured();
  }

  @override
  void didUpdateWidget(_HomeScroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.featured?.coverUrl != widget.featured?.coverUrl) _prefetchFeatured();
  }

  /// 首屏推荐位是一张大图（`memCacheWidth: 960`），不预热的话刷新后第一眼就是一个大灰块。
  void _prefetchFeatured() {
    final url = widget.featured?.coverUrl;
    if (url == null || url.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(precacheCover(url, 960, context));
    });
  }

  /// 右下角刷新：重新拉首页数据（各行的分页状态会通过 homeRefreshTokenProvider 重置），
  /// 并滚回顶部，让刷新结果立刻可见。
  Future<void> _refreshAll() async {
    await ref.read(homeSectionsProvider.notifier).refresh();
    if (!mounted || !_controller.hasClients) return;
    _controller.jumpTo(0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Stack(
        children: [
          CustomScrollView(
            controller: _controller,
            physics: const AlwaysScrollableScrollPhysics(),
            scrollCacheExtent: const ScrollCacheExtent.pixels(1200),
            slivers: [
              if (widget.featured != null) SliverToBoxAdapter(child: RepaintBoundary(child: _FeaturedVideo(video: widget.featured!))),
              for (final section in widget.sections) _HomeSection(section: section, showHeader: widget.showHeader),
              SliverToBoxAdapter(child: SizedBox(height: MediaQuery.paddingOf(context).bottom)),
            ],
          ),
          Positioned(right: 0, bottom: 0, child: ScrollActions(controller: _controller, onRefresh: _refreshAll)),
        ],
      );
}

/// 切分区会重建对应的 `_HomeSection`（第一页来自带缓存的 feed），但滚动累积的分页
/// 会随 State 一起消失，切回来就得逐页重新加载。这里按「更多链接」把分页记在进程内。
final _sectionPageCache = <String, ({List<VideoCard> videos, int page, int? totalPages})>{};

class _HomeSection extends ConsumerStatefulWidget {
  const _HomeSection({required this.section, this.showHeader = true});

  final HomeSection section;
  final bool showHeader;

  @override
  ConsumerState<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends ConsumerState<_HomeSection> {
  late List<VideoCard> _videos = widget.section.videos;
  var _page = 1;
  int? _totalPages;
  var _loading = false;
  var _failed = false;
  var _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  var _retryDelay = Duration.zero;

  /// 每次「换分区 / 刷新」都会自增。切分区时这个 State 是被复用的，而上一分区的分页
  /// 请求还在飞 —— 不作废它的话，它回来会 setState 把旧分区的数据追加进新分区（表现为
  /// 「切分区后有概率混进别的分区的影片」），而且随后还会以新分区的 key 写进分页缓存，
  /// 把污染固化下来（切换几次都还在）。
  var _generation = 0;

  /// 上一次重接分页时所在的站点，用来识别 [didUpdateWidget] 里的「换了站点」。
  String? _siteKey;

  /// Unknown until the first extra page comes back, so the first probe always
  /// gets a chance to ask for it.
  bool get _hasMore => widget.section.moreUrl != null && (_totalPages == null || _page < _totalPages!);

  @override
  void initState() {
    super.initState();
    _restorePages();
    // 右下角刷新与下拉刷新都会自增这个令牌：丢掉滚动时累积的分页，从第一页重新开始。
    ref.listenManual(homeRefreshTokenProvider, (previous, next) => _reloadFromFirstPage());
    // 惰性分区（AV 源只有第一个分区带内容）被选中时才会走到这里，这时补抓第一页。
    unawaited(_loadFirstPageIfNeeded());
    _schedulePrefetch();
  }

  @override
  void didUpdateWidget(_HomeSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The parent rebuilds the section objects on every build, so identity is
    // taken from the "more" link and the first card instead of the object.
    // 站点变化也要按「换了分区」处理：两个站的分区有可能同名且 moreUrl 相同（例如都叫
    // `/newest`），只比对 moreUrl 与首卡片 id 会漏掉这种情况。
    final siteChanged = _siteKey != null && _siteKey != _site;
    final changed = siteChanged || oldWidget.section.moreUrl != widget.section.moreUrl || oldWidget.section.videos.firstOrNull?.id != widget.section.videos.firstOrNull?.id;
    // 切到另一个分区：接上它之前滚动加载过的分页（没有就从第一页开始），
    // 不要把数据丢掉，否则切回来又要逐页重新加载。
    if (changed) {
      _restorePages();
      // 惰性分区（AV 源只有第一个分区带内容，其余是占位）就是在这里被选中的：
      // 换成它以后必须补抓第一页，否则永远空白（initState 只对最开始那个分区生效）。
      unawaited(_loadFirstPageIfNeeded());
      _schedulePrefetch();
    }
  }

  /// 当前站点（`homeBaseUrl` 已含镜像与漫画模式的解析结果）。
  String get _site => ref.read(settingsProvider).valueOrNull?.homeBaseUrl ?? '';

  /// 分页缓存的 key **必须带上站点**：不同站点的 moreUrl 可能撞车（例如都叫
  /// `/search?genre=xxx`），只按 moreUrl 缓存的话，切换站点后新站点的分区会读到上一个
  /// 站点滚动加载过的分页 —— 表现就是「换站后首页某些分区混进另一个站点的影片」。
  /// 带上站点后各站的分页天然隔离，切回来也还能接上原来的进度。
  String get _cacheKey => '$_site|${widget.section.moreUrl ?? widget.section.title}';

  /// 接上本分区之前加载过的分页；没有缓存时回到「只有第一页」的状态。
  void _restorePages() {
    // 作废上一分区还在飞的请求，并把它的 loading 占用放掉 —— 否则新分区的补抓
    // （[_loadFirstPageIfNeeded] 里的 `_loading` 判断）会被这个旧占用挡掉。
    _generation++;
    _loading = false;
    _siteKey = _site;
    final cached = _sectionPageCache[_cacheKey];
    if (cached == null) {
      _videos = widget.section.videos;
      _page = 1;
      _totalPages = null;
      _failed = false;
      _retryDelay = Duration.zero;
      _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
      return;
    }
    _videos = cached.videos;
    _page = cached.page;
    _totalPages = cached.totalPages;
  }

  /// 回到「只有第一页数据」的状态：刷新时把滚动累积的额外分页清掉，
  /// 顺带清掉失败标记与退避，让这一行重新有机会加载。
  void _reloadFromFirstPage({bool notify = true}) {
    _generation++;
    _loading = false;
    _sectionPageCache.remove(_cacheKey);
    _videos = widget.section.videos;
    _page = 1;
    _totalPages = null;
    _failed = false;
    _retryDelay = Duration.zero;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    // 惰性分区刷新后回到「还没有内容」的状态，需要重新补抓第一页。
    unawaited(_loadFirstPageIfNeeded());
    _schedulePrefetch();
    // didUpdateWidget 是在 build 期间被调用的，那里不能 setState。
    if (notify && mounted) setState(() {});
  }

  void _schedulePrefetch() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        unawaited(_prefetch());
        unawaited(_filterByTags());
      }
    });
  }

  double get _viewportWidth => MediaQuery.sizeOf(context).width;

  /// The home page only ships the first page of each row, so the rest is pulled
  /// from the same search the row's "more" link points at.
  Future<void> _loadMore() => _fetchPage(_page + 1);

  /// 分区还没有内容时补抓它的第一页。
  ///
  /// AV 源的首页只带第一个分区的内容，其余分区是占位（不然一次要发十几个页面请求，
  /// 既慢又容易被站点限流）；它们被选中时（也就是这个 State 被创建时）才来这里抓。
  Future<void> _loadFirstPageIfNeeded() async {
    if (_videos.isNotEmpty || _loading || widget.section.moreUrl == null) return;
    await _fetchPage(1, replace: true);
  }

  Future<void> _fetchPage(int page, {bool replace = false}) async {
    final moreUrl = widget.section.moreUrl;
    if (_loading || moreUrl == null) return;
    if (!replace && !_hasMore) return;
    // 上次失败后先退避一小会儿：probe 每次被重建都会来问一次，不能立刻打爆站点。
    if (DateTime.now().difference(_lastAttempt) < _retryDelay) return;
    final generation = _generation;
    _lastAttempt = DateTime.now();
    setState(() {
      _loading = true;
      _failed = false;
    });
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
            page: page,
          );
      // 请求期间可能已经切了分区：这份结果属于上一个分区，必须丢掉。
      if (!mounted || generation != _generation) return;
      final subscribed = ref.read(libraryProvider).valueOrNull?.artists.map((artist) => artist.name.toLowerCase()).toSet() ?? <String>{};
      final current = ref.read(settingsProvider).valueOrNull;
      final known = replace ? const <String>{} : _videos.map((video) => video.id).toSet();
      final extra = result.items.where((video) => !known.contains(video.id) && _visible(video, current, subscribed)).toList();
      debugPrint('[home] ${widget.section.title}: page ${result.page}/${result.totalPages}, +${extra.length}');
      setState(() {
        _videos = replace ? extra : [..._videos, ...extra];
        _page = result.page;
        _totalPages = result.totalPages;
      });
      _sectionPageCache[_cacheKey] = (videos: _videos, page: _page, totalPages: _totalPages);
      _retryDelay = Duration.zero;
      // 刚拿到的这一批先预热封面，滚过去时就不会先看到一片灰。
      unawaited(_prefetch(extra));
    } catch (error) {
      debugPrint('[home] load failed: $error');
      // 过期的失败也不该记到新分区头上（否则新分区会莫名其妙地显示「重试」）。
      if (generation != _generation) return;
      final seconds = _retryDelay == Duration.zero ? 2 : _retryDelay.inSeconds * 2;
      _retryDelay = Duration(seconds: seconds > 30 ? 30 : seconds);
      if (mounted) setState(() => _failed = true);
    } finally {
      // 过期请求不能动 _loading：它已经归新分区的请求管了。
      if (generation == _generation && mounted) setState(() => _loading = false);
    }
  }

  /// 页尾「重试」按钮：忽略退避，立刻再试一次。
  Future<void> _retry() {
    _retryDelay = Duration.zero;
    _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
    return _loadMore();
  }

  /// 预热封面。[videos] 为空时预热列表开头那几行（首屏）。
  /// 行数给得宽一点：CDN 一张图要 1-2 秒，预热不足的话快速滚过去时只能看到灰块。
  Future<void> _prefetch([List<VideoCard>? videos]) async {
    if (!mounted) return;
    final context = this.context;
    final width = _viewportWidth;
    final columns = homeWaterfallColumns(width);
    final cacheWidth = videoCardCacheWidth(homeWaterfallCardWidth(width, columns), MediaQuery.devicePixelRatioOf(context));
    final targets = (videos ?? _videos).take(columns * 6).where((video) => video.coverUrl.isNotEmpty).toList(growable: false);
    // 图片站点单张要 0.3-5s，一次把几十张全发出去会互相争带宽而且更容易握手失败，
    // 所以分批下载；失败的补一次重试（实测偶发 SSL 握手中断）。
    for (var index = 0; index < targets.length; index += 6) {
      await Future.wait(targets.skip(index).take(6).map((video) => precacheCover(video.coverUrl, cacheWidth, context)));
    }
    // 顺带把缺元数据的卡片排进补全队列（受 provider 内部并发闸门限制）：
    // 滚到它们时通常已经补好了，不会先看到空着的作者/评分行。
    unawaited(_prefetchMeta(videos ?? _videos));
    unawaited(_filterByTags());
  }

  /// 预取卡片元数据。站点部分分类（里番、泡麵番）的列表页只给封面和标题，
  /// 卡片得去详情页把时长/播放量/作者/评分补回来，这里提前排队减少滚动时的等待。
  ///
  /// AV 视频源不预热：它们每个分区就有二三十张缺元数据的卡片，而详情页是几百 KB、
  /// 还隔着代理和 Cloudflare，一次性打几十个请求既慢又容易触发限流。滚动到可见时
  /// 卡片自己会按需补（`VideoCardTile` 的 `autoFetchMeta`）。
  Future<void> _prefetchMeta(List<VideoCard> videos) async {
    if (javSiteFor(ref.read(settingsProvider).valueOrNull?.homeBaseUrl) != null) return;
    final targets = videos.take(homeWaterfallColumns(_viewportWidth) * 4).where((video) => video.id.isNotEmpty && !hasVideoCardMeta(video)).toList(growable: false);
    if (targets.isEmpty) return;
    await Future.wait([
      for (final video in targets) ref.read(videoCardMetaProvider(video.id).future).then<VideoCard?>((value) => value, onError: (Object _, StackTrace __) => null),
    ]);
  }

  Future<void> _filterByTags() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null || settings.blockedVideoTags.isEmpty || _videos.isEmpty) return;
    final targets = _videos.where((video) => video.id.isNotEmpty).take(homeWaterfallColumns(_viewportWidth) * 6).toList(growable: false);
    final cache = ref.read(videoMetaCacheProvider);
    final repository = ref.read(han1meRepositoryProvider);
    await Future.wait([
      for (final video in targets)
        if (cache.read(video.id)?.tags.isNotEmpty != true)
          repository.video(settings.resolvedBaseUrl, video.id).then((detail) async {
            await cache.put(VideoCard(
              id: video.id,
              title: video.title,
              coverUrl: detail.coverUrl ?? video.coverUrl,
              duration: detail.duration ?? video.duration,
              views: detail.views ?? video.views,
              rating: detail.rating ?? video.rating,
              artist: detail.artist ?? video.artist,
              uploadTime: detail.uploadDate ?? video.uploadTime,
              tags: detail.tags.map((tag) => tag.name).where((tag) => tag.isNotEmpty).toList(growable: false),
            ));
          }).catchError((_) {}),
    ]);
    if (!mounted) return;
    final blocked = ref.read(settingsProvider).valueOrNull?.blockedVideoTags ?? const <String>[];
    if (blocked.isEmpty) return;
    final filtered = _videos.where((video) {
      final meta = cache.read(video.id);
      final tags = meta?.tags ?? video.tags;
      return !blocked.any((blockedTag) => tags.any((tag) => tag.toLowerCase().contains(blockedTag.toLowerCase())));
    }).toList(growable: false);
    if (filtered.length == _videos.length) return;
    setState(() => _videos = filtered);
  }

  @override
  Widget build(BuildContext context) {
    final width = _viewportWidth;
    final columns = homeWaterfallColumns(width);
    final hasMore = _hasMore;
    final cardWidth = homeWaterfallCardWidth(width, columns);
    return SliverMainAxisGroup(
      slivers: [
        if (widget.showHeader) SliverToBoxAdapter(child: _SectionHeader(section: widget.section)),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(_gridPadding, 0, _gridPadding, 20),
          sliver: SliverGrid(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: columns,
              mainAxisSpacing: 14,
              crossAxisSpacing: _gridSpacing,
              mainAxisExtent: cardWidth * 9 / 16 + videoCardMetaHeight(_videos, assumeMeta: true),
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => index == _videos.length - 1 && hasMore
                  ? _LoadMoreProbe(onProbe: _loadMore, child: VideoCardTile(video: _videos[index], horizontal: true, autoFetchMeta: true))
                  : VideoCardTile(video: _videos[index], horizontal: true, autoFetchMeta: true),
              childCount: _videos.length,
            ),
          ),
        ),
        if (hasMore)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Center(
                child: _loading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5))
                    : _failed
                        ? TextButton.icon(onPressed: () => unawaited(_retry()), icon: const Icon(Icons.refresh, size: 18), label: Text(AppLocalizations.of(context)!.retry))
                        : const SizedBox(height: 24),
              ),
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
    _probe();
  }

  /// 这个格子被重建时（父级 setState、上一次加载失败后重建等）再试探一次。
  /// 只在 initState 里试探的话，一次失败就会把这一行永久卡住。
  @override
  void didUpdateWidget(_LoadMoreProbe oldWidget) {
    super.didUpdateWidget(oldWidget);
    _probe();
  }

  void _probe() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.onProbe());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
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

class _FeaturedVideoSurface extends ConsumerWidget {
  const _FeaturedVideoSurface({required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Material(
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          // 统一入口：Windows 上按设置弹出独立播放窗口，其余平台窗口内跳转。
          onTap: video.id.isEmpty ? null : () => openVideo(context, ref, video.id),
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: video.coverUrl,
                cacheManager: appImageCacheManager,
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
