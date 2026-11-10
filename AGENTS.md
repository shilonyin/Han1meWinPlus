## 语言

- 始终使用简体中文输出，包括思考过程（thinking / reasoning）、解释、总结和计划。
- 代码、命令、标识符、文件路径、日志和报错原文保持原样，不翻译。

> 这条规则同时写在 [`.github/copilot-instructions.md`](.github/copilot-instructions.md)。
> 之所以在根 `AGENTS.md` 里**再写一遍**：部分 agent 只读根目录的 `AGENTS.md`、
> 不读 `.github/copilot-instructions.md`，只靠后者会导致输出仍是英文。

## 提交信息

只写**改了什么**，概括即可，不要把排查过程、推理链条、验证步骤、对照实验数据写进去。

```
类型(范围): 一句话说明

补充说明改动的要点，几行即可。
```

- 类型用 `修复` / `功能` / `文档` / `重构` / `构建` / `测试` 等
- 过程性的内容（怎么发现的、试过哪些方案、为什么之前的结论是错的）留在
  issue、PR 描述或代码注释里，不放进提交信息
- 篇幅控制在几行；确实需要交代背景时，指向对应文件或 issue，不复述

## 提交前本地代码审查（强制）

每次提交（commit）之前，**默认先跑一遍本地审查，确认没问题再提交/推送**。
这条规则同样写在 `.github/copilot-instructions.md`。

- 用 delegate 模式，不配 LLM API Key、不产生额外模型调用：
  `& .\tools\ocr\review.ps1 -Out .design_tmp\review_pending.md`
  （审查单个已提交版本用 `-Commit <sha>`，分支区间用 `-From main -To master`）。
- 脚本只做确定性的一半：按 `.opencodereview/rule.json` 筛文件/匹配规则/取 diff，
  生成 Markdown 材料。**实际的审查推理由 agent 自己完成** —— 读材料，按规则逐项核对
  （枚举序列化兼容、dispose 资源泄漏、三语 arb 与 getter 同步、Symbols 图标风格、
  Windows 平台判断等），有问题先改好再提交。
- 结论需要人工判断，OCR 历史上出过误报（曾把 PowerShell 变量累加判成作用域问题）。
- 审查材料写在 `.design_tmp/` 下，已被 .gitignore 忽略，不要提交。
- CI 自动审查已在 `ce4df3b` 移除（fork PR 会消耗仓库 owner 的额度），不要再恢复。

## Agent skills

### UI 令牌与注释

动 UI 之前先读 [docs/design-tokens.md](docs/design-tokens.md)：圆角、动效、颜色各走哪个令牌，
哪些值必须推导而不是写死。写注释前读 [docs/comment-style.md](docs/comment-style.md)。
三条守卫测试（`test/radius_token_guard_test.dart`、`test/motion_token_guard_test.dart`、
`test/comment_style_guard_test.dart`）会挡住回退，改不动它们时先读文件头的说明，
不要直接调大额度。

### Issue tracker

Issues and specs live as GitHub issues on `shilonyin/Han1meWinPlus`, read and written through the `deck_*` tools. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one root `CONTEXT.md` plus `docs/adr/`. See `docs/agents/domain.md`.
