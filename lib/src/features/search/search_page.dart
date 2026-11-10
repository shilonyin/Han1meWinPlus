import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:g1455/g1455.dart';
import 'package:m3e_core/m3e_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_motion.dart';
import '../../core/app_radius.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/remote/han1me_api.dart'
    show CloudflareChallengeException, SearchResult;
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';
import '../shared/app_error.dart';
import '../shared/press_scale.dart';
import '../shared/scroll_actions.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import '../video/play_window.dart';
import 'search_controller.dart';
import 'search_suggestions.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_dialog.dart';
import '../navigation/app_shell.dart';

/// 搜索结果的默认列数（除下面两类竖版海报分区之外都用它）。
const _searchColumns = 4;

/// 里番、泡麵番的列表封面是竖版海报（新番预告实测 268x394，这两类同源），
/// 塞进 16:9 的槽位会把海报按宽度放大再上下裁掉，只剩中间一条 —— 看上去就是放大的
/// 身体特写，海报全貌没了。这两类改按海报比例排版，并像 B 站「追番」页那样一排六个。
///
/// 判据是分类的**站点键**（`search_key`），不是界面文案：不同语言下这里显示的是
/// 「里番 / 裏番 / Hentai」，写死文案会在换语言或换站点时失效。调用方先用
/// `SearchOptionGroup.canonical` 归一，再和这里比。
const _posterGenres = {'裏番', '泡麵番'};
const _posterColumns = 6;
const _posterAspectRatio = 3 / 4;

class SearchPage extends ConsumerStatefulWidget {
  const SearchPage({super.key, required this.request});

  final SearchRouteRequest request;

  @override
  ConsumerState<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends ConsumerState<SearchPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();
  final _searchFocus = FocusNode();

  /// 建议面板按搜索框的实际位置摆放，所以两边的几何都要能取到。
  final _panelHostKey = GlobalKey();
  final _fieldKey = GlobalKey();

  /// 输入框聚焦时在它下方铺开「搜索历史 + 热门」面板（与首页顶栏同一个面板）。
  var _panelOpen = false;

  /// 上次把「首屏结果」喂给分页状态时的条件指纹，用于识别「首屏换了」。
  Object? _pagingKey;

