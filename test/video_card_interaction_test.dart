import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/shared/video_card.dart';
import 'package:han1me_win_plus/src/features/video/play_window.dart';

/// 1x1 的透明 PNG。卡片封面在测试里不需要真图，给个能解码的最小图就够了——
/// 不给的话会走 CachedNetworkImage，测试进程里没有网络也没有缓存目录。
final MemoryImage _cover = MemoryImage(
  base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==',
  ),
);

VideoCard _video(String id) => VideoCard(
  id: id,
  title: '测试视频标题',
  coverUrl: 'https://example.invalid/cover.jpg',
  artist: '测试作者',
  rating: '99%',
  uploadTime: '3-5',
);

/// 固定返回一份设置的 SettingsController 替身（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

Widget _tile(VideoCard video) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(() => _StubSettings(AppSettings())),
  ],
  child: MaterialApp(
    theme: ThemeData(colorSchemeSeed: Colors.indigo),
    home: Scaffold(
      body: Center(
        // 高宽给足：横版卡是「16:9 封面 + 一行元信息」，盒子太小会报
        // RenderFlex 溢出，那是测试自己的问题，不是卡片的问题。
        child: SizedBox(
          width: 260,
          height: 300,
          child: VideoCardTile(
            video: video,
            horizontal: true,
            coverImage: _cover,
          ),
        ),
      ),
    ),
  ),
);

/// 卡片上会有两个 AnimatedScale：PressScale 的按下缩放与封面自己的悬停放大，
/// 所以这里看的是「集合里有没有 1.06」，而不是「唯一那个的 scale」。
Iterable<double> _scales(WidgetTester tester) => tester
    .widgetList<AnimatedScale>(find.byType(AnimatedScale))
    .map((widget) => widget.scale);

void main() {
  test('点开过的 id 记进 openedVideoIdsProvider，重复点不重复记', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    expect(container.read(openedVideoIdsProvider), isEmpty);
    container.read(openedVideoIdsProvider.notifier).mark('a');
    container.read(openedVideoIdsProvider.notifier).mark('a');
    container.read(openedVideoIdsProvider.notifier).mark('b');

    expect(container.read(openedVideoIdsProvider), {'a', 'b'});
  });

  testWidgets('鼠标移到卡片上时封面放大，移开后还原', (tester) async {
    await tester.pumpWidget(_tile(_video('v1')));
    await tester.pumpAndSettle();
    expect(_scales(tester), isNot(contains(1.06)));

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);

    // 悬停放大挂在封面上，不是整张卡：得把光标放到封面上，放到下面
    // 的文字区（卡片中心就在那儿）是不会放大的。
    final card = tester.getRect(find.byType(VideoCardTile));
    await mouse.moveTo(Offset(card.center.dx, card.top + 40));
    await tester.pumpAndSettle();
    expect(_scales(tester), contains(1.06));

    // 移出卡片（左上角在卡片外）。
    await mouse.moveTo(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(_scales(tester), isNot(contains(1.06)));
  });

  testWidgets('点开过的卡片标题染主题色', (tester) async {
    // 换成不真正拉进程的启动器：openVideo 会一路返回 true，不再 push 路由。
    final previous = launchExecutable;
    launchExecutable = (arguments) async => true;
    addTearDown(() => launchExecutable = previous);

    final video = _video('v7');
    await tester.pumpWidget(_tile(video));
    await tester.pumpAndSettle();

    Color? titleColor() =>
        tester.widget<Text>(find.text(video.title)).style?.color;

    final primary = Theme.of(
      tester.element(find.byType(VideoCardTile)),
    ).colorScheme.primary;

    // 还没点开过：标题是主题自己的行内色，不是主题色。
    expect(titleColor(), isNot(primary));

    await tester.tap(find.text(video.title));
    await tester.pumpAndSettle();

    expect(titleColor(), primary);
  });
}
