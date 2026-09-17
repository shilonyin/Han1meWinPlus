import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/settings.dart';
import '../../data/han1me_repository.dart';
import '../../data/video_translation_repository.dart';
import '../../domain/models/video.dart';
import '../../domain/models/video_translation.dart';
import '../settings/settings_controller.dart';
import '../account/account_controller.dart';
import '../shared/comments_page.dart' show CommentSort;

final videoTabProvider = StateProvider.autoDispose.family<int, String>((ref, id) => 0);
final videoCommentSortProvider = StateProvider.autoDispose.family<CommentSort, String>((ref, id) => CommentSort.latest);
final selectedCommentVideoIdProvider = StateProvider.autoDispose.family<String, String>((ref, id) => id);
final favoriteOverrideProvider = StateProvider.autoDispose.family<bool?, String>((ref, id) => null);
final subscriptionOverrideProvider = StateProvider.autoDispose.family<bool?, String>((ref, id) => null);
final videoTranslationProvider = AsyncNotifierProvider.autoDispose.family<VideoTranslationController, VideoTranslation?, String>(VideoTranslationController.new);

final videoDetailProvider = FutureProvider.autoDispose.family<VideoDetail, String>((ref, id) async {
  // 详情页数据量大、站点响应慢，保留住避免来回进出时重复加载。
  ref.keepAlive();
  ref.watch(accountProvider);
  // 只依赖「站点地址」这一个字段。
  //
  // 不能写成 await ref.watch(settingsProvider.future)：那等于依赖整个设置对象，
  // 改任何一项设置都会让详情重新加载，页面退回 loading 态、把播放器整个从树上摘掉，
  // 表现为「切超分辨率档位时画面变成加载中，声音却还在响」（旧播放器还在异步销毁）。
  final baseUrl = await ref.watch(settingsProvider.selectAsync((settings) => settings.resolvedBaseUrl));
  return ref.watch(han1meRepositoryProvider).video(baseUrl, id);
});

class VideoTranslationController extends AutoDisposeFamilyAsyncNotifier<VideoTranslation?, String> {
  @override
  Future<VideoTranslation?> build(String videoId) async => null;

  Future<void> translate(VideoDetail video, AppLanguage language, String systemLanguageCode) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(videoTranslationRepositoryProvider).translate(video, _targetLanguage(language, systemLanguageCode)),
    );
  }

  String _targetLanguage(AppLanguage language, String systemLanguageCode) => switch (language) {
        AppLanguage.simplifiedChinese => 'zh-CN',
        AppLanguage.traditionalChinese => 'zh-TW',
        AppLanguage.english => 'en',
        AppLanguage.system => systemLanguageCode.toLowerCase().startsWith('zh-tw') || systemLanguageCode.toLowerCase().startsWith('zh-hant')
            ? 'zh-TW'
            : systemLanguageCode.toLowerCase().startsWith('zh')
                ? 'zh-CN'
                : 'en',
      };
}
