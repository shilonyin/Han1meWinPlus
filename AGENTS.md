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

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues on `shilonyin/Han1meWinPlus`, read and written through the `deck_*` tools. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one root `CONTEXT.md` plus `docs/adr/`. See `docs/agents/domain.md`.
