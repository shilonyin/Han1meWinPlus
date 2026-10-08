# UI 打磨清单（better-ui）

来源：`https://www.skills.sh/jakubkrehel/skills/better-ui`（`SKILL.md`）。
它是一份**打磨与验收规范**，不是设计系统：排版归 better-typography、配色归 better-colors、
命中区与无障碍归 better-accessibility。原文是写给 Web/CSS 的，下面只留对 Flutter 适用、
并且本仓库确实有落差的条目。

## 背景：为什么玻璃退役

`docs` 之外的另一件事记在这里，免得后来人又走一遍：g1455 的玻璃在这台机器上有两条绕不过去的
限制 —— ① 它的 `GlassHost` 一屏只录**一张**共享的降采样图、且在 post-frame 回调里录，
所以采样天生晚一帧，滚动时上一帧的标题/图标会被采进玻璃卡（就是「滚动浮出灰块」），
只有当材质 tint 的 alpha 很低（超透/磨砂 = .22）时才看得见；② 我们的页面底色被刻意压成
近乎纯色（`#F2F2F7`/`#070A12` + 光晕 6~8%），背景没有内容可透时，玻璃在数学上只剩
「一层半透明色」。结论：**玻璃只保留在 g1455 自带的控件（开关、滑条、搜索框）里**，
导航层与内容卡片回到主题自己的 surface。

后续（2026-10 死代码清理）：`lib/src/core/settings.dart` 里那 6 个玻璃枚举
（材质 / 预设 / 染色 / 波纹 / 渲染 / 对比度）、`AppSettings` 上的对应字段与 44 个 `glass*`
文案键全部删掉了 —— 渲染层早就不读它们，留着只会让后来人以为「改了有用」。
`setting.json` 里的老键（`glassMaterial` / `glassQuality` / `glassTier` 等）现在只是被忽略的
陌生字段：`fromJson` 只读它认得的键，多余键不会报错，但下次保存起就不再写回。

## 已达标

- 减弱动效：`lib/src/core/app_motion.dart:73` 的 `motionEnabledOf` 已经同时看
  `MediaQuery.disableAnimationsOf` 与 `TickerMode.valuesOf`；`motionDuration()` 在关闭时归零，
  控件直接跳终态 —— 这条规范里**最容易漏的一条我们已经有了**。
- 图标：统一用 `Symbols.*_rounded`；`currentColor` 等价物是 `IconTheme`/`color:`，无需双资源。

## 已修（本次）

| 条目 | 规范 | 本仓库处理 |
| --- | --- | --- |
| 状态图标瞬间替换 | 切图标要有 `scale .25→1` + `opacity 0→1` + `blur 4→0`，300ms、不回弹 | 新增 `lib/src/features/shared/motion_icon.dart` 的 `MotionStateIcon`，用在播放/暂停、画中画、投屏三处 |
| 动画时长散成字面量 | 只过渡真正变的属性，时长走语义令牌 | 7 个文件里的 200/220/240/250/260/320ms 全部收进 `AppMotion.*`（`lib/src/core/app_motion.dart`） |
| 缩略图没有内描边 | 图片贴边时给 1px 内描边，浅色 `black/10`、深色 `white/10` | `lib/src/features/shared/video_card.dart` 与 `compact_video_card.dart` 的封面加 `Positioned.fill` 描边 |
| 按下反馈 | `scale .96` / 150ms ease-out；`disableAnimations` 时不播 | 新增 `lib/src/features/shared/press_scale.dart` 的 `PressScale`，全应用 267 处按钮/卡片统一包一层（58 个文件）；`motionDuration` 归零时直接跳变 |

## 不适用

- `overscroll-behavior: contain`：Flutter 的 dialog/sheet 是独立路由，没有「滚动链」这回事。
- `@media (hover: hover)`、`will-change`、`oklch`、`box-shadow` 分层：CSS 专有；Flutter 侧
  对应的是 `MouseRegion`、`RepaintBoundary`、`Color` 与 `BoxShadow`，仓库里本来就在用。
- 首帧不播状态动画：Flutter 的 `AnimatedX` 首帧就是终态，天然满足。

## 尚未做（按优先级）

目前没有已知的落差条目。最后一条（`video_detail_content.dart` 的 `_TitleText.maxLines`
参数没人传值，`unused_element_parameter`）已在 2026-10 的清理里收成类内常量 `_maxLines`：
唯一调用点本来就固定用 2，参数是「写了但没人能改」的中间态。
