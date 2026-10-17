# SignPath Foundation 申请草稿

> **现状：申请已被拒（理由为外部可验证的声誉不足），本页仅作重申时的备用参考。**
> 重申条件与已核实的替代途径见 [`code-signing.md`](code-signing.md)。

> 申请入口：<https://signpath.org/apply>（站内导航「Apply」）——页面内嵌一个 HubSpot 表单，
> 直接往下滚就能看到，**没有独立的表单页 URL**。
>
> **照着填请用 [`signpath-apply-checklist.md`](signpath-apply-checklist.md)**：那份是按表单
> **实际字段**逐项写的（字段名、必填与否、下拉框合法取值都核对过）。本文件是同一批内容的
> 成文版，供需要完整段落时取用。
>
> 条款：<https://signpath.org/terms> —— 提交前对照 [`code-signing.md`](code-signing.md)
> 第 0 节那张表逐条核对。
>
> **提交前请先读「已知的弱点」一节** —— 那里列了本项目暂时拿不出的证据，
> 心里有数就行，不必因此不提交。

---

## 表单字段与本文的对应关系

2026-10 核对 <https://signpath.org/apply> 的实际表单，共 20 项：

| 表单字段 | 必填 | 本文对应处 |
| --- | --- | --- |
| Project Name | ✅ | §1 |
| Repository URL | ✅ | §2 |
| Homepage URL | ✅ | §3 |
| Download URL | — | §4（**页面须提及 SignPath Foundation**） |
| Privacy Policy URL | — | §5 |
| Wikipedia URL | — | §5（留空） |
| Tagline | ✅ | §6（**可能公开展示**） |
| Category | ✅ | §7（下拉，选 `Other`） |
| Description | ✅ | §8 |
| Reputation | ✅ | §9 |
| Maintainer Type | — | §10（下拉） |
| Build System | ✅ | §11（下拉，选 `GitHub Actions`） |
| First Name / Last Name | ✅ | §12 |
| Email | ✅ | §12 |
| Company Name | — | 留空 |
| Primary Discovery Channel | ✅ | §13（下拉） |
| Please specify the exact source | — | §13 |
| 同意 Code of Conduct / 存储个人数据 | ✅ | 页面底部两个复选框 |

> **表单里没有的**：License 字段、专门的「Build system / reproducibility」文本框、
> 「Signing request / artifacts」字段、「条款前置条件」字段。这些内容在表单里没有对应
> 输入框，§14 只作为**备查材料**保留（万一对方在邮件往来里追问）。
>
> **本文不能照抄的地方**：License、构建可复现性、产物清单、条款自检这四段，
> 表单都不问。真正要粘的是 §1–§13。

---

## 1. Project Name

```
Han1meWinPlus
```

表单提示：*A Google search for this name should clearly identify your project.*
直接搜 `Han1meWinPlus` 能找到本仓库，符合要求。

## 2. Repository URL

```
https://github.com/shilonyin/Han1meWinPlus
```

## 3. Homepage URL

```
https://github.com/shilonyin/Han1meWinPlus
```

表单接受「项目专属网站 **或** 仓库页面」。本项目没有独立站点。

## 4. Download URL

```
https://github.com/shilonyin/Han1meWinPlus/releases/latest
```

> **这一项有硬性要求**，表单原话：*"This page must mention that the project uses the
> SignPath Foundation for code signing."*
> `README.md` 的「下载」一节与 `README.en.md` 的 "Download" 一节已含这句话；
> Releases 页面指向默认分支的 README，因此该 URL 满足要求。
> **别把下载区里那段 SignPath 说明删掉**，删了这个字段就不合格。

## 5. Privacy Policy URL / Wikipedia URL

```
https://github.com/shilonyin/Han1meWinPlus#隐私政策
```

- 表单说明：*required if the software collects user data*。本项目保存登录凭据与观看历史，
  建议填。目标小节是 `README.md` 的「隐私政策」，锚点 `#隐私政策`（GitHub 保留中文原文，
  **不要**写成 `%E9%9A%90%E7%A7%81%E6%94%BF%E7%AD%96`，那样会 404）。
- Wikipedia URL：**留空**，本项目没有维基百科条目。

## 6. Tagline

> 提示：*A short one-sentence summary of your project. This may be displayed on the
> SignPath Foundation website.* 可能公开展示，写中性准确的一版。

```
A Windows desktop client for a video streaming site, built with Flutter.
```

## 7. Category

下拉框合法取值只有 10 个：`Accessibility` / `AI Tools` / `Audio` / `Developer Tools` /
`Educational` / `Gaming` / `Graphics` / `Productivity` / `Science` / `Other`。

选：

```
Other
```

没有「视频 / 媒体播放器」这一类，`Audio` 只涵盖音频，`Graphics` 不贴。

## 8. Description

> 提示：*Avoid listing version-specific features or dependencies.*

