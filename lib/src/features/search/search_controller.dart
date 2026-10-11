import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/assets/search_option_catalog.dart';
import '../../data/han1me_repository.dart';
import '../../data/local/json_store.dart';
import '../../data/local/search_history_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/search_query.dart';
import '../../domain/models/video.dart';
import '../../domain/video_metrics.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';

final searchQueryProvider = NotifierProvider.family<SearchQueryNotifier, SearchQuery, SearchRouteRequest>(SearchQueryNotifier.new);

final searchHistoryProvider = AsyncNotifierProvider<SearchHistoryController, List<SearchQuery>>(SearchHistoryController.new);

class SearchQueryNotifier extends FamilyNotifier<SearchQuery, SearchRouteRequest> {
  @override
  SearchQuery build(SearchRouteRequest request) {
    // 监听「当前是不是 AV 源」：在设置里换源后立刻重算，把 hanime1 专有条件清掉。
    ref.watch(settingsProvider.select((value) => javSiteFor(value.valueOrNull?.resolvedBaseUrl ?? '') != null));
    return _forSource(request.initialQuery?.copyWith(page: 1) ?? SearchQuery.fromUri(request.initialUrl));
  }

  /// 清掉 AV 源不支持的条件。
  ///
  /// 标签/分类/排序/时长这些只有 hanime1 认。带着它们去搜 AV 源时，条件会被解析层丢
  /// 掉、关键词又是空的，界面只会报「没有找到匹配的视频」，看不出真正原因（换了源但
  /// 旧条件留在搜索页就是这么来的）。这里直接清掉，只留 `text` 和 `genre`——后者
  /// 扛着首页分区的列表路径。
  SearchQuery _forSource(SearchQuery value) {
    if (javSiteFor(ref.read(settingsProvider).valueOrNull?.resolvedBaseUrl ?? '') == null) return value;
    return value.copyWith(tags: const [], sort: '', date: '', duration: '', type: '', broad: false);
  }

  void text(String value) => _update(state.copyWith(text: value, page: 1));
  void genre(String value) => _update(state.copyWith(genre: value, page: 1));
  void sort(String value) => _update(state.copyWith(sort: value, page: 1));
  void date(String value) => _update(state.copyWith(date: value, page: 1));
  void duration(String value) => _update(state.copyWith(duration: value, page: 1));
  void tags(List<String> value, bool broad) => _update(state.copyWith(tags: List.unmodifiable(value), broad: broad, page: 1));
  void type(String value) => _update(state.copyWith(type: value, page: 1));
  void artist(String value) => _update(state.copyWith(text: value, type: '', page: 1));
  void page(int value) => state = state.copyWith(page: value);
  void replace(SearchQuery value) => _update(value.copyWith(page: 1));
  void reset() => _update(const SearchQuery());

  void _update(SearchQuery next) {
    final value = _forSource(next);
    if (value == state) return;
    state = value;
  }
}

class SearchHistoryController extends AsyncNotifier<List<SearchQuery>> {
  final _repository = SearchHistoryRepository(JsonStore());
  Future<void> _write = Future<void>.value();

  @override
  Future<List<SearchQuery>> build() => _repository.load();

  Future<void> record(SearchQuery query) async {
    if (!query.hasSearchCriteria) return;
    final current = state.valueOrNull ?? await future;
    final next = [query, ...current.where((item) => item != query)].take(30).toList(growable: false);
    state = AsyncData(next);
    _write = _write.catchError((_) {}).then((_) => _repository.save(next));
    await _write;
  }

  Future<void> remove(SearchQuery query) async {
    final current = state.valueOrNull ?? await future;
    final next = current.where((item) => item != query).toList(growable: false);
    state = AsyncData(next);
    _write = _write.catchError((_) {}).then((_) => _repository.save(next));
    await _write;
  }

  Future<void> clear() async {
    state = const AsyncData([]);
    _write = _write.catchError((_) {}).then((_) => _repository.save(const []));
    await _write;
  }
}

