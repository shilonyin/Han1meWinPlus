# Copilot 指令

## 语言

- 始终使用简体中文输出，包括思考过程（thinking / reasoning）、解释、总结和计划。
- 代码、命令、标识符、文件路径、日志和报错原文保持原样，不翻译。

## 提交信息

只写**改了什么**，概括即可，不要把排查过程、推理链条、验证步骤、对照实验数据写进去。

```
类型(范围): 一句话说明

补充说明改动的要点，几行即可。
```

- 类型用 `修复` / `功能` / `文档` / `重构` / `构建` / `测试` 等
- 过程性的内容留在 issue、PR 描述或代码注释里，不放进提交信息
- 篇幅控制在几行；确实需要交代背景时，指向对应文件或 issue，不复述

## 提交前本地代码审查（强制）

每次提交（commit）之前，**默认先跑一遍本地审查，确认没问题再提交/推送**。
这条规则同时写在根 `AGENTS.md`。

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

## UI 令牌

- 圆角取 `AppRadius`、动效取 `AppMotion`、颜色按「基准面 vs 跟随主题」分（见 [docs/design-tokens.md](docs/design-tokens.md)）。
- 不要新写 `BorderRadius.circular(<数字>)` 或 `Duration(milliseconds: …)`，守卫测试会拦。
- 注释解释 why，不写过程流水账；规范见 [docs/comment-style.md](docs/comment-style.md)。
