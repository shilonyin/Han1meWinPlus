// 回归测试：卡片作者行的三件事（用户要求，见 m05830）。
//
// 背景：
// 1. 「作者名和点赞这几个视频都不在一条水平线上，取个平均值固定水平」—— 标题原来按
//    实际行数留高，一行标题的卡与两行标题的卡会把作者行/评分行推到不同高度。现在
//    标题区固定两行高（`_titleBoxHeight`），作者行（18）与评分行（16）都是固定高度。
// 2. 「作者名也要可以点击，直接转跳作者详细页」—— 作者名是链接，点了进
//    `/search?query=<作者>`（与详情页作者卡同一条路径）。
// 3. 「在作者名右边加个视频上传时间」—— 日期与作者同一行、靠右显示。
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/video_card.dart';

/// 1x1 透明 PNG：测试里不碰网络图片（没有网络也没有缓存目录）。
final MemoryImage _cover = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==',
  ),
);

/// 固定返回一份设置的设置替身（不读盘）。
class _StubSettings extends SettingsController {
  @override
  Future<AppSettings> build() async => AppSettings();
}

VideoCard _video({
  required String id,
  required String title,
  required String artist,
  String? uploadTime,
}) => VideoCard(
  id: id,
  title: title,
  coverUrl: 'https://example.invalid/cover.jpg',
  artist: artist,
  rating: '99%',
  uploadTime: uploadTime,
);

/// 一行卡片：同一行里放两张卡（宽度、高度一致，只有标题长短不同）。
Widget _row(List<VideoCard> videos) => ProviderScope(
  overrides: [settingsProvider.overrideWith(_StubSettings.new)],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: Row(
              children: [
                for (final video in videos)
                  SizedBox(
                    width: 260,
                    height: 300,
                    child: VideoCardTile(
                      video: video,
                      horizontal: true,
                      coverImage: _cover,
                    ),
                  ),
              ],
            ),
          ),
        ),
        // 作者页等价物：把 URL 里的 query 显示出来，用来断言跳转真的带上了作者名。
        GoRoute(
          path: '/search',
          builder: (context, state) =>
              Scaffold(body: Text('搜索页：${state.uri.queryParameters['query']}')),
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('标题一行与两行的卡片：作者行、评分行都在同一条水平线上', (tester) async {
    await tester.pumpWidget(
      _row([
        _video(id: 'a', title: '短标题', artist: '甲作者'),
        _video(id: 'b', title: '一个会折成两行的很长很长的中文标题测试用例', artist: '乙作者'),
      ]),
    );
    await tester.pumpAndSettle();

    // 前提：长标题确实排成了两行（单行宽度超过卡片给它的宽度），否则这条测试就
    // 没在测它想测的东西 —— 两张卡都一行时，对齐断言会白白通过。
    const longTitle = '一个会折成两行的很长很长的中文标题测试用例';
    final longStyle = tester.widget<Text>(find.text(longTitle)).style;
    final oneLine = TextPainter(
      text: TextSpan(text: longTitle, style: longStyle),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    final titleWidth = tester.getSize(find.text(longTitle)).width;
    expect(
      oneLine.width,
      greaterThan(titleWidth),
      reason: '长标题一行就放得下，测试前提（一行 / 两行）不成立',
    );
    expect(
      tester.getTopLeft(find.text('甲作者')).dy,
      tester.getTopLeft(find.text('乙作者')).dy,
      reason: '两张卡的作者行没有对齐：标题区没有固定成两行高',
    );
    expect(
      tester.getTopLeft(find.text('99%').first).dy,
      tester.getTopLeft(find.text('99%').last).dy,
      reason: '两张卡的评分行没有对齐',
    );
  });

  testWidgets('标题一行与两行的卡片：封面高度一致、下沿也在同一条水平线上', (tester) async {
    await tester.pumpWidget(
      _row([
        _video(id: 'a', title: '短标题', artist: '甲作者'),
        _video(id: 'b', title: '一个会折成两行的很长很长的中文标题测试用例', artist: '乙作者'),
      ]),
    );
    await tester.pumpAndSettle();

    final covers = find.byType(Image);
    expect(covers, findsNWidgets(2), reason: '这一行应该有且只有两张封面图');
    final short = tester.getRect(covers.first);
    final long = tester.getRect(covers.last);
    expect(
      short.height,
      closeTo(long.height, 0.5),
      reason: '一行标题的卡封面比两行标题的高：标题区没有固定成两行高',
    );
    expect(
      short.bottom,
      closeTo(long.bottom, 0.5),
      reason: '两张卡的封面下沿不在同一条水平线上',
    );
  });

  testWidgets('上传时间显示在作者名右边（同一行、靠右）', (tester) async {
    await tester.pumpWidget(
      _row([
        _video(id: 'a', title: '短标题', artist: '甲作者', uploadTime: '2026-04-24'),
      ]),
    );
    await tester.pumpAndSettle();

    final author = tester.getRect(find.text('甲作者'));
    final date = tester.getRect(find.text('2026-04-24'));
    expect(date.left, greaterThan(author.left), reason: '日期应该在作者名右边');
    expect(date.top, closeTo(author.top, 6), reason: '日期与作者名不该差出一行');
  });

  testWidgets('点作者名进作者页（/search?query=作者），不会点开视频', (tester) async {
    await tester.pumpWidget(
      _row([_video(id: 'a', title: '短标题', artist: '甲作者', uploadTime: '2026-04-24')]),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('甲作者'));
    await tester.pumpAndSettle();

    expect(find.text('搜索页：甲作者'), findsOneWidget);
  });
}
