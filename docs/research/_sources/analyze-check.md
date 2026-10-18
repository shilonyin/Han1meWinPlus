# `flutter analyze` 验证记录

**目的**：确认 `docs/research/featured-carousel-motion.md` 里给出的 Dart 代码能被分析器
接受——即类型正确、API 名与参数名真实存在、`AppMotion`/`AppRadius`/`PressScale` 引用成立。

## 怎么验的

把文档 4.3～4.5 三段的代码整体抄进临时探针
`lib/src/features/explore/_carousel_motion_probe.dart`，用占位模型 `_ProbeVideo`
替代 `VideoCard`、用 `ColoredBox` 替代 `AppCachedNetworkImage`（缓存层 API 已另行核实，
见下方「与文档的差异」），然后执行：

```
C:\flutter-3.47.4\bin\flutter.bat analyze lib/src/features/explore/_carousel_motion_probe.dart
```

## 结果

```
Analyzing _carousel_motion_probe.dart...
No issues found! (ran in 0.9s)
```

无 error、无 warning、无 info。探针验完已删除，不进入提交。

## 这一轮实际证明成立的点

| 文档中的写法 | 验证到的事实 |
|---|---|
| `PageView.builder(itemCount: null, ...)` | `itemCount` 接受 `null`，无穷页写法通过类型检查 |
| `PageController(initialPage: 10000)` + `nextPage(duration:, curve:)` / `previousPage(duration:, curve:)` | 两个方法名与具名参数都存在 |
| `controller.page ?? controller.initialPage.toDouble()` | `page` 是 `double?`、`initialPage` 是 `int`，空安全写法成立 |
| `ListenableBuilder(listenable: controller, ...)` | `PageController` 直接可用作 `Listenable`，无需额外适配 |
| `motionDuration(context, AppMotion.page / AppMotion.emphasis)` | `app_motion.dart` 里两个 token 与免费函数均可从本文件 import 路径到达 |
| `AppMotion.standardCurve` / `AppMotion.decelerate` | 两个曲线成员存在 |
| `AppRadius.all(AppRadius.md * (1 - distance).clamp(0.0, 1.0))` | 返回类型是 `BorderRadius`，可直接喂 `Material.borderRadius` |
| `Material(borderRadius: radius, clipBehavior: Clip.antiAlias, ...)` | 参数存在且类型匹配 |
| `ListenableBuilder` 里读 `controller.page` 再逐帧重算 `Opacity` | 无 lint 告警 |
| `PressScale(child: ...)` | 单参数构造成立（探针里只传了 `child`） |

## 与文档的差异（探针简化，不影响结论）

1. 探针用 `ColoredBox(color: cover)` 顶替 `AppCachedNetworkImage`。后者是项目自有 widget，
   参数清单已核实（`lib/src/features/shared/app_image_cache.dart:122`：`imageUrl` / `fit` /
   `memCacheWidth` / `fadeInDuration` / `errorWidget` 等），文档里用法与既有
   `explore_page.dart:1257-1263` 完全一致，未改动。
2. 探针里箭头按钮用 `IconButton` 占位，文档中保留项目原有的 `_SwiperButton`（`PressScale`
   + `Material` + `InkWell` + `Tooltip` + `SizedBox`），后者是既有代码，本次不改。
3. 探针省略了 `_advance` 里「外层滚动中跳过」「卡片滚出视口跳过」两条守卫（需要真实
   `Scrollable` / `RenderSliver` 祖先才能触发，探针环境里没有）。这两条是既有逻辑，文档中
   原样保留。

## 没能验证的部分

`flutter analyze` 只做静态检查，以下需要真机运行才能确认，已列入文档 4.8 的验收清单：

- 视差与缩放的实际观感（`_coverParallax` 0.88 / `_coverZoom` 0.045 / `_metaParallax` 0.62
  这几个值是按比例推的，需要在 16:5、宽 1200px 左右的实际画框上肉眼确认）；
- 拖动到一半松手的吸附落点；
- 「减少动态效果」开关下的瞬时切换。