/// 搜索结果的**第一页**（外加「还没有条件时」的推荐位）。
///
/// 第 2 页往后不在这里：结果区是无限滚动的瀑布流，后续页由
/// [searchMoreResultsProvider] 追加，这条 provider 只负责首屏的加载/错误状态，
/// 以及提供总页数——不然每接一页都要重跑首屏，滚动会一跳一跳的。
final searchResultsProvider = FutureProvider.autoDispose.family<SearchResult, SearchRouteRequest>((ref, request) async {
  // 切回搜索结果页（或翻页回来）时不再重新请求；条件变化会自然重算。
  ref.keepAlive();
  // 只关心「登录/登出的用户变化」，不要 watch 整个 AsyncValue：账号请求会经历
  // loading → data（被站点拦时还有 error → 重试），每次状态跳变都会让本 provider
  // 重建、重新发一次搜索请求，界面表现就是「一直转圈 / 点了没内容」。
  ref.watch(accountProvider.select((value) => value.valueOrNull?.id));
  final settings = await ref.watch(settingsProvider.future);
  final query = ref.watch(searchQueryProvider(request));
  final repository = ref.watch(han1meRepositoryProvider);
  // AV 视频源没有 hanime1 的那套分类/排序/标签，条件原样交给解析层
  // （首页分区的「加载更多」正是靠 genre 携带列表路径走这条分支）。
  final javSource = javSiteFor(settings.resolvedBaseUrl) != null;
  // 还没输关键词、也没在浏览某个分区时，给一份「推荐」而不是一张空页面——搜索页
  // 可能只是被点开，用户还没想好搜什么。推荐直接复用首页的第一段内容（同一次
  // 请求会被仓库层缓存，不会多打一次站点）。
  if (query.text.trim().isEmpty && query.genre.isEmpty) return _recommendations(settings, repository);
  final catalog = javSource ? null : await ref.watch(searchOptionCatalogProvider.future);
  // 第 1 页走原路径（保留 catalog 的 await，不依赖它是否已经加载完），
  // 追加页由 `searchMoreResultsProvider` 用同一个加载器取。
  final result = await repository
      .search(
        baseUrl: settings.resolvedBaseUrl,
        query: query.text,
        genre: javSource ? query.genre : catalog!.genres.canonical(query.genre),
        sort: javSource ? '' : catalog!.sorts.canonical(query.sort),
        date: javSource ? '' : catalog!.releaseDates.canonical(query.date),
        duration: javSource ? '' : catalog!.durations.canonical(query.duration),
        tags: javSource ? const <String>[] : query.tags.map(catalog!.canonicalTag).toList(growable: false),
        broad: javSource ? false : query.broad,
        type: javSource ? '' : query.type,
        page: query.page,
      )
      // 站点偶尔「连上却不回数据」：没有超时的话搜索页会一直转圈，看起来就像卡死。
      // 给一个上限，超时后走错误态（带重试按钮），用户至少知道发生了什么。
      .timeout(const Duration(seconds: 45));
  final authorName = request.authorName?.trim();
  if (javSource && authorName != null && authorName.isNotEmpty) {
    final verified = await verifyAuthorMatches(
      items: result.items,
      expectedAuthor: authorName,
      detailLoader: (id) => repository.video(settings.resolvedBaseUrl, id),
      timeout: const Duration(seconds: 8),
    );
    return SearchResult(items: verified, page: result.page, totalPages: result.totalPages);
  }
  return SearchResult(items: visibleVideos(result.items, settings), page: result.page, totalPages: result.totalPages);
});

Future<List<VideoCard>> verifyAuthorMatches({
  required List<VideoCard> items,
  required String expectedAuthor,
  required Future<VideoDetail> Function(String id) detailLoader,
  Duration timeout = const Duration(seconds: 8),
}) async {
  final expected = expectedAuthor.trim().toLowerCase();
  final verified = await Future.wait(videosNeedingAuthorCheck(items, expectedAuthor).map((video) async {
    try {
      final detail = await detailLoader(video.id).timeout(timeout);
      return detail.artist?.trim().toLowerCase() == expected ? video : null;
    } on TimeoutException {
      return null;
    } catch (_) {
      return null;
    }
  }));
  return verified.whereType<VideoCard>().toList(growable: false);
}

