# 设计令牌手册

> 这份文档的读者是**要动 UI 的人**（包括 AI）。它回答三个问题：
> 手上这个值该用哪个令牌、为什么不能就地写字面量、加新令牌要满足什么条件。
>
> 相关：[ui-polish.md](ui-polish.md)（打磨验收条目）、[CONTEXT.md](../CONTEXT.md)（领域词汇）。

## 令牌住在哪

| 模块 | 收什么 | 不收什么 |
| --- | --- | --- |
| `lib/src/core/app_design_tokens.dart` | 设计稿实测的**基准面**（侧栏、顶栏、首页骨架）：颜色、尺寸 | 可由主题推导出来的颜色（用 `accentOf`） |
| `lib/src/core/app_radius.dart` | 圆角，**按元素尺寸分档** | 某个页面专用的圆角 |
| `lib/src/core/app_motion.dart` | 时长、曲线、`motionDuration()` | 某个动画专用的曲线 |
| `lib/src/core/app_surface_tokens.dart` | 有**推导规则**的底色（按明暗、按档位算） | `colorScheme.surfaceContainerLow` 这类直接转发 |
| `lib/src/core/color_contrast.dart` | 对比度判定与兜底换色（纯函数） | 任何 `BuildContext` 相关的东西 |
| `lib/src/core/progressive_fade.dart` | 遮罩渐变（五阶 alpha） | widget 或状态 |
| `lib/src/core/app_scroll_behavior.dart` | 滚动条/滚轮行为 | — |

判断标准只有一条：**这个值有规则吗**。
- 有规则（按明暗推导、按尺寸分档、按语义取语义色）→ 收进令牌模块，调用点只做**选择**。
- 没规则（就是设计稿上一个数）→ 直接写字面量，但**同一个语义在全应用只能有一个数**。

反面例子写在 `app_surface_tokens.dart` 的开头：曾经有一张「各档玻璃浓度」表，
它和材质真实的 `tint` alpha 是两份真相，改了一边另一边就悄悄对不上。同一个值
在两个地方各自维护，就是在制造这种漂移。

## 圆角：按元素尺寸分档

`AppRadius` 的分档依据是**元素高度**，不是页面归属。同样的 12 放在 40px 高的 chip 上
是药丸，放在 300px 宽的卡片上几乎看不出——所以「同一个卡片在三个页面是三个数」是错的，
「同一个尺寸在任何页面是同一个数」才是对的。

| 令牌 | 值 | 用于 |
| --- | --- | --- |
| `AppRadius.xs` | 6 | 进度条、色块、角标、封面内的细节描边 |
| `AppRadius.sm` | 10 | 封面切口、缩略图、紧凑卡片、菜单项 |
| `AppRadius.md` | 12 | 列表行、设置卡片、下拉、浮层提示 |
| `AppRadius.lg` | 16 | 内容卡片、对话框里的分组、面板 |
| `AppRadius.xl` | 24 | 对话框、底部弹层、整块面板 |
| `AppRadius.pill` | 999 | chip、标签、开关滑块 |

新增档位的前提是**出现了现有档位装不下的尺寸**，而不是「这个页面想用 14」。

`AppRadius` 存在之前，34 个文件里散着 15 种圆角值（2/4/6/8/10/12/14/15/16/18/22/24/28/40/999）。
迁移是渐进的：`test/design_token_guard_test.dart` 用一份**只减不增**的额度表挡住回退，
谁写新的字面量谁就把额度加一，同时刻意留下的历史值集中在一处、看得见。

## 动效：语义命名，不写数字

`AppMotion` 把 Material 3 的 token 换成业务语义名：

| 令牌 | 对应 M3 | 用于 |
| --- | --- | --- |
| `instant` | short1 (50ms) | 按压、hover 高亮 |
| `quick` | short2 (100ms) | 图标切换、tooltip 淡入 |
| `brief` | short3 (150ms) | 控件展开收起、焦点态 |
| `standard` | short4 (200ms) | 页面内小幅位移、卡片状态变化 |
| `emphasis` | medium1 (250ms) | 面板展开、底部弹层 |
| `dialog` | medium2 (300ms) | 对话框进出 |
| `page` | medium4 (400ms) | 整页切换 |
| `showcase` | extralong1 (700ms) | 启动动画、进度扫光 |

