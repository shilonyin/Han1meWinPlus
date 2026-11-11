# baoyu-design（宝玉设计技能集）学习笔记

来源：https://github.com/JimLiu/baoyu-design （MIT 自有代码 + Anthropic dataviz 版权）
性质：**把 claude.ai 的 Artifact 编辑器搬到本地 Agent 的技能集 + DeepSeek Harness 插件**。不是通用设计方法论，是一整套「Agent 写文件 → 本地编辑器实时显示 → 人机轮流改」的工具。

## 一、它是什么（6 个 Artifact 技能）
| 技能 | 产出 | 编辑/导出 |
|---|---|---|
| claude-slides | 幻灯片：project/deck.json + 每页 HTML | 幻灯片编辑器，导出 PDF/HTML/PPT |
| claude-design | 设计画布：canvas.json + .dc.html 设计组件 | 画布编辑器（画板并排、互动原型、改文案）|
| claude-design-system | 设计系统：tokens.json + 品牌手册 README + 组件预览 + 字体 + 素材 | 设计系统编辑器 |
| claude-dashboard | 数据看板：datasets(CSV/TSV/JSON) + 图表/数字/表格页 | 看板页，Sources 面板溯源 |
| claude-motion | 动画短片（10-30s，最多 15min，按场景写代码） | Motion 播放器，导出 MP4/GIF |
| claude-whiteboard | 白板：示意/流程/想法地图 | 白板编辑器 |
另有 motion-director（做有观点的成片）和 dataviz（画任何图表前读的指南）。

## 二、对我们项目（Han1meWinPlus, Flutter）真正有帮助的三块

### 1. claude-design-system 的 from-code.md（从代码仓库提取设计系统）
正是我们要做的事（从 app_design_tokens.dart 提炼 DESIGN.md）。它的规范值得照抄：
- 目标：把 CSS 自定义属性/token 文件 → tokens.json；字体文件/logo/图标 → fonts/assets；组件库 → bundle.js
- token 映射规则：每个 theme selector 一个 color.themes 条目（:root/light 在前，dark 变体在后）；`--name` 去 `--`、`/`出`.`→`-`；值原样（hex 小写、rgb/hsl/oklch 保留）；颜色引用其他变量→别名 `"{other}"`；calc/color-mix→跳过并注明
- 按用途归类：颜色→color；长度按名字（space/gap/pad→spacing、radius/rounded→radius、shadow→shadow）；字号/行高/字重/字体→type.groups + type.families
- 精确取值：源码真实名字和值、按它原有顺序；5px 就是 5px 不吸附网格；代码是真相、截图是有损参考
- 素材只复制不重构：没有 logo 就用纯文字写名字并注明缺失，绝不凭记忆画真实公司的标志
- 库存由源码定义：组件只做源码里有的族，不补 Toast/Avatar 之类「常规」件

### 2. claude-design-system 的 craft.md（写好设计系统的规则）
- README 是给消费方 Agent 的使用规则（祈使句，点名 token/style/asset），不是文档
- Assets 只复制不近似；Exact values from real sources（源码压过任何相似的库）
- 大系统按路径读；一对一 value 单一来源（清��时从 stylesheet 移除已进 tokens.json 的值）

### 3. dataviz（画任何图表前必读）【Anthropic 出品，版权非 MIT】
**这条对我们最实用**——项目里迟早有图表（播放量统计/收藏分布等）：
- 顺序：先选对形态（量级/身份/极性/单一头条/随时间变化；有时答案不是图表而是数字卡）→ 按职责分配颜色 → **跑脚本验证配色**（validate_palette.js，色盲安全 CVD ΔE≥8、明度带、对比度）→ mark 规格 → 悬停层 → 无障碍 → 渲染后再看一眼
- 不可破的军规：**分类色固定顺序不可循环**；**永不双 Y 轴**（最常见错误）；颜色跟实体不跟排名；顺序色单色相由浅到深、发散色两色相+中性中点，绝不彩虹；文字用 text token 不用系列色；状态色保留（good/warning/serious/critical）配图标+文字不只靠颜色
- 提供 palette validator 脚本和 references（choosing-a-form/color-formula/marks-and-anatomy/interaction/anti-patterns/palette）

## 三、能不能直接用？
- **插件不能用在 Flutter 项目**：它是给 DeepSeek Harness 桌面版装的本地编辑器插件（React 产物 artifacts），和 Flutter 技术栈无关，只能作为「设计协作界面形态」的参考。
- **方法/规则可以用**：from-code.md 的 token 提取规范、craft.md 的设计系统作者规则、dataviz 的图表配色法 —— 都是语言无关的方法论，可直接套到我们的 docs/DESIGN.md 和未来的图表上。
- 如果要装插件体验（幻灯片/看板/白板等），需在 DSH 插件页按 npm 名安装 + 重启，仅用于**非本项目**的独立设计产出。

## 四、和之前学到的三者关系
- oil-ui：设计方法论（怎么定方向、翻译模糊词、评审）
- affectUI：AI Agent 组件的具体形态（Agent Tree/Tool Call Card）
- bento-ui-motion：动效语言 + 120fps 视频流水线
- **awesome-design-md：DESIGN.md 文档范本（84 个真实品牌）**
- **baoyu-design：本地 Artifact 编辑器技能集；对我们最有价值的是 from-code 的 token 提取规范 + dataviz 图表法**
