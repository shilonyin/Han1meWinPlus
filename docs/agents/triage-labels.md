# Triage Labels

The skills speak in terms of five canonical triage roles. This file maps those roles to the actual label strings used in this repo's issue tracker.

| Label in skill package | Label in our tracker | Meaning                                  |
| -------------------------- | -------------------- | ---------------------------------------- |
| `needs-triage`             | `needs-triage`       | Maintainer needs to evaluate this issue  |
| `needs-info`               | `needs-info`         | Waiting on reporter for more information |
| `ready-for-agent`          | `ready-for-agent`    | Fully specified, ready for an AFK agent  |
| `ready-for-human`          | `ready-for-human`    | Requires human implementation            |
| `wontfix`                  | `wontfix`            | Will not be actioned                     |

When a skill mentions a role (e.g. "apply the AFK-ready triage label"), use the corresponding label string from this table.

Edit the right-hand column to match whatever vocabulary you actually use.

## 本仓库的实际情况

- 五个标签字符串与角色同名，**保留默认**，没有做重命名。
- 这五个标签已经建在 `shilonyin/Han1meWinPlus` 上。
  建标签时必须带 `--repo shilonyin/Han1meWinPlus`，避免落到其它仓库。
- 仓库里另有历史遗留的自定义标签（`accessibility` / `chore` / `P0` / `P1` / `P2` / `P3` 与 GitHub 默认标签），
  它们与本套技能无关。**技能只应用上表这五个 triage 标签，不额外强制任何其它标签。**
