# SignPath 申请：照着填

打开 <https://signpath.org/apply> ，按下面顺序粘贴。全部内容也都在
[`signpath-application.md`](signpath-application.md) 里，这里是复制的便利版。

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

## 7. 条款前置条件（若表单问「是否符合条款」）

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

## 8. 项目自述（可选，但建议保留）

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

## 提交前最后一件事

**确认您的 GitHub 账号已开启两步验证（2FA）。** 条款明确要求所有项目成员对
SignPath 与代码仓库访问都启用 MFA。这是唯一一项我无法替您核实的。

## 提交之后

审核 1–2 周，结果发邮件。**通过 → 不要自己乱配**，回来告诉我，我按
[`signpath-setup.md`](signpath-setup.md) 带您建 Project / Trusted Build /
Artifact Configuration / Signing Policy，填好 4 个变量 + 1 个 token，然后打一个
tag 验证整条链路。被拒 → 不影响任何现有流程，CI 那三步一直会跳过。
