// 回归测试：窗口材质（Mica / Acrylic）的下发路径。
//
// 背景：独立播放窗口曾经完全不下发材质——只有主窗口的 AppStartupEffects 会调用
// WindowBackdropEffect.apply。播放窗口虽然给 appTheme 传了 backdrop（表面是半透明的），
// 但系统层从没收到材质请求，于是半透明的设置页 / 搜索页透出的是 runner 的纯色底刷，
// 而不是桌面壁纸，观感比主窗口平一块。实测播放窗口的 SYSTEMBACKDROP_TYPE 为 0
//（未应用），主窗口为 3（Acrylic）。
//
// 这里用 windowBackdropApplier 这个测试缝把真正碰 DWM 的调用换掉，
// 从而在纯 Dart 单元测试里观察「下发了什么、下发了几次、失败后是否重试」。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/core/window_backdrop.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/video/play_window_app.dart';

/// 记录每次下发请求；可按序号让某几次失败，用来验证「失败不记账、会重试」。
class _Recorder {
  _Recorder({this.failOn = const {}});

  /// 第几次调用（0 基）返回失败。
  final Set<int> failOn;
  final List<(WindowBackdrop, bool)> calls = [];

  Future<bool> call(WindowBackdrop backdrop, {required bool dark}) async {
    final index = calls.length;
    calls.add((backdrop, dark));
    return !failOn.contains(index);
  }
}

/// 把 windowBackdropApplier 换成记录器，测试结束自动还原。
_Recorder _useRecorder({Set<int> failOn = const {}}) {
  final previous = windowBackdropApplier;
  final recorder = _Recorder(failOn: failOn);
  windowBackdropApplier = recorder.call;
  addTearDown(() => windowBackdropApplier = previous);
  return recorder;
}

void main() {
  // 播放窗口落地页换成轻量替身：真实 VideoPage 会拉起一串网络 provider。
  setUp(() => playWindowPageBuilder = ({required id, localVideo, onBack, onHome}) => const SizedBox.shrink());

  group('WindowBackdropController 串行下发', () {
    test('相同组合只下发一次（didChangeDependencies 会反复触发）', () async {
      final recorder = _useRecorder();
      final controller = WindowBackdropController();

      await controller.request(WindowBackdrop.acrylic, dark: false);
      await controller.request(WindowBackdrop.acrylic, dark: false);
      await controller.request(WindowBackdrop.acrylic, dark: false);

      expect(recorder.calls, [(WindowBackdrop.acrylic, false)]);
    });

    test('深浅变化会重新下发（材质要跟着主题走）', () async {
      final recorder = _useRecorder();
      final controller = WindowBackdropController();

      await controller.request(WindowBackdrop.mica, dark: false);
      await controller.request(WindowBackdrop.mica, dark: true);

      expect(recorder.calls, [
        (WindowBackdrop.mica, false),
        (WindowBackdrop.mica, true),
      ]);
    });

    test('切换材质种类会下发', () async {
      final recorder = _useRecorder();
      final controller = WindowBackdropController();

      await controller.request(WindowBackdrop.acrylic, dark: true);
      await controller.request(WindowBackdrop.mica, dark: true);
      await controller.request(WindowBackdrop.none, dark: true);

      expect(recorder.calls.map((c) => c.$1).toList(), [
        WindowBackdrop.acrylic,
        WindowBackdrop.mica,
        WindowBackdrop.none,
      ]);
    });

    test('失败不记成已应用：下一次请求仍会重试', () async {
      // 首次失败（窗口刚创建时 Window.initialize 可能失败），
      // 若把失败也当成已应用，之后主题切换就再也不会重试。
      final recorder = _useRecorder(failOn: {0});
      final controller = WindowBackdropController();

      await controller.request(WindowBackdrop.acrylic, dark: true);
      expect(recorder.calls.length, 1, reason: '第一次尝试');

      // 同样的组合再请求一次：因为上次没成功，必须重试。
      await controller.request(WindowBackdrop.acrylic, dark: true);
      expect(recorder.calls.length, 2, reason: '失败后同组合要重试');
      expect(recorder.calls.last, (WindowBackdrop.acrylic, true));
    });

    test('成功后同组合不再重试', () async {
      final recorder = _useRecorder();
      final controller = WindowBackdropController();

      await controller.request(WindowBackdrop.acrylic, dark: true);
      await controller.request(WindowBackdrop.acrylic, dark: true);

      expect(recorder.calls.length, 1);
    });

    test('并发请求只保留最后一个目标（连点主题按钮）', () async {
      final gate = Completer<void>();
      final previous = windowBackdropApplier;
      final seen = <(WindowBackdrop, bool)>[];
      windowBackdropApplier = (backdrop, {required dark}) async {
        seen.add((backdrop, dark));
        if (seen.length == 1) await gate.future;
        return true;
      };
      addTearDown(() => windowBackdropApplier = previous);

      final controller = WindowBackdropController();
      final first = controller.request(WindowBackdrop.mica, dark: true);
      // 第一个还卡在 gate 上，此时连发两个更新的目标。
      final second = controller.request(WindowBackdrop.acrylic, dark: false);
      final third = controller.request(WindowBackdrop.none, dark: false);
      gate.complete();
      await Future.wait([first, second, third]);

      // 中间的 acrylic 被跳过，最终收敛到最后一次选择。
      expect(seen, [
        (WindowBackdrop.mica, true),
        (WindowBackdrop.none, false),
      ]);
    });
  });

  group('播放窗口也会下发材质', () {
    testWidgets('启动后按设置把材质下发给本窗口的系统层', (tester) async {
      final recorder = _useRecorder();
      const settings = AppSettings(
        themeMode: AppThemeMode.light,
        windowBackdrop: WindowBackdrop.acrylic,
      );

      await tester.pumpWidget(_playWindowApp(settings));
      await tester.pump();

      expect(
        recorder.calls,
        isNotEmpty,
        reason: '播放窗口必须自己下发材质（AppStartupEffects 只挂在主窗口）',
      );
      expect(recorder.calls.last, (WindowBackdrop.acrylic, false));
    });

    testWidgets('深色主题下按深色下发', (tester) async {
      final recorder = _useRecorder();
      const settings = AppSettings(
        themeMode: AppThemeMode.dark,
        windowBackdrop: WindowBackdrop.mica,
      );

      await tester.pumpWidget(_playWindowApp(settings));
      await tester.pump();

      expect(recorder.calls.last, (WindowBackdrop.mica, true));
    });

    testWidgets('材质关闭时不报错，界面照常建起来', (tester) async {
      _useRecorder();
      const settings = AppSettings(
        themeMode: AppThemeMode.light,
        windowBackdrop: WindowBackdrop.none,
      );

      await tester.pumpWidget(_playWindowApp(settings));
      await tester.pump();

      expect(tester.takeException(), isNull);
    });
  });
}

/// 建一个最小可跑的 PlayWindowApp：路由只挂播放页，且把落地页换成轻量替身
/// （真实 VideoPage 会拉起一串网络 provider，测试拆解时噪音太大）。
Widget _playWindowApp(AppSettings settings) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(() => _StubSettings(settings)),
  ],
  child: const PlayWindowApp(videoId: 'v1'),
);

class _StubSettings extends SettingsController {
  _StubSettings(this.initial);

  final AppSettings initial;

  @override
  Future<AppSettings> build() async => initial;
}
