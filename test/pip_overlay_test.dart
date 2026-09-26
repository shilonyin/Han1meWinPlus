import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/data/local/watch_repository.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/video/pip_controller.dart';
import 'package:han1me_win_plus/src/features/video/pip_overlay.dart';
import 'package:video_player/video_player.dart';

/// 画中画（迷你播放器）的状态机与渲染。
///
/// 这里不碰真实播放内核：`VideoPlayerController` 只用来当「同一个实例」的标识，
/// 断言的是「谁持有它」「谁该销毁它」这套所有权转移，以及小窗该不该出现在界面上。

/// 顶掉真实的观看进度仓库：画中画会在播放期间写进度，测试里不该落到磁盘。
class _FakeWatchController extends WatchController {
  @override
  Future<WatchState> build() async => const WatchState(continueItems: [], histories: []);
}

VideoPlayerController _controller() => VideoPlayerController.networkUrl(Uri.parse('https://example.test/a.m3u8'));

VideoDetail _video(String id) => VideoDetail(
      id: id,
      title: '标题 $id',
      coverUrl: '',
      sources: const [VideoSource(quality: '720', url: 'https://example.test/a.m3u8', type: 'hls')],
      tags: const [],
      playlist: const [],
      related: const [],
    );

void main() {
  group('PipController 的所有权转移', () {
    late ProviderContainer container;

    setUp(() {
      container = ProviderContainer(overrides: [watchProvider.overrideWith(_FakeWatchController.new)]);
      addTearDown(container.dispose);
    });

    test('adopt 之后画中画持有播放器，且 owns 认得它', () {
      final pip = container.read(pipControllerProvider.notifier);
      final controller = _controller();
      pip.adopt(video: _video('a'), controller: controller, qualityLabel: '720');

      final state = container.read(pipControllerProvider)!;
      expect(state.video.id, 'a');
      expect(state.qualityLabel, '720');
      expect(state.visible, isTrue);
      expect(pip.owns(controller), isTrue);
    });

    test('takeBack 只交还同一部片的播放器，并把画中画清空', () {
      final pip = container.read(pipControllerProvider.notifier);
      final controller = _controller();
      pip.adopt(video: _video('a'), controller: controller);

      // 视频对不上不交还，画中画保持不变。
      expect(pip.takeBack('b'), isNull);
      expect(container.read(pipControllerProvider), isNotNull);

      expect(pip.takeBack('a'), same(controller));
      expect(container.read(pipControllerProvider), isNull);
      // 交还后画中画不再「拥有」它，播放页 dispose 时才会正常销毁。
      expect(pip.owns(controller), isFalse);
    });

    test('moveTo 记录吸附位置，hide / show 只切可见性', () {
      final pip = container.read(pipControllerProvider.notifier);
      pip.adopt(video: _video('a'), controller: _controller());

      pip.moveTo(left: 24, top: 40, right: null, bottom: null);
      expect(container.read(pipControllerProvider)!.left, 24);
      expect(container.read(pipControllerProvider)!.top, 40);

      pip.hide();
      expect(container.read(pipControllerProvider)!.visible, isFalse);
      expect(container.read(pipVisibleProvider), isFalse);
      // 隐藏不影响位置。
      expect(container.read(pipControllerProvider)!.left, 24);

      pip.show();
      expect(container.read(pipVisibleProvider), isTrue);
    });

    test('close 清空状态并让 owns 变假（随后才销毁播放器）', () async {
      final pip = container.read(pipControllerProvider.notifier);
      final controller = _controller();
      pip.adopt(video: _video('a'), controller: controller);

      await pip.close();
      expect(container.read(pipControllerProvider), isNull);
      expect(pip.owns(controller), isFalse);
    });
  });

  group('PipOverlay 渲染', () {
    testWidgets('没有画中画时不占任何位置', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [watchProvider.overrideWith(_FakeWatchController.new)],
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Stack(children: [PipOverlay()])),
          ),
        ),
      );

      expect(find.byType(Slider), findsNothing);
      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('有画中画时渲染出控制栏（播放 / 音量 / 关闭）', (tester) async {
      final container = ProviderContainer(overrides: [watchProvider.overrideWith(_FakeWatchController.new)]);
      addTearDown(container.dispose);
      container.read(pipControllerProvider.notifier).adopt(video: _video('a'), controller: _controller());

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: Stack(children: [PipOverlay()])),
          ),
        ),
      );
      await tester.pump();

      // 控制栏里的三个常驻入口。音量按钮用的是 Material 的音量图标之一。
      expect(find.byIcon(Icons.play_arrow), findsWidgets);
      expect(find.byIcon(Icons.close), findsOneWidget);
      expect(find.byType(Slider), findsOneWidget);
    });
  });
}
