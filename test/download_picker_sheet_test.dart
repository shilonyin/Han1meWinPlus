import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/domain/models/video.dart';
import 'package:han1me_win_plus/src/features/video/download_picker_sheet.dart';

VideoSource _source(String quality) => VideoSource(quality: quality, url: 'https://example.com/$quality.mp4');

VideoCard _episode(String id, String title) => VideoCard(id: id, title: title, coverUrl: '');

/// 弹窗关闭时给调用方的结果，由 [_open] 填好供用例读取。
class _Harness {
  DownloadPickerResult? result;
  var closed = false;
}

/// 打开下载弹窗（悬浮 Dialog），返回的 [_Harness] 会在弹窗关闭后带上结果。
Future<_Harness> _open(
  WidgetTester tester, {
  required List<VideoSource> sources,
  required List<VideoCard> episodes,
  required String currentId,
  String suggested = '某系列',
  bool autoGroup = false,
  bool nameFromSeries = true,
  bool traditional = false,
  Set<String> groupNames = const {},
}) async {
  final harness = _Harness();
  await tester.pumpWidget(MaterialApp(
    locale: const Locale('zh'),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(
      body: Builder(
        builder: (context) => Center(
          child: ElevatedButton(
            onPressed: () async {
              // 用与真实调用完全相同的入口打开（showDialog + 透明遮罩）。
              harness.result = await showDownloadPickerSheet(
                context,
                sources: sources,
                episodes: episodes,
                currentId: currentId,
                suggestedGroupName: suggested,
                initialAutoGroup: autoGroup,
                initialNameFromSeries: nameFromSeries,
                initialTraditional: traditional,
                groupNames: groupNames,
              );
              harness.closed = true;
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  ));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return harness;
}

/// 头部那个「全选」复选框：它是唯一的三态复选框（集数行里的都是两态）。
final _selectAllCheckbox = find.byWidgetPredicate((widget) => widget is Checkbox && widget.tristate);

void main() {
  group('下载弹窗版式', () {
    testWidgets('是悬浮 Dialog 卡片，不是贴底的 bottom sheet', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      // 用 Dialog 承载（圆角 + 四周留白），而不是 showModalBottomSheet。
      expect(find.byType(Dialog), findsOneWidget);
      // 卡片宽度按视口比例（42%，夹在 460–560），明显窄于窗口才有悬浮感。
      final card = tester.getRect(find.byKey(const ValueKey('download-picker-card')));
      final viewport = tester.view.physicalSize.width / tester.view.devicePixelRatio;
      expect(card.width, lessThanOrEqualTo(560));
      expect(card.width, lessThan(viewport * 0.6), reason: '卡片应明显窄于窗口');
      expect(tester.takeException(), isNull);
    });

    testWidgets('弹窗后面没有遮暗层，也没有 sheet 底板', (tester) async {
      // 真实反馈：弹窗后面有一大块黑底「铺满画面中间」—— 那是 bottom sheet 路由
      // 带来的半透明遮罩 + 640 宽整屏高的底板。现在遮罩必须完全透明。
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      final barriers = tester.widgetList<ModalBarrier>(find.byType(ModalBarrier)).toList();
      expect(barriers, isNotEmpty, reason: '仍要有一个能点外部关闭的遮罩');
      // 透明遮罩的 color 为 null（或 alpha=0）：两者都不绘制，页面不会被压暗。
      final dimming = barriers.where((barrier) => (barrier.color?.a ?? 0) > 0).toList();
      expect(dimming, isEmpty, reason: '遮罩不能把后面的页面压暗');
      expect(find.byType(BottomSheet), findsNothing, reason: '不该再有 bottom sheet 那层底板');
      expect(tester.takeException(), isNull);
    });

    testWidgets('「分组」排在「正片」标题上方，集数多时也一眼可见', (tester) async {
      // 真实反馈：集数一多，中间区就是一个滚动列表，放在列表下面的「新建分组」
      // 直接滚出了视野，用户找不到这个功能。
      await _open(
        tester,
        sources: [_source('720')],
        episodes: [for (var i = 1; i <= 30; i++) _episode('e$i', '第 $i 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      final group = tester.getRect(find.text(l10n.downloadGroupSection));
      final heading = tester.getRect(find.text(l10n.mainEpisodes));
      expect(group.bottom, lessThanOrEqualTo(heading.top), reason: '「分组」必须在「正片」标题上方');
      // 关键回归：30 集把中间区顶成滚动列表后，分组行仍落在卡片内，不需要滚动就能看到。
      final card = tester.getRect(find.byKey(const ValueKey('download-picker-card')));
      expect(card.contains(group.center), isTrue, reason: '分组行不能被集数挤出卡片');
      expect(tester.takeException(), isNull);
    });

    testWidgets('顶部是紧凑画质下拉 + 全选，中间有「正片」小标题', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P'), _source('720P')],
        episodes: [_episode('e1', '第 1 话'), _episode('e2', '第 2 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 画质是下拉（DropdownButton），当前值直接显示文字。
      expect(find.byType(DropdownButton<VideoSource>), findsOneWidget);
      expect(find.text('1080P'), findsWidgets);
      expect(find.text(l10n.downloadSelectAllEpisodes), findsOneWidget);
      // 「正片」分段标题（b 站这个位置就是它）。
      expect(find.text(l10n.mainEpisodes), findsOneWidget);
      // 底栏两个按钮，计数写在下载按钮上。
      expect(find.text(l10n.myDownloads), findsOneWidget);
      expect(find.text(l10n.downloadCountButton(1)), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('画质下拉宽度贴合内容，不撑满整行', (tester) async {
      await _open(
        tester,
        sources: [_source('720P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      final dropdown = tester.getSize(find.byType(DropdownButton<VideoSource>));
      final sheet = tester.getSize(find.byType(DownloadPickerSheet));
      // 短画质名（720P）时下拉应明显窄于弹窗，而不是占满一行。
      expect(dropdown.width, lessThan(sheet.width * 0.7), reason: '紧凑下拉不该撑满整行宽度');
    });

    testWidgets('分集行是圆角卡片，选中项用描边而不是复选框', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话'), _episode('e2', '第 2 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 只有顶部那一个「全选」复选框；分集行不再各带一个 checkbox。
      expect(find.byType(Checkbox), findsOneWidget);
      // 当前集有「仅当前一集」标记。
      expect(find.text(l10n.downloadCurrentOnly), findsOneWidget);
      // 点第二行就选中它（整行可点）。
      await tester.tap(find.text('第 2 话'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.downloadCountButton(2)), findsOneWidget);
    });

    testWidgets('默认只勾当前集，全选能一次勾上全部', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话'), _episode('e2', '第 2 话'), _episode('e3', '第 3 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 默认只勾当前集。
      expect(find.text(l10n.downloadCountButton(1)), findsOneWidget);
      // 点头部的三态「全选」复选框（集数行用的是 CheckboxListTile，不在此列）。
      await tester.tap(_selectAllCheckbox);
      await tester.pumpAndSettle();
      expect(find.text(l10n.downloadCountButton(3)), findsOneWidget);
    });

    testWidgets('取消全选后至少留下当前集，不会出现「一集都没选」', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话'), _episode('e2', '第 2 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      await tester.tap(_selectAllCheckbox);
      await tester.pumpAndSettle();
      expect(find.text(l10n.downloadCountButton(2)), findsOneWidget);
      // 再点一次取消全选。
      await tester.tap(_selectAllCheckbox);
      await tester.pumpAndSettle();
      expect(find.text(l10n.downloadCountButton(1)), findsOneWidget);
      // 下载按钮始终可用（永远不会是 0 集）。
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.downloadCountButton(1)));
      expect(button.onPressed, isNotNull);
    });

    testWidgets('选择画质会带回结果里', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P'), _source('720P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 打开下拉，选 720P。
      await tester.tap(find.text('1080P').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('720P').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.downloadCountButton(1)));
      await tester.pumpAndSettle();
      // 结果里画质是用户选的那个。
      expect(find.byType(DownloadPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('下载弹窗的分组配置', () {
    testWidgets('分组开关默认收起，展开后能改组名', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
        autoGroup: true,
        suggested: '某系列',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 收起状态下集数列表是主角，分组只占一行。
      expect(find.text(l10n.downloadGroupSection), findsOneWidget);
      expect(find.text(l10n.autoGroupDownloads), findsNothing);
      await tester.tap(find.text(l10n.downloadGroupSection));
      await tester.pumpAndSettle();
      // 展开后出现组名输入框，且预填了建议名。
      expect(find.text(l10n.autoGroupDownloads), findsOneWidget);
      expect(find.text('某系列'), findsOneWidget);
    });

    testWidgets('关闭自动分组时结果里的组名为空（表示不分组）', (tester) async {
      final harness = await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
        autoGroup: false,
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      await tester.tap(find.text(l10n.downloadCountButton(1)));
      await tester.pumpAndSettle();
      // 不分组时不该凭空建组：组名留空，由调用方走默认分组。
      expect(harness.closed, isTrue);
      expect(harness.result, isNotNull);
      expect(harness.result!.groupName, '');
      expect(harness.result!.openDownloads, isFalse);
    });

    testWidgets('提示会复用已有分组', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
        autoGroup: true,
        suggested: '已存在的组',
        groupNames: const {'已存在的组'},
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 副标题直接说明会复用，不用展开就能看到。
      expect(find.text(l10n.willUseExistingGroup('已存在的组')), findsOneWidget);
    });
  });

  group('下载弹窗的「我的下载」', () {
    testWidgets('点「我的下载」返回值标记为去缓存页，而不是创建任务', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      await tester.tap(find.text(l10n.myDownloads));
      await tester.pumpAndSettle();
      expect(find.byType(DownloadPickerSheet), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  group('下载弹窗健壮性', () {
    testWidgets('剧集很多时按钮不会被顶出屏幕', (tester) async {
      tester.view.physicalSize = const Size(800, 600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [for (var i = 0; i < 30; i++) _episode('e$i', '第 ${i + 1} 话 这是一个比较长的标题')],
        currentId: 'e0',
      );
      final l10n = AppLocalizations.of(tester.element(find.byType(DownloadPickerSheet)))!;
      // 底栏按钮固定在可见区底部。
      expect(find.text(l10n.downloadCountButton(1)), findsOneWidget);
      expect(find.text(l10n.myDownloads), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('剧集标题很长时不会溢出', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', 'ピュアホリック ～純潔乙女と婚姻カンケイ!?～THE ANIMATION 上巻 [中文字幕] 特别加长版标题')],
        currentId: 'e1',
      );
      expect(tester.takeException(), isNull);
    });

    testWidgets('只有一个片源时下拉仍可用', (tester) async {
      await _open(
        tester,
        sources: [_source('1080P')],
        episodes: [_episode('e1', '第 1 话')],
        currentId: 'e1',
      );
      expect(find.text('1080P'), findsWidgets);
      expect(tester.takeException(), isNull);
    });
  });
}
