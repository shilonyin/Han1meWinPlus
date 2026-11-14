# 12 个设计灵感站点学习笔记

> 抓取整理于 2026-11-14。12 个站点一次性过了一遍，按用途归类，标注**对 Han1meWinPlus（Flutter 番剧 App）的可迁移点**。
> 目的：以后做 UI / 动效 / 素材时，知道该去哪个站、以及能从里面拿走什么。
>
> 相关：[ui-polish.md](../ui-polish.md)（打磨验收）、[design-tokens.md](../design-tokens.md)（令牌手册）、[DESIGN.md](../DESIGN.md)。

## 速查索引（我要做 X → 去哪个站）

| 场景 | 首选站 | 备注 |
| --- | --- | --- |
| 看同类 App 的页面怎么排（详情页/播放页/付费墙/引导页） | **Mobbin** | 60 万+ 真实上架截图，可按 Flows 看完整流程 |
| 找具体微交互「该动成什么样」 | **60fps.design** | 2140 条 App 动效录屏，可当动效标杆 |
| 复刻交互逻辑（瀑布流、滑动确认、选择器） | **beUI** | 76 个 React Native 组件，逻辑直接翻译成 Flutter |
| 补背景 / 渐变 / 噪点 / 星空素材 | **Backgrounds Supply** | 免费下载，还能导出 MP4 循环背景 |
| 换标题字体、提视觉档次 | **Fontshare** | 免费商用字体（Satoshi 等） |
| 找图标库 / 插画 / Figma kit | **DesignBookmark** | 2722 个工具目录，当黄页查 |
| 做官网 / 展示页 / README 封面 | Landdding、v0 templates、Wedoflow | Web 向，App 内页用不太上 |
| 读高端网页动效的「规格级描述」 | Motion (motionin.design) | 每段带完整 prompt 和逐句动效说明 |

---

## 一、真实产品界面参考

### 1. Mobbin — https://mobbin.com
**是什么**：2018 年起做的「截图文件夹」，现在是 60 万+ 真实上架 App / 网站的界面库，每周更新。分区：Apps / Sites / Screens / Flows / Animations / UI Elements。
**能学到什么**：不是「好看」的抽象风格，而是**真实产品怎么解决问题**——付费墙怎么说服升级、Onboarding 怎么拆步、KYC 流程怎么排。
**对项目**：番剧 App 的详情页、播放页、订阅/会员页、空状态，直接搜同类（视频流媒体、内容社区）照着看结构。它家还有 **Mobbin MCP**（Pro/Team 可用），能把设计参考直接喂给 AI agent。
**注意**：Pro 才解锁完整库与 Flows；免费只给一部分。

### 2. Landdding — https://landdding.com
**是什么**：2.7k 落地页 / 官网灵感，2k 设计师、40 个行业分类、5 个平台（Webflow/Framer/WordPress/Wix/Squarespace），每日更新。
**能学到什么**：单页官网的首屏结构、留白节奏、行业配色。
**对项目**：App 内页帮助有限；做项目官网、下载页、README/宣传图时参考。★★

### 3. Navbar Gallery — https://navbar.gallery
**是什么**：专收导航栏：Static/Sticky、Dropdown/Flyout、Mega Menu、Side Bar、Search Bar、Announcement Bar、Full Screen、Breadcrumbs。
**能学到什么**：导航的 8 种基本形态及其适用场景。
**对项目**：偏 Web。App 的底部 Tab、顶部 AppBar、抽屉侧栏形态可作参考，但不是主战场。★★（该站由 Mobbin 赞助）

---

## 二、动效与微交互（与本项目 motion 令牌最对口）

### 4. 60fps.design — https://60fps.design ★★★★★
**是什么**：2140 个 Shots / 499 个 App / 96 个站点 / 83 段 Motion / 32 段 Snippets / 67 个 Storyboards。专收**一流 App 的「细节动效」录屏**，可在 Shots 里按 App 浏览。
**里面有什么（首页可见样本）**：Apple Health 的 Longevity 开场动画、Revolut 的「卡片就绪」动画、Plasma 的「卡片设置」动画、Runmo 的脉搏/心跳 ECG 交互、Day Counter、距离滚轮填充、Splash 动画、Circle 气泡弹出、Notion 式文本翻转（Value Prop Text Flip）。
**能学到什么**：**Splash / 加载 / 卡片入场 / 数字滚动 / 手势反馈**这些「让 App 显贵」的瞬间。项目里已经有 `motion_token_guard_test.dart`，这些正好是「该动成什么样」的验收标杆。
**对项目**：启动动画（`showcase` 700ms 档）、骨架屏、封面卡片入场、按钮按压反馈，挑 1~2 处对着复刻。
**注意**：它也有 MCP（同样由 Mobbin 提供设计参考）。

