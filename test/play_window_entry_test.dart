// 验证播放窗口的落地组件 PlayWindowVideo：缓存查询完成前不建播放页。
//
// 本轮改动让缓存视频也走独立播放窗口（以前是在主窗口内 push VideoPage）。
// 跨进程传不了 VideoDetail 对象，所以由播放窗口进程自己按 id 读一次缓存。
//
// 核心风险：如果先按网络源建一个播放页、查完再换成缓存源，播放器会被建两次
// —— 那正是这轮一直在修的「加载出来又重来一遍」。这个文件直接测真实组件
// （PlayWindowVideo 就是生产代码里那条路由用的组件），锁住「结果未定时不建页面」。
//
// 页面构造用 playWindowPageBuilder 换成轻量替身：真实的 VideoPage 会拉起一串
// 网络 provider，测试拆解时会留下「provider 已销毁」的噪音，反而看不清时序。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/video/play_window_app.dart';

/// 造一个能看出「拿到的是哪份 VideoDetail」的轻量页面。
Widget _stubPage({
  required String id,
  required VideoDetail? localVideo,
  VoidCallback? onBack,
  VoidCallback? onHome,
}) => Text(
  'page:$id:${localVideo == null ? 'network' : 'cached:${localVideo.sources.single.url}'}',
);

VideoDetail _cached({String quality = '1080'}) => VideoDetail(
  id: 'v1',
  title: '缓存标题',
  coverUrl: '',
  sources: [VideoSource(quality: quality, url: r'C:\a\v1.mp4')],
  tags: const [],
  playlist: const [],
  related: const [],
);

/// 建好的页面是一段 Text；用有没有 Text 判断「是否已建页」。
bool get _hasPage => find.byType(Text).evaluate().isNotEmpty;

void main() {
  setUp(() => playWindowPageBuilder = _stubPage);
  tearDown(() {
    cachedVideoLookup = (id) async => null;
  });

  testWidgets('查询未完成前不建播放页', (tester) async {
    final completer = Completer<VideoDetail?>();
    cachedVideoLookup = (_) => completer.future;

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();

    expect(_hasPage, isFalse, reason: '结果未定时不该建播放页');

    completer.complete(_cached());
    await tester.pump();
    await tester.pump();

    expect(_hasPage, isTrue);
    expect(find.text(r'page:v1:cached:C:\a\v1.mp4'), findsOneWidget);
  });

  testWidgets('命中缓存 → 建页面时带上本地 VideoDetail', (tester) async {
    cachedVideoLookup = (_) async => _cached();

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(find.text(r'page:v1:cached:C:\a\v1.mp4'), findsOneWidget);
  });

  testWidgets('没有缓存 → 建页面时 localVideo 为空（走网络）', (tester) async {
    cachedVideoLookup = (_) async => null;

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(find.text('page:v1:network'), findsOneWidget);
  });

  testWidgets('查询抛异常 → 回退网络播放，而不是卡在加载态', (tester) async {
    cachedVideoLookup = (_) async => throw StateError('boom');

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();

    expect(
      find.text('page:v1:network'),
      findsOneWidget,
      reason: '读缓存失败也必须能打开视频',
    );
  });

  testWidgets('整段过程中只查询一次缓存', (tester) async {
    var lookups = 0;
    cachedVideoLookup = (_) async {
      lookups++;
      return _cached();
    };

    await tester.pumpWidget(const MaterialApp(home: PlayWindowVideo(id: 'v1')));
    await tester.pump();
    await tester.pump();
    await tester.pump();

    expect(lookups, 1, reason: '不该反复读盘');
  });
}
