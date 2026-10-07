import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:g1455/g1455.dart';
import 'package:han1me_win_plus/src/features/shared/glass/glass_scroll_edge_bar.dart';

/// [glassScrollEdgeAppBar] / [barExtent] 的行为，以及「三处一起改」这条规矩。
///
/// 这组测试的由来：scroll edge 要生效必须同时改三处（Scaffold 的
/// extendBodyBehindAppBar、包过的 appBar、body 顶部让开 bar 高度），
/// 少一处不报错、只是效果没了或内容被压住 —— 靠肉眼很容易漏。
void main() {
  group('glassScrollEdgeAppBar', () {
    test('barExtent 就是 bar 自己的高度', () {
      expect(barExtent(AppBar()), kToolbarHeight);
    });

    test('带 bottom 的 bar 高度把 bottom 算进去', () {
      final AppBar bar = AppBar(
        title: const Text('t'),
        bottom: const TabBar(tabs: [Tab(text: 'a'), Tab(text: 'b')]),
      );
      expect(barExtent(bar), greaterThan(kToolbarHeight));
    });

    test('外面那层比 bar 高：多出来的是 scroll edge 自己的渐变/模糊区', () {
      final AppBar bar = AppBar(title: const Text('t'));
      final PreferredSizeWidget wrapped = glassScrollEdgeAppBar(bar);
      // 少了这一段，GlassScrollEdge 会被 Scaffold 裁掉，效果就没了。
      expect(wrapped.preferredSize.height, greaterThan(barExtent(bar)));
    });

    test('里面确实是 g1455 的 GlassScrollEdge，且 bar 原样传给它', () {
      final AppBar bar = AppBar(title: const Text('t'));
      final Widget wrapped = glassScrollEdgeAppBar(bar) as Widget;
      final PreferredSize sized = wrapped as PreferredSize;
      final GlassScrollEdge edge = sized.child as GlassScrollEdge;
      expect(edge.side, GlassScrollEdgeSide.top);
      expect(edge.extent, barExtent(bar));
      expect(edge.child, same(bar));
    });

    test('bar 有 bottom 时 extent 也跟着变高', () {
      final AppBar bar = AppBar(
        title: const Text('t'),
        bottom: const TabBar(tabs: [Tab(text: 'a')]),
      );
      final GlassScrollEdge edge = (glassScrollEdgeAppBar(bar) as PreferredSize).child as GlassScrollEdge;
      expect(edge.extent, barExtent(bar));
      expect(edge.extent, greaterThan(kToolbarHeight));
    });
  });

  group('三处一起改', () {
    // 源码扫描：只改 Scaffold、忘了包 appBar（或反过来）都会让效果悄悄消失。
    test('用了 extendBodyBehindAppBar 的页面必须也用了 glassScrollEdgeAppBar', () {
      final Directory lib = Directory('lib');
      expect(lib.existsSync(), isTrue, reason: '测试要在仓库根目录跑');

      final List<String> offenders = <String>[];
      for (final FileSystemEntity entity in lib.listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final String source = entity.readAsStringSync();
        final bool behind = source.contains('extendBodyBehindAppBar: true');
        final bool wrapper = source.contains('glassScrollEdgeAppBar(');
        if (behind != wrapper) {
          offenders.add('${entity.path}  extendBodyBehindAppBar=$behind wrapper=$wrapper');
        }
      }
      expect(offenders, isEmpty, reason: '这两件事要么一起做，要么都不做：\n${offenders.join('\n')}');
    });
  });
}
