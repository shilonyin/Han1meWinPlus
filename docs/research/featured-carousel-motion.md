# 首页推荐位轮播：切换动效方案

> 目标文件：`lib/src/features/explore/explore_page.dart`（`_FeaturedSwiper` / `_FeaturedVideoSurface`）
> 约束：不引入新依赖 · 时长 200–500ms · 暗/亮双主题 · 不改卡片布局与内容

## 结论速览

把「一整块圆角卡片平移过去」换成「**圆角画框钉死不动，框里的画面分层换**」：

| 项目 | 现状 | 改成 |
|---|---|---|
| 承运组件 | `CarouselView.builder`（material_ui） | `PageView.builder` + 无穷页 |
| 卡片宽度 | 滑出时被压扁（`maxExtent → 0`） | 恒定一页宽，不再变形 |
| 圆角来源 | 每张卡片自己 `Material(borderRadius)` | 外层固定 `ClipRRect`（画框）；卡片圆角过渡中收平 |
| 封面 | 跟着卡片整体平移 | 抵消 88% 位移 + 最多 4.5% 推近 |
| 文字 | 跟着卡片整体平移 | 抵消 62% 位移 + 快速淡出（差速视差） |
| 首尾衔接 | 从最后一张回卷到第一张（整排倒掠） | 无穷页，直接接上 |
| 时长 | 固定 600ms 字面量 | 自动 `AppMotion.page`(400ms) / 手动 `AppMotion.emphasis`(250ms) |

---

## 一、过渡方式：为什么整块平移会「怪」

### 先定位病根

`material_ui-1.2.0/lib/src/carousel.dart` 的 `_RenderSliverFixedExtentCarousel._buildItemExtent`
（:848-890）对**正在滑出的首项**返回：

```dart
final double effectiveExtent = maxExtent - offscreenExtent;
return math.max(effectiveExtent, effectiveMinExtent);
```

当前调用没传 `shrinkExtent`（默认 `0.0`），`itemExtent: double.infinity` 又被
`clampDouble(itemExtent, 0, mainAxisExtent)`（:748-750）钳到视口宽。结果：**每一张卡在滑出
过程中，主轴宽度从满宽被线性压缩到 0**。

于是画面上发生的不是「一张卡向左移动」，而是「一张矩形被横向挤扁，圆角相对半径随着宽度
缩小而变大，封面图被压、标题被挤」。

再叠一层：`CarouselView.builder` 走 `itemBuilder` 路径时**不经过** `_buildCarouselItem`
（:706 与 :709 是二选一），所以它的 `padding` / `shape` / `itemClipBehavior` 全部不生效——圆角
只来自 `_FeaturedVideoSurface` 自己的 `Material(borderRadius: AppRadius.md)`。圆形裁切跟着
被压扁的矩形走，就是用户说的「连圆角整个切换」。

### 第二个病根：回卷

`_advance` 里 `next = (_current.value + delta) % videos.length`，而
`CarouselController.animateToItem` 的目标偏移是线性的 `index * itemExtent`。从最后一张切回
第一张时，控制器要从 `n` 一路滚到 `0`——**跨过全部中间页**。6 秒一次，每次都有一段「整排
倒着掠过」。这个闪动和上面的压缩是两回事，必须一起修。

### 选定方案：固定画框 + 分层视差 + 叠化

三层动作，各自可控：

1. **画框**：外层 `ClipRRect(borderRadius: AppRadius.all(AppRadius.md))` 包住整个轮播区，
   位置、尺寸、圆角半径全程一个像素都不变。它是「舞台」。
2. **页面位置**：`PageView` 负责手势、吸附和连续进度 `page`，但每页内容用
   `Transform.translate(offset: Offset(-δ * extent * k, 0))` **反向抵消**大部分滚动位移。
   `k` 取 0.88（封面）与 0.62（文字），留下的差值就是视差。
3. **叠化**：索引大的页绘制在上层（`sliver_multi_box_adaptor.dart:726-746` 从 `firstChild`
   用 `childAfter` 递增遍历 `paintChild`）。据此只让上层新页淡入、下层旧页保持不透明，
   过渡中不闪背景。

