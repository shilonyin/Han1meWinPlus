// 回归测试：设置卡片列表的「被包一层就降级成裸行」问题。
//
// 背景（用户报的现象）：网络设置页里「投屏接收端」那一行没有卡片背景，
// 和上面「常规」分组里的条目明显不统一。
//
// 根因：SettingsCardList 原来按**运行时类型**分派 children ——
//     children.whereType<SettingsCardItem>()  → 进 SettingsSection（有玻璃卡片）
//     其余（包括被包装的）                     → 只套一层 Padding，没有卡片
// 投屏那一项为了监听 CastReceiver.instance.running，被 ValueListenableBuilder
// 包了一层，运行时类型不再等于 SettingsCardItem，于是整张卡片皮肤丢失。
// 热键页按键捕获态用 Focus 包 SettingsCardItem，是同一个坑。
//
// 现在 SettingsCardList 不再按类型分派，全部交给 SettingsSection.tiles。
// 下面这些断言就是钉住这一点：**被包装过的条目必须和裸条目一样落在 GlassPanel 里**。
// 变异验证过：把生产代码改回 whereType 分派，本文件会红。
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/core/settings.dart';
import 'package:han1me_win_plus/src/features/settings/settings_card_list.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_panel.dart';

Widget _host(Widget child) => ProviderScope(
  child: MaterialApp(
    theme: appTheme(null, AppThemeColor.purple.seedColor('62539F')),
    home: Scaffold(body: child),
  ),
);

/// 该 widget 是否落在玻璃卡片（GlassPanel）子树里 —— 卡片皮肤的唯一可靠标志。
bool _inCard(WidgetTester tester, Finder finder) =>
    find.ancestor(of: finder, matching: find.byType(GlassPanel)).evaluate().isNotEmpty;

void main() {
  testWidgets('裸条目与包装条目都渲染成卡片', (tester) async {
    final running = ValueNotifier(false);
    await tester.pumpWidget(
      _host(
        SettingsCardList(
          title: '网络',
          children: [
            const SettingsCardItem(title: '裸条目'),
            ValueListenableBuilder<bool>(
              valueListenable: running,
              builder: (context, value, _) => SettingsCardItem(title: '包装条目 $value'),
            ),
            Focus(child: const SettingsCardItem(title: 'Focus 包装条目')),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 基线：这条在修复前也是绿的，用来证明检测手段本身有效。
    expect(_inCard(tester, find.text('裸条目')), isTrue, reason: '裸条目本来就该在卡片里');
    // 下面两条修复前为假 —— 它们才是本次回归的靶子。
    expect(_inCard(tester, find.text('包装条目 false')), isTrue, reason: 'ValueListenableBuilder 包住后不能丢卡片');
    expect(_inCard(tester, find.text('Focus 包装条目')), isTrue, reason: 'Focus 包住后不能丢卡片');
  });

  testWidgets('包装条目的监听值变化后，卡片仍在且文案跟着更新', (tester) async {
    final running = ValueNotifier(false);
    await tester.pumpWidget(
      _host(
        SettingsCardList(
          children: [
            ValueListenableBuilder<bool>(
              valueListenable: running,
              builder: (context, value, _) => SettingsCardItem(
                title: '投屏接收端',
                subtitle: value ? '已在局域网广播' : '未广播',
              ),
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('未广播'), findsOneWidget);
    expect(_inCard(tester, find.text('投屏接收端')), isTrue);

    running.value = true;
    await tester.pumpAndSettle();

    expect(find.text('已在局域网广播'), findsOneWidget);
    expect(find.text('未广播'), findsNothing);
    expect(_inCard(tester, find.text('投屏接收端')), isTrue, reason: '重建后不能掉出卡片');
  });

  testWidgets('每一条各有一张卡片，顺序与传入一致', (tester) async {
    await tester.pumpWidget(
      _host(
        SettingsCardList(
          children: const [
            SettingsCardItem(title: '第一'),
            SettingsCardItem(title: '第二'),
            SettingsCardItem(title: '第三'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(GlassPanel), findsNWidgets(3), reason: '一条一张卡，不能合并也不能少');
    final tops = ['第一', '第二', '第三'].map((t) => tester.getTopLeft(find.text(t)).dy).toList();
    expect(tops[0] < tops[1] && tops[1] < tops[2], isTrue, reason: '顺序不能被重排');
  });

  testWidgets('分组标题与空列表', (tester) async {
    await tester.pumpWidget(
      _host(
        SettingsCardList(
          title: '网络',
          children: const [SettingsCardItem(title: '站点')],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('网络'), findsOneWidget, reason: '分组标题要渲染');

    // 空列表不该崩，也不该留下一个空的卡片。
    await tester.pumpWidget(_host(const SettingsCardList(children: [])));
    await tester.pumpAndSettle();
    expect(find.byType(GlassPanel), findsNothing);
  });
}