/// 当前结果列表的分页状态。
///
/// 「翻页」现在是往下接一页（无限滚动的瀑布流），而不是换掉整个列表，所以
/// `searchQueryProvider.page` 不再是数据源 —— 页面不能只靠它显示第几页；它只留作
/// 路由/历史里的初始页码，以及「换条件要回到第 1 页」的语义。这里存的是滚动加载
/// 真正走到哪儿了，外加「在加载 / 加载失败」两个给页面做提示的状态。
class SearchPagingState {
  const SearchPagingState({this.page = 1, this.loadingMore = false, this.error});

  final int page;
  final bool loadingMore;
  final Object? error;

  SearchPagingState copyWith({int? page, bool? loadingMore, Object? error, bool clearError = false}) => SearchPagingState(
        page: page ?? this.page,
        loadingMore: loadingMore ?? this.loadingMore,
        error: clearError ? null : (error ?? this.error),
      );
}

typedef SearchPageLoader = Future<SearchResult> Function(SearchQuery query, int page);

/// 按搜索页的 request 建一个加载器，负责「取第 N 页 + 套上搜索页的过滤规则」。
///
/// 单独抽出来是为了让首屏与「往下接一页」共用同一套过滤/作者校验；
/// 两处各写一份的话，改动很容易只落在一边（表现就是「第一页过滤对了、翻页漏掉」）。
SearchPageLoader searchPageLoader(Ref ref, SearchRouteRequest request) {
  final settings = ref.read(settingsProvider).valueOrNull ?? const AppSettings();
  final author = request.authorName?.trim() ?? '';
  final repository = ref.read(han1meRepositoryProvider);
  final catalog = ref.read(searchOptionCatalogProvider).valueOrNull;
  final javSource = javSiteFor(settings.resolvedBaseUrl) != null;
  return (query, page) async {
    final result = await repository
        .search(
          baseUrl: settings.resolvedBaseUrl,
          query: query.text,
          genre: javSource ? query.genre : catalog?.genres.canonical(query.genre) ?? query.genre,
          sort: javSource ? '' : catalog?.sorts.canonical(query.sort) ?? query.sort,
          date: javSource ? '' : catalog?.releaseDates.canonical(query.date) ?? query.date,
          duration: javSource ? '' : catalog?.durations.canonical(query.duration) ?? query.duration,
          tags: javSource ? const <String>[] : query.tags.map((tag) => catalog?.canonicalTag(tag) ?? tag).toList(growable: false),
          broad: javSource ? false : query.broad,
          type: javSource ? '' : query.type,
          page: page,
        )
        .timeout(const Duration(seconds: 45));
    if (javSource && author.isNotEmpty) {
      return SearchResult(
        items: await verifyAuthorMatches(items: result.items, expectedAuthor: author, detailLoader: (id) => repository.video(settings.resolvedBaseUrl, id)),
        page: result.page,
        totalPages: result.totalPages,
      );
    }
    return SearchResult(items: visibleVideos(result.items, settings), page: result.page, totalPages: result.totalPages);
  };
}

/// 在 [searchResultsProvider] 拿到的首屏之上继续往下接页（瀑布流）。
///
/// 首屏仍由原 provider 负责（它管加载/错误/推荐位那套状态），这里只负责第 2 页往后：
/// 用同一个加载器、同一套过滤规则，把新页追加到已有列表末尾。
final searchMoreResultsProvider = AsyncNotifierProvider.autoDispose.family<SearchMoreResults, List<VideoCard>, SearchRouteRequest>(SearchMoreResults.new);

class SearchMoreResults extends AutoDisposeFamilyAsyncNotifier<List<VideoCard>, SearchRouteRequest> {
  var _page = 1;
  var _totalPages = 1;
  var _loading = false;

  /// 条件一变（换关键词、点标签、改排序）就整体作废重新数页码。
  SearchQuery? _lastQuery;

  @override
  Future<List<VideoCard>> build(SearchRouteRequest arg) async => const <VideoCard>[];

  /// 已经取到第几页（首屏算第 1 页）。
  int get page => _page;

  /// 站点说的总页数，首屏还没回来时先当 1（调用方会拿不到下一页）。
  int get totalPages => _totalPages;

  /// 首屏数据到手后由页面喂进来，对齐页码与总页数。
  ///
  /// 只在「首屏换了」的时候对齐。首屏 provider 会因为账号变化之类的原因重算，
  /// 那时不能把已经翻到第 5 页的进度打回第 1 页（列表还留在第 5 页）。
  void adopt(SearchResult result) {
    if (result.items.isEmpty && result.page <= _page) return;
    if (result.page == 1) {
      _page = 1;
      _totalPages = result.totalPages;
    }
  }