为什么比整块平移好——三点：

- **不动的东西多了**：画框、圆角半径、卡片外轮廓全程静止，观众的眼睛有稳定参照物。
  整块平移时画面上没有任何静止元素，视觉系统只能把运动解释成「物体在动」。
- **变形消失了**：宽度恒定，`BoxFit.cover` 的裁切框不变，封面不会被横向挤压。
- **有纵深**：封面推近（scale 1→1.045）而文字位移更小、淡出更快，模拟「摄影机推进 +
  叠化剪辑」，这是影视预告片里最常见的换镜方式，观众已经习惯把它读成「同一处画面换了」。

对抗的替代方案与取舍：

| 备选 | 为什么不选 |
|---|---|
| 只把 `shrinkExtent` 调大（如 0.9 视口宽） | 能消除压缩，但仍是从左往右掠过的整块平移；回卷问题也还在，且 `CarouselView.builder` 不认 `shape`/`padding`，圆角仍由卡片自己带 |
| 纯交叉淡化（不做位移抵消） | 两页按槽位并排各占半屏，本质还是「两个物体」，只是硬度降低 |
| 视差但保留 100% 位移 | 方向感更强，但画框边缘会不断被卡片边缘撞到，仍读成「物体移动」 |
| 自己写 `AnimatedSwitcher` 换图 | 失去手势拖动，且「拖到一半松手」的连续进度没有来源，做不到跟手 |

---

## 二、圆角怎么处理才不突兀

核心一句话：**让圆角从「卡片的属性」变成「画框的属性」。**

问题的本质不是圆角半径不对，而是**相邻两页各自带着自己的圆角矩形**。当它们错位重叠时，
画面上会同时出现两个圆角轮廓——两条弧线一错位，就会被读成「两个物体」而不是「一个窗口」。

处理办法分两步：

1. **外层固定画框**：`ClipRRect(borderRadius: AppRadius.all(AppRadius.md))` 包在
   `Listener` 内、`Stack` 外。它裁的是整个轮播区，半径恒定。只要它存在，过渡中露出的
   圆角永远只有一套。
2. **卡片自己的圆角在过渡中收平**：`_FeaturedVideoSurface` 的 `Material` 用

   ```dart
   final radius = AppRadius.all(AppRadius.md * (1 - progress.abs()).clamp(0.0, 1.0));
   ```

   静止时 `progress == 0` → 半径 12，与外层画框**同心同半径**，两者完全重合，看不出任何
   差别；过渡中 `progress` 走到 ±1 → 半径收到 0，卡片变成直角矩形，它的边缘被外层画框的
   圆弧裁掉。**视觉上圆角始终只有一个，且始终不动。**

为什么这样不突兀：圆角在过渡中「消失」的过程是连续的（线性 12 → 0），而外层画框的圆角
同时把它盖住，所以观者看不到「圆角在变小」，只看到「画面变了但窗口没变」。半径从不为负、
从不跳变，也就不存在插值导致的抖动。

不用 `ClipRRect` 直接裁每页而依赖 `Material` 的原因：`Material` 的裁剪发生在每页自己的
坐标系里，会跟着 `Transform` 一起动；只有画框级的裁剪才是全局静止的。

> 若你希望完全不动 `_FeaturedVideoSurface` 的圆角，退化做法是把 `radius` 恒定为
> `AppRadius.md`：外层画框仍然保证静止圆角存在，但过渡中两页错位约 12% 画框宽时，
> 下层卡的圆角会从左边缘露出来。可用性不受影响，观感略差，本方案推荐收平。

---

## 三、手动点击与自动轮播的参数差异

两种触发的心理场景不同，参数就该不同：

| | 自动轮播 | 手动点击 |
|---|---|---|
| 触发 | `Timer.periodic` 每 6 秒 | 左/右箭头 `_SwiperButton` |
| 谁在等 | 没人等，观众可能没在看 | 用户刚点完，在等反馈 |
| 时长 | `AppMotion.page`（400ms） | `AppMotion.emphasis`（250ms） |
| 曲线 | `AppMotion.standardCurve` = `Easing.standard` `Cubic(0.2, 0, 0, 1)` | `AppMotion.decelerate` = `Easing.standardDecelerate` `Cubic(0, 0, 0, 1)` |
| 观感 | 从容、两端都缓，不抢注意力 | 立刻起步、末段缓停，回应干脆 |

