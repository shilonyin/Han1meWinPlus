# affectUI 学习笔记（供迁移到 Flutter 参考）

来源：https://github.com/flohoeller/affectui （MIT，React 19 + shadcn registry）。定位 "UI for AI agents"。
免费仓库含 46 个组件 + 2 个 block + 17 个插画 + 4 个动效。Agent Tree / Trace Waterfall / Context Map / Agent Inbox / Agent Handoff 属 Pro，源码不在仓库。

## 一、Tool Call Card（components/tool-call-card.tsx）
一个工具调用压成一行，点开展开参数与结果。

### 头部一行（始终可见）
- 左：图标块（默认扳手，可传 icon）
- 中：工具名（等宽字体）+ 摘要（单行省略）
- 右：状态区
  - running：转圈 + 实时计时（100ms tick，<1 分钟显示一位小数如 12.3s）
  - success：对勾 + 耗时
  - error：错误图标 + 文本 "Failed"
- 最右：chevron 折叠箭头
- 整行是 button，aria-expanded 控制

### 展开区
- error：错误图标 + message + Retry（旋转箭头图标）
- Arguments 段：label + 复制按钮 + 高亮 JSON 代码块
- Result 段：同上；running 时显示 "Waiting for result…"
- 代码块超 maxCodeHeight(默认220px)：淡出遮罩 + Show all/Show less，展开后最长 640px 内部滚动
- 复制按钮点后 1.4s 显示对勾

### JSON 高亮
正则匹配：字符串(键时识别后跟冒号)、true/false/null、数字。其余保持标点色。
toText：字符串若 {/[ 开头尝试 JSON.parse 美化，否则原样；对象 JSON.stringify(...,2)。

### ToolCallGroup（多张折一行）
- header：左侧 3 个重叠图标堆叠 + 标题
- running 标题用 shimmer 斜光扫过
- 完成："Used 3 tools"/"Used 1 tool"，失败加 "· 2 failed"，耗时 "· 2.4s"
- 耗时=各卡时长之和；running 从最早开始的卡算并累加多段

### 动画要点（Flutter 用 AnimatedSize/AnimatedCrossFade/CustomPainter 实现）
- 展开/收起：高度裁剪动画（AnimatedSize）
- 对勾：SVG path 描边动画（CustomPainter + PathMetric）
- spinner：环 + 弧线旋转
- 状态切换 key={status} 触发重挂载动画

### formatMs
<1s 非live → "Nms"；<60s → 一位小数 "12.3s"；<1h → "2m 05s"；<1d → "3h 12m"；否则 "2d 4h"

## 二、Agent Tree（Pro，仅 README 描述）
"谁启动了谁"——编排器 + 子 Agent 作为活树：
- 每张卡带 状态/成本/耗时
- 成本沿分支向上汇总（父=子之和）
- 分支可折叠成一行
- 实时状态用色与图标区分
Flutter 思路：递归 Widget 树 + 左侧竖向连接线（CustomPainter/Container）+ 每层缩进；折叠用 AnimatedSize；成本汇总在 model 层 reduce。

## 三、其他可借鉴
- Thinking Loader：8 道射线 spinner + 标签斜光扫过；phase 轮播（旧标签上滚模糊出、新滚入、pill 宽度平滑过渡）；done 时 spinner 变对勾、标签定格 "Thought for 6s"
- Number Ticker：数字像里程表逐位滚动，涨向上跌向下，首次从 0 计数；Intl 格式化符号不动只动数字
- 动效四件：grid-background / number-ticker / shimmer-loader / text-reveal
- 通用原则：单文件、样式内联、dark mode 靠祖先 class、container query 响应式、尊重 prefers-reduced-motion、可访问（真按钮/aria-live/keyboard）

## 四、迁移到本项目（Han1meWinPlus，Flutter）要点
- 技术栈不同：affectUI 是 React/TSX，只能照规格重写，不能直接引入。
- 复用项目既有设计语言（oil-ui 原则：存量沿用现有变量）：
  - app_design_tokens.dart：accent #C8527C / accentDeep #B3265A / ink #1B1B1F / inkSubtle #5F5F6B / inkMuted #8A8A96 / surface / pageBackground #F4F4F7 / stroke #E2E2E8 / divider #ECECF1 / fieldFill #EDEDF2
  - app_radius.dart：xs6 sm10 md12 lg16（特大档）
  - 图标统一 Symbols.xxx_rounded（material_symbols_icons），选中态显式 fill:1
  - 可复用：press_scale.dart（按压缩放）、staggered_entrance.dart（错峰入场）、motion_icon.dart、glass/
- 状态色需补 token：running=accent、success=绿、error=红
- 落地场景待定：项目本身是追番播放器无 Agent；若要展示"下载队列/任务进度"可套 Tool Call Card 的行形态（如下载进度=一行+展开详情）。