```
Han1meWinPlus is a Windows desktop client for an online video streaming site. It
provides a native playback experience as an alternative to the site's web player,
with hardware-accelerated decoding, a local library for favourites and watch
history, and offline downloads.

The application is written in Flutter with a custom C++ Windows runner. Release
builds are compiled automatically on GitHub-hosted runners and published as a
signed installer plus a portable archive.
```

## 9. Reputation

> **唯一一个拿不出强证据的字段。不要编。**

```
The project is young and its public footprint is still small, and we would rather
state that plainly than overstate it.

Quantitative evidence available today:
- Repository: https://github.com/shilonyin/Han1meWinPlus (public, AGPL-3.0)
- 19 GitHub Releases published in the first month (repository created 2026-09-13)
- Cumulative downloads across all releases: see the Downloads badge in the README
- Active development: frequent releases, public issue tracker, per-release changelog

External coverage: none that we can point to at this time (no articles, blog posts
or community threads). We are not claiming any.

Comparable projects already holding Foundation certificates, such as third-party
media clients listed at https://signpath.org/projects, show what kind of software
this is, but we understand that is not a reputation signal of our own.
```

> 交表前把「see the Downloads badge」换成一次真实核对过的数字。

## 10. Maintainer Type

下拉取值：`Independent community project (no formal organization)` /
`Non-profit foundation or research/educational institution` /
`For-profit company or corporate-backed project` / `Individual maintainer(s)` /
`Other (please specify)`。

选：

```
Individual maintainer(s)
```

（若想强调社区定位，`Independent community project (no formal organization)` 也成立。）

## 11. Build System

下拉只有两个值：`GitHub Actions` / `GitLab CI/CD`。选：

```
GitHub Actions
```

本项目的构建全部在 `.github/workflows/build-windows.yml` 中于 GitHub 托管 runner 上执行。

## 12. First Name / Last Name / Email / Company Name

- First / Last Name：表单提示「将成为 SignPath 里的用户账号名」，填您的名字（建议英文或拼音）
- Email：账号与审核通知的收件地址
- Company Name：**留空**（个人项目）

## 13. Primary Discovery Channel / Please specify the exact source

下拉取值：`Organic search` / `AI, LLM tools` / `Developer platforms (e.g. GitHub)` /
`Community platforms` / `Social media` / `Events` / `Referral` / `Direct contact`。

选：

```
Developer platforms (e.g. GitHub)
```

> 这一项只影响 SignPath 自己的统计，**不影响审核结果**，如实填即可。
> 「Please specify the exact source」可选，填一句来源说明。

---

## 14. 备查材料（表单不问，邮件追问时用）

### 许可与合规

```
- License: AGPL-3.0 (OSI-approved, no commercial dual-licensing); LICENSE in repo root
- No proprietary components; all sources public
- Product metadata is uniform across signed binaries:
  ProductName=Han1meWinPlus, ProductVersion identical for the installer and the main exe
```

### 构建与产物（表单没有对应字段）

```
Platform: Windows (x64)
CI: GitHub Actions, GitHub-hosted runners, fully automated
Workflow: .github/workflows/build-windows.yml

Every release is built on GitHub-hosted runners from a tagged commit: Flutter
(version pinned via .fvmrc) compiles the app, Inno Setup packages the installer, and
the artifacts are published to GitHub Releases together with SHA256 checksums.

Artifacts to be signed (both produced by that workflow):
1. Han1meWinPlus-Setup.exe   — the installer users download and run
2. han1me_win_plus.exe       — the main executable inside the portable archive

Both are uploaded as a single workflow artifact and submitted to one signing request.
The code signing step is already integrated in the workflow and gated on SignPath
configuration — it activates automatically once credentials exist.
```

### 条款自检（表单没有对应字段）

```
All prerequisites from https://signpath.org/terms are already in place:

- OSI-approved license (AGPL-3.0), no commercial dual-licensing
- No proprietary components; all sources public
- Actively maintained (19 releases in the first month) and already released
- Functionality described in README, the project's download/home page
- "Code signing policy" section on the project home page with the required wording,
  team roles (Authors / Reviewers / Approvers) and a privacy policy
  (the section was removed from the README after this application was declined;
  restore it from git history — commit 4824bf4 in README.md — before reapplying)
- Only our own binaries are submitted; no upstream pre-built files are signed
- Provides uninstallation (the installer ships an uninstaller)
- Writes only to the user's own %APPDATA% / %LOCALAPPDATA%, no silent system changes
```

---

## 已知的弱点（提交前请过一眼）

审核实际看的是**外部可证实的声誉**。本项目当前：

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

> 上表是「我们的现状」，不是「所以会被拒」的论据。SignPath 实际的量化门槛
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
   - Artifact Configuration slug：`windows-release`（AniBaka 的取值）
   - Signing Policy slug：`release-signing`；另可配 `test-signing` 用自签测试证书先跑通
3. 把四个值填进仓库的 Secrets & Variables —— **填完立刻生效**，下次打 tag 就会签名
4. 被拒 → 不影响任何现有流程（CI 里那三步一直会跳过），把「已知的弱点」里的空缺补上
   后可再申请