理由：

- **自动要慢一点**。6 秒一次的被动动画如果 250ms 就完成，会像「闪一下」，反而更抓眼睛；
  400ms 的完整淡入淡出让切换读起来像「换了一幅画」。
- **手动要快一点**。用户点击后已经有明确预期，超过 300ms 就会觉得「卡」。250ms 是
  Material 规范里「小范围状态变化」的上界，正好。
- **曲线方向不同**。自动用 `standard`（两端缓）——没有起点冲击感；手动用 `decelerate`
  （起点即最高速、末端缓出）——点击瞬间就动起来，符合「用户指令已被执行」的反馈要求。
- 两者都在 200–500ms 区间内，且都落在 `AppMotion` 现有 token 上，不新增字面量。

实现上只差一个布尔参数：

```dart
void _advance(int delta, {bool automatic = false}) { ... }
```

定时器传 `automatic: true`，按钮走默认 `false`。

**方向语义**：`delta > 0` 用 `nextPage`，`delta < 0` 用 `previousPage`。无穷页下两者都不会
碰到边界。

---

## 四、Flutter 落地要点

### 4.1 依赖与前置事实

全部用 Flutter 内建，无新依赖。三项已核实（详见
`docs/research/_sources/pageview-capability.md`）：

- `PageView.builder` 的 `itemCount` 是 `int?`（`page_view.dart:748`），传 `null` 即无穷页。
- `PageController.page` 在 `initialPage = 10000` 量级下精度充足（`page_view.dart:401-410`
  只做一次除法），但类型是 `double?`，读取须写 `?? initialPage.toDouble()`。
- 视口内多页**索引大的后画、在上层**（`sliver_multi_box_adaptor.dart:726-746`）。

### 4.2 改哪几处

| 位置 | 改动 |
|---|---|
| `_FeaturedSwiperState` | `CarouselController` → `PageController`（大 `initialPage`）；`_advance` 换 `nextPage`/`previousPage` 并区分自动/手动；build 外层加 `ClipRRect` |
| 新增 `_CarouselPage` | 逐页读 `controller.page`，算 `δ`，给整页 `Opacity`，把 `δ` / 页宽传给卡片 |
| `_FeaturedVideoSurface` | 新增两个可选参数 `progress` / `extent`（默认 `0` / `0`，单张卡路径行为不变）；封面层与文字层外侧各加一层 `Transform`；`Material` 圆角按 `1 - |δ|` 收平 |

`_FeaturedVideoSurface` 的 `Positioned` 仍直接挂在 `Stack` 下，`left` / `right` / `bottom` /
`height` / 文字样式 / 层序全部不动——只是每层内部多包了一层变换。

### 4.3 `_FeaturedSwiperState`

