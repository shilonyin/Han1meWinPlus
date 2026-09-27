import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/video/play_window.dart';

/// 记录每次启动请求的参数，并按需失败——用来覆盖多进程播放窗口的启动与回退。
class _FakeLauncher {
  _FakeLauncher({this.succeeds = true});

  final bool succeeds;
  final List<List<String>> calls = [];

  Future<bool> call(List<String> arguments) async {
    calls.add(arguments);
    return succeeds;
  }
}

/// 把 [launchExecutable] 换成假实现，测试结束自动还原。
_FakeLauncher _useLauncher({bool succeeds = true}) {
  final previous = launchExecutable;
  final fake = _FakeLauncher(succeeds: succeeds);
  launchExecutable = fake.call;
  addTearDown(() => launchExecutable = previous);
  return fake;
}

/// 一个只挂 /video/:id 的最小路由，用来看 openVideo 到底 push 了没有。
class _Probe {
  final List<String> pushed = [];
}

Widget _app(_Probe probe, {bool openInWindow = true}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(
      () => _StubSettings(AppSettings(openVideoInWindow: openInWindow)),
    ),
  ],
  child: MaterialApp.router(
    routerConfig: GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            // 用 Consumer 拿真正的 WidgetRef，并 watch settingsProvider——
            // 不 watch 的话 provider 永远不会初始化，openVideo 里读到的会是
            // AsyncLoading（valueOrNull = null，fallback 成默认 true）。
            body: Consumer(
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                return Center(
                  child: ElevatedButton(
                    onPressed: () => openVideo(context, ref, 'v123'),
                    child: const Text('open'),
                  ),
                );
              },
            ),
          ),
        ),
        GoRoute(
          path: '/video/:id',
          builder: (context, state) {
            probe.pushed.add(state.uri.toString());
            return Scaffold(body: Text('video ${state.pathParameters['id']}'));
          },
        ),
      ],
    ),
  ),
);

/// 固定返回一份设置的 SettingsController 替身（不读盘、不碰网络）。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// 挂载 App、等 settingsProvider 首次 build 完成（否则 openVideo 读到的还是
/// AsyncLoading，valueOrNull 为 null，会 fallback 成默认值 true 而不是用例里
/// 指定的设置）、点击、再等路由跳完。
Future<void> _openVideo(
  WidgetTester tester,
  _Probe probe, {
  bool openInWindow = true,
}) async {
  await tester.pumpWidget(_app(probe, openInWindow: openInWindow));
  await tester.pumpAndSettle();
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  group('PlayWindowArgs.fromArguments', () {
    test('完整参数（flag + video）→ 解析出视频 id', () {
      final args = PlayWindowArgs.fromArguments([
        '--play-window',
        '--video=abc123',
      ]);
      expect(args, isNotNull);
      expect(args!.videoId, 'abc123');
    });

    test('参数顺序颠倒照样解析（runner 不保证顺序）', () {
      final args = PlayWindowArgs.fromArguments([
        '--video=abc123',
        '--play-window',
      ]);
      expect(args?.videoId, 'abc123');
    });

    test('只有 flag、没有 video → 不是播放窗口启动', () {
      expect(PlayWindowArgs.fromArguments(['--play-window']), isNull);
    });

    test('只有 video、没有 flag → 不是播放窗口启动（普通启动也可能带参数）', () {
      expect(PlayWindowArgs.fromArguments(['--video=abc123']), isNull);
    });

    test('--video= 为空 → 不启动播放窗口（否则会开一个加载不出视频的窗口）', () {
      expect(
        PlayWindowArgs.fromArguments(['--play-window', '--video=']),
        isNull,
      );
    });

    test('无参数（双击启动）→ 走主应用', () {
      expect(PlayWindowArgs.fromArguments(const []), isNull);
    });

    test('深链参数不会被误判成播放窗口', () {
      expect(
        PlayWindowArgs.fromArguments(['han1me://video/abc']),
        isNull,
      );
    });

    test('同时带多个参数时取最后一个 video', () {
      final args = PlayWindowArgs.fromArguments([
        '--play-window',
        '--video=first',
        '--video=second',
      ]);
      expect(args?.videoId, 'second');
    });
  });

  group('launchPlayWindow / revealMainWindow', () {
    test('launchPlayWindow 带上 --play-window 与 --video=<id>', () async {
      final fake = _useLauncher();
      final ok = await launchPlayWindow('abc123');
      expect(ok, isTrue);
      expect(fake.calls, [
        ['--play-window', '--video=abc123'],
      ]);
    });

    test('revealMainWindow 无参启动（交给 runner 的单实例逻辑激活主窗口）', () async {
      final fake = _useLauncher();
      await revealMainWindow();
      expect(fake.calls, [<String>[]]);
    });

    test('启动失败时返回 false（调用方据此回退）', () async {
      _useLauncher(succeeds: false);
      expect(await launchPlayWindow('abc123'), isFalse);
    });
  });

  group('openVideo 的分支', () {
    testWidgets('开启独立窗口且启动成功 → 不 push 播放页', (tester) async {
      final fake = _useLauncher();
      final probe = _Probe();
      await _openVideo(tester, probe);

      expect(fake.calls, [
        ['--play-window', '--video=v123'],
      ]);
      expect(probe.pushed, isEmpty);
    });

    testWidgets('启动失败 → 回退到窗口内 push 播放页（不能让用户点不开）', (tester) async {
      _useLauncher(succeeds: false);
      final probe = _Probe();
      await _openVideo(tester, probe);

      expect(probe.pushed, ['/video/v123']);
      expect(find.text('video v123'), findsOneWidget);
    });

    testWidgets('设置里关掉独立窗口 → 直接在当前窗口 push，不起进程', (tester) async {
      final fake = _useLauncher();
      final probe = _Probe();
      await _openVideo(tester, probe, openInWindow: false);

      expect(fake.calls, isEmpty);
      expect(probe.pushed, ['/video/v123']);
    });
  });
}
