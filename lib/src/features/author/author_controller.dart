import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../data/remote/han1me_api.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/video.dart';
import '../search/search_controller.dart';
import '../settings/settings_controller.dart';

/// 作者页的三档排序 —— 直接用**用户上传页**自己的排序键（页面上就是
/// `?page=1&sort=latest|popular|oldest`），正好对上 B 站的「最新 / 熱門 / 最早」，
/// 不用自己造一套。
const authorSortLatest = 'latest';
const authorSortPopular = 'popular';
const authorSortOldest = 'oldest';

/// 退路（按作者名搜索）走的是**搜索页**的排序键，和用户上传页不是一套；
/// 搜索页没有「最早」这一档，只能退回「最新上市」。
String _searchSortFor(String sort) => switch (sort) {
  authorSortPopular => '觀看次數',
  _ => '最新上市',
};

/// 作者页的一次查询：同一位作者按不同排序各是一份独立的数据。
typedef AuthorRequest = ({String artist, String sort});

/// 作者页当前这一段影片。
class AuthorVideos {
  const AuthorVideos({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.loadingMore = false,
    this.artistId = '',
    this.profile,
  });

  final List<VideoCard> items;
  final int page;
  final int totalPages;

  /// 「查看更多」正在取下一页：只影响按钮转圈，不动已经显示的内容。
  final bool loadingMore;

  /// 已经解析出来的站点用户 id：翻页时接着用它继续走用户上传页，
  /// 不要每页都重新去搜一遍作者名。
  final String artistId;

  /// 用户上传页顶部的资料（头像 / 订阅数 / 影片数）。只有主路径（用户上传页）
  /// 才拿得到 —— 它也是唯一公开别人订阅数的地方。
  final AuthorProfile? profile;

  bool get hasMore => page < totalPages;

  AuthorVideos copyWith({
    List<VideoCard>? items,
    int? page,
    int? totalPages,
    bool? loadingMore,
    String? artistId,
    AuthorProfile? profile,
  }) => AuthorVideos(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loadingMore: loadingMore ?? this.loadingMore,
    artistId: artistId ?? this.artistId,
    profile: profile ?? this.profile,
  );
}

