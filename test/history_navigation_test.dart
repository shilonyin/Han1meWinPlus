// 播放窗口顶部栏两个箭头翻的是观看历史，不是剧集列表。
//
// 最容易错的三处：
//   1. 同一部片子看多次会 append 多条记录，导航只认最近一次的位置；
//   2. histories 的顺序不保证（WebDAV 同步合并后会乱），不能依赖输入顺序；
//   3. 当前视频还没被记进历史时，两个箭头都要灰着，不能凭空插到最新位置。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/domain/history_navigation.dart';
import 'package:han1me_win_plus/src/domain/models/library.dart';

WatchHistory _entry(String code, int createdAt) => WatchHistory(
  id: '$code-$createdAt',
  videoCode: code,
  title: code,
  watchedMs: 60000,
  date: '2026-10-16',
  createdAt: createdAt,
);

void main() {
  group('历史里找前后条', () {
    test('中间那条：前后都有', () {
      final history = [_entry('a', 100), _entry('b', 200), _entry('c', 300)];
      final result = historyNeighbours(history, 'b');

      expect(result.previous?.videoCode, 'a');
      expect(result.next?.videoCode, 'c');
      expect(result.hasPrevious, isTrue);
      expect(result.hasNext, isTrue);
    });

    test('最早那条只有下一条', () {
      final history = [_entry('a', 100), _entry('b', 200)];
      final result = historyNeighbours(history, 'a');

      expect(result.hasPrevious, isFalse);
      expect(result.next?.videoCode, 'b');
    });

    test('最新那条只有上一条', () {
      final history = [_entry('a', 100), _entry('b', 200)];
      final result = historyNeighbours(history, 'b');

      expect(result.previous?.videoCode, 'a');
      expect(result.hasNext, isFalse);
    });

    test('只有一条记录时两头都没有', () {
      final result = historyNeighbours([_entry('a', 100)], 'a');

      expect(result.hasPrevious, isFalse);
      expect(result.hasNext, isFalse);
    });

    test('空历史 / 空 id 不炸', () {
      expect(historyNeighbours(const [], 'a').hasPrevious, isFalse);
      expect(historyNeighbours(const [], 'a').hasNext, isFalse);
      expect(historyNeighbours([_entry('a', 100)], '').hasPrevious, isFalse);
      expect(historyNeighbours([_entry('a', 100)], '').hasNext, isFalse);
    });

    test('当前视频不在历史里 → 两头都没有', () {
      final history = [_entry('a', 100), _entry('b', 200)];
      final result = historyNeighbours(history, 'z');

      expect(result.hasPrevious, isFalse);
      expect(result.hasNext, isFalse);
    });
  });

  group('同一部片子看过多次', () {
    test('只认最近一次的位置，不在旧记录之间来回跳', () {
      // a 看过两次：100 和 400。b 在中间。
      final history = [
        _entry('a', 100),
        _entry('b', 200),
        _entry('a', 400),
      ];
      final result = historyNeighbours(history, 'a');

      expect(
        result.previous?.videoCode,
        'b',
        reason: 'a 最近一次在 400，比它早的只有 b',
      );
      expect(result.hasNext, isFalse, reason: 'a 就是最新的那条');
    });

    test('中间的片子两侧都能拿到（其它视频的旧记录不参与去重）', () {
      // 时间线：a(100) → b(200) → a(400) → c(500)。
      // 当前在看 b，锚在 b(200)：上一条是 a(100)，下一条是 a(400)。
      final history = [
        _entry('a', 100),
        _entry('b', 200),
        _entry('a', 400),
        _entry('c', 500),
      ];
      final result = historyNeighbours(history, 'b');

      expect(result.previous?.videoCode, 'a');
      expect(
        result.next?.videoCode,
        'a',
        reason: '看完 b 接着看的正是 a 的第二遍，不是 c',
      );
      expect(result.next?.createdAt, 400);
    });

    test('连看两遍同一部片子时跳过自己', () {
      // a(100) → a(200) → b(300)。当前在看 a，锚在最近一次 a(200)。
      final history = [_entry('a', 100), _entry('a', 200), _entry('b', 300)];
      final result = historyNeighbours(history, 'a');

      expect(
        result.previous,
        isNull,
        reason: '再往前只有自己的旧记录，不该指向自己',
      );
      expect(result.next?.videoCode, 'b');
    });
  });

  group('不依赖输入顺序', () {
    test('乱序输入按 createdAt 排', () {
      final history = [_entry('c', 300), _entry('a', 100), _entry('b', 200)];
      final result = historyNeighbours(history, 'b');

      expect(result.previous?.videoCode, 'a');
      expect(result.next?.videoCode, 'c');
    });

    test('乱序 + 重复也按时间排', () {
      final history = [_entry('a', 400), _entry('b', 200), _entry('a', 100)];
      final result = historyNeighbours(history, 'a');

      expect(result.previous?.videoCode, 'b');
      expect(result.hasNext, isFalse);
    });
  });
}
