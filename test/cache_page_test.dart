import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/app/app_theme.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart';
import 'package:han1me_win_plus/src/domain/models/download.dart';
import 'package:han1me_win_plus/src/features/cache/cache_folder_page.dart';
import 'package:han1me_win_plus/src/features/cache/cache_page.dart';

/// 用固定数据顶掉真实的 [DownloadController]（它要读设置、建目录、扫磁盘）。
///
/// 任务都不带封面地址，卡片就不会去碰网络图片；这里验的是布局与分组聚合。
class _FakeController extends DownloadController {
  _FakeController(this._state);

  final DownloadState _state;

  @override
  Future<DownloadState> build() async => _state;
}

const _seriesA = 'ピュアホリック ～純潔乙女と婚姻カンケイ!?～THE ANIMATION';
const _seriesB = '人付き合いが苦手な亡人少女さんと呪いの指輪';

DownloadTask _task({
  required String id,
  required DownloadStatus status,
  Set<String> groupIds = const {},
  int totalBytes = 0,
  int createdAt = 0,
}) =>
    DownloadTask(
      id: id,
      videoCode: id,
      title: '作品 $id',
      groupIds: groupIds,
      quality: '1080',
      status: status,
      progress: .4,
      downloadedBytes: totalBytes ~/ 2,
      totalBytes: totalBytes,
      createdAt: createdAt,
      updatedAt: createdAt,
    );

final _state = DownloadState(
  groups: const [
    DownloadGroup(id: 'default', name: 'Cached', createdAt: 0),
    DownloadGroup(id: 'a', name: _seriesA, createdAt: 1),
    DownloadGroup(id: 'b', name: _seriesB, createdAt: 2),
  ],
  tasks: [
    // 系列 A 两集已下完 -> 聚成一张文件夹卡。
    _task(id: 'a1', status: DownloadStatus.completed, groupIds: {'a'}, totalBytes: 100 * 1024 * 1024),
    _task(id: 'a2', status: DownloadStatus.completed, groupIds: {'a'}, totalBytes: 200 * 1024 * 1024),
    // 系列 B 一集下完。
    _task(id: 'b1', status: DownloadStatus.completed, groupIds: {'b'}, totalBytes: 50 * 1024 * 1024),
    // 没有分组的进默认组。
    _task(id: 'd1', status: DownloadStatus.completed, totalBytes: 10 * 1024 * 1024),
    // 进行中的。
    _task(id: 'p1', status: DownloadStatus.downloading, totalBytes: 400 * 1024 * 1024),
    _task(id: 'p2', status: DownloadStatus.paused, totalBytes: 400 * 1024 * 1024),
    _task(id: 'p3', status: DownloadStatus.queued, totalBytes: 400 * 1024 * 1024),
  ],
);

