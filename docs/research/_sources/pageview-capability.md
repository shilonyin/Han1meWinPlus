# PageView 能力核实（Flutter 3.47.4）

为「推荐位轮播」动效方案确认四项前置事实。全部结论均带源码行号，源码位于
`C:\flutter-3.47.4\packages\flutter\lib\src\`。

## ① `PageView.builder` 的 `itemCount` 可以为空 → 可做无限页

`widgets/page_view.dart:748`：

```dart
int? itemCount,
```

`:768` 直接把它交给 delegate：

```dart
childCount: itemCount,
```

`SliverChildBuilderDelegate.childCount` 为 `null` 时列表不设上界，滚到任意索引都会继续
向 builder 要子项。**结论：`itemCount: null` 即可实现无穷分页**，不需要任何第三方包，也不
需要自己复制首尾数据。

## ② `PageController.page` 在千级 `initialPage` 下精度足够

`widgets/page_view.dart:174` 起，`page` 返回 `double?`（未挂载时为 `null`，因为它会断言
`positions.isNotEmpty`）。真正的换算在 `_PagePosition.getPageFromPixels`
（`widgets/page_view.dart:401-410`）：

```dart
double getPageFromPixels(double pixels, double viewportDimension) {
  assert(viewportDimension > 0.0);
  final double actual =
      math.max(0.0, pixels - _initialPageOffset) / (viewportDimension * viewportFraction);
  final double round = actual.roundToDouble();
  if ((actual - round).abs() < precisionErrorTolerance) {
    return round;
  }
  return actual;
}
```

一次浮点除法。取 `initialPage = 10000`、页宽 1200 逻辑像素，像素量级约 `1.2e7`，
IEEE-754 double 的整数精确上限是 `2^53 ≈ 9.0e15`，相差八个数量级；`precisionErrorTolerance`
（`1e-10`）也就是吸附判定用的容差，远大于该量级的表示误差。**结论：精度足够，
`index - controller.page` 算出的 `δ` 在整页附近会精确落到 0，不会因为初始页大而漂移。**

注意：`page` 是可空的，读取时必须写 `_controller.page ?? _controller.initialPage`，
否则在首帧（尚未布局出 content dimensions）会拿到 `null`。

## ③ 视口内多页的绘制顺序：索引大的后画，在上层

`PageView` 内部是一个 sliver（`_SliverFixedExtentCarousel` 之外的 `PageView` 走
`SliverFillViewport`），其多子项绘制逻辑在 `rendering/sliver_multi_box_adaptor.dart:726-746`：

```dart
RenderBox? child = firstChild;
while (child != null) {
  final double mainAxisDelta = childMainAxisPosition(child);
  ...
  if (mainAxisDelta < constraints.remainingPaintExtent &&
      mainAxisDelta + paintExtentOf(child) > 0) {
    context.paintChild(child, childOffset);
  }

  child = childAfter(child);
}
```

从 `firstChild` 起用 `childAfter` 逐个向后遍历并 `paintChild`——**先画索引小的，后画索引
大的**。后画的覆盖先画的，因此：

> **索引较大的页绘制在上层。**

这条直接决定交叉淡化时谁该淡出。当向前翻页（`page` 从 `n` 涨到 `n+1`）时，索引 `n+1`
覆盖在 `n` 之上：`n` 是被压在下层的那张，它此时应该保持不透明（否则会透出更下层的背景），
由上层的新页 `n+1` 负责淡入。反之向后翻页（`page` 从 `n` 掉到 `n-1`）时，`n` 是上层，
它负责淡出，露出下方已经完全不透明的 `n-1`。

也就是说，透明度规则必须**单侧**生效：

- `δ = index - page`。`δ ∈ (0, 1)` 的页（在 `page` 左侧、正在滑出）恒为 `opacity: 1`；
- `δ ∈ (-1, 0)` 的页（在 `page` 右侧、正在滑入）在上层，需要 `opacity` 随 `|δ|` 从 0 涨到 1。

若这条顺序反过来（索引小的在上），规则要翻向：让左侧滑出的页淡出。**因此这里必须有明确
答案而不能靠推测 —— 源码给出的是「索引大的在上」，上面的规则可用。**

## ④ `PageView` 的 `clipBehavior` 默认 `Clip.hardEdge`，可覆盖

三个构造器都写死默认值（`widgets/page_view.dart:699`、`:753`、`:795`）：

```dart
this.clipBehavior = Clip.hardEdge,
```

文档注释在 `:918` 也是「Defaults to [Clip.hardEdge]」。**结论：默认会硬裁剪超出视口的
子项。**本方案把固定圆角裁剪放在更外层的 `ClipRRect` 上，`PageView` 自身的裁剪不影响
结果；但如果希望页面内容的 `Transform` 位移能溢出画框，需要显式传
`clipBehavior: Clip.none` 并由外层 `ClipRRect` 承担裁剪，否则溢出部分会被硬切出直角边。

## 对方案的影响（一句话）

四项全部支持「画框恒定 + 无穷页 + 分层视差」的路线：`itemCount: null` 提供无缝接回、
`page` 的精度足以驱动亚像素视差与透明度、绘制顺序确定「新页在上层淡入」、
`clipBehavior` 由外层 `ClipRRect` 接管。**方案里唯一需要防御的是 `page` 可空**，
读取处统一写 `?? initialPage`。
