# SignPath Foundation 申请草稿

> 申请入口：<https://signpath.org/apply>（站内导航「Apply」）。
> 条款：<https://signpath.org/terms> —— **提交前对照 `code-signing.md` 第 0 节那张表逐条核对**，
> 里面列的是条款要求、申请前就必须成立的条件。
>
> **提交前请先读「已知的弱点」一节** —— 那里列了本项目暂时拿不出的证据，
> 心里有数就行，不必因此不提交。

---

## 1. Project name

```
Han1meWinPlus
```

## 2. GitHub repository

```
https://github.com/shilonyin/Han1meWinPlus
```

## 3. License

```
AGPL-3.0
```

（OSI 认可的开源许可，符合要求。仓库根目录有 `LICENSE` 全文。）

## 4. Project description

```
Han1meWinPlus is a Windows desktop client for a video streaming website,
offering a native playback experience as an alternative to the web player.

Built with Flutter and a custom C++ Windows runner. Distributed as a signed
installer and a portable archive via GitHub Releases. Maintained for Windows
only; other platform directories are inherited from the upstream project and
kept for reference.
```

## 5. Build system / reproducibility

```
Platform: Windows (x64)
CI: GitHub Actions, hosted runners, fully automated
Workflow: .github/workflows/build-windows.yml

Every release is built on GitHub-hosted runners from a tagged commit:
Flutter (version pinned via .fvmrc) compiles the app, Inno Setup packages
the installer, and the artifacts are published to GitHub Releases together
with SHA256 checksums.

The code signing step is already integrated in the workflow and gated on
SignPath configuration — it activates automatically once credentials exist.
```

## 6. Signing request / artifacts

```
Platform: Windows Authenticode (PE)
Artifacts to sign (both produced by the CI workflow):

1. Han1meWinPlus-Setup.exe   — the installer users download and run
2. han1me_win_plus.exe       — the main executable inside the portable archive

Both are submitted as a single artifact to one signing request.
See docs/code-signing.md in the repository for the artifact configuration.
```

## 7. Conditions from the terms (self-checked)

```
All prerequisites from https://signpath.org/terms are already in place:

- OSI-approved license (AGPL-3.0), no commercial dual-licensing
- No proprietary components; all sources public
- Actively maintained (19 releases in the past month) and already released
- Functionality described in README
- "Code signing policy" section on the project home page, including the
  required wording, team roles (Authors / Reviewers / Approvers) and a
  privacy policy: https://github.com/shilonyin/Han1meWinPlus#代码签名政策
- Only our own binaries are submitted; no upstream pre-built files are signed
- Product metadata is uniform across signed binaries:
  ProductName=Han1meWinPlus, ProductVersion identical for installer and main exe
```

## 8. Admission of what we lack (optional, but honest)

```
We are a small, early-stage project: the repository was created in September 2026,
so it is about one month old. In that time it has published 19 releases with around
212 cumulative downloads, a handful of stars, and no forks. We do not claim a level
of public visibility we do not have yet.

We are applying because unsigned binaries are a real obstacle for our users,
and because we intend to keep shipping releases and growing the project's
public footprint. If the Foundation's bar is not met at this time, we would
rather be told so than ship unsigned binaries indefinitely, and we will keep
building and reapply later.

For reference, comparable Windows desktop clients — including
AniBakaBaka/AniBaka, an anime player that holds a Foundation certificate — are
listed at https://signpath.org/projects.
```

---

## 已知的弱点（提交前请过一眼）

Form 之外，审核实际看的是**外部可证实的声誉**。本项目当前：

| 维度 | 现状 | 是否有现成证据 |
| --- | --- | --- |
| 仓库创建时间 | 2026-09-13（**迄今约 1 个月**） | ✅ 可从仓库页看到 |
| GitHub stars | 4 | — |
| Forks | 0 | — |
| Contributors | 除维护者外无 | — |
| Release 下载量 | 212（19 个版本，单版最高 73） | ✅ 可从 Releases 页看到 |
| 持续活跃 | 一个月内 19 个版本，提交频繁 | ✅ git 历史可证 |
| 外部讨论（Reddit / 贴吧 / B站 / YouTube） | **未检索到** | ❌ 空缺 |
| 文章 / 博客 / 机构推荐 | **未检索到** | ❌ 空缺 |
| 用户反馈截图 / 讨论串 | **未收集** | ❌ 空缺 |

**最后三行是当前最明显的缺口**，而它们恰恰是花时间就能攒的：把项目发到相关社群、
收集几条真实用户反馈、让外部站点提到它。这几项出现一项，材料就厚一档。

> 需要注意，上表是「我们的现状」，不是「所以会被拒」的论据。SignPath 实际的量化门槛
> 公开资料里没有，我们只能看到它看重哪些维度，**无法据此估计通过率**。
> 参见 [code-signing.md](code-signing.md) 第一节对这一点的完整讨论。

**关于项目性质**：本项目是面向成人内容站点的第三方客户端。此前这里写的是「这类项目
是否会被判定为不适合签发证书无法从公开资料确认」—— 那段猜测已被证伪，不再保留。
现有的事实是：**同类内容领域的项目已经拿到过 Foundation 证书** ——

- `AniBakaBaka/AniBaka`（GPL-3.0，Dart/Flutter，动漫播放器）持有证书，其公开仓库配置里
  可读到证书主题 `CN=SignPath Foundation, O=SignPath Foundation, C=US, S=DE, L=Lewes`，
  Organization ID `ad88b2e9-2cf4-4984-b56b-4f4d2e575e15`，Project slug `AniBaka`，
  Artifact Configuration slug `windows-release`，Signing Policy `release-signing`，
  使用 `signpath/github-action-submit-signing-request@v2`。
- [signpath.org/projects](https://signpath.org/projects) 已收录清单里有大量同类第三方
  客户端（游戏启动器、Mod 管理器，以及众多 B站 / Steam / 网易云相关客户端）。

**这能证明的**：这类软件没有被一刀切排除。**这不能证明的**：某一内容领域的具体项目
是否会因内容性质被拒，仍无公开正反例可查 —— 这一点保持未知，但不构成已成立的障碍。

---

## 提交之后

1. 人工审核，通常 1–2 周，结果发邮件
2. 通过 → 拿到 SignPath Organization，按 [code-signing.md](code-signing.md) 第二节建
   Project / Trusted Build / Artifact Configuration / Signing Policy。
   命名可以直接对齐 AniBaka 的公开配置：
   - Project slug：与仓库同名即可（AniBaka 用的就是 `AniBaka`）
   - Artifact Configuration slug：`windows-release`（AniBaka 的取值，含义是「面向
     Windows 发布的产物集」）
   - Signing Policy slug：`release-signing`；另可配一个 `test-signing` 用自签测试证书
     跑通链路，再切到 Foundation 证书
3. 把四个值填进仓库的 Secrets & Variables —— **填完立刻生效**，下次打 tag 就会签名。
   Organization ID 这类非保密值照 AniBaka 的做法硬编码在 workflow 里也可以，
   只有 API token 必须放 Secret
4. 被拒 → 不影响任何现有流程（CI 里那三步一直会跳过），把「已知的弱点」里的空缺补上
   后可再申请
