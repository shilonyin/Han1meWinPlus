import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/home_cache.dart';
import '../../domain/models/video.dart';
import '../account/account_controller.dart';
import '../settings/settings_controller.dart';

final homeCacheProvider = Provider((_) => HomeCache());
final homeSectionsProvider = AsyncNotifierProvider<HomeSectionsController, HomeFeed>(HomeSectionsController.new);

/// 切换站点（或换账号、改镜像、清缓存）后重新取首页。
///
/// 只 `invalidate` 是不够的：Riverpod 会把旧值当作新 `AsyncLoading` 的 previous 保留下来，
/// 首页又是用 `when(skipLoadingOnReload: true)` 画的，于是它继续显示**上一个站点**的卡片；
/// 而新站点往往要走 WebView 代取，要等好几秒——用户看到的就是「换了源首页却没变化、
/// 不加载该源的内容」。先把状态清成没有数据的 loading，界面才会老实地转圈。
void resetHomeFeed(WidgetRef ref) {
  ref.read(homeSectionsProvider.notifier).clear();
  ref.invalidate(homeSectionsProvider);
}

/// Bumped every time the feed is fetched again, so the rows can drop the extra
/// pages they accumulated while scrolling and start over from the first page.
final homeRefreshTokenProvider = StateProvider<int>((_) => 0);

class HomeSectionsController extends AsyncNotifier<HomeFeed> {
  @override
  Future<HomeFeed> build() async {
    ref.listen(accountProvider, (previous, next) {
      if (previous?.valueOrNull?.id != next.valueOrNull?.id) ref.invalidateSelf();
    });
    final account = await ref.watch(accountProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final cached = await ref.read(homeCacheProvider).read(settings.homeBaseUrl, account?.id);
    if (cached != null) {
      unawaited(refresh());
      return cached;
    }
    return refresh();
  }

  Future<HomeFeed> refresh() async {
    final account = await ref.read(accountProvider.future);
    final settings = await ref.read(settingsProvider.future);
    final feed = await ref.read(han1meRepositoryProvider).home(settings.homeBaseUrl);
    await ref.read(homeCacheProvider).write(settings.homeBaseUrl, account?.id, feed);
    state = AsyncData(feed);
    ref.read(homeRefreshTokenProvider.notifier).state++;
    return feed;
  }

  /// 丢掉当前内容（见 [resetHomeFeed]）。
  void clear() => state = const AsyncLoading<HomeFeed>();
}