  @override
  void initState() {
    super.initState();
    final query = ref.read(searchQueryProvider(widget.request));
    _textController.text = query.text;
    if (query.hasSearchCriteria) {
      unawaited(ref.read(searchHistoryProvider.notifier).record(query));
    }
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    final open = _searchFocus.hasFocus;
    if (!mounted || open == _panelOpen) return;
    // 空白搜索页的输入框是 autofocus 的：焦点在首帧 build 里就拿到，
    // 那时同步 setState 会直接抛错，所以这一帧的变更推到帧末。
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _panelOpen = _searchFocus.hasFocus);
      });
      return;
    }
    setState(() => _panelOpen = open);
  }

  void _closePanel() {
    _searchFocus.unfocus();
    if (_panelOpen) setState(() => _panelOpen = false);
  }

  @override
  void didUpdateWidget(covariant SearchPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.request == widget.request) return;
    _textController.text = ref.read(searchQueryProvider(widget.request)).text;
  }

  @override
  void dispose() {
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final result = ref.watch(searchResultsProvider(request));
    final query = ref.watch(searchQueryProvider(request));
    final notifier = ref.read(searchQueryProvider(request).notifier);
    final options = ref.watch(searchOptionCatalogProvider).valueOrNull;
    final baseUrl = ref.watch(
      settingsProvider.select(
        (settings) => settings.valueOrNull?.resolvedBaseUrl ?? '',
      ),
    );
    final javSource = javSiteFor(baseUrl) != null;
    final l10n = AppLocalizations.of(context)!;
    // 往下接的页（瀑布流）。首屏由上面那条 provider 负责，这里只管第 2 页往后。
    final more = ref.watch(searchMoreResultsProvider(request));
    final paging = ref.read(searchMoreResultsProvider(request).notifier);
    final page = result.valueOrNull;
    // 首屏换了（新关键词 / 新标签）时要重新数页码，否则会把上一组条件的「已翻到第几页」
    // 带过来，表现是「换了条件第一次滚动就跳页」。
    if (page != null) {
      final resultKey = Object.hash(request.sessionId, query);
      if (_pagingKey != resultKey) {
        _pagingKey = resultKey;
        paging.adopt(page);
      }
    }
    ref.listen<SearchQuery>(searchQueryProvider(request), (previous, next) {
      if (previous != next && next.hasSearchCriteria) {
        unawaited(ref.read(searchHistoryProvider.notifier).record(next));
      }
      if (_textController.text != next.text) {
        _textController.value = _textController.value.copyWith(
          text: next.text,
          selection: TextSelection.collapsed(offset: next.text.length),
        );
      }
    });
    void submit(String value) {
      notifier.text(value.trim());
      unawaited(
        ref
            .read(searchHistoryProvider.notifier)
            .record(ref.read(searchQueryProvider(request))),
      );
    }

    Future<void> loadMore() async {
      final current = ref.read(searchResultsProvider(request)).valueOrNull;
      if (current == null) return;
      await ref
          .read(searchMoreResultsProvider(request).notifier)
          .next(query, totalPages: current.totalPages);
    }

    // 分类浏览模式：无关键词、只指定了分类（侧栏「里番 / 泡面番」点进来就是这种）。
    // 设计稿的「分类列表页」和「搜索结果页」是两种布局：分类页没有顶栏搜索框，
    // 而是「页头大标题 + 统计行」，也没有分类页签行。
    final browseMode = query.text.trim().isEmpty && query.genre.isNotEmpty;

    final pageWidget = Scaffold(
      // 设计稿顶栏：左侧返回按钮 32×32 圆角10，右侧搜索框撑满剩余宽度
      // （1280 画布里 1000 宽，即内容区左右各留 204-176=28 边距）。
      appBar: browseMode
          ? AppBar(
              // 设计稿分类页页头：窗口按钮带占顶部 28，那一行在按钮带**下方**。
              // toolbarHeight 只算内容区高度、不含按钮带，所以内容自身还要再让出
              // `windowControlsHeight`，否则整行会钻进窗口按钮里（实测顶到 y40）。
              toolbarHeight: 56,
              leadingWidth: 0,
              automaticallyImplyLeading: false,
              backgroundColor: AppDesignTokens.pageBackground,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 0,
              // 设计稿分类页页头：「里番」与副标题同一行，右侧一条矮窄的灰底搜索框。
              title: Padding(
                padding: const EdgeInsets.fromLTRB(
                  28,
                  AppDesignTokens.windowControlsHeight,
                  28,
                  0,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Text(
                      query.genre,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: AppDesignTokens.ink,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      '题材、年份、评分',
                      style: TextStyle(
                        fontSize: 12,
                        color: AppDesignTokens.fieldHint,
                      ),
                    ),
                    const Spacer(),
                    // 设计稿的搜索框是右侧一条固定宽度的小框，不跟着窗口拉长 ——
                    // 撑满整行会变成一条横贯页面的长条，和设计稿差得很远。
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 420),
                      child: SizedBox(
                        width: 420,
                        child: KeyedSubtree(
                          key: _fieldKey,
                          child: _SearchInput(
                            controller: _textController,
                            focusNode: _searchFocus,
                            hintText: '${query.genre} 关键词、作者、标签，回车直接搜',
                            autoFocus: false,
                            compact: true,
                            onSubmitted: submit,
                            onClear: () {
                              _textController.clear();
                              notifier.text('');
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : AppBar(
              // 设计稿搜索页：← 与搜索框那一行落在 y64~111（框高 48），页头总高 112。
              toolbarHeight: 112,
              leadingWidth: 0,
              automaticallyImplyLeading: false,
              backgroundColor: AppDesignTokens.pageBackground,
              surfaceTintColor: Colors.transparent,
              elevation: 0,
              titleSpacing: 0,
              title: Padding(
                padding: const EdgeInsets.fromLTRB(28, 64, 28, 0),
                child: Row(
                  children: [
                    PressScale(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(AppRadius.sm),
                        onTap: () => context.pop(),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F1F5),
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                          ),
                          child: const Icon(
                            Symbols.arrow_back_rounded,
                            size: 16,
                            color: AppDesignTokens.inkSubtle,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: KeyedSubtree(
                        key: _fieldKey,
                        child: _SearchInput(
                          controller: _textController,
                          focusNode: _searchFocus,
                          hintText: l10n.searchHint,
                          autoFocus:
                              request.initialUrl == null &&
                              request.initialQuery == null,
                          onSubmitted: submit,
                          onClear: () {
                            _textController.clear();
                            notifier.text('');
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
      body: Stack(
        key: _panelHostKey,
        children: [
          Column(
            children: [
              // AV 视频源只有关键词搜索（没有 hanime1 那套分类/排序/标签筛选），
              // 所以整行筛选控件直接不渲染，避免点了没效果的假控件。
              //
              // 分类浏览模式也不显示「分类页签行 / 整排排序胶囊」——设计稿的分类页
              // 是「统计行 + 右侧 3 个排序胶囊」，见 _CategoryStatsBar。
              if (!javSource && !browseMode) ...[
                _GenreTabs(options: options, query: query, notifier: notifier),
                _SortRow(options: options, query: query, notifier: notifier),
              ],
              if (!javSource && browseMode)
                _CategoryStatsBar(
                  query: query,
                  options: options,
                  notifier: notifier,
                  total: result.valueOrNull?.totalPages,
                ),
              Expanded(
                child: Stack(
                  children: [
                    result.when(
                      loading: () =>
                          const Center(child: M3EContainedLoadingIndicator()),
                      error: (error, stackTrace) => AppErrorView(
                        error: error,
                        onRetry: () =>
                            ref.invalidate(searchResultsProvider(request)),
                        // 首页与播放页都能就地过 Cloudflare 校验，搜索页原来只有「重试」,
                        // 被挑战时用户只能干等。这里补上同一条恢复路径（走应用内 WebView 拿
                        // cf_clearance，成功回来再重跑这次搜索）。
                        onCloudflareVerified: () async {
                          final url = error is CloudflareChallengeException
                              ? error.url
                              : null;
                          if (await context.push<bool>(
                                '/cloudflare',
                                extra: url,
                              ) ==
                              true) {
                            await Future<void>.delayed(
                              const Duration(milliseconds: 250),
                            );
                            ref.invalidate(searchResultsProvider(request));
                          }
                        },
                      ),
                      data: (page) => page.items.isEmpty
                          // AV 源没有标签/分类筛选，从历史里带过来的条件会被清掉，空结果的原因
                          // 就变成「还没输关键词」，直接说清楚，别报成「没有找到匹配的视频」。
                          ? _EmptyState(
                              message:
                                  javSource &&
                                      query.text.trim().isEmpty &&
                                      query.genre.isEmpty
                                  ? l10n.javSourceSearchHint
                                  : l10n.noSearchResults,
                            )
                          : _SearchResultsGrid(
                              key: ValueKey(query),
                              result: page,
                              more: more,
                              query: query,
                              scrollController: _scrollController,
                              // 分类先归一到站点键再比（界面文案随语言变，不能拿来当判据）。
                              posterLayout: _posterGenres.contains(
                                options?.genres.canonical(query.genre) ??
                                    query.genre,
                              ),
                              // 设计稿的分类页没有「搜索结果」这一行，统计行下面直接是卡片。
                              showTitle: !browseMode,
                              // 首屏算第 1 页，所以「已接上的页数」= 当前页码 - 1。
                              loadedPages:
                                  ref
                                      .read(
                                        searchMoreResultsProvider(
                                          request,
                                        ).notifier,
                                      )
                                      .page -
                                  1,
                              onLoadMore: loadMore,
                              onRetryMore: () => ref.invalidate(
                                searchMoreResultsProvider(request),
                              ),
                            ),
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: ScrollActions(
                        controller: _scrollController,
                        onRefresh: () async {
                          // 下拉/点刷新等于「从头看」：连同已经接上的页一起丢掉，
                          // 否则刷新后前面是第 1 页、后面还挂着第 5 页的内容。
                          ref.invalidate(searchMoreResultsProvider(request));
                          final refreshed = ref.refresh(
                            searchResultsProvider(request).future,
                          );
                          if (!context.mounted) return;
                          await refreshed;
                        },
                        onError: (error) => showAppErrorBar(
                          context,
                          error,
                          onRetry: () =>
                              ref.invalidate(searchResultsProvider(request)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_buildSuggestionsPanel(context) case final panel?) panel,
        ],
      ),
    );

    // 设计稿的搜索页/分类页左侧都是同一条常驻侧栏（`base_search.png` 与
    // `base_category_hentai.png` 两张都画了 logo+导航+账号卡），但 `/search` 挂在
    // 根导航器上（它会被视频页这类全屏页 push），拿不到 StatefulNavigationShell，
    // 所以这里直接复用公开的侧栏组件，桌面宽度下把它摆在左侧。
    if (MediaQuery.sizeOf(context).width >= 900) {
      // 必须包一层 Material：侧栏里的 InkWell / Card 都要求有 Material 祖先，
      // 直接把它们塞进裸 Row 时那个祖先不存在 —— release 下不会红屏，但点击
      // 直接失效，表现就是「点里番进去以后，侧栏其他项都点不动了」。
      return Material(
        color: AppDesignTokens.pageBackground,
        child: Row(
          children: [
            const AppDesktopSidebar(),
            Expanded(child: pageWidget),
          ],
        ),
      );
    }
    return pageWidget;
  }

  /// 点建议条目：就地替换当前查询条件。
  ///
  /// 搜索页不该为每次点选再压一页路由（首页那一侧才是「跳到搜索页」）。就地替换
  /// 会走 `ref.listen` 的记录逻辑，历史照样会更新，只是不留一摞一模一样的搜索页。
  void _applySuggestion(SearchQuery query) {
    _closePanel();
    ref.read(searchQueryProvider(widget.request).notifier).replace(query);
  }

  /// 建议面板按搜索框的实际位置摆放（宽度、水平位置都与搜索框一致），
  /// 与首页顶栏用的是同一个 `SearchSuggestions`，两处观感必须一致。
  Widget? _buildSuggestionsPanel(BuildContext context) {
    final fieldBox = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    final hostBox =
        _panelHostKey.currentContext?.findRenderObject() as RenderBox?;
    if (fieldBox == null ||
        hostBox == null ||
        !fieldBox.hasSize ||
        !hostBox.hasSize) {
      return null;
    }
    // 输入框在 AppBar 里、面板挂在 body 的 Stack 里，两者是兄弟不是父子，
    // 所以不能用 ancestor 定位，只能各自取全局坐标再相减。
    final fieldTopLeft =
        fieldBox.localToGlobal(Offset.zero) -
        hostBox.localToGlobal(Offset.zero);
    final width = fieldBox.size.width.clamp(240.0, 640.0);
    final left = fieldTopLeft.dx.clamp(
      0.0,
      (hostBox.size.width - width).clamp(0.0, double.infinity),
    );
    // 面板顶在输入框下缘再留 6。body 的 Stack 从 AppBar 下面开始，算出来的 top
    // 正常就在 0 附近；夹到 0 是为了不让 Stack 把面板顶边裁掉。
    final top = (fieldTopLeft.dy + fieldBox.size.height + 6).clamp(
      0.0,
      double.infinity,
    );
    return Positioned(
      left: left,
      top: top,
      width: width,
      child: IgnorePointer(
        ignoring: !_panelOpen,
        child: AnimatedSlide(
          duration: AppMotion.standard,
          curve: AppMotion.settle,
          offset: _panelOpen ? Offset.zero : const Offset(0, -0.03),
          child: AnimatedOpacity(
            duration: AppMotion.brief,
            opacity: _panelOpen ? 1 : 0,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(AppRadius.md),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x55000000),
                    blurRadius: 20,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              child: SearchSuggestions(
                width: width,
                maxHeight: (MediaQuery.sizeOf(context).height - 220).clamp(
                  200.0,
                  560.0,
                ),
                onSelected: _applySuggestion,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 搜索页顶部输入框：圆角填充、右侧「清除 + 搜索」，样式对齐主流视频站点。
class _SearchInput extends StatelessWidget {
  const _SearchInput({
    required this.controller,
    required this.focusNode,
    required this.hintText,
    required this.autoFocus,
    required this.onSubmitted,
    required this.onClear,
    this.compact = false,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hintText;
  final bool autoFocus;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  /// 分类浏览页页头用更矮、灰底、更圆的紧凑款（设计稿 34 高、圆角接近药丸、
  /// 底色是灰 #ECECF0 而不是白）。
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // 设计稿 searchBox：1000×48、圆角 12、白底。左侧放大镜 18、文字 14、
    // 右侧清除按钮 26×26 圆角 8 底色 #EDEDF2。不用玻璃胶囊（浅底上和白底同色、
    // 占位字被压得看不见）。
    final height = compact ? 34.0 : 48.0;
    final radius = compact ? AppRadius.pill : AppRadius.md;
    final fill = compact ? AppDesignTokens.fieldFill : AppDesignTokens.surface;
    final verticalPad = compact ? 8.0 : 14.0;
    final iconSize = compact ? 16.0 : 18.0;
    final fontSize = compact ? 12.5 : 14.0;
    return SizedBox(
      height: height,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autoFocus,
        textInputAction: TextInputAction.search,
        onSubmitted: onSubmitted,
        style: TextStyle(fontSize: fontSize, color: AppDesignTokens.ink),
        decoration: InputDecoration(
          isDense: true,
          hintText: hintText,
          hintStyle: TextStyle(
            fontSize: fontSize,
            color: AppDesignTokens.fieldHint,
          ),
          filled: true,
          fillColor: fill,
          contentPadding: EdgeInsets.symmetric(
            horizontal: 16,
            vertical: verticalPad,
          ),
          prefixIcon: Icon(
            Symbols.search_rounded,
            size: iconSize,
            color: AppDesignTokens.fieldHint,
          ),
          prefixIconConstraints: BoxConstraints(
            minWidth: compact ? 40 : 52,
            minHeight: height,
          ),
          suffixIcon: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: controller,
                builder: (context, value, _) => value.text.isEmpty
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: PressScale(
                          child: InkWell(
                            borderRadius: BorderRadius.circular(AppRadius.sm),
                            onTap: onClear,
                            child: Container(
                              width: 26,
                              height: 26,
                              decoration: BoxDecoration(
                                color: compact
                                    ? AppDesignTokens.surface
                                    : AppDesignTokens.fieldFill,
                                borderRadius: BorderRadius.circular(
                                  AppRadius.sm,
                                ),
                              ),
                              child: const Icon(
                                Symbols.close_rounded,
                                size: 14,
                                color: AppDesignTokens.inkSubtle,
                              ),
                            ),
                          ),
                        ),
                      ),
              ),
              const SizedBox(width: 12),
            ],
          ),
          suffixIconConstraints: BoxConstraints(minHeight: height),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radius),
            borderSide: const BorderSide(
              color: AppDesignTokens.accent,
              width: 1.4,
            ),
          ),
        ),
      ),
    );
  }
}

/// 第一行：内容分类页签（全部 / 各分类），选中项染色 + 下划线。
class _GenreTabs extends StatelessWidget {
  const _GenreTabs({
    required this.options,
    required this.query,
    required this.notifier,
  });

  final SearchOptionCatalog? options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final catalog = options;
    if (catalog == null) return const SizedBox(height: 44);
    final l10n = AppLocalizations.of(context)!;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final items = catalog.genres.options;
    return SizedBox(
      height: 44,
      child: UnderlineTabStrip(
        center: true,
        // 与首页顶栏同一支胭脂粉：同一个控件在两个页面必须是同一个强调色。
        selectedColor: AppDesignTokens.accent,
        labels: [
          for (final item in items)
            item.searchKey == null ? l10n.all : item.labelFor(locale),
        ],
        index: items.indexWhere(
          (item) => (item.searchKey ?? '') == query.genre,
        ),
        onSelected: (value) => notifier.genre(items[value].searchKey ?? ''),
      ),
    );
  }
}

/// 分类浏览页的统计行：左「共 N 部作品」+ 提示，右侧「综合/最新/热门」排序胶囊。
///
/// 设计稿：`共 536 部作品` 14 Bold `#1B1B1F`；`按更新时间倒序 · 向下滚动自动加载`
/// 12 `#9595A0`；排序胶囊组 `#E7E7ED` 圆角8、28 高，选中项白底 + 墨字。
class _CategoryStatsBar extends StatelessWidget {
  const _CategoryStatsBar({
    required this.query,
    required this.options,
    required this.notifier,
    this.total,
  });

  final SearchQuery query;
  final SearchOptionCatalog? options;
  final SearchQueryNotifier notifier;
  final int? total;

  @override
  Widget build(BuildContext context) {
    // 设计稿分类页只露三个排序：综合 / 最新 / 热门（视觉优先，写死这三个名字）。
    // 站点真实的排序键不一定叫这两个名字，所以这里用「第 0/1/2 个排序项」来承载，
    // 名字按设计稿显示，点击仍切到真实排序键。
    final catalog = options;
    final real = catalog?.sorts.options.take(3).toList() ?? const [];
    const designLabels = ['综合', '最新', '热门'];
    final chips = <({String label, String? key})>[
      for (var i = 0; i < 3; i++)
        (
          label: designLabels[i],
          key: real.length > i ? (real[i].searchKey ?? '') : null,
        ),
    ];
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 10),
      child: Row(
        children: [
          if (total != null && total! > 0) ...[
            Text(
              '共 $total 部作品',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: AppDesignTokens.ink,
              ),
            ),
            const SizedBox(width: 16),
            const Text(
              '按更新时间倒序 · 向下滚动自动加载',
              style: TextStyle(fontSize: 12, color: AppDesignTokens.inkMuted),
            ),
          ],
          const Spacer(),
          Container(
            height: 28,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppDesignTokens.fieldFill,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final chip in chips)
                  Builder(
                    builder: (context) {
                      // 选中判定：综合 = 空排序键；其余按真实键比。
                      final selected = (chip.key ?? '') == query.sort;
                      return PressScale(
                        child: InkWell(
                          borderRadius: BorderRadius.circular(AppRadius.xs),
                          onTap: chip.key == null
                              ? null
                              : () => notifier.sort(chip.key!),
                          child: Container(
                            width: 48,
                            height: 20,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: selected
                                  ? AppDesignTokens.surface
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                            ),
                            child: Text(
                              chip.label,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: selected
                                    ? AppDesignTokens.ink
                                    : AppDesignTokens.inkSubtle,
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 第二行：排序方式（文本胶囊）+ 右侧「更多筛选」。
class _SortRow extends StatelessWidget {
  const _SortRow({
    required this.options,
    required this.query,
    required this.notifier,
  });

  final SearchOptionCatalog? options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final catalog = options;
    final l10n = AppLocalizations.of(context)!;
    if (catalog == null) return const SizedBox(height: 46);
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    return SizedBox(
      height: 46,
      child: Stack(
        children: [
          // 排序胶囊居中；两侧留出「更多筛选」的宽度，窄窗时内容仍可横向滚动。
          Center(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 112),
              child: Row(
                children: [
                  for (final item in catalog.sorts.options)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: _SortChip(
                        label: item.searchKey == null
                            ? l10n.searchSortGeneral
                            : item.labelFor(locale),
                        selected: (item.searchKey ?? '') == query.sort,
                        onTap: () => notifier.sort(item.searchKey ?? ''),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: _MoreFiltersMenu(
                options: catalog,
                query: query,
                notifier: notifier,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return PressScale(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? scheme.primary : scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              color: selected ? scheme.onPrimary : scheme.onSurfaceVariant,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}

/// 「更多筛选」：把发布日期、时长、标签、作者收进一个菜单，菜单项直接显示当前取值。
class _MoreFiltersMenu extends StatelessWidget {
  const _MoreFiltersMenu({
    required this.options,
    required this.query,
    required this.notifier,
  });

  final SearchOptionCatalog options;
  final SearchQuery query;
  final SearchQueryNotifier notifier;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final locale = searchOptionLocaleKey(Localizations.localeOf(context));
    final dates = options.releaseDates;
    final durations = options.durations;
    return MenuAnchor(
      menuChildren: [
        SubmenuButton(
          leadingIcon: const Icon(Symbols.calendar_month_rounded, size: 18),
          menuChildren: [
            for (final item in dates.options)
              MenuItemButton(
                onPressed: () => notifier.date(item.searchKey ?? ''),
                child: Text(
                  (item.searchKey ?? '').isEmpty
                      ? l10n.all
                      : item.labelFor(locale),
                ),
              ),
            const Divider(height: 8),
            MenuItemButton(
              onPressed: () async {
                final date = await _showDateFilter(
                  context,
                  query.date,
                  dates.options,
                  locale,
                );
                if (date != null) notifier.date(date);
              },
              child: Text(l10n.specificYearMonth),
            ),
          ],
          child: Text(
            l10n.releaseDate(
              query.date.isEmpty
                  ? l10n.all
                  : dates.localize(query.date, locale) ?? query.date,
            ),
          ),
        ),
        SubmenuButton(
          leadingIcon: const Icon(Symbols.schedule_rounded, size: 18),
          menuChildren: [
            for (final item in durations.options)
              MenuItemButton(
                onPressed: () => notifier.duration(item.searchKey ?? ''),
                child: Text(
                  (item.searchKey ?? '').isEmpty
                      ? l10n.all
                      : item.labelFor(locale),
                ),
              ),
          ],
          child: Text(
            l10n.duration(
              query.duration.isEmpty
                  ? l10n.all
                  : durations.localize(query.duration, locale) ??
                        query.duration,
            ),
          ),
        ),
        MenuItemButton(
          leadingIcon: const Icon(Symbols.sell_rounded, size: 18),
          onPressed: () async {
            final selection = await _showTagFilter(
              context,
              query.tags,
              query.broad,
              options,
              locale,
            );
            if (selection != null) {
              notifier.tags(selection.tags, selection.broad);
            }
          },
          child: Text(
            query.tags.isEmpty
                ? l10n.tags
                : l10n.tagsSelected(query.tags.length),
          ),
        ),
        MenuItemButton(
          leadingIcon: Icon(
            query.type == 'artist'
                ? Symbols.check_rounded
                : Symbols.person_search_rounded,
            size: 18,
          ),
          onPressed: () =>
              notifier.type(query.type == 'artist' ? '' : 'artist'),
          child: Text(l10n.searchAuthors),
        ),
      ],
      builder: (context, controller, child) => PressScale(
        child: TextButton.icon(
          onPressed: controller.open,
          icon: const Icon(Symbols.tune_rounded, size: 18),
          label: Text(l10n.searchMoreFilters),
        ),
      ),
    );
  }
}

enum _DateMode { range, month }

Future<String?> _showDateFilter(
  BuildContext context,
  String currentDate,
  List<SearchOption> options,
  String locale,
) => showAppDialog<String>(
  context: context,
  builder: (context) => _DateFilterDialog(
    currentDate: currentDate,
    options: options,
    locale: locale,
  ),
);

class _DateFilterDialog extends StatefulWidget {
  const _DateFilterDialog({
    required this.currentDate,
    required this.options,
    required this.locale,
  });

  final String currentDate;
  final List<SearchOption> options;
  final String locale;

  @override
  State<_DateFilterDialog> createState() => _DateFilterDialogState();
}

class _DateFilterDialogState extends State<_DateFilterDialog> {
  _DateMode _mode = _DateMode.range;
  String _range = '';
  String _year = '';
  String _month = '';

  @override
  void initState() {
    super.initState();
    if (widget.options
        .map((item) => item.searchKey)
        .contains(widget.currentDate)) {
      _range = widget.currentDate;
    } else if (widget.currentDate.isNotEmpty) {
      final values = widget.currentDate.split(' ');
      _year = values.take(2).join(' ');
      _month = values.length > 2 ? values.skip(2).take(2).join(' ') : '';
      _mode = _DateMode.month;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final years = [
      for (var year = DateTime.now().year; year >= 1990; year--) '$year 年',
    ];
    return AlertDialog(
      title: Text(l10n.releaseDateTitle),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 换成 g1455 的分段控件：按住时整条选中胶囊会像水珠一样抬起来。
            // 配色接回主题色，不然默认的 iOS 白胶囊在暗色弹窗里会显得没接上主题。
            GlassSegmentedControl(
              segments: [Text(l10n.dateRange), Text(l10n.specificYearMonth)],
              selectedIndex: _mode.index,
              onSelected: (index) =>
                  setState(() => _mode = _DateMode.values[index]),
              thumbColor: Theme.of(context).colorScheme.primary,
            ),
            const SizedBox(height: 16),
            if (_mode == _DateMode.range)
              DropdownButtonFormField<String>(
                initialValue: _range,
                decoration: InputDecoration(labelText: l10n.releaseDateTitle),
                items: widget.options
                    .map(
                      (item) => DropdownMenuItem(
                        value: item.searchKey ?? '',
                        child: Text(
                          (item.searchKey?.isEmpty ?? true)
                              ? l10n.all
                              : item.labelFor(widget.locale),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _range = value ?? ''),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField(
                      initialValue: _year,
                      decoration: InputDecoration(labelText: l10n.year),
                      items: ['', ...years]
                          .map(
                            (value) => DropdownMenuItem(
                              value: value,
                              child: Text(
                                value.isEmpty ? l10n.allYears : value,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) => setState(() => _year = value ?? ''),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField(
                      initialValue: _month,
                      decoration: InputDecoration(labelText: l10n.month),
                      items:
                          [
                                for (var month = 1; month <= 12; month++)
                                  '$month 月',
                                '',
                              ]
                              .map(
                                (value) => DropdownMenuItem(
                                  value: value,
                                  child: Text(
                                    value.isEmpty ? l10n.allMonths : value,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (value) =>
                          setState(() => _month = value ?? ''),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _mode == _DateMode.range
                  ? _range
                  : [
                      _year,
                      _month,
                    ].where((value) => value.isNotEmpty).join(' '),
            ),
            child: Text(l10n.apply),
          ),
        ),
      ],
    );
  }
}

class _TagSelection {
  const _TagSelection(this.tags, this.broad);

  final List<String> tags;
  final bool broad;
}

Future<_TagSelection?> _showTagFilter(
  BuildContext context,
  List<String> selectedTags,
  bool broad,
  SearchOptionCatalog catalog,
  String locale,
) => showAppDialog<_TagSelection>(
  context: context,
  builder: (context) => _TagFilterDialog(
    selectedTags: selectedTags,
    broad: broad,
    catalog: catalog,
    locale: locale,
  ),
);

class _TagFilterDialog extends StatefulWidget {
  const _TagFilterDialog({
    required this.selectedTags,
    required this.broad,
    required this.catalog,
    required this.locale,
  });

  final List<String> selectedTags;
  final bool broad;
  final SearchOptionCatalog catalog;
  final String locale;

  @override
  State<_TagFilterDialog> createState() => _TagFilterDialogState();
}

class _TagFilterDialogState extends State<_TagFilterDialog>
    with SingleTickerProviderStateMixin {
  late final Set<String> _selected;
  late final TabController _tabController;
  late bool _broad;
  late String _group;

  @override
  void initState() {
    super.initState();
    _selected = widget.selectedTags.map(widget.catalog.canonicalTag).toSet();
    _broad = widget.broad;
    _group = widget.catalog.tags.keys.first;
    _tabController = TabController(
      length: widget.catalog.tags.length,
      vsync: this,
    );
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final availableHeight =
        MediaQuery.sizeOf(context).height -
        MediaQuery.viewInsetsOf(context).vertical;
    final dialogHeight = (availableHeight - 120).clamp(180.0, 520.0).toDouble();
    return AlertDialog(
      title: Text(l10n.tags),
      content: SizedBox(
        width: 560,
        height: dialogHeight,
        child: Column(
          children: [
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              title: Text(l10n.broadMatch),
              subtitle: Text(l10n.broadMatchDescription),
              value: _broad,
              onChanged: (value) => setState(() => _broad = value),
            ),
            TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: widget.catalog.tags.keys
                  .map((group) => Tab(text: _tagGroupLabel(l10n, group)))
                  .toList(growable: false),
              onTap: (index) => setState(
                () => _group = widget.catalog.tags.keys.elementAt(index),
              ),
            ),
            Expanded(
              child: ListView(
                children: [
                  _TagGroup(
                    tags: widget.catalog.tags[_group]!.options,
                    locale: widget.locale,
                    selected: _selected,
                    onChanged: (tag, selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(tag);
                        } else {
                          _selected.remove(tag);
                        }
                      });
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        PressScale(
          child: TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel),
          ),
        ),
        PressScale(
          child: FilledButton(
            onPressed: () => Navigator.pop(
              context,
              _TagSelection(_selected.toList()..sort(), _broad),
            ),
            child: Text(l10n.apply),
          ),
        ),
      ],
    );
  }
}

class _TagGroup extends StatelessWidget {
  const _TagGroup({
    required this.tags,
    required this.locale,
    required this.selected,
    required this.onChanged,
  });

  final List<SearchOption> tags;
  final String locale;
  final Set<String> selected;
  final void Function(String tag, bool selected) onChanged;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: tags
              .map(
                (tag) => FilterChip(
                  label: Text(tag.labelFor(locale)),
                  selected: selected.contains(tag.searchKey),
                  onSelected: (value) => onChanged(tag.searchKey ?? '', value),
                ),
              )
              .toList(),
        ),
      ],
    ),
  );
}

String _tagGroupLabel(AppLocalizations l10n, String group) => switch (group) {
  'video_attributes' => l10n.tagVideoAttributes,
  'character_relationships' => l10n.tagRelationships,
  'characteristics' => l10n.tagCharacterSettings,
  'appearance_and_figure' => l10n.tagAppearance,
  'story_location' => l10n.tagSettings,
  'story_plot' => l10n.tagStory,
  'sex_positions' => l10n.tagPositions,
  _ => group,
};

/// 结果区：首屏（[SearchResult]）+ 后续接上的页（[more]）拼成一条瀑布流。
///
/// 以前这里是「一页一屏 + 底部分页条」，滚到底要回头去点下一个箭头；站点本来就是
/// 一页一页给数据，所以改成滚到底自动往下列，翻页条整个去掉。分页条同时还挤在结果
/// 和右下角悬浮按钮之间，去掉之后列表能多吃一段高度。
class _SearchResultsGrid extends ConsumerWidget {
  const _SearchResultsGrid({
    super.key,
    required this.result,
    required this.more,
    required this.query,
    required this.scrollController,
    required this.posterLayout,
    required this.showTitle,
    required this.loadedPages,
    required this.onLoadMore,
    required this.onRetryMore,
  });

  /// 首屏（已经是第 1 页）。
  final SearchResult result;

  /// 第 2 页往后的追加结果；还没接过页时是空的。
  final AsyncValue<List<VideoCard>> more;

  final SearchQuery query;
  final ScrollController scrollController;

  /// 里番 / 泡麵番走竖版海报排版（见 [_posterGenres]）：整张封面可见，且一排六个。
  final bool posterLayout;

  /// 要不要显示「搜索结果 共 N 条」这一行。
  ///
  /// 设计稿把两种页面画成了两套布局：**搜索结果页**有这一行（右侧还带
  /// 全部/视频/作者/标签 四个胶囊），而**分类浏览页**（`base_category_hentai.png`）
  /// 统计行下面直接就是卡片，没有这一行 —— 分类页已经在上面写了「共 N 部作品」，
  /// 再来一行「搜索结果 共 N 条」是两个说法重复，还把整片卡片往下顶了 40px。
  final bool showTitle;

  /// 首屏之后已经接上的页数（由分页状态提供，页面 watch 到变化后传进来）。
  final int loadedPages;

  final Future<void> Function() onLoadMore;
  final VoidCallback onRetryMore;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context)!;
    final isRecommendations = query.text.trim().isEmpty && query.genre.isEmpty;
    final appended = more.valueOrNull;
    final videos = isRecommendations
        ? result.items
        : [...result.items, ...?appended];
    // 还能不能往下接：推荐位没有分页（`totalPages` 恒为 1），天然不会触发加载。
    // 看的是「已经被要走的页码」（`loadedPages`，由页面喂进来的分页状态提供），
    // 而不是站点给的总页数 —— 页码只是分页条的遗留概念，瀑布流不显示它。
    final hasMore =
        !isRecommendations &&
        result.totalPages > 1 &&
        loadedPages < result.totalPages;
    final loading = more.isLoading;
    final failure = more.error;
    final aspectRatio = posterLayout ? _posterAspectRatio : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 没输关键词时这页给的是推荐内容，加个小标题说明一下来源，
        // 免得被当成搜索结果的兜底。
        if (isRecommendations)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Text(
              l10n.recommendedVideos,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (showTitle)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Text(
                  '搜索结果',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  '共 ${videos.length} 条',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        Expanded(
          child: VideoCardGrid(
            videos: videos,
            cardsPerRow: posterLayout ? _posterColumns : _searchColumns,
            horizontal: true,
            // 这页右下角浮着刷新 / 回到顶部，末尾得把高度让出来，
            // 否则滚到底时最后一行右侧那张卡被按钮压住点不到。
            bottomPadding: floatingActionsClearance + (hasMore ? 56 : 0),
            // 竖版海报结果按海报比例留高，不再裁成 16:9 的一条。
            coverAspectRatio: aspectRatio,
            controller: scrollController,
            itemBuilder: (context, index, video, _) {
              final tile = VideoCardTile(
                video: video,
                horizontal: true,
                coverAspectRatio: aspectRatio,
                // 统一入口：Windows 上按设置弹出独立播放窗口，其余平台窗口内跳转。
                onTap: video.id.isEmpty
                    ? null
                    : () => openVideo(context, ref, video.id),
              );
              // 末尾那张卡片走进「缓存区」时就去要下一页，滚到之前通常已经拼好了。
              if (!hasMore || index != videos.length - 1) return tile;
              return _LoadMoreProbe(onProbe: onLoadMore, child: tile);
            },
          ),
        ),
        // 页尾只在「正在接下一页」或「接失败了」时才占位置：以前这里常驻一根
        // 「第几页 / 共几页」的分页条，瀑布流本来就靠滚动表达进度，留着只是噪音。
        if (hasMore && (loading || failure != null))
          SizedBox(
            height: 40,
            child: Center(
              child: loading
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    )
                  : PressScale(
                      child: TextButton.icon(
                        onPressed: onRetryMore,
                        icon: const Icon(Symbols.refresh_rounded, size: 18),
                        label: Text(l10n.retry),
                      ),
                    ),
            ),
          ),
      ],
    );
  }
}

/// 末尾卡片上的探针：它被建出来（也就是滚进缓存区）时去要下一页。
///
/// 与首页分区用的是同一套做法 —— 只在 `initState` 里试一次的话，一次失败就会把
/// 这一行永久卡住；`didUpdateWidget` 让父级重建时还能再试。
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

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Symbols.search_off_rounded, size: 56),
        const SizedBox(height: 12),
        Text(message, style: Theme.of(context).textTheme.bodyLarge),
      ],
    ),
  );
}
