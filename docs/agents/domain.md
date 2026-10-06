# Domain Docs

How the engineering skills should consume this repo's domain documentation when exploring the codebase.

## 本仓库的布局：single-context

本仓库是 **single-context（单上下文）**：一个仓库共用一份根目录的 `CONTEXT.md`，架构决定放在 `docs/adr/`。

判断依据（初始化时实地核对过，不是假设）：

- 没有 `pnpm-workspace.yaml`，`package.json` 里没有 `workspaces` 字段；
- 没有多个各自带 `src/` 的独立子包；
- 这是个 Flutter 应用（`pubspec.yaml` + `lib/`），各目录是一个程序的模块划分，不是各自独立开发的子项目。

因此本仓库**不使用**多上下文布局：不创建根目录 `CONTEXT-MAP.md`，也不创建各子项目的 `CONTEXT.md`。

> 本次初始化**只记录这个结论，不创建 `CONTEXT.md`**。按技能约定，域文档是惰性创建的 —— 等到第一次真正
> 写下词条或做出决定时，由 `/domain-modeling`（经 `/grill-with-docs`、`/improve-codebase-architecture` 触达）
> 再创建，架构决定同理写进 `docs/adr/`。

## Before exploring, read these

- **`CONTEXT.md`** at the repo root, or
- **`CONTEXT-MAP.md`** at the repo root if it exists — it points at one `CONTEXT.md` per context. Read each one relevant to the topic.
- **`docs/adr/`** — read ADRs that touch the area you're about to work in. In multi-context repos, also check `src/<context>/docs/adr/` for context-scoped decisions.

If any of these files don't exist, **proceed silently**. Don't flag their absence; don't suggest creating them upfront. The `/domain-modeling` skill (reached via `/grill-with-docs` and `/improve-codebase-architecture`) creates them lazily when terms or decisions actually get resolved.

## File structure

Single-context repo (this repo):

```
/
├── CONTEXT.md                 ← 尚未创建，等 /domain-modeling 惰性写入
├── docs/adr/                  ← 尚未创建，等第一条架构决定写入
│   ├── 0001-<decision>.md
│   └── 0002-<decision>.md
└── lib/                       ← Flutter 应用源码
```

Multi-context repo (presence of `CONTEXT-MAP.md` at the root) — **本仓库不适用**：

```
/
├── CONTEXT-MAP.md
├── docs/adr/                          ← system-wide decisions
└── src/
    ├── ordering/
    │   ├── CONTEXT.md
    │   └── docs/adr/                  ← context-specific decisions
    └── billing/
        ├── CONTEXT.md
        └── docs/adr/
```

## Use the glossary's vocabulary

When your output names a domain concept (in an issue title, a refactor proposal, a hypothesis, a test name), use the term as defined in `CONTEXT.md`. Don't drift to synonyms the glossary explicitly avoids.

If the concept you need isn't in the glossary yet, that's a signal — either you're inventing language the project doesn't use (reconsider) or there's a real gap (note it for `/domain-modeling`).

## Flag ADR conflicts

If your output contradicts an existing ADR, surface it explicitly rather than silently overriding:

> _Contradicts ADR-0007 (event-sourced orders) — but worth reopening because…_
