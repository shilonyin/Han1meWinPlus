// 回归测试：AppWindowFrame 在 MaterialApp.builder 里（Navigator 之外）提供的自定义
// 标题栏必须能正常渲染，而且**里面不能放依赖 Overlay 的组件**。
//
// 用户报的现象（第一轮）：播放窗口里鼠标移到标题栏上，那一整块变成灰色。
// 根因：AppWindowFrame 跑在 MaterialApp.builder 回调里，也就是包在 Navigator
// **外面**；而 Overlay 是每个 route 各自建在 Navigator **内部**。当时标题栏用了
// Tooltip，它需要 Overlay 祖先 —— 缺了就抛「No Overlay widget found ... RawTooltip
// widgets require an Overlay widget ancestor」，整条标题栏被 RenderErrorBox
// （默认底色 0xF0C0C0C0，叠在深色上就是截图里那个 (183,183,183) 灰块）顶掉。
// 悬停才发作是因为 Tooltip 懒构建。
//
// 用户报的现象（第二轮）：改成给标题栏单独套一层 Overlay.wrap 之后，提示气泡
// **被裁掉半截** —— 因为那条 Overlay 只有标题栏本身那么高，气泡往下弹就落到
// 内容区被裁。所以最终方案是**标题栏里不挂 Tooltip**，状态改用悬停高亮表达、
// 无障碍标签走 Semantics。
//
// 这个文件守住「builder 层的标题栏渲染不抛异常」以及「不引入需要 Overlay 的组件」。
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_controller.dart';
import 'package:han1me_win_plus/src/features/window/app_title_bar.dart';
import 'package:han1me_win_plus/src/features/window/play_window_title_bar.dart';

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
    builder: (context, child) =>
        AppWindowFrame(titleBar: titleBar, child: child ?? const SizedBox()),
    home: const Scaffold(body: ColoredBox(color: Colors.black)),
  ),
);

/// 一个不含任何 Overlay 依赖的标题栏，模拟播放窗口那条的形状。
class _PlainTitleBar extends StatelessWidget {
  const _PlainTitleBar({this.label = '第一话'});

  final String label;

  @override
  Widget build(BuildContext context) => Material(
    color: const Color(0xFF1E2022),
    child: SizedBox(
      height: 48,
      child: Row(
        children: [
          const Text('回到主界面', style: TextStyle(color: Colors.white)),
          const Spacer(),
          Text(label, style: const TextStyle(color: Colors.white)),
          const Spacer(),
          const Icon(Icons.push_pin_outlined, color: Colors.white),
          const Icon(Icons.branding_watermark_outlined, color: Colors.white),
          const Icon(Icons.close, color: Colors.white),
        ],
      ),
    ),
  );
}

void main() {
  testWidgets('builder 层的标题栏渲染时不得抛异常', (tester) async {
    await tester.pumpWidget(_host(titleBar: const _PlainTitleBar()));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('回到主界面'), findsOneWidget);
    expect(find.byIcon(Icons.push_pin_outlined), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);
  });

  testWidgets('标题栏内容更新后仍然生效', (tester) async {
    var label = '第一话';
    late StateSetter setLabel;
    await tester.pumpWidget(
      _host(
        titleBar: StatefulBuilder(
          builder: (context, setState) {
            setLabel = setState;
            return _PlainTitleBar(label: label);
          },
        ),
      ),
    );
    await tester.pump();
    expect(find.text('第一话'), findsOneWidget);

    setLabel(() => label = '第二话');
    await tester.pump();
    expect(find.text('第二话'), findsOneWidget);
  });

  testWidgets('真实的播放窗口标题栏里不得出现需要 Overlay 的组件', (tester) async {
    // 这是本轮修复的核心约束：标题栏没有 Overlay 祖先，放了 Tooltip / 菜单这类
    // 组件就会在第一次用到时抛异常、整条栏变成灰块。
    // 这里直接挂真实的 PlayWindowTitleBar，确保将来没人再把 Tooltip 加回去。
    await tester.pumpWidget(
      _host(titleBar: PlayWindowTitleBar(onHome: () {})),
    );
    await tester.pump();

    expect(
      find.byType(Tooltip),
      findsNothing,
      reason: '标题栏里不能有 Tooltip（没有 Overlay 祖先，悬停时会整条变灰）',
    );
    expect(find.byType(PopupMenuButton<Object?>), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('真实标题栏的悬停不抛异常（用户就是这样触发的）', (tester) async {
    await tester.pumpWidget(
      _host(titleBar: PlayWindowTitleBar(onHome: () {})),
    );
    await tester.pump();

    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: Offset.zero);
    addTearDown(gesture.removePointer);
    await tester.pump();

    // 逐个悬停到右侧那些图标按钮上
    for (final icon in [
      Icons.push_pin_outlined,
      Icons.branding_watermark_outlined,
      Icons.remove,
      Icons.close,
    ]) {
      final finder = find.byIcon(icon);
      if (finder.evaluate().isEmpty) continue;
      await gesture.moveTo(tester.getCenter(finder));
      await tester.pump(const Duration(milliseconds: 700));
      expect(
        tester.takeException(),
        isNull,
        reason: '悬停 $icon 不该抛异常（会整条栏变灰）',
      );
    }
  });
}