```dart
class _FeaturedSwiperState extends State<_FeaturedSwiper> {
  static const Duration _interval = Duration(seconds: 6);

  /// 无穷分页的起始页：足够大，用户连续点几千次也走不到两端。
  static const int _initialPage = 10000;

  late final PageController _controller = PageController(initialPage: _initialPage);
  final _current = ValueNotifier<int>(0);
  Timer? _timer;
  bool _interacting = false;

  int get _count => widget.videos.length;

  @override
  void initState() {
    super.initState();
    _current.value = _initialPage % _count;
    _restartTimer();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _current.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _restartTimer() {
    _timer?.cancel();
    if (_count < 2) return;
    _timer = Timer.periodic(_interval, (_) => _advance(1, automatic: true));
  }

  void _advance(int delta, {bool automatic = false}) {
    if (!mounted || _interacting) return;
    final position = Scrollable.maybeOf(context)?.position;
    if (position != null && position.isScrollingNotifier.value) return;
    final sliver = context.findAncestorRenderObjectOfType<RenderSliver>();
    if (sliver?.geometry?.visible != true) return;

    final duration = motionDuration(
      context,
      automatic ? AppMotion.page : AppMotion.emphasis,
    );
    final curve = automatic ? AppMotion.standardCurve : AppMotion.decelerate;
    if (delta > 0) {
      _controller.nextPage(duration: duration, curve: curve);
    } else {
      _controller.previousPage(duration: duration, curve: curve);
    }
    _restartTimer();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final total = _count;
    return Listener(
      onPointerDown: (_) {
        _interacting = true;
        _timer?.cancel();
      },
      onPointerUp: (_) {
        _interacting = false;
        _restartTimer();
      },
      onPointerCancel: (_) {
        _interacting = false;
        _restartTimer();
      },
      child: ClipRRect(
        // 画框：位置、尺寸、圆角半径全程不动。
        borderRadius: AppRadius.all(AppRadius.md),
        child: Stack(
          fit: StackFit.expand,
          children: [
            PageView.builder(
              controller: _controller,
              itemCount: null, // 无穷页
              onPageChanged: (index) => _current.value = index % total,
              itemBuilder: (context, index) => _CarouselPage(
                controller: _controller,
                index: index,
                video: widget.videos[index % total],
              ),
            ),
            // 右下箭头、底部指示点保持原样，不在此展开。
          ],
        ),
      ),
    );
  }
}
```

箭头按钮的 `onTap` 不变：`() => _advance(-1)` / `() => _advance(1)`。

指示点仍用 `ValueListenableBuilder<int>(valueListenable: _current)`，`_current` 现在是
`index % total`，比较逻辑无需改。

### 4.4 新增 `_CarouselPage`

```dart
/// 一页轮播：读取连续滚动进度，换算成整页透明度并下发视差参数。
class _CarouselPage extends StatelessWidget {
  const _CarouselPage({
    required this.controller,
    required this.index,
    required this.video,
  });

  final PageController controller;
  final int index;
  final VideoCard video;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final extent = constraints.maxWidth;
        return ListenableBuilder(
          listenable: controller,
          builder: (context, _) {
            final page = controller.page ?? controller.initialPage.toDouble();
            final delta = (index - page).clamp(-1.0, 1.0);
            // 索引大的页绘制在上层：只让上层（delta > 0，即将进入）淡入，
            // 下层（delta < 0，正在退出）保持不透明，避免中途露出容器底色。
            final opacity = delta > 0 ? (1.0 - delta).clamp(0.0, 1.0) : 1.0;
            return Opacity(
              opacity: opacity,
              child: _FeaturedVideoSurface(
                video: video,
                progress: delta,
                extent: extent,
              ),
            );
          },
        );
      },
    );
  }
}
```

`Opacity` 在值等于 0 时会跳过子树绘制，所以离屏页没有多余开销。

### 4.5 `_FeaturedVideoSurface` 的增量

新增字段与常量（放在现有 `_titleStyle` 附近）：

```dart
final VideoCard video;

/// 当前页相对「正在展示页」的偏移：0 = 正中央，[-1, 1] 之内处于过渡中。
final double progress;

/// 画框宽度（逻辑像素）。为 0 表示未启用视差（单张推荐卡的场景）。
final double extent;

/// 封面层抵消滚动位移的比例。1.0 = 完全抵消，画框看起来纹丝不动。
static const double _coverParallax = 0.88;

/// 封面在偏移满一页时的放大比例，制造纵深。
static const double _coverZoom = 0.045;

/// 文字层抵消比例，小于封面，形成「文字比画面慢」的视差。
static const double _metaParallax = 0.62;

/// 文字在偏移满一页时的淡出速率。
static const double _metaFade = 1.8;
```

构造器加两个默认参数，单张卡路径零影响：

```dart
const _FeaturedVideoSurface({
  required this.video,
  this.progress = 0,
  this.extent = 0,
});
```

build 里加三行派生量：

```dart
final distance = progress.abs();
final shift = -progress * extent;
// 圆角从「卡片的属性」过渡成「画框的属性」：过渡中收平，静止时与外层画框重合。
final radius = AppRadius.all(AppRadius.md * (1 - distance).clamp(0.0, 1.0));
```

`Material` 的 `borderRadius` 从 `BorderRadius.circular(AppRadius.md)` 改成 `radius`。

