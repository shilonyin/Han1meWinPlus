// 播放窗口顶部栏那两个箭头翻的是**本窗口里「我点开过哪些视频」的顺序**，
// 不是全局观看历史。用户的说法：正在看 A，点开 B 播放，看完想回 A —— 左箭头
// 就该回 A。观看历史做不到这件事，它只在播满时长后才写，同一部片子的多条记录
// 还会按「看过的时间」重新排队。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/play_window_nav_history.dart';

PlayWindowNavEntry _entry(String code) =>
    PlayWindowNavEntry(videoCode: code, title: 'title-$code');

void main() {
  late PlayWindowNavHistory nav;

  setUp(() {
    nav = PlayWindowNavHistory.instance;
    nav.reset();
  });

  tearDown(() => nav.reset());

  group('记录打开顺序', () {
    test('刚打开第一个：两个箭头都灰', () {
      nav.record(_entry('a'));

      expect(nav.canGoPrevious, isFalse);
      expect(nav.canGoNext, isFalse);
    });

    test('接着点开第二个：上一条是刚才那个', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));

      expect(nav.previous?.videoCode, 'a');
      expect(nav.next, isNull, reason: '刚点开的是最新的，没有「下一个」');
    });

    test('三个依次打开：中间那个前后都有', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));
      nav.record(_entry('c'));

      expect(nav.previous?.videoCode, 'b');
      expect(nav.index, 2);

      // 退到 b
      expect(nav.goTo(_entry('b')), isTrue);
      expect(nav.previous?.videoCode, 'a');
      expect(nav.next?.videoCode, 'c');
    });

    test('同一个视频重复 record 不会多出一条', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));
      nav.record(_entry('b'));
      nav.record(_entry('b'));

      expect(nav.entries.length, 2);
      expect(nav.index, 1);
    });

    test('空 id 不记', () {
      nav.record(const PlayWindowNavEntry(videoCode: '', title: 'x'));

      expect(nav.entries, isEmpty);
    });
  });

  group('箭头跳转', () {
    test('goTo 之后 record 认领目标，不会在栈尾追加', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));

      // 点左箭头回 a：先 goTo，页面换过去后再 record。
      expect(nav.goTo(_entry('a')), isTrue);
      nav.record(_entry('a'));

      expect(nav.entries.length, 2, reason: '回退不该往栈尾追加一条，否则越退越长');
      expect(nav.index, 0);
      expect(nav.previous, isNull);
      expect(nav.next?.videoCode, 'b');
    });

    test('来回退两次仍然只有两条', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));

      nav.goTo(_entry('a'));
      nav.record(_entry('a'));
      nav.goTo(_entry('b'));
      nav.record(_entry('b'));
      nav.goTo(_entry('a'));
      nav.record(_entry('a'));

      expect(nav.entries.length, 2);
      expect(nav.index, 0);
    });

    test('goTo 一个不在栈里的视频返回 false', () {
      nav.record(_entry('a'));

      expect(nav.goTo(_entry('z')), isFalse);
      expect(nav.index, 0);
    });

    test('从中间点开新视频：丢掉原来的「前进」部分', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));
      nav.record(_entry('c'));

      // 退到 b，此时 c 是「下一个」
      nav.goTo(_entry('b'));
      nav.record(_entry('b'));
      expect(nav.next?.videoCode, 'c');

      // 从 b 点开全新的 d：c 应该被丢掉（和浏览器一致）
      nav.record(_entry('d'));

      expect(nav.entries.map((e) => e.videoCode), ['a', 'b', 'd']);
      expect(nav.index, 2);
      expect(nav.previous?.videoCode, 'b');
      expect(nav.next, isNull);
    });

    test('用户说的那个场景：看 A、点开 B、想回 A', () {
      // 在 A 上开始
      nav.record(_entry('a'));
      expect(nav.canGoPrevious, isFalse);

      // 点开 B
      nav.record(_entry('b'));
      expect(nav.canGoPrevious, isTrue, reason: '这时左箭头应该能回 A');

      // 点左箭头回 A
      nav.goTo(_entry('a'));
      nav.record(_entry('a'));

      expect(nav.index, 0);
      expect(nav.next?.videoCode, 'b', reason: '回 A 之后右箭头应该能再去 B');
      expect(nav.previous, isNull);
    });
  });

  group('与观看历史无关', () {
    test('没播满时长也照样能回上一个视频', () {
      // 这里不涉及任何观看历史写入：栈只认 record 调用。
      nav.record(_entry('a'));
      nav.record(_entry('b'));

      expect(nav.canGoPrevious, isTrue, reason: '以前按观看历史翻，没播满 5 秒就不进历史，箭头全是灰的');
    });

    test('同一部片子连开两次仍只占一条', () {
      nav.record(_entry('a'));
      nav.record(_entry('b'));
      nav.record(_entry('a'));

      // a 已经在栈里但 index 不在它上面（index=1 在 b），所以追加一条新的 a。
      // 这与浏览器一致：回到 a 又往前走了，历史里 a 出现两次。
      expect(nav.entries.map((e) => e.videoCode), ['a', 'b', 'a']);
      expect(nav.index, 2);
      expect(nav.previous?.videoCode, 'b');
    });
  });
}
