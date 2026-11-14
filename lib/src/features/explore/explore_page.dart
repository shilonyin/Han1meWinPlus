import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:g1455/g1455.dart';
import 'package:go_router/go_router.dart';
import 'package:m3e_core/m3e_core.dart';

import 'package:material_symbols_icons/symbols.dart';
import '../../../l10n/app_localizations.dart';
import '../../core/app_radius.dart';
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
import '../../data/local/watch_repository.dart';
import '../../core/settings.dart';
import '../settings/settings_controller.dart';
import '../search/search_suggestions.dart';
import '../shared/app_error.dart';
import '../shared/app_image_cache.dart';
import '../shared/press_scale.dart';
import '../shared/scroll_actions.dart';
import '../shared/underline_tab_strip.dart';
import '../shared/video_card.dart';
import '../video/play_window.dart';
import 'explore_controller.dart';
import '../../core/app_design_tokens.dart';
import '../../core/app_motion.dart';

const _gridPadding = 28.0;
const _gridSpacing = 24.0;

/// 首页「影院版」的深色底。
const _cinemaBg = Color(0xFF0A0A0D);

/// 首页「影院版」深色外壳：只包住滚动内容，顶部导航仍在浅色骨架里。
///
/// 用 [ThemeData.dark] 而不是对浅色主题 copyWith(brightness:)。[VideoCardTile] 的
/// 标题色取自 [ThemeData.textTheme]，只翻 brightness 不换 textTheme，标题在深底上
/// 仍是深字，等于没生效。这里给一整套深色主题，卡片自带的 brightness==dark 分支
/// 才会把作者/评分换成浅灰。
Widget _cinemaShell(BuildContext context, Widget child) => Theme(
  data: ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: AppDesignTokens.accent,
      brightness: Brightness.dark,
    ),
    scaffoldBackgroundColor: _cinemaBg,
  ),
  child: ColoredBox(color: _cinemaBg, child: child),
);

/// 网格的行距。设计稿的卡片是「封面 238×152 + 标题 + 作者行」，一张卡占 218 高，
/// 相邻两行封面之间留 30 的空白 —— 比列距（10）宽得多，正是为了让上一行的
/// 两行文字不至于贴到下一行的封面上。
/// 行距。设计稿 `home_v5_base.png` 实测：第一排卡片的「点赞」行底在 y560，
/// 第二排封面从 y580 开始 —— 中间只有 20。原来写 30，两排之间多出一截空白，
/// 下面那半屏整体被推下去。
const _gridRowSpacing = 30.0;

/// 首页顶栏的高度。顶栏本体、内容顶部的占位、以及顶栏底下那条 scroll edge
/// 都用它，所以提成常量 —— 三处各写一个 56 迟早会改漏。
/// v6 设计稿是 60：顶栏里要放下 34 高的搜索框，上下各留 13 才不憋。
const double _homeBarHeight = AppDesignTokens.topBarHeight;

/// 瀑布流卡片的目标宽度（逻辑像素）。窗口变化时靠它反推列数，
/// 使卡片密度保持在可读的范围内，同时把宽度用满。

