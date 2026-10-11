import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/han1me_repository.dart';
import '../../data/local/download_repository.dart';
import '../../domain/models/download.dart';
import '../../domain/models/video.dart';
import '../settings/settings_controller.dart';

/// HLS/播放列表源不能当成普通文件下载（那只会存到一个清单），下载只对渐进式片源开放。
bool isStreamPlaylistSource(VideoSource source) =>
    (source.type ?? '').toLowerCase().contains('mpegurl') ||
    source.url.contains('.m3u8');

/// [enqueueDownloads] 的核心：把「用户选好的集」变成下载任务。
///
/// 与 provider 容器解耦是为了能单独测——发起下载有**两个调用方**（主窗口的下载弹窗、
/// 主窗口代播放窗口执行），逻辑只有一份，测试也就不必再起一个 widget 树。
Future<({int added, int failed})> enqueueDownloadsWith({
  required DownloadController controller,
  required Han1meRepository repository,
  required String baseUrl,
  required List<VideoCard> episodes,
  required String quality,
  required String groupName,
  required Iterable<String> seriesIds,
  VideoDetail? currentDetail,
}) async {
  if (episodes.isEmpty) return (added: 0, failed: 0);

  var groupId = 'default';
  if (groupName.isNotEmpty) {
    groupId = await controller.resolveAutoGroup(
      groupName,
      DownloadGroupSort.defaultOrder,
    );
  }

  var added = 0;
  var failed = 0;
  for (final episode in episodes) {
    try {
      // playlist 里只有 id/title，没有片源地址；当前集可以直接复用已有详情页。
      final detail = episode.id == currentDetail?.id
          ? currentDetail!
          : await repository.video(baseUrl, episode.id);
      final candidates = detail.sources
          .where((item) => !isStreamPlaylistSource(item))
          .toList(growable: false);
      if (candidates.isEmpty) {
        failed++;
        continue;
      }
      // 按用户选的清晰度取源；没有同名清晰度就退回第一个可下载的渐进式源。
      final match = candidates
              .where((item) => item.quality == quality)
              .firstOrNull ??
          candidates.first;
      await controller.create(detail, match, groupId);
      added++;
    } catch (_) {
      failed++;
    }
  }

  // 同系列的旧任务若还在默认分组，一并归入新组；用户手动分过组的不动。
  if (groupId != 'default') {
    await controller.adoptSeriesTasks(seriesIds, groupId);
  }
  return (added: added, failed: failed);
}

/// 把「用户选好的集」真正变成下载任务，返回成功与失败条数。
///
/// 抽出来是因为这件事有**两个发起方**：
/// - 主窗口：用户在播放页的下载弹窗里点「下载(N)」；
/// - 主窗口代播放窗口执行：用户在独立播放窗口里点「下载(N)」时，播放窗口只把
///   意图写进信箱（见 download_requests.dart），真正建任务的是主窗口。
///
/// 两条路都必须落在**同一个** `downloadProvider` 上 —— 下载调度器持有内存状态并且
/// 会写回下载索引，两个进程各跑一份就会互相覆盖。所以播放窗口只投递、不执行。
///
/// [currentDetail] 是调用方手上已有的详情页（当前正在看的那一集），省一次网络请求；
/// 代播放窗口执行时没有它，那一集也照常走网络取详情。
Future<({int added, int failed})> enqueueDownloads(
  WidgetRef ref, {
  required List<VideoCard> episodes,
  required String quality,
  required String groupName,
  required Iterable<String> seriesIds,
  VideoDetail? currentDetail,
}) async {
  final settings = await ref.read(settingsProvider.future);
  return enqueueDownloadsWith(
    controller: ref.read(downloadProvider.notifier),
    repository: ref.read(han1meRepositoryProvider),
    baseUrl: settings.resolvedBaseUrl,
    episodes: episodes,
    quality: quality,
    groupName: groupName,
    seriesIds: seriesIds,
    currentDetail: currentDetail,
  );
}
