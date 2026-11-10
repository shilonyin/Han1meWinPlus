// 回归：点一行设置时，**其他行的缩放必须保持不变**。
//
// 背景（用户报的现象）：点任意按钮，左侧/其它行的文字会跟着一起缩一下，
// 出现一个缩小版的重影。
//
// 这条测试直接渲染两张 `SettingsCardList`，点第 1 张里的一行，
// 断言第 2 张里所有行的缩放矩阵仍然严格是单位阵。
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:han1me_win_plus/src/features/settings/settings_card_list.dart';
import 'package:han1me_win_plus/src/features/shared/press_scale.dart';

void main() {
  testWidgets('点一个开关，另一张卡里的开关不缩放', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: Column(
              children: [
                SettingsCardList(
                  children: [
                    SettingsCardItem(
                      title: 'A1',
                      subtitle: 'a1 副标题',
                      trailing: Switch(value: false, onChanged: (_) {}),
                    ),
                    SettingsCardItem(title: 'A2', subtitle: 'a2 副标题'),
                  ],
                ),
                SettingsCardList(
                  children: [
                    SettingsCardItem(
                      title: 'B1',
                      subtitle: 'b1 副标题',
                      trailing: Switch(value: false, onChanged: (_) {}),
                    ),
                    SettingsCardItem(title: 'B2', subtitle: 'b2 副标题'),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );

    /// 收集所有 `PressScale` 自己那层 `Transform` 的缩放值（按树中顺序）。
    List<double> scales() => tester
        .widgetList<Transform>(find.byType(Transform))
        .where((t) => t.transformHitTests == false)
        .map((t) => t.transform.entry(0, 0))
        .toList();

    final before = scales();
    expect(
      before.length,
      greaterThanOrEqualTo(2),
      reason: '带开关的行各有一个 PressScale',
    );
    expect(before.every((s) => s == 1.0), isTrue, reason: '初始全部为 1');

    // 按第 1 个 PressScale（A 卡第一行的开关）。
    final pressScales = find.byType(PressScale);
    expect(pressScales, findsNWidgets(2));
    final target = tester.getCenter(pressScales.at(0));
    final gesture = await tester.startGesture(target);
    await tester.pumpAndSettle();

    final during = scales();
    // 被按的那个缩到 0.96，其余必须仍是 1。
    for (var i = 0; i < during.length; i++) {
      if (i == 0) {
        expect(during[i], closeTo(0.96, 0.001), reason: '被按的第 1 个应当缩到 0.96');
      } else {
        expect(during[i], 1.0, reason: '第 ${i + 1} 个没有被按，不该缩放');
      }
    }

    await gesture.up();
    await tester.pumpAndSettle();
    expect(scales().every((s) => s == 1.0), isTrue, reason: '抬起后全部回到 1');
  });
}