曲线同理：`enter` / `exit` / `standardCurve` / `accelerate` / `decelerate` / `linear`。

**所有时长都要过 `motionDuration(context, ...)`**。它在系统「减少动画」或祖先
`TickerMode` 关闭时返回 `Duration.zero`，控件直接跳终态。直接写 `Duration(milliseconds: 200)`
不只是「散成字面量」，还绕过了这条无障碍兜底。

> 例外：`configured_media_kit_video_player.dart`、`dlna_media_renderer.dart` 里的
> `Duration(milliseconds:)` 是**播放器心跳/超时**，不是界面动效，不该换成 `AppMotion`。
> 守卫测试只扫 `lib/src/features`，原因就在这里。

## 颜色：基准面 vs 跟随主题

这是本仓库最容易搞错的一条。

- **骨架**（侧栏、顶栏、首页列表）用 `AppDesignTokens.accent` / `accentDeep` 等固定色，
  还原设计稿的 「#C8527C 胭脂粉」。那里是基准面，不参与换色。
- **可交互控件**（开关、滑块、选中描边、按钮）一律 `AppDesignTokens.accentOf(context)`，
  取 `colorScheme.primary`。用户在「主题与色彩」里把颜色换成青，控件还是粉的，
  看起来就是「换色没生效」。

半透明底色不要在调用点自创：`scheme.surface.withValues(alpha: .62)` 这种「当场决定多不透明」
的写法有规则（按明暗推导），应走 `AppSurfaceTokens.closedSurface()`。
`test/surface_token_guard_test.dart` 会拦。

文字压在半透明底上时，先 `opaqueCompositeOver()` 合成再 `meetsContrast()` 判定，
不要拿 RGBA 直接比 —— `Colors.white70` 的真实观感远低于把它当纯白算出来的结果。

## 加令牌的清单

1. **先找语义**，再找值：这个数要表达的是「内容卡片圆角」还是「16」？
2. **能推导就不要存**：能从 `colorScheme` / `brightness` / 元素高度推出来的，写成函数。
3. **只保留一个来源**：同一个语义出现第二份数据就是 bug，不是「保险」。
4. **文档注释写清「为什么是这个值」**：设计稿实测、规避什么回归、换算过程。
   写「卡片圆角」没有信息，写「设计稿封面圆角 12，卡片本体/封面切口/选中描边共用，
   避免几处各写一个数后走样」才是。
5. **加回归守卫**：能用静态检查挡住的（regex 扫源码）就加进
   `test/design_token_guard_test.dart`，不要只靠 review。
6. **故意写一次违规**，确认守卫真的会红 —— 守卫永远绿的守卫等于没有守卫。

## 布局：哪些「实测数字」值得记

设计稿还原时的空间测量（如「顶栏 112 高 = 34 窗口按钮带 + 78 内容带」）写进令牌的
文档注释里，不要只留在 PR 描述或聊天记录。判断标准：**改了别的结构，这个数会不会失效**。

会失效的例子（值得记）：

```dart
/// 设计稿页签下划线落在 y90~92，内容带底是 y112，因此贴底留 20。
/// 但这里取 12.5 —— 顶栏 Stack 的底边实测比内容带底高 7.5，20 - 7.5 = 12.5
/// 才能把下划线落到设计稿位置。改了顶栏结构要重新校准。
static const topBarTabBaselineGap = 12.5;
```

不会失效的例子（不值得记）：某一行 `EdgeInsets.symmetric(horizontal: 16)`。
横向间距目前没有统一令牌，因为设计稿里它基本恒为 16/20/24 三档，写死不会走样；
一旦发现同一个语义出现第三种值，再收令牌。

## 间距：目前没有令牌，为什么

`EdgeInsets.*` 与 `SizedBox` 的字面量在全仓各有 400+ 处。**没收不等于可以随便写**，
而是因为 Flutter 的布局组合方式与 Web 的盒模型不同：`Column(gap)`、`Padding`、
`SizedBox` 三种表达同一件事，收成令牌后调用点仍然要在三者之间选，令牌帮不上忙。

真要做的话，第一步不是造 `AppSpacing.sm`，而是**先确认设计稿的间距阶梯**（4/8/12/16/24/32？），
再决定用哪种表达。在那之前，遵守一条就够了：**同一个组件内的间距用同一个数**。
