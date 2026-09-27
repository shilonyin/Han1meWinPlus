// 验证：设置异步就绪时 ref.listen 真的会补上那次同步（否则播放器永远不加载）。
//
// 这是上一条修复的配套风险：_syncSource 在设置未就绪时直接返回，
// 若 ref.listen 的就绪回调不触发，播放器就会永远停在加载态（比原 bug 更糟）。
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';

/// 手动控制何时给出设置，用来复现「先 loading、后就绪」的真实时序。
class _DeferredSettings extends SettingsController {
  _DeferredSettings(this.completer);
  final Completer<AppSettings> completer;

  @override
  Future<AppSettings> build() => completer.future;
}

/// 复刻 VideoPlayerPanel.build 里那段 ref.listen 的注册方式与选中值。
class _Probe extends ConsumerStatefulWidget {
  const _Probe({required this.onSync});
  final void Function() onSync;

  @override
  ConsumerState<_Probe> createState() => _ProbeState();
}

class _ProbeState extends ConsumerState<_Probe> {
  var notifications = 0;
  final selected = <(bool, int)>[];

  @override
  Widget build(BuildContext context) {
    ref.listen<(bool, int)>(
      settingsProvider.select((value) {
        final settings = value.valueOrNull;
        return (settings != null, settings?.preferredQuality ?? 720);
      }),
      (previous, next) {
        if (previous == next) return;
        notifications++;
        selected.add(next);
        widget.onSync();
      },
    );
    return const SizedBox.shrink();
  }
}

void main() {
  testWidgets('设置从 loading 变为就绪 → ref.listen 触发一次同步', (tester) async {
    final completer = Completer<AppSettings>();
    var syncCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _DeferredSettings(completer)),
        ],
        child: MaterialApp(home: _Probe(onSync: () => syncCount++)),
      ),
    );
    await tester.pump();

    // 此时设置还在加载：不该有任何同步。
    expect(syncCount, 0, reason: '就绪前不能触发同步');

    // 设置就绪，且偏好是 1080（与 fallback 720 不同 —— 用户真实场景）。
    completer.complete(const AppSettings(preferredQuality: 1080));
    await tester.pumpAndSettle();

    expect(syncCount, 1, reason: '就绪时必须补一次同步，否则播放器永远不加载');
  });

  testWidgets('用户偏好恰好是 720（与 fallback 相同）也要触发', (tester) async {
    // 这是只 select 画质、不 select 就绪状态时会踩的坑：
    // loading 与就绪值折叠成同一个 720，监听不触发，播放器永远不加载。
    final completer = Completer<AppSettings>();
    var syncCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _DeferredSettings(completer)),
        ],
        child: MaterialApp(home: _Probe(onSync: () => syncCount++)),
      ),
    );
    await tester.pump();
    completer.complete(const AppSettings(preferredQuality: 720));
    await tester.pumpAndSettle();

    expect(syncCount, 1, reason: 'record 里的就绪标志能区分 loading 与 720');
  });

  testWidgets('设置反复变化不会重复触发（去抖）', (tester) async {
    final completer = Completer<AppSettings>();
    var syncCount = 0;

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          settingsProvider.overrideWith(() => _DeferredSettings(completer)),
        ],
        child: MaterialApp(home: _Probe(onSync: () => syncCount++)),
      ),
    );
    await tester.pump();
    completer.complete(const AppSettings(preferredQuality: 1080));
    await tester.pumpAndSettle();
    expect(syncCount, 1);

    // 再 pump 几帧（值没变）不该再触发。
    await tester.pump();
    await tester.pump();
    expect(syncCount, 1, reason: '值未变时 previous == next，不应重复同步');
  });
}
