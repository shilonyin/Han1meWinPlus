import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/l10n/app_localizations.dart';
import 'package:han1me_win_plus/src/data/local/download_repository.dart';
import 'package:han1me_win_plus/src/domain/models/download.dart';
import 'package:han1me_win_plus/src/features/cache/cache_folder_page.dart';
import 'package:han1me_win_plus/src/features/cache/cache_format.dart';

DownloadTask _task({
  required String id,
  DownloadStatus status = DownloadStatus.completed,
  int totalBytes = 0,
  int downloadedBytes = 0,
  int createdAt = 0,
  int updatedAt = 0,
  String title = '标题',
  String quality = '1080',
  Set<String> groupIds = const {},
}) =>
    DownloadTask(
      id: id,
      videoCode: id,
      title: title,
      groupIds: groupIds,
      quality: quality,
      status: status,
      progress: 0,
      downloadedBytes: downloadedBytes,
      totalBytes: totalBytes,
      createdAt: createdAt,
      updatedAt: updatedAt,
    );

Widget _host(Widget child) => MaterialApp(
      locale: const Locale('zh'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: child,
    );

void main() {
  group('暂停状态可持久化', () {
    test('paused 能写进 JSON 并读回来', () {
      // 状态按枚举名存盘，新增 paused 之后必须能原样往返；
      // 读不回来就意味着重启后暂停的任务会自己跑起来。
      final task = _task(id: 'a', status: DownloadStatus.paused, downloadedBytes: 512, totalBytes: 2048);
      final restored = DownloadTask.fromJson(task.toJson());
      expect(restored.status, DownloadStatus.paused);
      expect(restored.downloadedBytes, 512);
      expect(restored.totalBytes, 2048);
    });

    test('旧存档里的未知状态回退到等待中，不会崩', () {
      final json = _task(id: 'a').toJson()..['status'] = 'somethingRemovedLater';
      expect(DownloadTask.fromJson(json).status, DownloadStatus.queued);
    });

    test('整个 DownloadState 往返后分组与暂停状态都在', () {
      final state = DownloadState(
        groups: const [
          DownloadGroup(id: 'default', name: 'Cached', createdAt: 0),
          DownloadGroup(id: 'g1', name: '系列 A', createdAt: 1),
        ],
        tasks: [
          _task(id: 'a', status: DownloadStatus.paused, groupIds: {'g1'}),
          _task(id: 'b', status: DownloadStatus.completed),
        ],
      );
      final restored = DownloadState.fromJson(state.toJson());
      expect(restored.groups.map((group) => group.name), containsAll(['Cached', '系列 A']));
      expect(restored.tasks.firstWhere((task) => task.id == 'a').status, DownloadStatus.paused);
      expect(restored.tasks.firstWhere((task) => task.id == 'a').groupIds, {'g1'});
    });
  });

  group('isActiveTask', () {
    test('未下完的都算进行中，已完成的除外', () {
      // 暂停/失败"还占着这条缓存"，仍然归到「正在缓存」页签下管理。
      expect(isActiveTask(_task(id: 'a', status: DownloadStatus.queued)), isTrue);
      expect(isActiveTask(_task(id: 'a', status: DownloadStatus.downloading)), isTrue);
      expect(isActiveTask(_task(id: 'a', status: DownloadStatus.paused)), isTrue);
      expect(isActiveTask(_task(id: 'a', status: DownloadStatus.failed)), isTrue);
      expect(isActiveTask(_task(id: 'a', status: DownloadStatus.completed)), isFalse);
    });
  });

  group('formatBytes', () {
    test('按 1024 进制换算并保留合适的精度', () {
      expect(formatBytes(0), '0 B');
      expect(formatBytes(512), '512 B');
      expect(formatBytes(1024), '1.0 KB');
      expect(formatBytes(1536), '1.5 KB');
      expect(formatBytes(95.9 * 1024 * 1024 ~/ 1), '95.9 MB');
      // 三位数以上不再留小数，否则「406.3 MB」比数字本身还宽。
      expect(formatBytes(406 * 1024 * 1024), '406 MB');
      expect(formatBytes(1024 * 1024 * 1024), '1.0 GB');
    });

    test('空值不产生 NaN 或负号', () {
      expect(formatBytes(0), '0 B');
      expect(formatSpeed(0), '0 B/s');
      expect(formatSpeed(-5), '0 B/s');
    });
  });

  group('sortTasks', () {
    test('默认序把正在下载的排最前，其余按加入时间倒序', () {
      final tasks = [
        _task(id: 'old', createdAt: 100),
        _task(id: 'downloading', status: DownloadStatus.downloading, createdAt: 50),
        _task(id: 'new', createdAt: 300),
      ];
      final sorted = sortTasks(tasks, DownloadGroupSort.defaultOrder);
      expect(sorted.map((task) => task.id), ['downloading', 'new', 'old']);
    });

    test('最近更新按 updatedAt 倒序', () {
      final tasks = [_task(id: 'a', updatedAt: 100), _task(id: 'b', updatedAt: 900)];
      expect(sortTasks(tasks, DownloadGroupSort.recentlyUpdated).map((task) => task.id), ['b', 'a']);
    });

    test('按名称忽略大小写', () {
      final tasks = [_task(id: 'a', title: 'banana'), _task(id: 'b', title: 'Apple')];
      expect(sortTasks(tasks, DownloadGroupSort.name).map((task) => task.id), ['b', 'a']);
    });

    test('排序不会改动传入的列表', () {
      final tasks = [_task(id: 'a', createdAt: 1), _task(id: 'b', createdAt: 2)];
      sortTasks(tasks, DownloadGroupSort.defaultOrder);
      expect(tasks.map((task) => task.id), ['a', 'b']);
    });
  });

  group('localizedGroupName', () {
    testWidgets('内置默认分组用本地化文案，用户分组原样显示', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        expect(localizedGroupName(const DownloadGroup(id: 'default', name: 'Cached', createdAt: 0), l10n), l10n.cachedDownloads);
        expect(localizedGroupName(const DownloadGroup(id: 'default', name: 'Default', createdAt: 0), l10n), l10n.cachedDownloads);
        // 用户把默认分组改成自己的名字后不该被内置文案盖掉。
        expect(localizedGroupName(const DownloadGroup(id: 'default', name: '我的收藏', createdAt: 0), l10n), '我的收藏');
        expect(localizedGroupName(const DownloadGroup(id: 'g1', name: '某系列', createdAt: 0), l10n), '某系列');
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
    });
  });

  group('taskDetailLine', () {
    testWidgets('拼出「清晰度 · 体积 · 日期」', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        final line = taskDetailLine(_task(id: 'a', quality: '1080', totalBytes: 310 * 1024 * 1024, updatedAt: DateTime(2026, 9, 25).millisecondsSinceEpoch));
        expect(line, '1080 · 310 MB · 2026-09-25');
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
    });

    testWidgets('缺字段时不留多余的分隔点', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        expect(taskDetailLine(_task(id: 'a', quality: '720')), '720');
        expect(taskDetailLine(_task(id: 'a', quality: '')), '');
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
    });
  });

  group('taskStatusLabel', () {
    testWidgets('每个状态都有文案（含新增的暂停）', (tester) async {
      await tester.pumpWidget(_host(Builder(builder: (context) {
        final l10n = AppLocalizations.of(context)!;
        // 五个状态逐一覆盖：漏掉一个就会在界面上显示成空白。
        expect(taskStatusLabel(l10n, DownloadStatus.queued), l10n.queued);
        expect(taskStatusLabel(l10n, DownloadStatus.downloading), l10n.downloading);
        expect(taskStatusLabel(l10n, DownloadStatus.completed), l10n.completed);
        expect(taskStatusLabel(l10n, DownloadStatus.failed), l10n.failed);
        expect(taskStatusLabel(l10n, DownloadStatus.paused), l10n.paused);
        return const SizedBox.shrink();
      })));
      await tester.pumpAndSettle();
    });
  });
}
