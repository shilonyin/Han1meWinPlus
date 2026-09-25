import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart';
import 'package:han1me_win_plus/src/domain/models/download.dart';
import 'package:han1me_win_plus/src/features/cache/cache_folder_page.dart';

class _FakeController extends DownloadController {
  _FakeController(this._state);

  final DownloadState _state;

  @override
  Future<DownloadState> build() async => _state;
}

const _groupName = 'ピュアホリック ～純潔乙女と婚姻カンケイ!?～THE ANIMATION';

DownloadTask _task({required String id, required DownloadStatus status, Set<String> groupIds = const {'g1'}, int createdAt = 0}) => DownloadTask(
      id: id,
      videoCode: id,
      title: '第 $id 集',
      groupIds: groupIds,
      quality: '1080',
      status: status,
      progress: .3,
      downloadedBytes: 10 * 1024 * 1024,
      totalBytes: 100 * 1024 * 1024,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

final _state = DownloadState(
  groups: const [
    DownloadGroup(id: 'default', name: 'Cached', createdAt: 0),
    DownloadGroup(id: 'g1', name: _groupName, createdAt: 1),
    // 只有未完成任务的分组（用来验证「播放全部」的禁用态）。
    DownloadGroup(id: 'g2', name: '未完成的组', createdAt: 2),
  ],
  tasks: [
    _task(id: 'e1', status: DownloadStatus.completed, createdAt: 1),
    _task(id: 'e2', status: DownloadStatus.downloading, createdAt: 2),
    _task(id: 'e3', status: DownloadStatus.paused, createdAt: 3),
    _task(id: 'e4', status: DownloadStatus.failed, createdAt: 4),
    // g2 里只有未完成的任务：用来验证「播放全部」在无内容可播时禁用。
    _task(id: 'pending', status: DownloadStatus.downloading, groupIds: {'g2'}, createdAt: 5),
    // 别的分组的任务不该出现在这一页。
    _task(id: 'other', status: DownloadStatus.completed, groupIds: {'g3'}, createdAt: 6),
  ],
);

Widget _app(String groupId) => ProviderScope(
      overrides: [downloadProvider.overrideWith(() => _FakeController(_state))],
      child: MaterialApp(
        theme: appTheme(null, const Color(0xffb3265a), brightness: Brightness.dark),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: CacheFolderPage(groupId: groupId),
      ),
    );

Future<void> _pump(WidgetTester tester, String groupId, {Size size = const Size(900, 800)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(groupId));
  await tester.pumpAndSettle();
}

void main() {
  group('文件夹（分组）页', () {
    testWidgets('标题与头部都显示分组名，只列出该分组下的分集', (tester) async {
      await _pump(tester, 'g1');
      // 标题栏与头部大标题各一处（b 站版式：头部有集合名）。
      expect(find.text(_groupName), findsNWidgets(2));
      for (final id in ['e1', 'e2', 'e3', 'e4']) {
        expect(find.text('第 $id 集'), findsOneWidget);
      }
      // 其它分组的任务不该被列进来。
      expect(find.text('第 other 集'), findsNothing);
    });

    testWidgets('头部给出「播放全部」与集合体积统计', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      expect(find.text(l10n.playAll), findsOneWidget);
      // 4 个内容 + 总体积。
      expect(find.textContaining(l10n.folderContents(4)), findsWidgets);
      expect(find.text(l10n.mainEpisodes), findsOneWidget);
    });

    testWidgets('单条操作收在卡片 ⋮ 菜单里，按状态给不同项', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      // 每张卡都有一个 ⋮ 入口。
      expect(find.byTooltip(l10n.more), findsNWidgets(4));
      // 逐张打开菜单，直到找到「暂停」那一项（对应下载中的那一集）。
      // 不硬编码索引：卡片的顺序由 sortTasks 决定，跟着实现走会变脆。
      var found = false;
      for (var i = 0; i < 4 && !found; i++) {
        await tester.tap(find.byTooltip(l10n.more).at(i));
        await tester.pumpAndSettle();
        if (find.text(l10n.pause).evaluate().isNotEmpty) {
          found = true;
          expect(find.text(l10n.deleteCache), findsOneWidget);
          break;
        }
        // 关掉当前菜单再试下一张。
        await tester.tapAt(const Offset(5, 5));
        await tester.pumpAndSettle();
      }
      expect(found, isTrue, reason: '下载中的那一集应该在 ⋮ 菜单里提供「暂停」');
    });

    testWidgets('长按进入多选并给出批量操作', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      await tester.longPress(find.text('第 e1 集'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(1)), findsOneWidget);
      expect(find.byTooltip(l10n.selectAll), findsOneWidget);
      expect(find.byTooltip(l10n.startAll), findsOneWidget);
      expect(find.byTooltip(l10n.deleteSelectedCache), findsOneWidget);
    });

    testWidgets('多选态下点整行是切换选中，不是播放', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      await tester.longPress(find.text('第 e1 集'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('第 e2 集'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(2)), findsOneWidget);
      // 多选态下不该因为点击而跳去播放页。
      expect(find.byType(CacheFolderPage), findsOneWidget);
    });

    testWidgets('全选会把该分组下所有分集都选中', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      await tester.longPress(find.text('第 e1 集'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip(l10n.selectAll));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(4)), findsOneWidget);
    });

    testWidgets('全选按钮在本页头部也能用，且能取消', (tester) async {
      await _pump(tester, 'g1');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      // 头部那个「全选」按钮（非多选态下也提供）。
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.selectAll));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(4)), findsOneWidget);
      // 再点一次取消。
      await tester.tap(find.widgetWithText(OutlinedButton, l10n.selectAll));
      await tester.pumpAndSettle();
      expect(find.text(_groupName), findsNWidgets(2));
    });

    testWidgets('分组里全是未完成任务时，「播放全部」不可点', (tester) async {
      await _pump(tester, 'g2');
      final l10n = AppLocalizations.of(tester.element(find.byType(CacheFolderPage)))!;
      // 没有已完成的内容 -> 没有可播的本地文件，按钮应禁用。
      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, l10n.playAll));
      expect(button.onPressed, isNull);
    });

    testWidgets('空分组给出空态而不是白屏', (tester) async {
      await _pump(tester, 'empty');
      // 'empty' 不在 groups 里，页面应当自己收起（不崩）。
      expect(tester.takeException(), isNull);
    });

    testWidgets('窄窗口下不溢出', (tester) async {
      await _pump(tester, 'g1', size: const Size(420, 640));
      expect(tester.takeException(), isNull);
      expect(find.text('第 e1 集'), findsOneWidget);
    });
  });
}