封面层——原来直接是 `AppCachedNetworkImage`，现在外面包两层：

```dart
Transform.translate(
  offset: Offset(shift * _coverParallax, 0),
  child: Transform.scale(
    scale: 1 + _coverZoom * distance,
    child: AppCachedNetworkImage(
      imageUrl: video.coverUrl,
      fit: BoxFit.cover,
      memCacheWidth: 1280,
      fadeInDuration: Duration.zero,
      errorWidget: (_, __, ___) => ColoredBox(color: cover),
    ),
  ),
),
```

它仍是 `Stack` 的非定位子节点，`StackFit.expand` 会强制填满，层序不变。

文字层——`Positioned(left: 20, right: 20, bottom: 18)` 内部、`IgnorePointer` 之下加两层：

```dart
Positioned(
  left: 20,
  right: 20,
  bottom: 18,
  child: IgnorePointer(
    child: Transform.translate(
      offset: Offset(shift * _metaParallax, 0),
      child: Opacity(
        opacity: (1 - _metaFade * distance).clamp(0.0, 1.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [ /* 标题与 meta 原样保留 */ ],
        ),
      ),
    ),
  ),
),
```

底部渐变遮罩层（`height: 140` 那段）**保持不动**——它负责压暗，跟着动会在边缘露出亮边；
让它稳定、文字在它上面浮动，层次反而更清楚。

### 4.6 关键参数一览

| 常量 | 值 | 作用 | 调大 / 调小的效果 |
|---|---|---|---|
| `_coverParallax` | 0.88 | 封面抵消滚动的比例 | →1.0 更「画框恒定」、方向感变弱；→0 退回整块平移 |
| `_coverZoom` | 0.045 | 封面最大推近 | 调大更有纵深，超过 0.08 开始像「放大镜」 |
| `_metaParallax` | 0.62 | 文字抵消比例 | 与封面的差越大，视差越明显；相等则无视差 |
| `_metaFade` | 1.8 | 文字淡出速率 | 1.8 时约在 0.56 页处淡完；调小会与新页标题重叠 |
| `_initialPage` | 10000 | 无穷页起点 | 任意大整数均可，两端余量足够即可 |

### 4.7 暗色 / 亮色主题

方案本身不引入任何颜色，只在尺寸与透明度上做文章，因此天然双主题通用：

- 圆角裁剪与透明度与主题无关；
- 指示点继续用 `theme.colorScheme.primary`，选中态发光沿用现有实现；
- 封面加载失败兜底继续用 `colorScheme.surfaceContainerHighest`；
- 文字继续是白字 + 黑色投影（压在图片上的既有做法），不因主题改变。

唯一需要留意的是**未选中指示点的 `Colors.white.withValues(alpha: .45)`**：亮色主题下若封面
本身很亮，白点会看不清。这是现状问题、不属于本次动效范围，但如果顺手要修，改成
`theme.colorScheme.onSurface.withValues(alpha: .45)` 更稳——**本次不改，仅记录**。

### 4.8 验收清单

- [ ] 切换过程中卡片外轮廓保持矩形→被画框裁成圆角，看不到第二条弧线
- [ ] 手动点击后 250ms 内完成，自动切换 400ms 完成
- [ ] 连续点击超过 2000 次仍能继续向前翻（无穷页未到底）
- [ ] 从最后一张点「下一张」直接到第一张，没有整排倒掠
- [ ] 拖动到一半松手，能正确吸附并落到相邻页
- [ ] 系统开启「减少动态效果」时切换瞬时完成（`motionDuration` 归零）
- [ ] 单张推荐（`videos.length == 1`）时行为与改动前完全一致
- [ ] `flutter analyze` 无新增告警

---

## 变更影响面

只动 `lib/src/features/explore/explore_page.dart` 一个文件，三处：`_FeaturedSwiperState`、
新增的私有 `_CarouselPage`、`_FeaturedVideoSurface`。`CarouselView` 在该文件中的唯一调用点
被替换；仓库内其它 `CarouselView`/`PageView`（`comic_pages.dart`、`getchu_preview_detail_page.dart`）
与推荐位无共享代码，不受影响。
