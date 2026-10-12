## 语言

- 始终使用简体中文输出，包括思考过程（thinking / reasoning）、解释、总结和计划。
- 代码、命令、标识符、文件路径、日志和报错原文保持原样，不翻译。

> 这条规则同时写在 [`.github/copilot-instructions.md`](.github/copilot-instructions.md)。
> 之所以在根 `AGENTS.md` 里**再写一遍**：部分 agent 只读根目录的 `AGENTS.md`、
> 不读 `.github/copilot-instructions.md`，只靠后者会导致输出仍是英文。

## Agent skills

### Issue tracker

Issues and specs live as GitHub issues on `shilonyin/Han1meWinPlus`, read and written through the `deck_*` tools. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its role name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — one root `CONTEXT.md` plus `docs/adr/`. See `docs/agents/domain.md`.
