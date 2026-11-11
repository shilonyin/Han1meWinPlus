---
version: alpha
name: Han1meWinPlus-design-system
description: "桌面端追番播放器 Han1meWinPlus 的视觉基准。以 v6 设计稿实测为准：近白的页面底 #F4F4F7 上压纯白卡片与胶囊，一支胭脂粉 #C8527C 作唯一强调色、深一档的 #B3265A 承载选中态；正文三级灰（#1B1B1F / #5F5F6B / #8A8A96）。字体为内置 HarmonyOS Sans SC（可变字体 9 档字重），侧栏 176 宽、顶栏 112 高。整体克制、留白充足，颜色是语义 token 而非主题转发层。"

# 说明：本文件由 lib/src/core/app_design_tokens.dart、app_radius.dart、
# app_motion.dart、lib/src/app/app_theme.dart 的真实取值整理而来。
# 规则：只记录源码里已有的名字与值，不发明新值；顺序与源码一致；值原样（hex 小写）。

colors:
  # ── 强调色（品牌基准面固定，不跟随用户主题） ──
  accent: "#c8527c"            # 主色：选中导航项、tab 下划线、tag、播放数胶囊
  accent-deep: "#b3265a"       # 选中态实际用色，比 accent 暗一档（只有骨架用）
  accent-of: "colorScheme.primary"  # 跟随用户主题色的强调色（设置页可交互控件用）
  nav-selected-wash: "#14b3265a"    # 选中导航项底色：accentDeep 压到 8%

  # ── 面 ──
  surface: "#ffffff"           # 侧栏 / 卡片底板
  page-background: "#f4f4f7"   # 页面底，白卡/白胶囊压在上面的基准
  account-card-fill: "#f6f6f9" # 侧栏底部账号卡底（比侧栏白暗一点，无描边）
  field-fill: "#ededf2"        # 输入框底色（非玻璃输入框）

  # ── 描边 / 分隔 ──
  stroke: "#e2e2e8"            # 卡片、输入框、胶囊的分隔描边
  divider: "#ececf1"           # 侧栏分组之间的细线

  # ── 文字（三级灰 + 说明） ──
  ink: "#1b1b1f"               # 正文 / 页头 / 卡片标题
  ink-subtle: "#5f5f6b"        # 次级正文：作者行、未选中项
  ink-muted: "#8a8a96"         # 说明文字：计数、日期、占位文字（fieldHint 并入此色）
  chip-scrim: "#1b1b1f"        # 封面上的胶囊底（播放数 / 时长）

  # ── 状态 ──
  switch-track-off: "#b7b7b9"  # 开关关闭态轨道（中灰，压白卡能看出关着的开关）

typography:
  # 字体：内置 HarmonyOS Sans SC（可变字体，单文件 9 档字重），
  # fallback: Microsoft YaHei UI / Segoe UI Emoji / Segoe UI Symbol。
  # 系统字体开关打开时交回平台默认字体。
  #
  # 本仓库没有集中的 TextTheme 字号表，字号按用途散在 token 与各页面里。
  # 以下只记录 token 中已显式命名的字号（不发明）：
  font-family: "HarmonyOS Sans SC"
  font-family-fallback: ["Microsoft YaHei UI", "Segoe UI Emoji", "Segoe UI Symbol"]
  sizes:
    sidebar-label: 13px        # 侧栏导航项文字（navText/*）
    section-title: 22px        # 分区标题

rounded:
  xs: 6px                      # 微元素：进度条、色块、小角标
  sm: 10px                     # 小元素：封面切口、缩略图、菜单项、tag 圆角
  md: 12px                     # 中元素：列表行、设置卡片、下拉、按钮
  lg: 16px                     # 大元素：内容卡片、面板
  xl: 24px                     # 特大：对话框、底部弹层、整块面板
  pill: 999px                  # 全圆药丸：chip、标签、开关滑块

