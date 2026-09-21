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
  final result = await repository.search(
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
  if (!settings.applyRecommendationFiltersToSearch) return result;
  return SearchResult(items: result.items.where((video) => _visible(video, settings)).toList(), page: result.page, totalPages: result.totalPages);
});

/// 首页（推荐位）内容：取第一个有内容的分区。
///
/// 站点被拦或改版时这里会失败，但「推荐拿不到」不该把整个搜索页变成错误页，
/// 所以失败就退回空结果（界面会显示原本的空状态提示）。
Future<SearchResult> _recommendations(AppSettings settings, Han1meRepository repository) async {
  try {
    // 推荐位不该让页面长时间空着：拿不到就退回空状态，别卡着让人以为死机。
    final feed = await repository.home(settings.resolvedBaseUrl).timeout(const Duration(seconds: 8));
    final videos = feed.sections.expand((section) => section.videos).toList(growable: false);
    final items = settings.applyRecommendationFiltersToSearch ? videos.where((video) => _visible(video, settings)).toList(growable: false) : videos;
    return SearchResult(items: items, page: 1, totalPages: 1);
  } catch (_) {
    return const SearchResult(items: [], page: 1, totalPages: 1);
  }
}

bool _visible(VideoCard video, AppSettings settings) {
  if (settings.blockedVideoTitleKeywords.any((keyword) => video.title.toLowerCase().contains(keyword.toLowerCase()))) return false;
  if (settings.blockedAuthors.any((author) => (video.artist ?? '').toLowerCase().contains(author.toLowerCase()))) return false;
  // 站点没给时长/播放量时按「未知」处理，不参与过滤：按 0 判会把 AV 源的卡片整页滤光
  // （它们本来就不带这些字段），表现是「AV 站点搜索全部没有结果」。
  final seconds = videoDurationSeconds(video.duration);
  if (seconds != null && seconds < settings.minimumVideoDurationSeconds) return false;
  final views = videoViews(video.views);
  if (views != null && views < settings.minimumVideoViews) return false;
  return true;
}