### 5. Motion (motionin.design) — https://motionin.design ★★★
**是什么**：高端**交互式 Web 区块**库，分类：Portfolio / Hero / Interactive Product Showcase / Immersive，分 Free/Paid。每个区块附带**一整段「复制 prompt → 直接出货」的描述**。
**能学到什么**：它的价值不在素材，而在**把动效写成规格的能力**。例如 Aperture 那个作品墙：不横向滚动、整面墙缓慢自下而上漂移、随滚动速度做「透镜式」轻微凸/凹弯折并带弹簧回弹、点击任意画框从其精确矩形放大到全屏再缩小回原位——这段描述本身就是一份可执行的动效规格书。
**对项目**：多是滚动驱动的 Web 效果，Flutter 实现成本高；只挑「画框点击 → 精确矩形放大到全屏」这类可迁移的转场思路。
**注意**：这是教人「怎么描述动效」的好范本，写动效需求可参考它的措辞。

### 6. beUI — https://beui.dev ★★★★
**是什么**：157 个 React 组件 + **76 个 React Native 组件**，Framer Motion + Tailwind / Reanimated + Gesture Handler + Uniwind，shadcn CLI 一键装、源码归你、MIT。分类：Components / Blocks / AI Agents / Charts / Casino / React Native / Playground。
**React Native 侧组件（最值得抄）**：
- Actions：Button（弹簧按压 + ripple）、Slide Button（拖动确认 → 转圈 + 打勾）、Keypad（数字键盘）
- Forms：Input、OTP Input、Select、Multi Select、Color Picker、Checkbox、Radio Group、Range Slider、Switch
- Navigation & lists：Bouncy Accordion、Tabs、**Swipeable List**
- Motion：Number Animation、Text Animation、Animated Badge、Loader、**Morphing Modal**、Toast
- AI agents：Message / Message Bubble / Message Scroller / Prompt Input / Streaming Response / Todo List / Tool Approval…
- Blocks：**Infinite Masonry（瀑布流）**、Notification Stack、Project Folder、Availability Scheduler…
**能学到什么**：**交互动效的手感参数**（弹簧阻尼、按压曲线、滑动确认的阈值与回弹）。虽是 RN，但逻辑 1:1 能翻成 Flutter。
**对项目**：优先复刻 `Infinite Masonry`（番剧封面瀑布流）、`Slide Button`（滑动确认/删除）、`Swipeable List`（列表左滑操作）、`Morphing Modal`（详情浮层）。看完记得**用项目的 motion / radius 令牌重写**，别把 RN 的数值直接搬进来。

---

## 三、素材 / 字体 / 资源目录

### 7. Backgrounds Supply — https://backgrounds.supply ★★★★
**是什么**：手作 + AI 生成的背景素材站。工具齐全：
- Gradient Lab（70+ 动态渐变，导出 PNG / MP4）、Free gradients（60+ 免费）
- Halftone 渐变生成器、Grain 噪点/颗粒（含 CSS noise）、Image to Gradient、Image Color Picker、Blur/Pixelate、Gradient Map（双色调）、Animated Background（极光/闪烁视频循环）、Galaxy 星空（免费 4K）、Color Mixer、Solid Color、Teams/Wallpaper Maker
**能学到什么**：把「一张图 / 一个色」快速变成有质感的底。
**对项目**：缺图占位底、卡片底图、空状态背景、启动页渐变、加载时的 aurora 循环（可导 MP4 作装饰）。注意体积，图片要压缩。