spacing:
  # 本仓库没有 4/8/12 的通用间距阶梯；间距写在调用处，圆角另见 rounded。
  # 以下只记录 token 中已命名的固定尺度（不发明）：
  sidebar-width: 176
  sidebar-icon-size: 18
  sidebar-item-pitch: 52       # 侧栏项中心到中心
  sidebar-item-height: 34      # 选中底高度（落在 52 行距里，上下各留 9）
  sidebar-item-inset-y: 9      # 由 (52-34)/2 推出
  top-bar-height: 112
  top-bar-chrome-height: 34    # 窗口按钮带
  window-controls-height: 28   # 自绘标题栏高度
  top-bar-tab-baseline-gap: 12.5
  search-box-width: 316
  search-box-height: 34

motion:
  # lib/src/core/app_motion.dart：直接把 Material 3 的 Durations/Easing
  # token 收成业务语义名，不发明新曲线。
  duration:
    instant: 50ms              # 按压、hover 高亮（short1）
    quick: 100ms               # 图标切换（short2）
    brief: 150ms               # 控件展开/收起（short3）
    standard: 200ms            # 页面内小幅位移、卡片状态（short4）
    emphasis: 250ms            # 面板展开、底部弹层（medium1）
    dialog: 300ms              # 对话框进出（medium2）
    page: 400ms                # 整页切换（medium4）
    showcase: 700ms            # 启动动画、进度扫光（extralong1）
  curve:
    enter: emphasizedDecelerate   # 进入屏幕
    exit: emphasizedAccelerate    # 离开屏幕
    standard: standard
    settle: easeOutCubic          # 控件级小幅过渡（进入视野/位移到位/淡入）
    unsettle: easeInCubic         # 反向
  reduce-motion: "motionEnabledOf(context) 为 false 时时长归零，控件直接跳终态"

components:
  # 只记录 token 与主题里已显式定义的组件形态（不发明）。
  card:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.lg}"
    border: "1px {colors.stroke}"
    elevation: 0
  dialog:
    backgroundColor: "{colors.surface}"
    rounded: "{rounded.xl}"
    elevation: 2
    shadowColor: "rgba(0,0,0,0.10)"
  snackbar:
    behavior: floating
    backgroundColor: "surfaceContainerHighest @ 92%"
    rounded: "{rounded.md}"
    elevation: 2
  tag-chip:
    backgroundColor: "{colors.field-fill}"
    textColor: "{colors.ink-subtle}"
    rounded: "{rounded.sm}"
    height: 24
    fontSize: 11
    padding: "0 10"
  sidebar-nav-item:
    selectedBackground: "{colors.nav-selected-wash}"
    selectedTextColor: "{colors.accent-deep}"
    height: 34
    iconSize: 18
    fontSize: 13
  primary-button:
    backgroundColor: "{colors.accent-deep}"
    textColor: "#ffffff"
    rounded: "{rounded.md}"
    height: 40
  icon-tile:
    backgroundColor: "{colors.field-fill}"
    rounded: "{rounded.sm}"
    size: 40
---

# Han1meWinPlus 设计系统

> 本文件是从代码整理出的**设计基准文档**，供人和 AI 编码代理阅读，用于生成视觉一致的界面。
> 所有取值来自 `lib/src/core/` 下的 token 文件与 `lib/src/app/app_theme.dart`；
> **源码是真相**，本文档只是它的可读投影。改 UI 前先读这里，改完更新这里。

## 颜色

颜色一律按 v6 设计稿取值，**不跟随用户主题色**（除非显式用 `accentOf`）。
设计稿主色 `#C8527C` 与主题种子 `#FB7299` 是不同色相，跟种子走还原不出那片胭脂粉。
换主题色的能力由报告页/播放页等处保留；侧栏、顶栏、首页是「基准面」，不参与换色。

