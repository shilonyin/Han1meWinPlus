import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:han1me_win_plus/src/core/progressive_fade.dart';

/// `LinearGradient` 的端点静态类型是 [AlignmentGeometry]，收窄后才能读 x/y。
Alignment _align(AlignmentGeometry geometry) => geometry as Alignment;

void main() {
  group('ProgressiveFade 停靠点算法', () {
    test('五阶停靠点等分，alpha 阶梯是 Telegram 原生值', () {
      expect(ProgressiveFade.stops, <double>[0, .25, .5, .75, 1]);
      expect(ProgressiveFade.alphaFactors, <double>[
        1,
        232 / 255,
        176 / 255,
        96 / 255,
        0,
      ]);
    });

    test('中段比两阶线性更实 —— 这正是消除马赫带的机制', () {
      const solid = Colors.black87;
      final colors = ProgressiveFade.fadeColors(solid, reversed: false);

      // 两阶线性渐变在 50% 处恰好是实色的一半。
      final linearMid = solid.a / 2;
      // 五阶在 50% 处仍留住七成，过渡因此不集中在中段。
      expect(colors[2].a, greaterThan(linearMid));

      // 而消散被压倒后半段：75% 处已不足实色的四成。
      expect(colors[3].a, lessThan(solid.a * .4));
    });

    test('alpha 按实色自身的透明度缩放，不写死', () {
      const half = Color(0x80000000); // 50% 黑（0x80/255，不是恰好 .5）
      final base = 0x80 / 255;
      final colors = ProgressiveFade.fadeColors(half, reversed: false);

      expect(colors.first.a, closeTo(base, 1e-6));
      expect(colors[1].a, closeTo(base * 232 / 255, 1e-6));
      expect(colors.last.a, 0);
    });

    test('消散端保留实色色相，不用 transparent（透明黑会在末端偏色）', () {
      const tint = Color(0xff7662ba); // morrow 品牌紫
      final colors = ProgressiveFade.fadeColors(tint, reversed: false);
      final tail = colors.last;

      expect(tail.a, 0);
      // 仍是那个紫，而不是透明黑。
      expect(tail.r, closeTo(tint.r, 1e-6));
      expect(tail.g, closeTo(tint.g, 1e-6));
      expect(tail.b, closeTo(tint.b, 1e-6));
      expect(tail, isNot(Colors.transparent));
    });

    test('topSolid 实色在顶部，向下消散', () {
      const solid = Colors.black87;
      final gradient = ProgressiveFade.topSolid(solid);

      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      // 实色端与原来手写渐变的端点一致，观感不会突然变重。
      expect(gradient.colors.first.a, closeTo(solid.a, 1e-6));
      expect(gradient.colors.last.a, 0);
    });

    test('bottomSolid 实色在底部，向上消散', () {
      const solid = Colors.black87;
      final gradient = ProgressiveFade.bottomSolid(solid);

      expect(gradient.begin, Alignment.topCenter);
      expect(gradient.end, Alignment.bottomCenter);
      expect(gradient.colors.first.a, 0);
      expect(gradient.colors.last.a, closeTo(solid.a, 1e-6));
    });

    test('reversed 只是把同一组阶梯倒过来，不改变集合', () {
      const solid = Colors.black87;
      final forward = ProgressiveFade.fadeColors(solid, reversed: false);
      final backward = ProgressiveFade.fadeColors(solid, reversed: true);

      expect(backward, forward.reversed.toList());
      expect(
        backward.map((c) => c.a).toSet(),
        forward.map((c) => c.a).toSet(),
      );
    });
  });

  group('ProgressiveFade.extent 收窄渐变范围', () {
    test('extent 为 1 时铺满整个绘制区', () {
      expect(
        ProgressiveFade.topSolid(Colors.black).end,
        Alignment.bottomCenter,
      );
      expect(
        ProgressiveFade.bottomSolid(Colors.black).begin,
        Alignment.topCenter,
      );
    });

    test('topSolid 收窄后渐变止于上段，下方保持透明', () {
      final narrow = ProgressiveFade.topSolid(Colors.black, extent: .4);

      expect(_align(narrow.begin), Alignment.topCenter);
      expect(_align(narrow.end).x, 0);
      expect(_align(narrow.end).y, closeTo(-.2, 1e-6));
      // 落点仍是透明，止点以下才不会被染上色。
      expect(narrow.colors.last.a, 0);
    });

    test('bottomSolid 收窄后渐变起于下段，上方保持透明', () {
      final narrow = ProgressiveFade.bottomSolid(Colors.black, extent: .4);

      expect(_align(narrow.end), Alignment.bottomCenter);
      expect(_align(narrow.begin).x, 0);
      expect(_align(narrow.begin).y, closeTo(.2, 1e-6));
      expect(narrow.colors.first.a, 0);
    });

    test('越界的 extent 被夹到合法区间', () {
      // 断言"夹取"本身：越界值必须与边界值等价，
      // 而不是硬编码某个具体端点（extent 为 0 时渐变退化，端点没有意义）。
      expect(
        ProgressiveFade.topSolid(Colors.black, extent: 2).end,
        ProgressiveFade.topSolid(Colors.black).end,
      );
      expect(
        ProgressiveFade.bottomSolid(Colors.black, extent: -1).begin,
        ProgressiveFade.bottomSolid(Colors.black, extent: 0).begin,
      );
    });
  });
}