### 8. Fontshare — https://fontshare.com ★★★★
**是什么**：Indian Type Foundry 的**免费商用**字体库（纯 JS 应用，抓不到正文，以下为已知信息，具体以站内 License 为准）。代表字体：**Satoshi、General Sans、Clash Display / Clash Grotesk、Cabinet Grotesk、Switzer、Author、Zodiak、Gambetta、Panchang、Ranade** 等，提供 woff2 下载与 CDN。
**能学到什么**：免费也能拿到「不像系统默认」的高质量字。
**对项目**：正文仍用系统字体（省体积、保一致），只给 H1 / 番剧大标题换 Satoshi 或 Clash Display；Flutter 里放 `assets/fonts/` 并在 pubspec 声明。**上线前确认具体字体 License 允许 App 内嵌**，并做子集化控包体。

### 9. DesignBookmark — https://designbookmark.com ★★★
**是什么**：免费设计工具目录，**2722 个工具 / 网站，59 个分类**（Design、Motion、AI、Skills、Development、No-Code & Web、Marketing、Productivity、Business、Content & Media、Learn & Community、平台/Mac/Win/Chrome 扩展），每周新增。可 Google 登录收藏同步。
**能学到什么**：找「某个具体需求用什么工具」时当黄页查（如 1104 图标的 Neat Icons、DjectStudio 的 Figma/Framer kit）。
**对项目**：找图标库 / 插画 / kit 的入口。

---

## 四、AI 建站 / 模板（Web 向，思路参考）

### 10. v0 templates — https://v0.app/templates ★★
**是什么**：Vercel v0 的社区模板库，分类含 Landing Pages / Dashboards / Components / Login / Blog / E-commerce / AI / Animations / Design Systems / Agents。可见大量成品（如 Hously 建筑工作室、Frosted Glass CRM、Elegance 奢华电商、COMPUTE、Optimus）。
**能学到什么**：快速验证一个 Web 页面长什么样时的现成参考。
**对项目**：做官网/展示页时可抄结构；App 无直接用途。

### 11. iter0 — https://iter0.com ★★
**是什么**：AI 建站工具，卖点是**先做竞品调研再出设计**：三个 researcher（读你的站点 / 找竞品 / 找合适版式）→ 出 3 版设计 → 选一版建成 → 发布到 `*.iter0.app`。标语强调「有原创想法，不像 Claude 千篇一律」。
**能学到什么**：**方法论**——「先研究竞品再动手设计」的流程值得借用（做新页面前先看 3 个同类怎么做）。
**对项目**：非素材；当设计流程参考。

### 12. Wedoflow — https://wedoflow.com ★★
**是什么**：216 套付费 Webflow 模板（$39~169），按行业分（Consulting/Medical/Education/Startup/Finance/Technology/SaaS/Agency/Portfolio/Architecture…），常有 95% OFF 促销。
**能学到什么**：成熟落地页的版式与信息结构。
**对项目**：仅做官网时参考。

---

## 五、对 Han1meWinPlus 的落地清单（按性价比排序）

> 前提：**不要改 `AppDesignTokens` / `AppRadius` / `AppMotion` 的既有值**。参考站点的数值只当灵感，落地时一律换成项目现有令牌；确实没有合适档位时，按 [design-tokens.md](../design-tokens.md) 的「加令牌清单」走流程。

1. **审美输入**：先泡 60fps（动效标杆）+ Mobbin（同类 App 页面结构）——这两步定「长什么样」。
2. **beUI 挑 2~3 个交互复刻**：`Infinite Masonry`（封面瀑布流）、`Slide Button`（滑动确认）、`Swipeable List`（左滑操作）。用 Flutter 原生 + 项目令牌重写，不走现成套件。
3. **60fps 选一个动效**：启动动画或封面卡片入场，映射到 `AppMotion.showcase` / `standard` + `motionDuration()` 兜底。
4. **Backgrounds Supply 补素材**：缺图占位底、空状态背景、启动页渐变；体积要压。
5. **Fontshare 换标题字**：只换 H1/番剧名，正文不动；确认 License + 子集化。
6. **DesignBookmark 当工具黄页**：找图标 / 插画时查。

## 六、抓取备注
- Fontshare 是纯 JS 应用，正文抓不到，字体清单为已知信息整理，**以站内 License 为准**。
- Mobbin / 60fps / v0 / motionin / iter0 含较多前端渲染内容，抓取到的多为首页可见部分，完整库需站内浏览（部分需 Pro）。
- 12 站全部 HTTP 200 可访问（均已 https 化）。
