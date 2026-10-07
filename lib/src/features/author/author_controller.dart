import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../data/remote/jav/jav_site.dart';
import '../../domain/models/video.dart';
import '../search/search_controller.dart';
import '../settings/settings_controller.dart';

/// 作者页当前这一段影片。
class AuthorVideos {
  const AuthorVideos({
    required this.items,
    this.page = 1,
    this.totalPages = 1,
    this.loadingMore = false,
  });

  final List<VideoCard> items;
  final int page;
  final int totalPages;

  /// 「查看更多」正在取下一页：只影响按钮转圈，不动已经显示的内容。
  final bool loadingMore;

  bool get hasMore => page < totalPages;

  AuthorVideos copyWith({
    List<VideoCard>? items,
    int? page,
    int? totalPages,
    bool? loadingMore,
  }) => AuthorVideos(
    items: items ?? this.items,
    page: page ?? this.page,
    totalPages: totalPages ?? this.totalPages,
    loadingMore: loadingMore ?? this.loadingMore,
  );
}

/// 作者页的影片：拿作者名去站点搜索，再按作者名精确筛一遍。
///
/// 站点没有「作者页」这种地址 —— 它的作者入口本身就是一次带关键字的搜索
/// （`?query=<作者>`），所以这里只能搜完再筛：关键字命中的结果里会混进「作者名
/// 只出现在标题或标签里」的别人的片子（详见 `verifyAuthorMatches`）。一条都不剩
/// 时退回原始结果：宁可多给几张，也不要给用户一张空页面。
class AuthorVideosController extends FamilyAsyncNotifier<AuthorVideos, String> {
  @override
  Future<AuthorVideos> build(String artist) => _fetch(artist, 1);

  /// 「查看更多」：追加下一页。失败就停在已经显示的内容上，不把整页打成错误态。
  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final next = await _fetch(arg, current.page + 1);
      state = AsyncData(
        AuthorVideos(
          items: [...current.items, ...next.items],
          page: next.page,
          totalPages: next.totalPages,
        ),
      );
    } catch (_) {
      final latest = state.valueOrNull;
      if (latest != null) state = AsyncData(latest.copyWith(loadingMore: false));
    }
  }

  Future<AuthorVideos> _fetch(String artist, int page) async {
    // 作者名为空时不要拿着空关键字去搜：仓库层对空关键字会返回首页内容，
    // 那样作者页会显示一堆和谁都不相关的片子。
    if (artist.trim().isEmpty) return const AuthorVideos(items: []);
    final settings = await ref.watch(settingsProvider.future);
    final repository = ref.watch(han1meRepositoryProvider);
    // 不套搜索页的分类/排序/标签：这是「这位作者的片子」，不是一次检索。
    final result = await repository
        .search(
          baseUrl: settings.resolvedBaseUrl,
          query: artist,
          genre: '',
          sort: '',
          date: '',
          duration: '',
          tags: const <String>[],
          broad: false,
          type: '',
          page: page,
        )
        // 站点偶尔「连上却不回数据」：没有超时的话这一页会一直转圈。
        .timeout(const Duration(seconds: 45));
    final matched = javSiteFor(settings.resolvedBaseUrl) == null
        ? _sameArtist(result.items, artist)
        : await verifyAuthorMatches(
            items: result.items,
            expectedAuthor: artist,
            detailLoader: (id) =>
                repository.video(settings.resolvedBaseUrl, id),
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
    AsyncNotifierProvider.family<AuthorVideosController, AuthorVideos, String>(
      AuthorVideosController.new,
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
