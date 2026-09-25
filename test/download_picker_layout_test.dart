import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/video/download_picker_sheet.dart';

/// 守的是一个真实反馈：下载弹窗「占画面太多，没有 b 站那种悬浮感」。
///
/// 实测当时的数据：占宽 50.4%、**占高 99.9%、上下留白各 0px** —— 完全贴满屏幕。
/// 根因是在 `Column(mainAxisSize.min)` 里套了 `Flexible + ListView(shrinkWrap)`：
/// Flexible 在 min 模式下仍会把高度顶到 maxHeight，于是集数少时也占满整屏。
///
/// 现在按 b 站「离线缓存」的比例定：卡片宽度取视口的 42%（夹在 460–560），
/// 高度按内容撑、上限 76%。参考值（b 站）约占宽 31%、占高 64%。
void main() {
  Future<void> open(WidgetTester tester, {required int episodes, required Size viewport}) async {
    // 先把上一轮可能还开着的弹窗收掉，否则新 pump 的按钮点不到。
    if (find.byType(Dialog).evaluate().isNotEmpty) {
      Navigator.of(tester.element(find.byType(Dialog))).pop();
      await tester.pumpAndSettle();
    }
    tester.view.physicalSize = viewport;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: appTheme(null, const Color(0xffb3265a), brightness: Brightness.dark),
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              // 与真实调用同一个入口（showDialog + 透明遮罩）。
              onPressed: () => showDownloadPickerSheet(
                context,
                sources: const [
                  VideoSource(quality: '720', url: 'a'),
                  VideoSource(quality: '1080P 高码率', url: 'b'),
                  VideoSource(quality: '4K · HDR 10', url: 'c'),
                ],
                episodes: [
                  for (var i = 1; i <= episodes; i++) VideoCard(id: 'e$i', title: '告白…… $i', coverUrl: ''),
                ],
                currentId: 'e1',
                suggestedGroupName: '告白…… ～ギャル三昧～ [中文字幕]',
                initialAutoGroup: true,
                initialNameFromSeries: true,
                initialTraditional: false,
                groupNames: const {},
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// 卡片本体（带固定 key 的那个 SizedBox）。
  Rect cardRect(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('download-picker-card')));

  group('下载弹窗是悬浮卡片，不占满屏幕', () {
    testWidgets('用户实际视口（1269x714）下，上下都有留白', (tester) async {
      const viewport = Size(1269, 714);
      await open(tester, episodes: 4, viewport: viewport);
      final rect = cardRect(tester);

      final topGap = rect.top;
      final bottomGap = viewport.height - rect.bottom;
      // 关键回归：修复前上下留白都是 0。
      expect(topGap, greaterThan(40), reason: '上方要留出悬浮的余地');
      expect(bottomGap, greaterThan(40), reason: '下方要留出悬浮的余地');
      expect(rect.height, lessThan(viewport.height * 0.8), reason: '不该占满屏幕高度');
      expect(rect.width, lessThan(viewport.width * 0.5), reason: '卡片应明显窄于窗口');
    });

    testWidgets('高度跟着集数走，而不是一律撑满', (tester) async {
      // 每个集数用独立的 view 尺寸驱动重建（同一用例内换数据要重新 pump）。
      const viewport = Size(1269, 900);
      await open(tester, episodes: 2, viewport: viewport);
      final few = cardRect(tester).height;

      // 关掉再重开，避免上一次的弹窗还在树上。
      await tester.binding.setSurfaceSize(viewport);
      await open(tester, episodes: 6, viewport: viewport);
      final many = cardRect(tester).height;

      expect(many, greaterThan(few), reason: '集数多 -> 卡片更高');
      expect(many, lessThan(viewport.height * 0.8), reason: '但也不该顶满');
    });

    testWidgets('窗口很高时卡片不会被拉长（靠内容取高）', (tester) async {
      const tall = Size(1269, 1000);
      await open(tester, episodes: 3, viewport: tall);
      final rect = cardRect(tester);
      expect(rect.height, lessThan(tall.height * 0.6), reason: '3 集的卡片不该在高窗口里被拉长');
      expect(rect.top, greaterThan(150), reason: '高窗口里应该是居中的小卡片');
    });

    testWidgets('窄窗口下卡片按比例收窄，且画质行不溢出', (tester) async {
      const narrow = Size(1000, 714);
      await open(tester, episodes: 8, viewport: narrow);
      final rect = cardRect(tester);
      expect(rect.width, lessThan(narrow.width * 0.5));
      // 之前卡片收到 460 时「画质下拉 + 全选」会溢出 11px。
      expect(tester.takeException(), isNull);
    });

    testWidgets('集数很多时仍不溢出（内部滚动兜底）', (tester) async {
      await open(tester, episodes: 40, viewport: const Size(1269, 714));
      expect(tester.takeException(), isNull);
      final rect = cardRect(tester);
      expect(rect.height, lessThanOrEqualTo(714 * 0.77));
    });
  });
}