Widget _app({Size size = const Size(1200, 900)}) => ProviderScope(
      overrides: [downloadProvider.overrideWith(() => _FakeController(_state))],
      child: MaterialApp(
        theme: appTheme(null, const Color(0xffb3265a), brightness: Brightness.dark),
        locale: const Locale('zh'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const CachePage(),
      ),
    );

Future<void> _pump(WidgetTester tester, {Size size = const Size(1200, 900)}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(_app(size: size));
  await tester.pumpAndSettle();
}

void main() {
  group('缓存页状态双页签', () {
    testWidgets('顶部有「已缓存视频 / 正在缓存」两个页签，进行中数量写进标题', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      expect(find.text(l10n.cachedVideos), findsOneWidget);
      // 3 条进行中（下载中 / 暂停 / 等待）。
      expect(find.text('${l10n.activeDownloads} 3'), findsOneWidget);
    });

    testWidgets('已缓存页签按分组聚成文件夹卡，不把每一集摊开', (tester) async {
      await _pump(tester);
      // 系列 A 有 2 集，聚合成一张卡：标题只出现一次。
      expect(find.text(_seriesA), findsOneWidget);
      expect(find.text(_seriesB), findsOneWidget);
      // 「N 个内容」角标说明这张卡里叠了几集。
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      expect(find.text(l10n.folderContents(2)), findsOneWidget);
      // 系列 B 只有 1 集，也是一张文件夹卡（它确实是个分组）。
      expect(find.text(l10n.folderContents(1)), findsOneWidget);
    });

    testWidgets('没有归组的影片单铺一张卡，不会被算进「全部」文件夹里重复一次', (tester) async {
      await _pump(tester);
      // 默认分组在本应用里的语义是「全部任务」，不能当文件夹渲染 ——
      // 否则 d1 会既在文件夹里、又单独铺一张，网格上出现两张一样的卡。
      expect(find.text(_seriesA), findsOneWidget);
      expect(find.text('作品 d1'), findsOneWidget);
      // 「全部」这个组名不该作为文件夹标题出现。
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      expect(find.text(l10n.cachedDownloads), findsNothing);
    });

    testWidgets('切到「正在缓存」页签能看到未完成的任务', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      await tester.tap(find.text('${l10n.activeDownloads} 3'));
      await tester.pumpAndSettle();
      // 三条未完成任务都在。
      expect(find.text('作品 p1'), findsOneWidget);
      expect(find.text('作品 p2'), findsOneWidget);
      expect(find.text('作品 p3'), findsOneWidget);
      // 已完成的那些不该出现在这个页签里。
      expect(find.text('作品 a1'), findsNothing);
    });

    testWidgets('进行中列表按状态给不同操作：下载中可暂停、暂停可继续', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      await tester.tap(find.text('${l10n.activeDownloads} 3'));
      await tester.pumpAndSettle();
      expect(find.byTooltip(l10n.pause), findsWidgets);
      expect(find.byTooltip(l10n.resume), findsWidgets);
    });
  });

  group('缓存页工具栏', () {
    testWidgets('显示容量概览与排序、分组管理入口', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      // 概览按全部已完成内容汇总。
      expect(find.textContaining(l10n.cacheSummary(4, '').split(' · ').first), findsOneWidget);
      expect(find.byTooltip(l10n.taskSort), findsOneWidget);
      expect(find.byTooltip(l10n.groupSettings), findsOneWidget);
    });

    testWidgets('排序菜单里能选最近更新', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      await tester.tap(find.byTooltip(l10n.taskSort));
      await tester.pumpAndSettle();
      expect(find.text(l10n.sortByRecent), findsOneWidget);
      await tester.tap(find.text(l10n.sortByRecent));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  });

  group('缓存页窄窗口', () {
    testWidgets('窄窗口下不溢出，仍然铺出网格', (tester) async {
      await _pump(tester, size: const Size(640, 800));
      expect(tester.takeException(), isNull);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      expect(find.text(l10n.folderContents(2)), findsOneWidget);
    });

    testWidgets('极窄窗口也不报 overflow', (tester) async {
      await _pump(tester, size: const Size(420, 700));
      expect(tester.takeException(), isNull);
    });
  });

  group('缓存页多选', () {
    testWidgets('点开页签后长按进入多选，标题变成已选数量', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      await tester.tap(find.text('${l10n.activeDownloads} 3'));
      await tester.pumpAndSettle();
      await tester.longPress(find.text('作品 p1'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(1)), findsOneWidget);
      // 多选态下提供全选/开始/删除。
      expect(find.byTooltip(l10n.selectAll), findsOneWidget);
      expect(find.byTooltip(l10n.deleteSelectedCache), findsOneWidget);
    });

    testWidgets('长按文件夹卡会选中该组下所有分集', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      // 系列 A 有两集，长按一次应该两集都选中（卡片代表的是整个分组）。
      await tester.longPress(find.text(_seriesA));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(2)), findsOneWidget);
      // 再长按一次取消选择。
      await tester.longPress(find.text(_seriesA));
      await tester.pumpAndSettle();
      expect(find.text(l10n.cache), findsOneWidget);
    });
  });

  group('进入文件夹', () {
    testWidgets('点文件夹卡进到分组页，能看到分集列表', (tester) async {
      await _pump(tester);
      await tester.tap(find.text(_seriesA));
      await tester.pumpAndSettle();
      // 进到了文件夹页：标题是分组名，列表里是这一组的分集。
      expect(find.byType(CacheFolderPage), findsOneWidget);
      expect(find.text('作品 a1'), findsOneWidget);
      expect(find.text('作品 a2'), findsOneWidget);
      // 其它组的内容不该跟进来。
      expect(find.text('作品 b1'), findsNothing);
    });

    testWidgets('文件夹里只有一条时也进这一层，不直接开播', (tester) async {
      await _pump(tester);
      // 系列 B 只有一集 —— 卡片画的是文件夹，点下去就该进文件夹，
      // 而不是绕过这一层直接播放（那与卡片给人的预期不符）。
      await tester.tap(find.text(_seriesB));
      await tester.pumpAndSettle();
      expect(find.byType(CacheFolderPage), findsOneWidget);
      expect(find.text('作品 b1'), findsOneWidget);
    });
  });

  group('未归组的单条影片', () {
    // 真实反馈：「已缓存视频」里右边那两张（没归组的单条）点上去毫无反应，
    // 只有左侧那张文件夹卡能点开。根因是卡片只接了 onLongPress、没有 onTap，
    // 而且调用点把点击传成了「切换多选」。
    testWidgets('点一下就走播放这条路径，而不是死键', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      await tester.tap(find.text('作品 d1'));
      await tester.pumpAndSettle();
      // 用例里的任务没有真实文件，所以能观察到的反馈是「本地文件不存在」提示 ——
      // 这恰好证明确实调到了播放逻辑（修复前点下去什么都不会发生）。
      expect(find.text(l10n.localVideoMissing), findsOneWidget);
      expect(find.byType(CacheFolderPage), findsNothing);
    });

    testWidgets('多选态下点卡片是选中，不会直接播放', (tester) async {
      await _pump(tester);
      final l10n = AppLocalizations.of(tester.element(find.byType(CachePage)))!;
      // 长按文件夹卡先进入多选（该组两集）。
      await tester.longPress(find.text(_seriesA));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(2)), findsOneWidget);
      await tester.tap(find.text('作品 d1'));
      await tester.pumpAndSettle();
      expect(find.text(l10n.selectedItems(3)), findsOneWidget);
      expect(find.text(l10n.localVideoMissing), findsNothing);
    });
  });
}