- **强调色**：`accent` `#C8527C` 只出现在强调元素上（选中导航、tab 下划线、tag、播放数胶囊）。`accent-deep` `#B3265A` 是选中态实际用色，**只在骨架（侧栏/顶栏/首页）用**。
- **可交互控件**（设置页开关/滑块/按钮）必须用 `accentOf()`（=`colorScheme.primary`）跟随用户主题，否则用户换色后控件还是粉的，看起来像「换色没生效」。
- **三级文字灰**：`ink` `#1B1B1F`（正文）→ `ink-subtle` `#5F5F6B`（次级）→ `ink-muted` `#8A8A96`（说明/占位）。占位文字 `fieldHint` 已并入 `ink-muted`，全页最多三种文字灰。
- **面**：页面底 `page-background` `#F4F4F7`，卡片 `surface` 纯白。白卡压近白底靠「极浅描边 + 一丝投影」读出边界，不靠明度差。

## 字体

- 内置 **HarmonyOS Sans SC**（可变字体，单文件 9 档字重），fallback `Microsoft YaHei UI / Segoe UI Emoji / Segoe UI Symbol`。
- 系统字体开关打开时交回平台默认字体。
- 中文排版：正文行高 ≥1.3、字距 0；长标题不固定单行高度。

## 圆角

按**元素尺寸**分档，不按页面：同尺寸的元素在任何地方用同一档。
`xs 6`（进度条/色块/角标）→ `sm 10`（缩略图/菜单项/tag）→ `md 12`（列表行/设置卡片/按钮）→ `lg 16`（内容卡片/面板）→ `xl 24`（对话框/弹层）→ `pill 999`（chip/标签/开关滑块）。
不做「全改同一个值」——大卡片会方正、小控件会臃肿。

## 尺度

侧栏 176 宽、导航项行距 52、选中底高 34（上下各留 9）、图标 18、文字 13；顶栏 112 高（窗口按钮带 34 + 内容带 78）；搜索框 316×34。

## 动效

统一走 `AppMotion`（M3 token 的语义化命名）：按压 `instant 50`、图标切换 `quick 100`、控件展开 `brief 150`、位移 `standard 200`、面板 `emphasis 250`、对话框 `dialog 300`、整页 `page 400`、启动 `showcase 700`。
曲线：进入 `emphasizedDecelerate`、离开 `emphasizedAccelerate`、控件级 `settle(easeOutCubic)`。
系统「减少动画」开启时（`motionEnabledOf` 为 false）时长归零，直接跳终态。

## Do / Don't

- **不要**跟随主题种子色去还原骨架面的粉色——骨架用固定 `accent`/`accent-deep`。
- **不要**在设置页可交互控件里写死 `accent-deep`，用 `accentOf()`。
- **不要**引入第四种文字灰；说明文字与占位文字共用 `ink-muted`。
- **不要**给普通卡片配不同强调色、粗边框、重阴影；层级靠极浅描边 + 一丝投影。
- **不要**在两处重复画分隔（同一处分隔不叠双线、单线不再加框）。
- **不要**靠 9–12px 小字装「精致」；信息多先删冗余、调层级。
- 图标统一 `Symbols.xxx_rounded`（material_symbols_icons），选中态显式 `fill: 1`；不混用 outlined/border 变体、emoji 当图标。

## Known Gaps（已知空白）

- 本仓库**没有集中的字号阶梯（TextTheme scale）**：除 `sidebar-label 13`、`section-title 22` 外，各处字号写在调用处。本文档不发明通用阶梯；需要时按真实页面补录。
- 本仓库**没有通用间距阶梯**（如 4/8/12/16）：间距写在调用处，本文档只记录 token 里已命名的固定尺度。
- 深色/AMOLED 主题由 Material 3 的 `ColorScheme` 派生（`surfaceContainer*` 用 `Color.lerp(black, primary, ...)`），未在本文档逐条展开。
- 玻璃材质档位：`app_surface_tokens.dart` 收的是滑块/关闭玻璃档的语义底色，玻璃浓度由材质自身的 tint 决定，不在本文档枚举。
