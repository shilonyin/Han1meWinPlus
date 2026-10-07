import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:g1455/g1455.dart';

/// 把 Material 的 [AppBar] 包进 g1455 的 scroll edge：内容滚到它下面时被模糊淡出。
///
/// **三处必须一起改，缺一不可**：
/// 1. `Scaffold(extendBodyBehindAppBar: true)` —— body 才会延伸到 bar 后面
/// 2. `appBar: glassScrollEdgeAppBar(bar)` —— bar 本身
/// 3. body 顶部让开 [barExtent]（下面例子里是 `+ 16` 之外再加的那一份）——
///    否则内容一开始就被 bar 压住
///
/// ```dart
/// final bar = AppBar(title: Text(title));
/// return Scaffold(
///   extendBodyBehindAppBar: true,
///   appBar: glassScrollEdgeAppBar(bar),
///   body: ListView(padding: EdgeInsets.fromLTRB(16, barExtent(bar) + 16, 16, 16), ...),
/// );
/// ```
///
/// **只有内容真的会滚到 bar 后面的页面才该接**：body 若是一个撑满高度的
/// `LayoutBuilder`/`Column`（比如打卡页），内容根本不经过 bar 底下，接了也白接。
///
/// 成本：soft 上边是一条屏幕宽的玻璃，滚动时每帧重录一次，静止屏幕不录。
PreferredSizeWidget glassScrollEdgeAppBar(PreferredSizeWidget bar) {
  final double extent = bar.preferredSize.height;
  final GlassScrollEdge edge = GlassScrollEdge(
    side: GlassScrollEdgeSide.top,
    extent: extent,
    child: bar,
  );
  return PreferredSize(
    // 光有 bar 的高度不够：scroll edge 还要在 bar 下方多占一段渐变/模糊区，
    // 少了这一段它会被 Scaffold 裁掉，效果也就没了。
    preferredSize: Size.fromHeight(math.max(edge.reach, extent)),
    child: edge,
  );
}

/// [bar] 的布局高度，也就是 body 顶部要让开的距离。
double barExtent(PreferredSizeWidget bar) => bar.preferredSize.height;