/// 预热一张封面：图片站点偶发 SSL 握手中断，失败时重试一次。
/// [context] 可为空 —— 等到信号量放行时页面可能已经销毁，此时直接跳过预热。
Future<void> precacheCover(
  String url,
  int cacheWidth,
  BuildContext? context,
) async {
  if (context == null) return;
  for (var attempt = 0; attempt < 2; attempt++) {
    try {
      await precacheImage(appCachedImage(url, maxWidth: cacheWidth), context);
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
/// 首页「影片」网格的列数。
///
/// **固定 4 列**，不再按可用宽度去「塞得下几列就几列」。
/// 设计稿（`home_v5_base.png`：内容区 204~1251、四列、单卡 244、列距 24，
/// 4×244 + 3×24 = 1048 正好铺满）定死的就是 4 列；按宽度自适应时窗口一变宽
/// 就多挤一列，卡片越切越窄，整片网格看着和设计稿不是一回事。
///
/// 窄屏（手机抽屉态）保留 2 列 —— 4 列在 400 宽里一张卡只有 90，标题全被截。
int homeWaterfallColumns(double width) => width < 720 ? 2 : 4;

double homeWaterfallCardWidth(double width, int columns) =>
    (width - _gridPadding * 2 - _gridSpacing * (columns - 1)) / columns;

class ExplorePage extends ConsumerStatefulWidget {
  const ExplorePage({super.key});

  @override
  ConsumerState<ExplorePage> createState() => _ExplorePageState();
}

class _ExplorePageState extends ConsumerState<ExplorePage> {
  var _sectionIndex = 0;

  /// Weebox 式：首页隐藏分类下拉 / 快捷页签（分类改由多行 rail 承担）。
  final bool _hideCategoryBar = true;
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
    setState(() => _searchFocused = true);
    _searchFocus.requestFocus();
    // 建议面板等搜索框**滑到中间、变宽之后**再铺开。
    //
    // 两件事同时 setState 的话，面板会在第一帧就整个出现，那一下跳变把
    // 搜索框的位移完全盖住 —— 用起来就是「点一下搜索框瞬移过去」，看不到过渡。
    // 延迟一个 standard（200ms，和 AnimatedAlign 的时长一致）就能看见它滑。
    Future<void>.delayed(AppMotion.standard, () {
      if (!mounted || !_searchFocused) return;
      setState(() => _searchPanelOpen = true);
    });
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
    final url = Uri(
      path: '/search',
      queryParameters: {'query': text},
    ).toString();
    context.push(url, extra: SearchRouteRequest(initialUrl: url));
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(homeSectionsProvider);
    // 首页固定用收起式分类（顶栏「当前分类 + 下拉菜单」+ 右侧快捷分类），
    // 原「首页使用收起式分类」开关已删除，见 `docs/ui-polish.md`。
    final categories = feed.valueOrNull == null
        ? const <_FeedCategory>[]
        : _feedCategories(feed.value!);
    final sections = [for (final category in categories) category.section];
    final index = sections.isEmpty
        ? 0
        : _sectionIndex.clamp(0, sections.length - 1).toInt();
    // Weebox 式：首页不再显示分类下拉 / 快捷页签（分类由下面的多行 rail 承担）。
    final showPicker = sections.isNotEmpty && !_hideCategoryBar;
    // 顶栏右侧的快捷分类 —— 按设计稿写死这 5 个（视觉优先）。
    // 设计稿 homePage·redesign v5 的页签就是：最新上传 / Motion Anime / 3D动画 / 2.5D / 2D动画。
    // 站点真实分区可能没有这些名字，点开可能空页，但视觉与设计稿一致；
    // 能对上真实分类名的就映射过去，对不上的落到第 i 个分区，保证可点击。
    const designTabs = ['最新上传', 'Motion Anime', '3D动画', '2.5D', '2D动画'];
    final quick = <({int index, String label})>[
      for (var i = 0; i < designTabs.length; i++)
        (
          index: () {
            final hit = categories.indexWhere(
              (c) => c.section.title == designTabs[i],
            );
            if (hit >= 0) return hit;
            return i < sections.length ? i : 0;
          }(),
          label: designTabs[i],
        ),
    ];
    // 已经作为快捷分类显示在右侧的分类，不再重复出现在左侧下拉菜单里。
    final quickIndexes = <int>{for (final item in quick) item.index};
    final pickerIndexes = <int>[
      for (var i = 0; i < sections.length; i++)
        if (!quickIndexes.contains(i)) i,
    ];
    final screenWidth = MediaQuery.sizeOf(context).width;
    // 顶栏右侧不再放图标（直播/我的都在侧栏里有入口），把空间让给搜索框。
    // 设计稿的静止搜索框是 316；窗口再宽也不跟着拉长 —— 一条 500 宽的胶囊摆在
    // 60 高的 bar 里会显得头重脚轻，多出来的空间留给快捷分类。
    final idleSearchWidth = screenWidth >= 1180
        ? AppDesignTokens.searchBoxWidth
        : (screenWidth >= 940 ? 280.0 : 172.0);
    final showDrawerButton = !permanentNavigationDrawer(context);
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      // 顶栏自己画在 body 的 Stack 里（不用 Scaffold.appBar）：这样搜索框与下方的建议面板
      // 处在同一个坐标系里，面板能跟搜索框严格对齐。
      body: Stack(
        key: _bodyStackKey,
        children: [
          // 列表铺满整块 body：它不再被顶栏挤下去，顶部让开的地方由它自己第一个
          // sliver 的占位给出 —— 只有这样内容才会滚到顶栏后面。它排在顶栏**之前**，
          // 因为 Stack 里后画的在上面，顶栏必须压在它上面才不会滚没了。
          Positioned.fill(
            child: feed.when(
              skipLoadingOnReload: true,
              skipLoadingOnRefresh: true,
              loading: () =>
                  const Center(child: M3EContainedLoadingIndicator()),
              error: (error, _) => AppErrorView(
                error: error,
                onRetry: () =>
                    ref.read(homeSectionsProvider.notifier).refresh(),
                onCloudflareVerified: () async {
                  final url = error is CloudflareChallengeException
                      ? error.url
                      : null;
                  if (await context.push<bool>('/cloudflare', extra: url) ==
                      true) {
                    await Future<void>.delayed(
                      const Duration(milliseconds: 250),
                    );
                    await ref.read(homeSectionsProvider.notifier).refresh();
                  }
                },
              ),
              data: (value) => _HomeFeedBody(
                featured: value.featured,
                sections: sections,
                index: index,
              ),
            ),
          ),
          // 顶栏浮在内容之上，底下带一条 scroll edge（g1455）：内容滚到它下面时
          // 会被模糊并淡出，也就是 iOS 26 那条「滚动边缘」。
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: GlassScrollEdge(
              side: GlassScrollEdgeSide.top,
              extent: _homeBarHeight,
              // 顶栏是导航层，而且它**不动**：内容从它底下滚过去。玻璃材质（磨砂的模糊、
              // 超透的清澈）只有在这种「玻璃下面有细节」的地方才看得出来；反过来，
              // 跟着内容一起滚的卡片会在滚动瞬间露出上一帧，所以那边不铺玻璃。
              child: Material(
                // 影院沉浸：顶栏透明，hero 从最上方开始，只有搜索框浮在图上。
                color: Colors.transparent,
                child: SizedBox(
                  height: _homeBarHeight,
                  child: Padding(
                    // 顶栏上沿 34 是窗口按钮悬浮带（见 AppDesignTokens.topBarChromeHeight），
                    // 内容（分类下拉/页签/搜索框）落在下方那条带里，按设计稿 y56~93 摆放。
                    padding: const EdgeInsets.only(
                      top: AppDesignTokens.topBarChromeHeight,
                      left: _gridPadding,
                      right: _gridPadding,
                    ),
                    child: Row(
                      children: [
                        if (showDrawerButton)
                          SizedBox(
                            width: 52,
                            child: PressScale(
                              child: IconButton(
                                tooltip: l10n.navigationDrawer,
                                onPressed: openAppDrawer,
                                icon: const Icon(Symbols.menu_rounded),
                              ),
                            ),
                          ),
                        Expanded(
                          child: SizedBox(
                            height:
                                AppDesignTokens.topBarHeight -
                                AppDesignTokens.topBarChromeHeight,
                            child: Stack(
                              key: _topBarKey,
                              children: [
                                // 左侧标题（分类下拉 + 快捷分类）：聚焦搜索时淡出并让位。
                                Positioned(
                                  left: 0,
                                  // 页签这一排**贴内容带的底**，不是垂直居中。
                                  //
                                  // 设计稿：页签下划线落在 y90~92，内容带底 y112 —— 中间正好还留 20。
                                  // 所以这里只给 bottom（子级高度由内容决定，从带底往上长），
                                  // 不再像搜索框那样 top:0/bottom:0 撑满后居中：居中会把它抬到
                                  // y85 左右，和搜索框的 56~90 对不上。
                                  bottom: AppDesignTokens.topBarTabBaselineGap,
                                  // 右侧要让出的宽度 = 搜索框 + 间距 + 「换一批」胶囊。
                                  // 只让搜索框的话，页签会钻到两个控件底下去（3D动画 被盖住就是这个原因）。
                                  right: idleSearchWidth + 8 + 92 + 8,
                                  child: IgnorePointer(
                                    ignoring: _searchFocused,
                                    child: AnimatedOpacity(
                                      duration: const Duration(
                                        milliseconds: 160,
                                      ),
                                      opacity: _searchFocused ? 0 : 1,
                                      child: showPicker
                                          ? Row(
                                              children: [
                                                if (pickerIndexes.isNotEmpty)
                                                  _CategorySelector(
                                                    sections: sections,
                                                    indexes: pickerIndexes,
                                                    index: index,
                                                    onSelected: (value) =>
                                                        setState(
                                                          () => _sectionIndex =
                                                              value,
                                                        ),
                                                  ),
                                                if (pickerIndexes.isNotEmpty &&
                                                    quick.isNotEmpty) ...[
                                                  const SizedBox(width: 8),
                                                  // 设计稿里分类下拉和页签之间是一根 18 高的短竖线，
                                                  // 并且染成浅灰而不是默认的描边色。
                                                  const SizedBox(
                                                    height: 18,
                                                    child: VerticalDivider(
                                                      width: 1,
                                                      color: AppDesignTokens
                                                          .divider,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                ],
                                                if (quick.isNotEmpty)
                                                  Expanded(
                                                    child: Builder(
                                                      builder: (context) {
                                                        // 设计稿里左侧下拉显示的正是「当前分类」，右侧页签
                                                        // 就只列**其它**分类 —— 否则当前分类（如「最新上市」）
                                                        // 会在下拉和页签首位各出现一次，显得重复。
                                                        final tabs = [
                                                          for (final item
                                                              in quick)
                                                            if (item.index !=
                                                                index)
                                                              item,
                                                        ];
                                                        if (tabs.isEmpty) {
                                                          return const SizedBox.shrink();
                                                        }
                                                        return UnderlineTabStrip(
                                                          labels: [
                                                            for (final item
                                                                in tabs)
                                                              item.label,
                                                          ],
                                                          index: tabs.indexWhere(
                                                            (item) =>
                                                                item.index ==
                                                                index,
                                                          ),
                                                          spacing: 4,
                                                          selectedColor:
                                                              AppDesignTokens
                                                                  .accent,
                                                          onSelected: (value) =>
                                                              setState(
                                                                () => _sectionIndex =
                                                                    tabs[value]
                                                                        .index,
                                                              ),
                                                        );
                                                      },
                                                    ),
                                                  ),
                                              ],
                                            )
                                          : null,
                                    ),
                                  ),
                                ),
                                // 搜索框 + 右侧图标：平时贴右边，聚焦后搜索框滑到中间并变宽。
                                //
                                // 必须包一层 Positioned.fill：Stack 里如果只有这一个「非定位」子级，
                                // Stack 的尺寸会被它收缩到 Row 的自然宽度（约 416），左侧那个
                                // Positioned(right: …) 就按这 416 来算让位，页签区被算得极窄 → 溢出，
                                // 搜索框也因为只是靠 416 的右缘而飘走看不见。给它一个铺满的约束，
                                // Stack 才有整个顶栏的宽度。
                                Positioned(
                                  // 只给 1 的上边偏移：搜索框和「换一批」都是 34 高，居中摆在
                                  // 内容带里会落在 55.7~89.0，顶边比设计稿的 56 差半像素；
                                  // 上边收 1 之后实际渲染到 56.2~89.5，就是设计稿的 56~89。
                                  top: 1,
                                  bottom: 0,
                                  // 左右都要给：只给 right 时 Positioned 的宽度是「由子级决定」，
                                  // 子级（AnimatedAlign）收缩到 Row 的自然宽度再被右对齐，
                                  // 里面那句 Alignment.center 就只在那一小段里居中 ——
                                  // 聚焦后搜索框会停在偏右的位置，看着就是「没居中」。
                                  left: _gridPadding,
                                  right: _gridPadding,
                                  child: AnimatedAlign(
                                    duration: AppMotion.standard,
                                    curve: AppMotion.settle,
                                    alignment: _searchFocused
                                        ? Alignment.center
                                        : Alignment.centerRight,
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        TweenAnimationBuilder<double>(
                                          duration: AppMotion.standard,
                                          curve: AppMotion.settle,
                                          tween: Tween<double>(
                                            begin: idleSearchWidth,
                                            end: _searchFocused
                                                ? 520
                                                : idleSearchWidth,
                                          ),
                                          // 搜索框自身就是 34 高（设计稿 searchBox 316×34）。这里**不能**给
                                          // _homeBarHeight：那会把搜索框拉成整条顶栏那么高，右侧「换一批」
                                          // 胶囊又按 34 走，两个控件一高一矮、底边对齐顶边差一半。
                                          builder: (context, width, child) =>
                                              SizedBox(
                                                key: _searchFieldKey,
                                                width: width,
                                                height: AppDesignTokens
                                                    .searchBoxHeight,
                                                child: child,
                                              ),
                                          child: _HomeSearchField(
                                            controller: _searchController,
                                            focusNode: _searchFocus,
                                            onTap: _openSearch,
                                            onSubmitted: _submitSearch,
                                            onClear: () {
                                              _searchController.clear();
                                              _closeSearch();
                                            },
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        // 「换一批」和搜索框是同一侧的兄弟控件：都贴右，同高同圆角。
                                        // 它必须挂在这里而不是外层 Row 的末尾 —— 外层那个 Stack 是
                                        // Expanded，会把后面的兄弟挤到左边去（这正是它一度飘到分类下拉旁边的原因）。
                                        // 聚焦时「换一批」要**退出布局**，不能只把透明度降到 0：
                                        // 它仍占着 92 宽，Row 的自然宽度就会多出这 92，搜索框
                                        // 在那个多出来的宽度里居中 → 视觉上仍然偏左。
                                        // widthFactor 归零后这一格宽度为 0，搜索框才真正落在屏幕中间。
                                        Align(
                                          alignment: Alignment.centerRight,
                                          widthFactor: _searchFocused ? 0 : 1,
                                          child: AnimatedOpacity(
                                            duration: AppMotion.brief,
                                            opacity: _searchFocused ? 0 : 1,
                                            child: IgnorePointer(
                                              ignoring: _searchFocused,
                                              // 「换一批」和搜索框同高（34）：Row 里两个控件高度不一致时，
                                              // 居中摆放会让它们中心线错开，看起来就是「没对齐」。
                                              child: PressScale(
                                                child: SizedBox(
                                                  height: AppDesignTokens
                                                      .searchBoxHeight,
                                                  child: TextButton.icon(
                                                    onPressed: () => ref
                                                        .read(
                                                          homeSectionsProvider
                                                              .notifier,
                                                        )
                                                        .refresh(),
                                                    style: TextButton.styleFrom(
                                                      // 设计稿的「换一批」是 92×34 的淡灰胶囊，不是裸文字按钮：
                                                      // 它和左边的搜索框同高同圆角，两个控件才像一条 bar 上的兄弟。
                                                      backgroundColor:
                                                          AppDesignTokens
                                                              .fieldFill,
                                                      foregroundColor:
                                                          AppDesignTokens
                                                              .inkSubtle,
                                                      minimumSize: const Size(
                                                        92,
                                                        AppDesignTokens
                                                            .searchBoxHeight,
                                                      ),
                                                      padding:
                                                          const EdgeInsets.symmetric(
                                                            horizontal: 12,
                                                          ),
                                                      shape: RoundedRectangleBorder(
                                                        borderRadius:
                                                            BorderRadius.circular(
                                                              AppRadius.md,
                                                            ),
                                                      ),
                                                    ),
                                                    icon: const Icon(
                                                      Symbols.refresh_rounded,
                                                      size: 16,
                                                    ),
                                                    label: const Text('换一批'),
                                                  ),
                                                ),
                                              ),
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
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          // 点搜索框展开的建议面板：底部铺一层透明遮罩，点它或点一条建议都会收起。
          IgnorePointer(
            ignoring: !_searchPanelOpen,
            child: AnimatedOpacity(
              duration: AppMotion.brief,
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
    final stackBox =
        _bodyStackKey.currentContext?.findRenderObject() as RenderBox?;
    // 搜索框是顶栏内居中的，顶栏宽度在动画期间不变，所以用顶栏几何来定位面板最稳。
    var width = (MediaQuery.sizeOf(context).width - 64).clamp(280.0, 520.0);
    var left = 0.0;
    if (barBox != null &&
        barBox.hasSize &&
        stackBox != null &&
        stackBox.hasSize) {
      width = width.clamp(240.0, barBox.size.width);
      final barLeft = barBox.localToGlobal(Offset.zero).dx;
      final stackLeft = stackBox.localToGlobal(Offset.zero).dx;
      left = (barLeft - stackLeft + (barBox.size.width - width) / 2).clamp(
        0.0,
        (stackBox.size.width - width).clamp(0.0, double.infinity),
      );
    }
    return Positioned(
      left: left,
      // 建议面板贴着顶栏下沿：顶栏 60 高的基础上留 2px 的缝，
      // 写死成 62 的话顶栏一改高度这条缝就会忽有忽无。
      top: _homeBarHeight + 2,
      width: width,
      child: IgnorePointer(
        ignoring: !_searchPanelOpen,
        child: AnimatedSlide(
          duration: AppMotion.standard,
          curve: AppMotion.settle,
          offset: _searchPanelOpen ? Offset.zero : const Offset(0, -0.03),
          child: AnimatedOpacity(
            duration: AppMotion.brief,
            opacity: _searchPanelOpen ? 1 : 0,
            child: DecoratedBox(
              // 建议面板回到主题自己的面（玻璃已停用，决策见 `docs/ui-polish.md`）。
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
                maxHeight: (MediaQuery.sizeOf(context).height - 100).clamp(
                  240.0,
                  640.0,
                ),
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
    final subscribed =
        ref
            .watch(libraryProvider)
            .valueOrNull
            ?.artists
            .map((artist) => artist.name.toLowerCase())
            .toSet() ??
        <String>{};
    final categories = feed.sections
        .map(
          (section) => _FeedCategory(
            rawTitle: section.title,
            section: HomeSection(
              title: localizedHomeSectionTitle(
                section,
                catalog,
                locale,
                l10n: AppLocalizations.of(context),
              ),
              videos: section.videos
                  .where((video) => _visible(video, settings, subscribed))
                  .toList(),
              moreUrl: section.moreUrl,
              isFeatured: section.isFeatured,
            ),
          ),
        )
        .toList();
    // AV 源的分区是**按需加载**的：只有第一个分区自带内容，其余的页签要保留下来
    // （被选中时才去抓第一页）。hanime1 那边空分区没有意义，照旧过滤掉。
    if (javSiteFor(settings?.homeBaseUrl) != null) return categories;
    return categories
        .where((category) => category.section.videos.isNotEmpty)
        .toList();
  }
}

/// 首页分类：`rawTitle` 是站点原始名（用于持久化与本地化查找），`section` 是本地化后的展示数据。
class _FeedCategory {
  const _FeedCategory({required this.rawTitle, required this.section});

  final String rawTitle;
  final HomeSection section;
}

class _HomeFeedBody extends ConsumerWidget {
  const _HomeFeedBody({
    required this.featured,
    required this.sections,
    required this.index,
  });

  final List<VideoCard> featured;
  final List<HomeSection> sections;
  final int index;

  @override
  Widget build(BuildContext context, WidgetRef ref) =>
      M3EPullToRefreshIndicator(
        onRefresh: () => ref.read(homeSectionsProvider.notifier).refresh(),
        // 下拉刷新失败时列表里已经有旧数据了，整页换成错误态太粗暴（还要重新找位置），
        // 弹一条可重试的提示就够。m3e 的默认行为是把异常吞掉，所以必须显式接住。
        onError: (error, _) => showAppErrorBar(
          context,
          error,
          onRetry: () =>
              unawaited(ref.read(homeSectionsProvider.notifier).refresh()),
        ),
        // 收起式分类：只画当前分类（分区标题由顶栏的下拉菜单承担）。
        child: _cinemaShell(
          context,
          _HomeScroll(
            featured: featured,
            // Weebox 式：把所有分区都交给首页，每个分区渲染成一行横向 rail。
            sections: sections,
          ),
        ),
      );
}

/// 顶栏里的搜索框：点击后左侧的分类与快捷页签淡出、它自己滑到中间变宽，回车直接进搜索页。
///
/// 用 g1455 的 [GlassTextField]：它是"bar 携带的搜索框"那一种玻璃胶囊
/// （g1455 的文档特意说过，卡片上的输入框该用普通输入框，只有 bar 上的才是玻璃）。
///
/// 尺寸取 v6 设计稿的 34 高：设计稿的顶栏是 60，搜索框在里面居中且不顶满，
/// 上下各留 13 才不憋。玻璃胶囊自己有 `kGlassMinTapTarget`（44×44）的下限，
/// 所以整条胶囊仍是 44 高 —— 34 是里面那层圆角面的高度，差出来的 10px 留在
/// 槽位里当上下留白，视觉上就是设计稿那条细胶囊。
class _HomeSearchField extends StatelessWidget {
  const _HomeSearchField({
    required this.controller,
    required this.focusNode,
    required this.onTap,
    required this.onSubmitted,
    required this.onClear,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onTap;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return SizedBox(
      // 设计稿 searchBox：316×34、圆角 12、底色 #EDEDF2、**无描边**。
      // 以导出图为准：就是一块浅灰底，靠底色和页面底 (#F4F4F7) 的细微差别区分，
      // 不加边框（加边会显得比设计稿重）。
      height: AppDesignTokens.searchBoxHeight,
      width: double.infinity,
      child: Listener(
        onPointerDown: (_) => onTap(),
        child: TextField(
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          onSubmitted: onSubmitted,
          style: TextStyle(fontSize: 13, color: AppDesignTokens.inkOf(context)),
          decoration: InputDecoration(
            isDense: true,
            hintText: l10n.searchHint,
            hintStyle: const TextStyle(
              fontSize: 13,
              color: AppDesignTokens.fieldHint,
            ),
            filled: true,
            fillColor: AppDesignTokens.fieldFillOf(context),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            prefixIcon: const Icon(
              Symbols.search_rounded,
              size: 18,
              color: AppDesignTokens.fieldHint,
            ),
            prefixIconConstraints: const BoxConstraints(
              minWidth: 34,
              minHeight: 34,
            ),
            suffixIcon: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ValueListenableBuilder<TextEditingValue>(
                  valueListenable: controller,
                  builder: (context, value, _) => value.text.isEmpty
                      ? const SizedBox.shrink()
                      : PressScale(
                          child: IconButton(
                            visualDensity: VisualDensity.compact,
                            iconSize: 16,
                            onPressed: onClear,
                            icon: const Icon(Symbols.close_rounded),
                          ),
                        ),
                ),
                // 这里**不再**放第二个放大镜：设计稿的搜索框里只有左边一个
                // 放大镜 + 一段占位文字（导出图实测框内暗色元素只有 x846~852 的
                // 图标和 x870 起的文字）。右边再来一个，框里就有两个放大镜。
                const SizedBox(width: 8),
              ],
            ),
            suffixIconConstraints: const BoxConstraints(minHeight: 34),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: const BorderSide(
                color: AppDesignTokens.accent,
                width: 1.4,
              ),
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
  const _CategorySelector({
    required this.sections,
    required this.indexes,
    required this.index,
    required this.onSelected,
  });

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
            leadingIcon: Icon(
              index == widget.index
                  ? Symbols.check_rounded
                  : Symbols.label_rounded,
              size: 18,
            ),
            child: Text(widget.sections[index].title),
          ),
      ],
      builder: (context, controller, child) => PressScale(
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      section.title,
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        // 设计稿：分类下拉「最新上市」是粉色加粗强调色（不是墨色），
                        // 和它下方那条粉色下划线一起，表明它是当前分类的入口。
                        color: AppDesignTokens.accentDeep,
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Symbols.keyboard_arrow_down_rounded,
                      size: 20,
                      color: AppDesignTokens.accentDeep,
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // 设计稿 tabUnderline：分类下拉正下方一条 73×3 的粉色下划线。
                Container(
                  height: 3,
                  width: 73,
                  decoration: BoxDecoration(
                    color: AppDesignTokens.accent,
                    borderRadius: BorderRadius.circular(AppRadius.xs),
                  ),
                ),
              ],
            ),
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
String localizedHomeSectionTitle(
  HomeSection section,
  SearchOptionCatalog? catalog,
  String locale, {
  AppLocalizations? l10n,
}) {
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
  final subscribedAuthor =
      video.artist != null && subscribed.contains(video.artist!.toLowerCase());
  if (!(settings.exemptSubscribedAuthors && subscribedAuthor)) {
    if (settings.blockedVideoTitleKeywords.any(
      (keyword) => video.title.toLowerCase().contains(keyword.toLowerCase()),
    )) {
      return false;
    }
    if (settings.blockedAuthors.any(
      (author) =>
          (video.artist ?? '').toLowerCase().contains(author.toLowerCase()),
    )) {
      return false;
    }
    if (settings.blockedVideoTags.any(
      (blockedTag) => video.tags.any(
        (tag) => tag.toLowerCase().contains(blockedTag.toLowerCase()),
      ),
    )) {
      return false;
    }
    // 站点没给时长/播放量时按「未知」处理，不参与过滤：按 0 判会把 AV 源的卡片整页
    // 滤光（它们本来就不带这些字段），表现是「搜索结果永远为空」。
    final seconds = videoDurationSeconds(video.duration);
    if (seconds != null && seconds < settings.minimumVideoDurationSeconds) {
      return false;
    }
    final views = videoViews(video.views);
    if (views != null && views < settings.minimumVideoViews) return false;
  }
  return true;
}

class _HomeScroll extends ConsumerStatefulWidget {
  const _HomeScroll({required this.featured, required this.sections});
  final List<VideoCard> featured;
  final List<HomeSection> sections;

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
    if (!listEquals(
      oldWidget.featured.map((video) => video.coverUrl).toList(),
      widget.featured.map((video) => video.coverUrl).toList(),
    )) {
      _prefetchFeatured();
    }
  }

  /// 首屏推荐位是一张大图（`memCacheWidth: 1280`），不预热的话刷新后第一眼就是一个大灰块。
  /// 轮播里的每一张都要预热，翻页时才不会白一下。
  void _prefetchFeatured() {
    final urls = [
      for (final video in widget.featured) video.coverUrl,
    ].where((url) => url.isNotEmpty).toList();
    if (urls.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final url in urls) {
        unawaited(precacheCover(url, 1280, context));
      }
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
          if (widget
              .featured
              .isNotEmpty) // banner 的左右边距跟网格同一条线（`_gridPadding`），上下留白全部交给
            // _FeaturedCarousel 自己的 Padding 管：这里再叠一层 4/12 会让 banner
            // 离顶栏、离「影片」标题各多出一小截，整片内容被往下推。
            SliverToBoxAdapter(
              child: RepaintBoundary(child: _CinemaHero(videos: widget.featured)),
            ),
          if ((ref.watch(watchProvider).valueOrNull?.continueItems ?? const [])
              .isNotEmpty)
            SliverToBoxAdapter(
              child: _CinemaRail(
                title: '继续观看',
                items: [
                  for (final item
                      in ref.watch(watchProvider).valueOrNull!.continueItems)
                    _RailItem(
                      id: item.videoCode,
                      title: item.title,
                      coverUrl: item.coverUrl,
                      progress: item.durationMs > 0
                          ? (item.positionMs / item.durationMs).clamp(0.0, 1.0)
                          : null,
                    ),
                ],
              ),
            ),
          // Weebox 式：每个分区一行横向海报 rail（取代原来的纵向无限网格）；
          // 第一行带排名徽章（对应「热门前十」）。
          for (var i = 0; i < widget.sections.length; i++)
            if (widget.sections[i].videos.isNotEmpty)
              SliverToBoxAdapter(
                child: _CinemaRail(
                  ranked: i == 0,
                  title: widget.sections[i].title.isEmpty
                      ? '影片'
                      : widget.sections[i].title,
                  items: [
                    for (final video in widget.sections[i].videos)
                      _RailItem(
                        id: video.id,
                        title: video.title,
                        coverUrl: video.coverUrl,
                      ),
                  ],
                ),
              ),
          // 末尾净空：右下角浮动的刷新 / 回到顶部不占列，得在这里把高度让出来
          // （见 `floatingActionsClearance`），再叠加系统安全区。
          SliverToBoxAdapter(
            child: SizedBox(
              height:
                  floatingActionsClearance +
                  MediaQuery.paddingOf(context).bottom,
            ),
          ),
        ],
      ),
      Positioned(
        right: 0,
        bottom: 0,
        // 刷新失败要被看见：`ScrollActions` 自己只负责转圈，异常得在这里接住
        // 弹成提示，否则「点了刷新没反应」会变成用户眼里的卡死。
        child: ScrollActions(
          controller: _controller,
          onRefresh: _refreshAll,
          onError: (error) => showAppErrorBar(
            context,
            error,
            onRetry: () => unawaited(_refreshAll()),
          ),
        ),
      ),
    ],
  );
}

/// 切分区会重建对应的 `_HomeSection`（第一页来自带缓存的 feed），但滚动累积的分页
/// 会随 State 一起消失，切回来就得逐页重新加载。这里按「更多链接」把分页记在进程内。
final _sectionPageCache =
    <String, ({List<VideoCard> videos, int page, int? totalPages})>{};

class _HomeSection extends ConsumerStatefulWidget {
  const _HomeSection({required this.section});

  final HomeSection section;

  @override
  ConsumerState<_HomeSection> createState() => _HomeSectionState();
}

class _HomeSectionState extends ConsumerState<_HomeSection> {
  late List<VideoCard> _videos = widget.section.videos;
  var _page = 1;
  int? _totalPages;
  var _loading = false;
  var _failed = false;

  /// 排序：0=综合（默认顺序），1=最新（按上传时间），2=热门（按播放量）。
  var _sortIndex = 0;
  var _lastAttempt = DateTime.fromMillisecondsSinceEpoch(0);
  var _retryDelay = Duration.zero;

  /// 每次「换分区 / 刷新」都会自增。切分区时这个 State 是被复用的，而上一分区的分页
  /// 请求还在飞 —— 不作废它的话，它回来会 setState 把旧分区的数据追加进新分区（表现为
  /// 「切分区后有概率混进别的分区的影片」），而且随后还会以新分区的 key 写进分页缓存，
  /// 把污染固化下来（切换几次都还在）。
  var _generation = 0;

  /// 上一次重接分页时所在的站点，用来识别 [didUpdateWidget] 里的「换了站点」。
  String? _siteKey;

  /// 正在请求中的页码。用来**挡住重复的同一页请求**。
  ///
  /// 为什么不能只靠 [_loading]：`_LoadMoreProbe` 在每次 `didUpdateWidget` 时都会
  /// 试探一次，而父级一个 store 更新就会重建它好几次 —— 实测同一次启动里
  /// 「page 2」被打了三遍（17:20:54 / 55 / 59），三份结果内容一模一样，白白多花
  /// 两三倍的等待时间，也更容易把站点打到限流。
  ///
  /// `_loading` 只能表达「有没有请求在飞」，表达不了「飞的是哪一页」：第一页的请求
  /// 还没回来时，probe 又要求第 2 页，这是合理的，不该被 `_loading` 挡掉。
  final _inFlightPages = <int>{};

  /// Unknown until the first extra page comes back, so the first probe always
  /// gets a chance to ask for it.
  bool get _hasMore =>
      widget.section.moreUrl != null &&
      (_totalPages == null || _page < _totalPages!);

  @override
  void initState() {
    super.initState();
    _restorePages();
    // 右下角刷新与下拉刷新都会自增这个令牌：丢掉滚动时累积的分页，从第一页重新开始。
    ref.listenManual(
      homeRefreshTokenProvider,
      (previous, next) => _reloadFromFirstPage(),
    );
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
    final changed =
        siteChanged ||
        oldWidget.section.moreUrl != widget.section.moreUrl ||
        oldWidget.section.videos.firstOrNull?.id !=
            widget.section.videos.firstOrNull?.id;
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
  String get _cacheKey =>
      '$_site|${widget.section.moreUrl ?? widget.section.title}';

  /// 接上本分区之前加载过的分页；没有缓存时回到「只有第一页」的状态。
  void _restorePages() {
    // 作废上一分区还在飞的请求，并把它的 loading 占用放掉 —— 否则新分区的补抓
    // （[_loadFirstPageIfNeeded] 里的 `_loading` 判断）会被这个旧占用挡掉。
    _generation++;
    _loading = false;
    // 旧分区的在途页码也要清掉：不清的话新分区请求同一页码会被当成「重复」挡回去，
    // 表现为切分区后那一页永远加载不出来。
    _inFlightPages.clear();
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
    // 刷新后要重新抓第一页，旧的在途页码不能再挡着。
    _inFlightPages.clear();
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
    if (_videos.isNotEmpty || _loading || widget.section.moreUrl == null) {
      return;
    }
    await _fetchPage(1, replace: true);
  }

  Future<void> _fetchPage(int page, {bool replace = false}) async {
    final moreUrl = widget.section.moreUrl;
    if (_loading || moreUrl == null) return;
    if (!replace && !_hasMore) return;
    // 同一页正在请求中就直接返回：`_LoadMoreProbe` 会在父级每次重建时再问一遍，
    // 不挡的话同一次启动里同页码会被请求 2~3 次（实测 `page 2` 打了三遍），
    // 既拖慢首屏也让站点更容易限流。
    if (_inFlightPages.contains(page)) return;
    // 已经有更靠后的页在飞时，也不必再请求这一页：它回来时会一并补上。
    if (!replace && _inFlightPages.any((pending) => pending > page)) return;
    // 上次失败后先退避一小会儿：probe 每次被重建都会来问一次，不能立刻打爆站点。
    if (DateTime.now().difference(_lastAttempt) < _retryDelay) return;
    final generation = _generation;
    _lastAttempt = DateTime.now();
    _inFlightPages.add(page);
    setState(() {
      _loading = true;
      _failed = false;
    });
    try {
      final settings = await ref.read(settingsProvider.future);
      final query = SearchQuery.fromUri(moreUrl);
      final result = await ref
          .read(han1meRepositoryProvider)
          .search(
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
      final subscribed =
          ref
              .read(libraryProvider)
              .valueOrNull
              ?.artists
              .map((artist) => artist.name.toLowerCase())
              .toSet() ??
          <String>{};
      final current = ref.read(settingsProvider).valueOrNull;
      final known = replace
          ? const <String>{}
          : _videos.map((video) => video.id).toSet();
      final extra = result.items
          .where(
            (video) =>
                !known.contains(video.id) &&
                _visible(video, current, subscribed),
          )
          .toList();
      debugPrint(
        '[home] ${widget.section.title}: page ${result.page}/${result.totalPages}, +${extra.length}',
      );
      setState(() {
        _videos = replace ? extra : [..._videos, ...extra];
        _page = result.page;
        _totalPages = result.totalPages;
      });
      _sectionPageCache[_cacheKey] = (
        videos: _videos,
        page: _page,
        totalPages: _totalPages,
      );
      _retryDelay = Duration.zero;
      // 刚拿到的这一批先预热封面，滚过去时就不会先看到一片灰。
      unawaited(_prefetch(extra));
    } catch (error) {
      debugPrint('[home] load failed: $error');
      // 过期的失败也不该记到新分区头上（否则新分区会莫名其妙地显示「重试」）。
      if (generation != _generation) return;
      final seconds = _retryDelay == Duration.zero
          ? 2
          : _retryDelay.inSeconds * 2;
      _retryDelay = Duration(seconds: seconds > 30 ? 30 : seconds);
      if (mounted) setState(() => _failed = true);
    } finally {
      // 无论成功失败都要把页码从「在途」里摘掉，否则那一页以后再也请求不了。
      _inFlightPages.remove(page);
      // 过期请求不能动 _loading：它已经归新分区的请求管了。
      if (generation == _generation && mounted) {
        setState(() => _loading = false);
      }
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
    final cacheWidth = videoCardCacheWidth(
      homeWaterfallCardWidth(width, columns),
      MediaQuery.devicePixelRatioOf(context),
    );
    final targets = (videos ?? _videos)
        .take(columns * 6)
        .where((video) => video.coverUrl.isNotEmpty)
        .toList(growable: false);
    // 并发预热，而不是「6 张一批、等这批全完再下一批」。
    //
    // 原来是串行的：每批 `await Future.wait` 完才发下一批。首屏要预热
    // `columns * 6` 张（4 列就是 24 张），每张 0.3–5s，串行最坏要等 4×5 = 20 秒 ——
    // 这期间滚动下去看到的全是灰块，用户感受到的就是「加载特别慢」。
    //
    // 现在一次全部发出，但用信号量把并发压到 [_coverFetchConcurrency]：
    // 并发太高会和站点互相争带宽、也更容易触发握手失败（实测过），
    // 这个值取 8 —— 既比原来的 6 张一批快得多，又不至于打爆。
    final gate = _AsyncGate(_coverFetchConcurrency);
    await Future.wait([
      for (final video in targets)
        () async {
          await gate.enter();
          try {
            // 排队期间页面可能已经被销毁，此时 `State.context` 已失效，直接跳过预热。
            if (!mounted) return;
            final coverContext = context;
            if (!coverContext.mounted) return;
            await precacheCover(video.coverUrl, cacheWidth, coverContext);
          } finally {
            gate.leave();
          }
        }(),
    ]);
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
    if (javSiteFor(ref.read(settingsProvider).valueOrNull?.homeBaseUrl) !=
        null) {
      return;
    }
    final targets = videos
        .take(homeWaterfallColumns(_viewportWidth) * 4)
        .where((video) => video.id.isNotEmpty && !hasVideoCardMeta(video))
        .toList(growable: false);
    if (targets.isEmpty) return;
    await Future.wait([
      for (final video in targets)
        ref
            .read(videoCardMetaProvider(video.id).future)
            .then<VideoCard?>(
              (value) => value,
              onError: (Object _, StackTrace __) => null,
            ),
    ]);
  }

  Future<void> _filterByTags() async {
    final settings = ref.read(settingsProvider).valueOrNull;
    if (settings == null ||
        settings.blockedVideoTags.isEmpty ||
        _videos.isEmpty) {
      return;
    }
    final targets = _videos
        .where((video) => video.id.isNotEmpty)
        .take(homeWaterfallColumns(_viewportWidth) * 6)
        .toList(growable: false);
    final cache = ref.read(videoMetaCacheProvider);
    final repository = ref.read(han1meRepositoryProvider);
    await Future.wait([
      for (final video in targets)
        if (cache.read(video.id)?.tags.isNotEmpty != true)
          repository
              .video(settings.resolvedBaseUrl, video.id)
              .then((detail) async {
                await cache.put(
                  VideoCard(
                    id: video.id,
                    title: video.title,
                    // 和 VideoCard._mergeMeta 保持一致：封面只认列表页给的那张，
                    // 否则这条缓存会让卡片下次命中时又换一次图。
                    coverUrl: video.coverUrl.isNotEmpty
                        ? video.coverUrl
                        : (detail.coverUrl ?? ''),
                    duration: detail.duration ?? video.duration,
                    views: detail.views ?? video.views,
                    rating: detail.rating ?? video.rating,
                    artist: detail.artist ?? video.artist,
                    uploadTime: detail.uploadDate ?? video.uploadTime,
                    tags: detail.tags
                        .map((tag) => tag.name)
                        .where((tag) => tag.isNotEmpty)
                        .toList(growable: false),
                  ),
                );
              })
              .catchError((_) {}),
    ]);
    if (!mounted) return;
    final blocked =
        ref.read(settingsProvider).valueOrNull?.blockedVideoTags ??
        const <String>[];
    if (blocked.isEmpty) return;
    final filtered = _videos
        .where((video) {
          final meta = cache.read(video.id);
          final tags = meta?.tags ?? video.tags;
          return !blocked.any(
            (blockedTag) => tags.any(
              (tag) => tag.toLowerCase().contains(blockedTag.toLowerCase()),
            ),
          );
        })
        .toList(growable: false);
    if (filtered.length == _videos.length) return;
    setState(() => _videos = filtered);
  }

  /// 当前排序后的列表（不改动分页累积的原始顺序）。
  List<VideoCard> get _sortedVideos {
    final list = [..._videos];
    switch (_sortIndex) {
      case 1:
        list.sort((a, b) => (b.uploadTime ?? '').compareTo(a.uploadTime ?? ''));
      case 2:
        list.sort(
          (a, b) => _parseViews(b.views).compareTo(_parseViews(a.views)),
        );
    }
    return list;
  }

  /// 把「8.8万次」「6288次」这类播放量解析成数字，用于热门排序。
  static double _parseViews(String? raw) {
    if (raw == null) return 0;
    final match = RegExp(r'([\d.]+)\s*(万)?').firstMatch(raw);
    if (match == null) return 0;
    var value = double.tryParse(match.group(1)!) ?? 0;
    if (match.group(2) == '万') value *= 10000;
    return value;
  }

  @override
  Widget build(BuildContext context) {
    // 列数必须按**内容区实际宽度**算，不能按窗口宽。
    //
    // 首页在 AppShell 里，左边还有 176 常驻侧栏；`MediaQuery.sizeOf(context).width`
    // 拿到的是整个窗口宽，用它算出来的列数每多一列，右边就多挤掉一截 ——
    // 表现是最右一列被窗口边缘裁掉。`SliverLayoutBuilder` 的 crossAxisExtent
    // 就是这一格的真实可用宽度。
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = homeWaterfallColumns(width);
        final hasMore = _hasMore;
        final cardWidth = homeWaterfallCardWidth(width, columns);
        final videos = _sortedVideos;
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: _SectionHeader(
                title: '影片',
                count: videos.length,
                sortIndex: _sortIndex,
                onSort: (value) => setState(() => _sortIndex = value),
              ),
            ),
            SliverPadding(
              // 上边 18：设计稿里「影片」标题的字底到第一排卡片顶还有 31，
              // 标题行本身（高 48、文字垂直居中）只吃掉了 13，剩下这 18 补在这里。
              padding: const EdgeInsets.fromLTRB(
                _gridPadding,
                9,
                _gridPadding,
                20,
              ),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  // 设计稿的行距比列距大：卡片下面是两行文字（标题 + 元信息），
                  // 行距跟列距一样时，上一行的元信息行会贴到下一行的封面上。
                  mainAxisSpacing: _gridRowSpacing,
                  crossAxisSpacing: _gridSpacing,
                  // 封面照设计稿的 16:9（244×137），下面文字区只留**一行标题 + 一行元信息**。
                  //
                  // 原来这里硬编码 `+ 42`（照「标题 14 + 间隙 + 作者行 10」估的），比实际
                  // 需要的少 6px —— 封面是按 16:9 定高的，卡高不够时多出来的那几像素只能
                  // 从封面上裁，于是封面被压扁成 240×128（1.88:1），比设计稿更扁。
                  // 现在用 `videoCardMetaHeight` 统一给出文字区高度，和 `VideoCardTile`
                  // 里的排版保持一致，两边不会再各算一套。
                  mainAxisExtent:
                      cardWidth / 0.68 +
                      videoCardMetaHeight(videos, assumeMeta: true),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => index == videos.length - 1 && hasMore
                      ? _LoadMoreProbe(
                          onProbe: _loadMore,
                          child: VideoCardTile(
                            video: videos[index],
                            horizontal: true,
                            coverAspectRatio: 0.68,
                            autoFetchMeta: true,
                          ),
                        )
                      : VideoCardTile(
                          video: videos[index],
                          horizontal: true,
                          coverAspectRatio: 0.68,
                          autoFetchMeta: true,
                        ),
                  childCount: videos.length,
                ),
              ),
            ),
            if (hasMore)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 24),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 24,
                            height: 24,
                            child: CircularProgressIndicator(strokeWidth: 2.5),
                          )
                        : _failed
                        ? PressScale(
                            child: TextButton.icon(
                              onPressed: () => unawaited(_retry()),
                              icon: const Icon(
                                Symbols.refresh_rounded,
                                size: 18,
                              ),
                              label: Text(AppLocalizations.of(context)!.retry),
                            ),
                          )
                        : const SizedBox(height: 24),
                  ),
                ),
              ),
          ],
        );
      },
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

/// 首页分区的标题行（半粗标题 + 右侧「换一批」）已随「首页使用收起式分类」开关一起删除：
/// 首页现在固定只画当前分类，分区名由顶栏那个下拉菜单承担，页面上不再有第二处标题。
/// 首页顶部的大卡片。比例和文字层按 AniBaka 首页横幅（`swiper_banner.dart`）来：
/// 宽扁的 16:6、左下角斜体粗标题压一条底部暗渐变，而不是原先固定 320 高 +
/// 整块压黑 + 常规字号 —— 整块压黑会把封面盖掉大半，只有底部渐变压暗时
/// 图看得清、字又压得住。
/// 首屏推荐位。只有一条时不带轮播控件，多条时给出自动轮播、左右按钮与下方指示点。
// ignore: unused_element
class _FeaturedCarousel extends StatelessWidget {
  const _FeaturedCarousel({required this.videos});

  final List<VideoCard> videos;

  /// 比例照 v6 设计稿的 banner：1048×200，也就是约 5.25:1。
  ///
  /// 关键是**铺满内容区**，左右只留常规边距，不再设宽度上限居中 ——
  /// 两侧留白一多，整块就变成居中一块窄卡片，跟下面一列列卡片对不齐。
  /// 宽度随窗口走，高度按比例跟出来，只留一道「别把首屏吃掉」的视口高度保险。
  static const double _ratio = 0.36; // 影院版把 5.25:1 的扁 banner 放大到约 2.8:1；再高会触发视口高度上限、hero 反而缩窄，和网格对不齐。
  static const double _minHeight = 120;
  static const double _maxViewportShare = 0.55;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final desktop = constraints.maxWidth >= 700;
      // banner 的左边缘要和下面的卡片网格对齐：网格的左右边距是 `_gridPadding`（16），
      // 内边距再各自加 24 的话 banner 会比一整列卡片缩进 8px，右侧短出去一截。
      // 外边距统一交给外层 Padding，这里只负责比例与居中。
      final maxHeight = math.max(
        MediaQuery.sizeOf(context).height * _maxViewportShare,
        _minHeight,
      );
      var width = constraints.maxWidth;
      var height = width * _ratio;
      // 窗口很矮时高度顶到视口上限，宽度按同一比例缩回来，比例始终不变。
      if (height > maxHeight) {
        height = maxHeight;
        width = height / _ratio;
      }
      return Padding(
        padding: EdgeInsets.only(top: desktop ? 0 : 4, bottom: 13),
        child: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: width,
            height: height,
            child: _FeaturedSwiper(videos: videos),
          ),
        ),
      );
    },
  );
}

/// 多条推荐位的轮播：底部压一层渐变，左下是标题与作者，右下是左右按钮，最下面一排指示点。
class _FeaturedSwiper extends StatefulWidget {
  const _FeaturedSwiper({required this.videos});

  final List<VideoCard> videos;

  @override
  State<_FeaturedSwiper> createState() => _FeaturedSwiperState();
}

class _FeaturedSwiperState extends State<_FeaturedSwiper> {
  /// 自动翻页间隔。抄 AniBaka 的 6 秒，用户手动翻过之后重新计时。
  static const Duration _interval = Duration(seconds: 6);

  /// 翻页动画时长与曲线，抄 AniBaka：fastOutSlowIn。
  ///
  /// 时长原先写 600，现在走 [AppMotion.page]（400）—— 600ms 配着背景图一起动
  /// 显得拖沓，400 更跟手。曲线保留 `Curves.fastOutSlowIn`（Material 2014 标准曲线），
  /// 它与 M3 的 `emphasizedDecelerate` 起始斜率不同，抄来的手感就是它。
  static const Duration _slide = AppMotion.page;
  static const Curve _slideCurve = Curves.fastOutSlowIn;

  /// 标题交叉切换。Baka 是 400ms，画面滑得慢、字换得快，读起来才跟得上。
  static const Duration _titleSwap = AppMotion.page;

  /// 无限循环靠「起始页放在很后面」实现：PageView 的负方向有尽头，
  /// 从第 0 页开始就没法往回翻，所以从第 1000 圈起步，两边都够滑。
  late final PageController _controller = PageController(
    initialPage: widget.videos.length > 1 ? widget.videos.length * 1000 : 0,
  );
  final ValueNotifier<int> _index = ValueNotifier<int>(0);
  Timer? _timer;

  /// 手指按在轮播上时暂停自动翻页，否则想拖的时候它正自己滑走。
  bool _interacting = false;

  int get _count => widget.videos.length;

  @override
  void initState() {
    super.initState();
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    _index.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer.periodic(_interval, (_) => _advance(1));
  }

  /// 翻到相邻一条。首尾相接，所以「上一张」在第一条上也能落脚。
  void _advance(int delta) {
    if (!mounted || _interacting) return;
    _restartTimer();
    if (!_controller.hasClients) return;
    // 首页自己往上滚走了就不再自动翻，回到顶部由用户重新触发。
    final sliver = context.findAncestorRenderObjectOfType<RenderSliver>();
    if (sliver?.geometry?.visible != true) return;
    final current = _controller.page?.round() ?? 0;
    _controller.animateToPage(
      current + delta,
      duration: _slide,
      curve: _slideCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _count;
    return Listener(
      onPointerDown: (_) {
        _interacting = true;
        _timer?.cancel();
      },
      onPointerUp: (_) {
        _interacting = false;
        _restartTimer();
      },
      onPointerCancel: (_) {
        _interacting = false;
        _restartTimer();
      },
      // 结构照 AniBaka 的 swiper_banner.dart：轮播本体铺满整个画框，
      // 圆角与裁切交给外层 ClipRRect —— 图在框里横向推入，框本身一动不动，
      // 所以看不到「连圆角一起滑走」。
      child: ClipRRect(
        borderRadius: AppRadius.all(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 用 PageView 而不是 CarouselView：Material 3 的轮播在滚动过半时
            // 会把当前页压成半宽给下一页腾地方（_RenderSliverFixedExtentCarousel
            // 的 effectiveMinExtent 就是剩余绘制宽度），全屏时两页并排各占一半，
            // 看着像两张图同时贴在一个画框里。PageView 是纯位移，一页就是一整屏。
            PageView.builder(
              controller: _controller,
              // itemCount 传 null 即无限：index 取模落回真实条目。
              itemCount: total > 1 ? null : total,
              onPageChanged: (index) => _index.value = index % total,
              itemBuilder: (context, index) => _FeaturedVideoSurface(
                key: ValueKey<int>(index % total),
                video: widget.videos[index % total],
              ),
            ),
            // 底部暗渐变。放在轮播外面，翻页时它不动 —— 跟着动会在卡片
            // 边缘抖出一条亮边。
            const Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 120,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x00000000), Color(0xD9000000)],
                    ),
                  ),
                ),
              ),
            ),
            // 标题与指示点同一行（Baka 就是这么排的）：标题换页时自己淡入上滑，
            // 指示点跟着当前页变长，右侧是左右按钮。
            Positioned(
              left: 20,
              right: 14,
              bottom: 12,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: IgnorePointer(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _index,
                        builder: (context, index, _) => _FeaturedCaption(
                          video: widget.videos[index % total],
                          duration: _titleSwap,
                        ),
                      ),
                    ),
                  ),
                  // 只有一条时不画轮播控件：没得翻，画出来只是噪声。
                  if (total > 1) ...[
                    const SizedBox(width: 16),
                    IgnorePointer(
                      child: ValueListenableBuilder<int>(
                        valueListenable: _index,
                        builder: (context, index, _) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            for (var i = 0; i < total; i++)
                              AnimatedContainer(
                                duration: AppMotion.dialog,
                                curve: Curves.easeOutQuart,
                                margin: const EdgeInsets.only(
                                  left: 4,
                                  bottom: 8,
                                ),
                                height: 4,
                                width: i == index ? 18 : 6,
                                decoration: BoxDecoration(
                                  color: i == index
                                      ? theme.colorScheme.primary
                                      : Colors.white.withValues(alpha: .4),
                                  borderRadius: BorderRadius.circular(AppRadius.xs),
                                  boxShadow: i == index
                                      ? [
                                          BoxShadow(
                                            color: theme.colorScheme.primary
                                                .withValues(alpha: .5),
                                            blurRadius: 8,
                                            spreadRadius: 1,
                                          ),
                                        ]
                                      : null,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _SwiperButton(
                          icon: Symbols.chevron_left_rounded,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).previousPageTooltip,
                          onTap: () => _advance(-1),
                        ),
                        const SizedBox(width: 8),
                        _SwiperButton(
                          icon: Symbols.chevron_right_rounded,
                          tooltip: MaterialLocalizations.of(
                            context,
                          ).nextPageTooltip,
                          onTap: () => _advance(1),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
            Positioned(
              left: 16,
              top: 16,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
                child: Text(
                  'NEW · 里番',
                  style: TextStyle(
                    color: theme.colorScheme.onPrimary,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 轮播上的圆形翻页按钮。
class _SwiperButton extends StatelessWidget {
  const _SwiperButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => PressScale(
    child: Material(
      color: Colors.black.withValues(alpha: .38),
      shape: const CircleBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Tooltip(
          message: tooltip,
          child: SizedBox(
            width: 34,
            height: 34,
            child: Icon(icon, size: 20, color: Colors.white),
          ),
        ),
      ),
    ),
  );
}

/// 推荐位里的一屏画面：只有封面，点了就播。
///
/// 标题、作者、指示点、按钮都在轮播外面单独叠着（见 `_FeaturedSwiperState.build`），
/// 这样翻页时只有封面在动，标题自己走 `AnimatedSwitcher` 淡入上滑 ——
/// 和 AniBaka 的横幅一个分工。
class _FeaturedVideoSurface extends ConsumerWidget {
  const _FeaturedVideoSurface({super.key, required this.video});

  final VideoCard video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cover = Theme.of(context).colorScheme.surfaceContainerHighest;
    return PressScale(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: AppRadius.all(AppRadius.md),
          // 统一入口：Windows 上按设置弹出独立播放窗口，其余平台窗口内跳转。
          onTap: video.id.isEmpty
              ? null
              : () => openVideo(context, ref, video.id),
          child: AppCachedNetworkImage(
            imageUrl: video.coverUrl,
            fit: BoxFit.cover,
            memCacheWidth: 1280,
            // 横幅是 5:1 的宽扁条，一张普通封面铺进来只剩中间三成高度。
            // 这时候再按人脸对齐，等于把镜头钉死在脸上：五官被放大到撑满整条，
            // 没人脸时走的「顶部兜底」更糟 —— 只取到最上面一条头发和背景。
            // 所以横幅统一居中裁切，人脸取景只留给下面的卡片。
            fadeInDuration: Duration.zero,
            errorWidget: (_, __, ___) => ColoredBox(color: cover),
          ),
        ),
      ),
    );
  }
}

/// 轮播左下角的标题与作者信息。
///
/// 单独抽出来是因为它用 `AnimatedSwitcher` 只换文字：翻页时新字从下方 30% 处
/// 淡入上滑、旧字淡出，而不是整块跟着封面一起推走。
class _FeaturedCaption extends StatelessWidget {
  const _FeaturedCaption({required this.video, required this.duration});

  final VideoCard video;
  final Duration duration;

  /// 标题样式抄 AniBaka：斜体、特粗、带投影 —— 卡片里压着图，不投影糊在亮画面上就散。
  static const TextStyle _titleStyle = TextStyle(
    color: Colors.white,
    fontSize: 22,
    height: 1.2,
    fontWeight: FontWeight.w900,
    fontStyle: FontStyle.italic,
    letterSpacing: 0.5,
    shadows: [
      Shadow(color: Colors.black87, blurRadius: 8, offset: Offset(0, 2)),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final meta = [video.artist, video.views]
        .whereType<String>()
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .join(' • ');
    return AnimatedSwitcher(
      duration: duration,
      switchInCurve: AppMotion.settle,
      switchOutCurve: AppMotion.unsettle,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.3),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      // 默认布局是 Stack(alignment: center)，会把这块左对齐的标题拽到卡片正中；
      // 靠左下角对齐，换标题时新旧两份也叠在同一处。
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: AlignmentDirectional.bottomStart,
        children: <Widget>[
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      // 用条目本身当 key：换到另一条才触发切换，同一条重绘不重置动画。
      child: Column(
        key: ObjectKey(video),
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            video.title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: _titleStyle,
          ),
          if (meta.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 分区标题行：「影片 共 N 部」+ 排序（综合 / 最新 / 热门）。
/// 注：该行在 SliverToBoxAdapter 里，右侧 Spacer/Expanded/Positioned 都可能不渲染，
/// 所以排序按钮紧跟标题之后排列。
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.count,
    required this.sortIndex,
    required this.onSort,
  });

  final String title;
  final int count;
  final int sortIndex;
  final ValueChanged<int> onSort;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // 排序胶囊组按设计稿手搓，而不是用 ChoiceChip：
    // 设计稿是一整条 132×28 的灰底胶囊（#EDEDF2、圆角 pill），里面三格等分，
    // 选中那一格是一块 48×20 的白底小胶囊（圆角 8）。ChoiceChip 自带描边与
    // 选中勾，样式收不回来，叠几层 Theme 也压不掉它的间距。
    Widget sortPill(int i, String label) {
      final selected = sortIndex == i;
      return GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSort(i),
        child: Container(
          width: 48,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? AppDesignTokens.surfaceOf(context) : Colors.transparent,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
          child: Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              fontSize: 11,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              color: selected
                  ? AppDesignTokens.inkOf(context)
                  : AppDesignTokens.inkSubtleOf(context),
            ),
          ),
        ),
      );
    }

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
      child: Row(
        children: [
          // 设计稿的分区标题是 22 号粗体，计数 13 号灰字并与标题**基线**对齐
          // （不是顶端对齐）：22 与 13 的字形高度差一半，顶端对齐时计数会贴着
          // 标题的上缘，看起来像浮在标题外面。
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontSize: AppDesignTokens.sectionTitleSize,
              fontWeight: FontWeight.w700,
              color: AppDesignTokens.inkOf(context),
            ),
          ),
          const SizedBox(width: 8),
          // 计数用「居中 + 下移 2」贴到标题的下缘，而不是 Baseline：
          // Baseline 的基线值一旦和 22 号标题的真实基线算不到一起，这一行就会
          // 整体偏上或偏下（原来 22*.78=17.16 明显偏小，计数看着比标题高半头）。
          // Row 交叉轴居中本身就够稳，再补 2 的微调就对上了设计稿。
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              '共 $count 部',
              style: theme.textTheme.bodySmall?.copyWith(
                fontSize: 13,
                color: AppDesignTokens.inkMutedOf(context),
              ),
            ),
          ),
          const Spacer(),
          Container(
            height: 28,
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: AppDesignTokens.fieldFillOf(context),
              borderRadius: BorderRadius.circular(AppRadius.pill),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                sortPill(0, '综合'),
                sortPill(1, '最新'),
                sortPill(2, '热门'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 封面预热的并发上限。
///
/// 取 8：图片站点单张 0.3–5s，并发太低会让首屏预热拖到十几秒，
/// 太高又会互相争带宽、握手失败率上升。8 是这两头之间的折中。
const _coverFetchConcurrency = 8;

/// 一个极简的计数信号量：限制同时进行的异步任务数。
///
/// [enter] 在额度用完时挂起，[leave] 唤醒最早一个等待者（FIFO，避免饿死）。
/// 只服务封面预热这一处，所以不追求通用性（不做超时、不做取消）。

/// 首页影院版一行横向海报的数据项。
class _RailItem {
  const _RailItem({
    required this.id,
    required this.title,
    required this.coverUrl,
    this.progress,
  });

  final String id;
  final String title;
  final String? coverUrl;

  /// 0..1，仅「继续观看」有进度。
  final double? progress;
}

/// 一行横向海报：热门行带 1..N 排名徽章，继续观看行带进度条。
class _CinemaRail extends StatelessWidget {
  const _CinemaRail({
    required this.title,
    required this.items,
    this.ranked = false,
  });

  final String title;
  final List<_RailItem> items;
  final bool ranked;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 26),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
            child: Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: AppDesignTokens.inkOf(context),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 300,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: _gridPadding),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 14),
              itemBuilder: (context, index) => _RailCard(
                item: items[index],
                rank: ranked ? index + 1 : null,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RailCard extends StatelessWidget {
  const _RailCard({required this.item, this.rank});

  final _RailItem item;
  final int? rank;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(AppRadius.md);
    return SizedBox(
      width: 176,
      child: PressScale(
        child: InkWell(
          borderRadius: radius,
          onTap: item.id.isEmpty ? null : () => context.push('/video/${item.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(
                    borderRadius: radius,
                    child: AspectRatio(
                      aspectRatio: 2 / 3,
                      child: AppCachedNetworkImage(
                        imageUrl: item.coverUrl ?? '',
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => ColoredBox(
                          color: AppDesignTokens.surfaceRaisedOf(context),
                        ),
                      ),
                    ),
                  ),
                  if (rank != null)
                    Positioned(top: 6, left: 6, child: _RankBadge(rank!)),
                  if (item.progress != null)
                    Positioned(
                      left: 6,
                      right: 6,
                      bottom: 6,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                        child: LinearProgressIndicator(
                          value: item.progress,
                          minHeight: 4,
                          backgroundColor: Colors.black.withValues(alpha: .45),
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                item.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: AppDesignTokens.inkOf(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 排名徽章：前三名金/银/铜，其余红。
class _RankBadge extends StatelessWidget {
  const _RankBadge(this.rank);

  final int rank;

  @override
  Widget build(BuildContext context) {
    final gradient = switch (rank) {
      1 => const LinearGradient(colors: [Color(0xFFFFD76E), Color(0xFFE0A326)]),
      2 => const LinearGradient(colors: [Color(0xFFE6ECF5), Color(0xFFA9B4C4)]),
      3 => const LinearGradient(colors: [Color(0xFFE6A978), Color(0xFFB9702F)]),
      _ => const LinearGradient(colors: [Color(0xFFFF5661), Color(0xFFC1121F)]),
    };
    final fg = rank <= 3 ? const Color(0xFF231A00) : Colors.white;
    return Container(
      width: 28,
      height: 28,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        gradient: gradient,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white70, width: 1.5),
      ),
      child: Text(
        '$rank',
        style: TextStyle(color: fg, fontSize: 13, fontWeight: FontWeight.w900),
      ),
    );
  }
}


/// 影院式 Hero（照 HTML 原型 v0.3）：封面强模糊做氛围底 + 深色渐变，
/// 上面只叠 大标题 / 元信息 / CTA / 左右箭头 / 分页点，不把真实大图直接铺满。
class _CinemaHero extends ConsumerStatefulWidget {
  const _CinemaHero({required this.videos});
  final List<VideoCard> videos;
  @override
  ConsumerState<_CinemaHero> createState() => _CinemaHeroState();
}

class _CinemaHeroState extends ConsumerState<_CinemaHero> {
  final PageController _controller = PageController();
  Timer? _timer;
  int _index = 0;

  int get _count => widget.videos.length;

  @override
  void initState() {
    super.initState();
    _restart();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _restart() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer.periodic(const Duration(seconds: 7), (_) {
      if (!mounted || !_controller.hasClients) return;
      _controller.animateToPage((_index + 1) % _count,
          duration: AppMotion.page, curve: AppMotion.standardCurve);
    });
  }

  void _go(int delta) {
    if (!_controller.hasClients || _count < 2) return;
    final next = (_index + delta) % _count;
    _controller.animateToPage(next < 0 ? next + _count : next,
        duration: AppMotion.page, curve: AppMotion.standardCurve);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.videos.isEmpty) return const SizedBox.shrink();
    final height = (MediaQuery.sizeOf(context).height * 0.62).clamp(420.0, 620.0);
    return SizedBox(
      height: height,
      child: Stack(
        children: [
          Positioned.fill(
            child: PageView.builder(
              controller: _controller,
              itemCount: _count,
              onPageChanged: (i) {
                setState(() => _index = i);
                _restart();
              },
              itemBuilder: (context, i) => _HeroPage(video: widget.videos[i]),
            ),
          ),
          if (_count > 1) ...[
            Positioned(
              left: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: _HeroArrow(
                    icon: Symbols.chevron_left_rounded, onTap: () => _go(-1)),
              ),
            ),
            Positioned(
              right: 18,
              top: 0,
              bottom: 0,
              child: Center(
                child: _HeroArrow(
                    icon: Symbols.chevron_right_rounded, onTap: () => _go(1)),
              ),
            ),
            Positioned(
              right: 44,
              bottom: 26,
              child: Row(
                children: [
                  for (var i = 0; i < _count; i++)
                    AnimatedContainer(
                      duration: AppMotion.brief,
                      margin: const EdgeInsets.only(left: 6),
                      height: 6,
                      width: i == _index ? 22 : 6,
                      decoration: BoxDecoration(
                        color: i == _index
                            ? AppDesignTokens.accentOf(context)
                            : Colors.white.withValues(alpha: .35),
                        borderRadius: BorderRadius.circular(AppRadius.xs),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _HeroPage extends ConsumerWidget {
  const _HeroPage({required this.video});
  final VideoCard video;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final meta = [
      if ((video.rating ?? '').isNotEmpty) '评分 ${video.rating}',
      if ((video.artist ?? '').isNotEmpty) video.artist!,
      if ((video.views ?? '').isNotEmpty) video.views!,
    ].join('   ·   ');
    return Stack(
      fit: StackFit.expand,
      children: [
        if (video.coverUrl.isNotEmpty)
          AppCachedNetworkImage(
            imageUrl: video.coverUrl,
            fit: BoxFit.cover,
            alignment: Alignment.topCenter,
            memCacheWidth: 1280,
            errorWidget: (c, u, e) => const ColoredBox(color: Color(0xFF14141A)),
          )
        else
          const ColoredBox(color: Color(0xFF14141A)),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [Color(0xF20A0A0D), Color(0xA60A0A0D), Color(0x140A0A0D)],
              ),
            ),
          ),
        ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Color(0xFF0A0A0D)],
                stops: [0.5, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(0.6, -0.45),
                  radius: 1.1,
                  colors: [
                    AppDesignTokens.accentOf(context).withValues(alpha: .20),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          left: 48,
          right: 48,
          bottom: 54,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Icon(Symbols.local_fire_department_rounded,
                      size: 15, color: Color(0xFFFF3B47)),
                  const SizedBox(width: 5),
                  Text('热门推荐',
                      style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 1,
                          color: AppDesignTokens.accentOf(context))),
                ],
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 760),
                child: Text(
                  video.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 34,
                    height: 1.12,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    color: Colors.white,
                    shadows: [Shadow(color: Colors.black54, blurRadius: 24)],
                  ),
                ),
              ),
              if (meta.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(meta,
                    style: TextStyle(
                        fontSize: 13.5,
                        color: Colors.white.withValues(alpha: .82))),
              ],
              const SizedBox(height: 20),
              Row(
                children: [
                  _HeroCta(
                    primary: true,
                    icon: Symbols.play_arrow_rounded,
                    label: '观看',
                    onTap: video.id.isEmpty
                        ? null
                        : () => openVideo(context, ref, video.id),
                  ),
                  const SizedBox(width: 12),
                  _HeroCta(
                    primary: false,
                    icon: Symbols.info_rounded,
                    label: '更多信息',
                    onTap: video.id.isEmpty
                        ? null
                        : () => context.push('/video/${video.id}'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeroArrow extends StatelessWidget {
  const _HeroArrow({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: .42),
                shape: BoxShape.circle),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      );
}

class _HeroCta extends StatelessWidget {
  const _HeroCta(
      {required this.primary,
      required this.icon,
      required this.label,
      required this.onTap});
  final bool primary;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => PressScale(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: Container(
            height: 46,
            padding: const EdgeInsets.symmetric(horizontal: 22),
            decoration: BoxDecoration(
              color: primary ? Colors.white : Colors.white.withValues(alpha: .18),
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon,
                    size: 20,
                    color: primary ? const Color(0xFF111111) : Colors.white),
                const SizedBox(width: 8),
                Text(label,
                    style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w800,
                        color:
                            primary ? const Color(0xFF111111) : Colors.white)),
              ],
            ),
          ),
        ),
      );
}

class _AsyncGate {
  _AsyncGate(this.maxConcurrent);

  final int maxConcurrent;
  var _active = 0;
  final _waiting = <Completer<void>>[];

  Future<void> enter() async {
    if (_active < maxConcurrent) {
      _active++;
      return;
    }
    final completer = Completer<void>();
    _waiting.add(completer);
    await completer.future;
  }

  void leave() {
    if (_waiting.isEmpty) {
      _active--;
    } else {
      // 额度直接转交给下一个等待者，_active 不变（它本来就被这个任务占着）。
      _waiting.removeAt(0).complete();
    }
  }
}
