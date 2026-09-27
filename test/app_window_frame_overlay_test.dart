// 回归测试：AppWindowFrame 在 MaterialApp.builder 里（Navigator 之外）提供的自定义
// 标题栏必须能正常渲染，尤其是里面用了 Tooltip 的控件。
//
// 用户报的现象：播放窗口里鼠标移到标题栏右半部分，那一整块变成灰色（其余正常）。
//
// 根因：AppWindowFrame 跑在 MaterialApp.builder 回调里，也就是包在 Navigator **外面**；
// 而 Overlay 是每个 route 各自建在 Navigator **内部**。播放窗口那条标题栏用了
// Tooltip，它需要 Overlay 祖先 —— 缺了就抛「No Overlay widget found ... RawTooltip
// widgets require an Overlay widget ancestor within the closest LookupBoundary」，
// 整条标题栏被 RenderErrorBox（默认底色 0xF0C0C0C0，叠在深色上就是截图里那个
// (183,183,183) 的灰块）顶掉。
//
// 悬停才发作是因为 Tooltip 懒构建：鼠标移上去才第一次去找 Overlay。
// 主窗口的 AppTitleBar 从不用 Tooltip，所以这个问题以前从未暴露。
//
// 这个文件守住「builder 层放带 Tooltip 的标题栏不能抛异常」。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/window/app_title_bar.dart';

/// 固定返回一份设置的替身：不读盘、不碰网络。
class _StubSettings extends SettingsController {
  _StubSettings(this._value);
  final AppSettings _value;

  @override
  Future<AppSettings> build() async => _value;
}

/// 复刻播放窗口的结构：MaterialApp.builder 里放 AppWindowFrame + 自定义标题栏。
/// builder 的 child 是 Navigator（内部才有 Overlay），所以标题栏在 Navigator 之外。
Widget _host({required Widget titleBar}) => ProviderScope(
  overrides: [
    settingsProvider.overrideWith(
      () => _StubSettings(const AppSettings(useSystemTitleBar: false)),
    ),
  ],
  child: MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    // 与 PlayWindowApp 一致：AppWindowFrame 在 builder 里，包住路由内容。
    builder: (context, child) =>
        AppWindowFrame(titleBar: titleBar, child: child ?? const SizedBox()),
    home: const Scaffold(body: ColoredBox(color: Colors.black)),
  ),
);

/// 一个最小的「带 Tooltip 的标题栏」，模拟播放窗口那条的关键特征。
class _TooltipTitleBar extends StatelessWidget {
  const _TooltipTitleBar();

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1E2022),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          const Text('左侧', style: TextStyle(color: Colors.white)),
          const Spacer(),
          // 就是它需要 Overlay 祖先。
          Tooltip(
            message: '窗口置顶',
            child: IconButton(
              onPressed: () {},
              icon: const Icon(Icons.push_pin_outlined, color: Colors.white),
            ),
          ),
          Tooltip(
            message: '画中画',
            child: IconButton(
              onPressed: () {},
              icon: const Icon(
                Icons.branding_watermark_outlined,
                color: Colors.white,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('builder 层的标题栏渲染时不得抛「No Overlay widget found」', (tester) async {
    await tester.pumpWidget(_host(titleBar: const _TooltipTitleBar()));
    await tester.pump();

    // 有任何 framework 异常（含 Overlay 缺失）都会让这条断言失败。
    expect(tester.takeException(), isNull);
    expect(find.text('左侧'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
  });

  testWidgets('鼠标悬停到 Tooltip 控件上不抛异常（这正是用户触发的方式）', (tester) async {
    await tester.pumpWidget(_host(titleBar: const _TooltipTitleBar()));
    await tester.pump();

    // Tooltip 是懒构建的：必须真的把指针移上去才会去找 Overlay。
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    await gesture.moveTo(tester.getCenter(find.byIcon(Icons.push_pin_outlined)));
    await tester.pump(const Duration(milliseconds: 600));

    expect(
      tester.takeException(),
      isNull,
      reason: '悬停 Tooltip 不能因为缺 Overlay 而抛异常（会整条栏变灰）',
    );
    // Tooltip 文案应该已经弹出。
    expect(find.text('窗口置顶'), findsOneWidget);
  });

  testWidgets('标题栏内容更新后仍然生效（Overlay 宿主不能把 child 冻住）', (tester) async {
    // Overlay 的 initialEntries 只在 initState 插一次；若不自己刷新 entry，
    // 后续 child 变化就不会体现。这里用一个会变的自定义标题栏验证。
    var label = '第一话';
    late StateSetter setLabel;
    await tester.pumpWidget(
      _host(
        titleBar: StatefulBuilder(
          builder: (context, setState) {
            setLabel = setState;
            return Material(
              color: const Color(0xFF1E2022),
              child: SizedBox(
                height: 48,
                child: Center(
                  child: Text(
                    label,
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('第一话'), findsOneWidget);

    setLabel(() => label = '第二话');
    await tester.pump();
    expect(
      find.text('第二话'),
      findsOneWidget,
      reason: 'Overlay 宿主必须把 child 的变化透传进去',
    );
  });
}
