// 播放窗口顶部栏的信息桥接：标题 / 上下集可用性 / 换集回调。
//
// 背景：顶部栏挂在窗口级（PlayWindowApp 的 AppWindowFrame），而标题与上下集能力
// 属于播放页内部（VideoDetail 与它的 playlist）。两者不在同一棵子树上，所以用一张
// 全局登记表桥接（PlayWindowTitleTarget）。
//
// 最容易错的是**换集时的时序**：播放页之间用 pushReplacement 互跳，Flutter 里旧路由的
// dispose 发生在新页面 initState 之后 —— 如果 clear() 无条件清空，旧页面退出时会把
// 新页面刚登记的标题擦掉，顶部栏变空白。所以登记表记「所有者」，只有登记它的那个
// 页面才有权清空。
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/play_window_title_target.dart';

void main() {
  setUp(PlayWindowTitleTarget.reset);
  tearDown(PlayWindowTitleTarget.reset);

  group('登记与清空', () {
    test('登记后标题与上下集可用性就位', () {
      final page = Object();
      PlayWindowTitleTarget.register(
        owner: page,
        title: '第1话 某标题',
        hasPrevious: false,
        hasNext: true,
        onNext: () {},
      );

      expect(PlayWindowTitleTarget.title.value, '第1话 某标题');
      expect(PlayWindowTitleTarget.hasPrevious.value, isFalse);
      expect(PlayWindowTitleTarget.hasNext.value, isTrue);
      expect(PlayWindowTitleTarget.nextEpisode, isNotNull);
    });

    test('所有者自己清空 → 全部复位', () {
      final page = Object();
      PlayWindowTitleTarget.register(
        owner: page,
        title: 't',
        hasPrevious: true,
        hasNext: true,
      );
      PlayWindowTitleTarget.clear(page);

      expect(PlayWindowTitleTarget.title.value, '');
      expect(PlayWindowTitleTarget.hasPrevious.value, isFalse);
      expect(PlayWindowTitleTarget.hasNext.value, isFalse);
      expect(PlayWindowTitleTarget.previousEpisode, isNull);
      expect(PlayWindowTitleTarget.nextEpisode, isNull);
    });

    test('没有上一集 / 下一集时回调为空（顶部栏据此置灰）', () {
      PlayWindowTitleTarget.register(
        owner: Object(),
        title: '单集',
        hasPrevious: false,
        hasNext: false,
      );
      expect(PlayWindowTitleTarget.previousEpisode, isNull);
      expect(PlayWindowTitleTarget.nextEpisode, isNull);
    });
  });

  group('换集时的时序（pushReplacement）', () {
    test('旧页面 dispose 不得擦掉新页面刚登记的标题', () {
      final oldPage = Object();
      final newPage = Object();

      // 1) 旧页面先登记。
      PlayWindowTitleTarget.register(
        owner: oldPage,
        title: '第1话',
        hasPrevious: false,
        hasNext: true,
      );
      expect(PlayWindowTitleTarget.title.value, '第1话');

      // 2) 点「下一集」：新页面 initState 先跑，登记第2话。
      PlayWindowTitleTarget.register(
        owner: newPage,
        title: '第2话',
        hasPrevious: true,
        hasNext: false,
      );
      expect(PlayWindowTitleTarget.title.value, '第2话');

      // 3) 旧页面 dispose 后到（顺序不确定，但这是最坏情况）→ 不得清掉第2话。
      PlayWindowTitleTarget.clear(oldPage);

      expect(
        PlayWindowTitleTarget.title.value,
        '第2话',
        reason: '旧页面退出不能把新页面的标题擦成空白',
      );
      expect(PlayWindowTitleTarget.hasPrevious.value, isTrue);
      expect(PlayWindowTitleTarget.hasNext.value, isFalse);
    });

    test('连续换两集：只有最后一个页面的话生效', () {
      final p1 = Object();
      final p2 = Object();
      final p3 = Object();

      PlayWindowTitleTarget.register(owner: p1, title: 'E1', hasPrevious: false, hasNext: true);
      PlayWindowTitleTarget.register(owner: p2, title: 'E2', hasPrevious: true, hasNext: true);
      PlayWindowTitleTarget.register(owner: p3, title: 'E3', hasPrevious: true, hasNext: false);

      // p1 / p2 的 dispose 陆续到达。
      PlayWindowTitleTarget.clear(p1);
      PlayWindowTitleTarget.clear(p2);

      expect(PlayWindowTitleTarget.title.value, 'E3');
      expect(PlayWindowTitleTarget.hasPrevious.value, isTrue);
      expect(PlayWindowTitleTarget.hasNext.value, isFalse);
    });

    test('最后离开播放页（所有者自己 dispose）→ 清空', () {
      final page = Object();
      PlayWindowTitleTarget.register(
        owner: page,
        title: 'E1',
        hasPrevious: false,
        hasNext: false,
      );
      PlayWindowTitleTarget.clear(page);
      expect(PlayWindowTitleTarget.title.value, '');
    });
  });
}