/// 作者页的影片。
///
/// 主路径是站点的用户上传页 `/user/<id>/uploaded`（见 `Han1meApi.userUploads`），
/// artistId 从这位作者第一个影片的详情里拿。
///
/// 拿不到 artistId 时（AV 源，或详情还在路上）退回「按作者名搜索 + 筛一遍」：
/// 搜索是模糊匹配，结果里会混进「作者名只出现在标题或标签里」的别人的片子
/// （详见 `verifyAuthorMatches`）；筛完一条不剩时退回原始结果：宁可多给几张，
/// 也不要给用户一张空页面。
class AuthorVideosController
    extends FamilyAsyncNotifier<AuthorVideos, AuthorRequest> {
  @override
  Future<AuthorVideos> build(AuthorRequest request) => _fetch(request, 1);

  /// 「查看更多」：追加下一页。失败就停在已经显示的内容上，不把整页打成错误态。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetch(arg, current.page + 1, artistId: current.artistId);
      state = AsyncData(
        AuthorVideos(
          items: [...current.items, ...next.items],
          page: next.page,
          totalPages: next.totalPages,
          artistId: next.artistId.isEmpty ? current.artistId : next.artistId,
          profile: next.profile ?? current.profile,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(loadingMore: false));
    }
  }

  Future<AuthorVideos> _fetch(
    AuthorRequest request,
    int page, {
    String artistId = '',
  }) async {
    final artist = request.artist;
    // 作者名为空时不要拿着空关键字去搜：仓库层对空关键字会返回首页内容，
    // 那样作者页会显示一堆和谁都不相关的片子。
    if (artist.trim().isEmpty) return const AuthorVideos(items: []);
    final settings = await ref.watch(settingsProvider.future);
    final repository = ref.watch(han1meRepositoryProvider);
    // 已知 artistId（翻页时）就走站点的用户上传页：那个页面就是「这位作者的全部
    // 影片」，结果精确、自带分页，不用再筛。
    if (artistId.isNotEmpty) {
      final exact = await repository
          .userUploads(
            baseUrl: settings.resolvedBaseUrl,
            artistId: artistId,
            sort: request.sort,
            page: page,
          )
          // 站点偶尔「连上却不回数据」：没有超时的话这一页会一直转圈。
          .timeout(const Duration(seconds: 45));
      return AuthorVideos(
        items: exact.result.items,
        page: exact.result.page,
        totalPages: exact.result.totalPages,
        artistId: artistId,
        profile: exact.profile,
      );
    }
    // 第一页：先用作者名搜一次（拿候选 + 顺手解析 artistId）。
    // 不套搜索页的分类/日期/时长/标签：这是「这位作者的片子」，不是一次检索。
    final result = await repository
        .search(
          baseUrl: settings.resolvedBaseUrl,
          query: artist,
          genre: '',
          sort: _searchSortFor(request.sort),
          date: '',
          duration: '',
          tags: const <String>[],
          broad: false,
          type: '',
          page: page,
        )
        .timeout(const Duration(seconds: 45));
    final resolved = await _resolveArtistId(repository, settings.resolvedBaseUrl, result.items, artist);
    if (resolved.isNotEmpty) {
      final exact = await repository
          .userUploads(
            baseUrl: settings.resolvedBaseUrl,
            artistId: resolved,
            sort: request.sort,
            page: page,
          )
          .timeout(const Duration(seconds: 45));
      // 用户上传页偶尔空手而归（作者没上传、或被拦）：空的话退回搜索结果，不要给空页面。
      if (exact.result.items.isNotEmpty) {
        return AuthorVideos(
          items: exact.result.items,
          page: exact.result.page,
          totalPages: exact.result.totalPages,
          artistId: resolved,
          profile: exact.profile,
        );
      }
    }
    return _fromSearch(repository, settings.resolvedBaseUrl, result, artist);
  }

  /// 从搜索结果里挑一个「确实是这位作者」的影片，用它的详情页解析站点用户 id。
  ///
  /// 站点没有作者接口，用户 id 只挂在影片详情上；搜索结果是模糊匹配，所以必须挑
  /// 作者字段对得上的那一条，否则会把别人的用户页当成这位作者的页面。
  Future<String> _resolveArtistId(
    Han1meRepository repository,
    String baseUrl,
    List<VideoCard> items,
    String artist,
  ) async {
    if (javSiteFor(baseUrl) != null) return '';
    final expected = artist.trim().toLowerCase();
    for (final item in items) {
      if (item.id.isEmpty) continue;
      if ((item.artist ?? '').trim().toLowerCase() != expected) continue;
      try {
        final detail = await repository
            .video(baseUrl, item.id)
            .timeout(const Duration(seconds: 15));
        final id = detail.artistId?.trim() ?? '';
        if (id.isNotEmpty) return id;
      } catch (_) {
        // 单条详情失败不影响整页：继续试下一条候选。
      }
    }
    return '';
  }

  /// 拿不到用户 id 时的退路：按作者名搜索 + 筛一遍。
  Future<AuthorVideos> _fromSearch(
    Han1meRepository repository,
    String baseUrl,
    SearchResult result,
    String artist,
  ) async {
    final matched = javSiteFor(baseUrl) == null
        ? _sameArtist(result.items, artist)
        : await verifyAuthorMatches(
            items: result.items,
            expectedAuthor: artist,
            detailLoader: (id) => repository.video(baseUrl, id),
          );
    return AuthorVideos(
      items: matched.isEmpty ? result.items : matched,
      page: result.page,
      totalPages: result.totalPages,
    );
  }

  /// AV 视频源的列表页本来就带着作者名，直接比对，不用再逐个打听详情。
  List<VideoCard> _sameArtist(List<VideoCard> items, String artist) {
    final expected = artist.trim().toLowerCase();
    if (expected.isEmpty) return items;
    final matched = items
        .where((video) => (video.artist ?? '').trim().toLowerCase() == expected)
        .toList(growable: false);
    return matched.isEmpty ? items : matched;
  }
}

final authorVideosProvider =
    AsyncNotifierProvider.family<
      AuthorVideosController,
      AuthorVideos,
      AuthorRequest
    >(AuthorVideosController.new);

/// 站点搜索页上的「作者卡」（`type=artist` 的结果）：作者名、头像，以及卡片上
/// 那个计数文本（站点在这一处给出作者级别的数字，详情页没有）。
///
/// 拿不到就返回 null：作者页会退回用影片详情里的头像、用自己的影片数。
final authorCardProvider = FutureProvider.autoDispose.family<VideoCard?, String>(
  (ref, artist) async {
    if (artist.trim().isEmpty) return null;
    final settings = await ref.watch(settingsProvider.future);
    final result = await ref
        .watch(han1meRepositoryProvider)
        .search(
          baseUrl: settings.resolvedBaseUrl,
          query: artist,
          genre: '',
          sort: '',
          date: '',
          duration: '',
          tags: const <String>[],
          broad: false,
          type: 'artist',
          page: 1,
        )
        .timeout(const Duration(seconds: 20));
    final expected = artist.trim().toLowerCase();
    for (final card in result.items) {
      if (card.title.trim().toLowerCase() == expected) return card;
    }
    return result.items.isEmpty ? null : result.items.first;
  },
);

/// 作者资料（头像 / artistId / csrf token）：站点没有独立的作者接口，这些字段只挂在
/// 影片详情上，所以借这位作者第一个影片的详情来拿；拿不到就只显示名字。
final authorProfileProvider = FutureProvider.autoDispose
    .family<VideoDetail?, String>((ref, videoId) async {
      if (videoId.isEmpty) return null;
      final settings = await ref.watch(settingsProvider.future);
      return ref
          .watch(han1meRepositoryProvider)
          .video(settings.resolvedBaseUrl, videoId);
    });