  Future<void> next(SearchQuery query, {int? totalPages}) async {
    if (_loading) return;
    final limit = totalPages ?? _totalPages;
    if (limit > 0 && _page >= limit) return;
    if (_lastQuery != null && _lastQuery != query) {
      _page = 1;
      state = const AsyncData(<VideoCard>[]);
    }
    _lastQuery = query;
    final target = _page + 1;
    final wasEmpty = state.valueOrNull?.isEmpty ?? true;
    if (wasEmpty) state = const AsyncLoading();
    _loading = true;
    try {
      final result = await searchPageLoader(ref, arg)(query, target);
      _page = target;
      _totalPages = result.totalPages;
      // 追加而不是替换：站点每次只给一页，用户是在「往下看」而不是「换一屏」。
      state = AsyncData([...?state.valueOrNull, ...result.items]);
    } catch (error, stackTrace) {
      state = AsyncError(error, stackTrace);
    } finally {
      _loading = false;
    }
  }
}

/// 首页（推荐位）内容：取第一个有内容的分区。
///
/// 站点被拦或改版时这里会失败，但「推荐拿不到」不该把整个搜索页变成错误页，
/// 所以失败就退回空结果（界面会显示原本的空状态提示）。
Future<SearchResult> _recommendations(AppSettings settings, Han1meRepository repository) async {
  try {
    // 推荐位不该让页面长时间空着：拿不到就退回空状态，别卡着让人以为死机。
    final feed = await repository.home(settings.resolvedBaseUrl).timeout(const Duration(seconds: 8));
    final videos = feed.sections.expand((section) => section.videos).toList(growable: false);
    return SearchResult(items: visibleVideos(videos, settings), page: 1, totalPages: 1);
  } catch (_) {
    return const SearchResult(items: [], page: 1, totalPages: 1);
  }
}

bool _visible(VideoCard video, AppSettings settings) {
  if (settings.blockedVideoTitleKeywords.any((keyword) => video.title.toLowerCase().contains(keyword.toLowerCase()))) return false;
  if (settings.blockedAuthors.any((author) => (video.artist ?? '').toLowerCase().contains(author.toLowerCase()))) return false;
  if (settings.blockedVideoTags.any((blockedTag) => video.tags.any((tag) => tag.toLowerCase().contains(blockedTag.toLowerCase())))) return false;
  // 站点没给时长/播放量时按「未知」处理，不参与过滤：按 0 判会把 AV 源的卡片整页滤光
  // （它们本来就不带这些字段），表现是「AV 站点搜索全部没有结果」。
  final seconds = videoDurationSeconds(video.duration);
  if (seconds != null && seconds < settings.minimumVideoDurationSeconds) return false;
  final views = videoViews(video.views);
  if (views != null && views < settings.minimumVideoViews) return false;
  return true;
}

/// 这一页结果里还该剩下哪些卡片。
///
/// 搜索页要把「推荐位过滤」和「AV 源作者精确匹配」这两套规则同时用在新加载出来的
/// 页上，但两套规则看的元数据来源不一样（作者筛选只能靠详情页），所以分开成两个
/// 纯函数；列表页自己的过滤直接收在原 provider 里。
List<VideoCard> visibleVideos(List<VideoCard> items, AppSettings settings) =>
    settings.applyRecommendationFiltersToSearch ? items.where((video) => _visible(video, settings)).toList(growable: false) : items;

/// 挑出列表页信息不够、需要去详情页比对作者的卡片。
///
/// 详情页是整页抓取（几百 KB），实测失败率不低；能白拿的元数据就不该再花一次请求：
/// 列表页已经给了作者时直接比对，「作者为空」（抓取失败）也认下来，否则翻页时被站点
/// 抽几页就会整页被丢光。
List<VideoCard> videosNeedingAuthorCheck(List<VideoCard> items, String expectedAuthor) {
  final expected = expectedAuthor.trim().toLowerCase();
  return items.where((video) => video.artist?.trim().toLowerCase() != expected).toList(growable: false);
}
