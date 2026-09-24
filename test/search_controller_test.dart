import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/search/search_controller.dart';

void main() {
  test('卡住的作者详情会超时并被忽略，避免搜索页一直转圈', () async {
    final items = <VideoCard>[
      const VideoCard(id: 'ok', title: 'ok', coverUrl: ''),
      const VideoCard(id: 'slow', title: 'slow', coverUrl: ''),
      const VideoCard(id: 'other', title: 'other', coverUrl: ''),
    ];

    final result = await verifyAuthorMatches(
      items: items,
      expectedAuthor: 'alice',
      detailLoader: (id) async {
        switch (id) {
          case 'ok':
            return const VideoDetail(
              id: 'ok',
              title: 'ok',
              artist: 'alice',
              tags: [],
              sources: [],
              playlist: [],
              related: [],
            );
          case 'slow':
            await Future<void>.delayed(const Duration(milliseconds: 200));
            return const VideoDetail(
              id: 'slow',
              title: 'slow',
              artist: 'alice',
              tags: [],
              sources: [],
              playlist: [],
              related: [],
            );
          default:
            return const VideoDetail(
              id: 'other',
              title: 'other',
              artist: 'bob',
              tags: [],
              sources: [],
              playlist: [],
              related: [],
            );
        }
      },
      timeout: const Duration(milliseconds: 50),
    );

    expect(result.map((video) => video.id), ['ok']);
  });
}
