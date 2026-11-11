# awesome-design-md 学习笔记

来源：https://github.com/VoltAgent/awesome-design-md （VoltAgent 维护，Ranked #150 on GitHub）
性质：**84 份来自真实网站的设计系统文档 DESIGN.md 的精选合集**。不是工具、不是组件库，是「让 AI 生成一致 UI」的设计系统文档范本库。

## DESIGN.md 是什么
Google Stitch 提出的概念：一份纯 Markdown 设计系统文档，AI 编码/设计代理读它就能生成视觉一致的 UI。类比：
- AGENTS.md = 告诉编码代理「怎么搭这个项目」
- DESIGN.md = 告诉设计代理「这个项目该怎么长」
没有 Figma 导出、没有 JSON schema、没有工具链，就是个 markdown 文件。Markdown 是 LLM 读得最好的格式。

## 仓库结构
- design-md/<品牌>/DESIGN.md（约 24KB）+ README.md（213字节简述）
- 84 个品牌：AI/开发工具（Claude/Cursor/Vercel/Linear/Stripe/Figma/Notion…）、金融（Stripe/Coinbase/Mastercard…）、汽车（Ferrari/BMW/Tesla…）、零售（Airbnb/Nike/Starbucks…）、媒体（Wired/Verge…）
- 每个品牌一句话卡片：名称 + 行业 + 视觉特征摘要（如 Linear = ultra-minimal precise purple accent）

## 一份 DESIGN.md 的标准结构（以 Linear 为范例，548 行）

### 1. YAML front matter（机器可读 token）
```yaml
---
version: alpha
name: Linear-design-analysis
description: <一段话把整套设计语言的骨架说清：底色/文字色/唯一强调色/字体/卡片/节奏>
colors: { primary, on-primary, primary-hover, primary-focus, ink, ink-muted, ink-subtle, ink-tertiary, canvas, surface-1..4, hairline, hairline-strong, inverse-*, semantic-success, semantic-overlay }
typography: { display-xl 80px/600/1.05/-3.0px, display-lg, headline, card-title, body-lg, body, body-sm, caption, button, eyebrow, mono }
rounded: { xs 4, sm 6, md 8, lg 12, xl 16, xxl 24, pill 9999, full 9999 }
spacing: { xxs 4, xs 8, sm 12, md 16, lg 24, xl 32, xxl 48, section 96 }
components: { button-primary: {backgroundColor: '{colors.primary}', textColor:..., typography: '{typography.button}', rounded: '{rounded.md}', padding: 8px 14px}, ... }
---
```
关键：**每个值都追溯到一个 token，组件用 `{colors.x}` `{typography.y}` 引用**，不写裸值。

### 2. Colors（正文解释每一支色「是什么、用在哪」）
- Text 组：ink / ink-muted / ink-subtle / ink-tertiary 四级文字灰，每级写清用在哪
- Surface 阶梯：canvas → surface-1..4，用于层级
- Hairline 边框：普通/强/三级
- Semantic：success、overlay（唯一语义色）

### 3. Typography
- Font Family：字体 + **fallback 栈** + **免费替代建议**（Linear 专有字体 → 推荐 Inter/Geist 替代）
- Hierarchy 表：Token | Size | Weight | Line Height | Letter Spacing | Use，逐行写清
- Principles：可观察的排版原则（如 display 激进负字距 -3.0px≈4%；eyebrow 用正字距 +0.4px 做区分；mono 只用于代码）

### 4. Layout
- Spacing System：base unit 4px，各档用途（卡片内 padding 24/32/48，按钮 8×14，输入框 8×12）
- Grid & Container：max 1280px，3-up/2-up/1-up 响应
- Whitespace Philosophy：一句话说清留白哲学（Linear：深色画布本身就是留白，靠 surface 抬起分区而非白底间隙）

### 5. Elevation & Depth
- 层级表：Level | Treatment | Use（0 flat / 1 charcoal lift / 2-3 surface lift / 4 focus ring）
- 说明该品牌抗阴影、用 surface 阶梯+细边框做深度

### 6. Shapes
- Border Radius Scale 表：token | value | use
- Photography/Illustration Geometry：截图/图标/头像的几何规则

### 7. Components（最实用）
- 每个组件：backgroundColor/textColor/typography/rounded/padding + 状态变体（hover/pressed/focused 各是一个独立 entry）
- 按 Buttons / Pricing Tabs / Cards & Containers / Inputs 分组

### 8. Do / Don't（用词克制清单）
- Don't use lavender as section background or card fill
- Don't introduce a second chromatic accent
- Don't add atmospheric gradients or spotlight cards
- 单强调色纪律：品牌色只出现在 brand mark/主 CTA/focus/link 强调

### 9. Responsive Behavior
- Breakpoints 表：name | width | key changes
- Touch Targets：≥40px / 44px
- Collapsing Strategy / Image Behavior

### 10. Iteration Guide（给 AI 的操作准则）
- 一次只改一个组件、按 token 名引用
- 新增区块先决定它在哪个 surface lift 上
- 改完跑 `npx @google/design.md lint DESIGN.md`

### 11. Known Gaps（诚实声明已知空白）
- 哪些值是从 CSS 变量提取、哪些页面没看到（错误态/校验）、light mode 没文档因为官网没有
- 专有字体有开源替代

## 对本项目（Han1meWinPlus）的启发
1. **我们其实已经有 DESIGN.md 的雏形**：lib/src/core/app_design_tokens.dart（颜色/语义）+ app_radius.dart（圆角分档）+ app_motion.dart（动效）——只是散在代码里，没有一份人类+AI 都能读的文档。
2. 可以**反推写一份 docs/DESIGN.md**：把现有 token 整理成 YAML front matter + 正文解释，这样 AI 改 UI 时读它就能保持一致（也符合 AGENTS.md 里「先读 docs/design-tokens.md」的约定）。
3. 可直接借鉴的写法：
   - 每个组件用 token 引用而非裸值；
   - 四级文字灰 + surface 阶梯 + hairline 三层边框这套结构（我们已有 ink/inkSubtle/inkMuted + surface/pageBackground + stroke/divider，几乎同构）；
   - Do/Don't 单强调色纪律；
   - Known Gaps 诚实声明。
4. 注意：这些是**Web 品牌营销页**的规范，偏「大标题+海报+留白」，和我们 Flutter 桌面工具类 App 的密度/交互不同，**只借结构和 token 纪律，不照抄字号留白**。
