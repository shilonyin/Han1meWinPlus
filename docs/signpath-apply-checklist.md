# SignPath 申请：照着填

> **现状：申请已被拒（理由为外部可验证的声誉不足），本页仅作重申时的备用参考。**
> 重申条件与已核实的替代途径见 [`code-signing.md`](code-signing.md)。

表单在 <https://signpath.org/apply>（页面内嵌的 HubSpot 表单，直接往下滚就能看到）。
下面按**表单实际出现的顺序**逐项给出该填的内容，标注了必填项和下拉框的合法取值。

> 这份清单是按**实际表单字段**逐项核对后写的。表单字段与内容如与本文不符，以表单为准。

---

## 一、项目信息

### Project Name `*`（单行文本）

```
Han1meWinPlus
```

> 表单提示：*A Google search for this name should clearly identify your project.*
> 现状：直接搜 `Han1meWinPlus` 能找到本仓库。**不要再加 `Han1meWinPlus (Hanime1 client)` 之类的后缀**，名字要与仓库名完全一致。

### Repository URL `*`（单行文本）

```
https://github.com/shilonyin/Han1meWinPlus
```

### Homepage URL `*`（单行文本）

```
https://github.com/shilonyin/Han1meWinPlus
```

> 表单允许「项目专属网站 **或** 仓库页面」。本项目没有独立站点，填仓库地址即可。

### Download URL（单行文本，**非必填但强烈建议填**）

```
https://github.com/shilonyin/Han1meWinPlus/releases/latest
```

> **这一项有额外的硬性要求**，表单原话：
> *"A page where users can download your software. This page must mention that the project uses the SignPath Foundation for code signing."*
> 即：**下载页必须提到使用了 SignPath Foundation 签名**。申请时 `README.md` 的「下载」一节与
> `README.en.md` 的 "Download" 一节已补上这句话，而 Releases 页面指向的默认分支 README 就是它，
> 所以填这个 URL 当时满足要求。**后来申请被拒、用户决定不再签名，这句话已从两份 README 的
> 下载区删掉（commit `8407bcc`），现在这个字段不合格 —— 重申前必须先把这句话加回去。**

### Privacy Policy URL（单行文本）

```
https://github.com/shilonyin/Han1meWinPlus#隐私政策
```

> 表单说明：*required if the software collects user data*。本项目会保存登录凭据与观看历史，
> 属于会处理用户数据，**建议填**。目标小节是 `README.md` 的「隐私政策」（原来在
> 「代码签名政策」节内，是 `README.md:238`；该节移除后提升为顶层节，现为 `README.md:216`），
> GitHub 生成的锚点是 `#隐私政策`（中文锚点会保留原文，不被转写），锚点未变、链接仍有效。
> 若表单不接受非 ASCII 锚点，退路是填仓库地址并在 `Reputation` 里说明隐私政策位置。

### Wikipedia URL (optional)（单行文本）

留空。本项目没有维基百科条目。

---

## 二、项目介绍

### Tagline `*`（多行文本框，但要求一句话）

> 表单提示：*A short one-sentence summary of your project. **This may be displayed on the
> SignPath Foundation website.*** —— 这句话可能被公开展示，写中性、准确的一版。

```
A Windows desktop client for a video streaming site, built with Flutter.
```

英文备选（若希望更明确平台）：

```
A native Windows desktop client for an online video site, offering hardware-decoded playback and offline downloads.
```

### Category `*`（下拉框）

可选值只有 10 个：

```
Accessibility / AI Tools / Audio / Developer Tools / Educational /
Gaming / Graphics / Productivity / Science / Other
```

选：

```
Other
```

> 理由：没有「视频 / 媒体播放器」这一类。`Audio` 只涵盖音频，`Graphics` 不贴，
> `Developer Tools` 明显不对。**选 `Other`**。

### Description `*`（多行文本框）

> 表单提示：*A short paragraph describing your project and its purpose. **Avoid listing
> version-specific features or dependencies.*** —— 不要写版本号、不要罗列依赖。

```
Han1meWinPlus is a Windows desktop client for an online video streaming site. It
provides a native playback experience as an alternative to the site's web player,
with hardware-accelerated decoding, a local library for favourites and watch
history, and offline downloads.

The application is written in Flutter with a custom C++ Windows runner. Release
builds are compiled automatically on GitHub-hosted runners and published as a
signed installer plus a portable archive.
```

---

## 三、声誉证据

### Reputation `*`（多行文本框）

> 表单提示：*Provide links or information showing that your project is widely used or
> trusted. Examples include media coverage, blog posts, download statistics, GitHub
> insights, or community discussions.*
>
> **这是唯一一个我们拿不出强证据的字段。** 不要编，如实写 + 把能给的量化数据都给上。

```
The project is young and its public footprint is still small, and we would rather
state that plainly than overstate it.

Quantitative evidence available today:
- Repository: https://github.com/shilonyin/Han1meWinPlus (public, AGPL-3.0)
- 19 GitHub Releases published in the first month (repository created 2026-09-13)
- Cumulative downloads across all releases: see "Downloads" badge on the README
- Active development: frequent releases, public issue tracker, changelog per release
- Verified usage: users install via the released installer and report back through
  GitHub Issues

External coverage: none that we can point to at this time (no articles, blog posts
or community threads). We are not claiming any.

Comparable projects already holding Foundation certificates, such as third-party
clients for media platforms listed at https://signpath.org/projects, show the kind
of software we are, but we understand this is not a reputation signal of our own.
```

> 交表前请核对一次下载量数字（README 上的 Downloads 徽章 / Releases 页面），
> 把上面「see Downloads badge」换成真实数字更有说服力。

### Maintainer Type（下拉框，非必填）

可选值：

```
Independent community project (no formal organization)
Non-profit foundation or research/educational institution
For-profit company or corporate-backed project
Individual maintainer(s)
Other (please specify)
```

选：

```
Individual maintainer(s)
```

> 本项目由单人维护。若您希望强调「社区项目」的定位，`Independent community project (no formal organization)` 也成立 —— 二者都不算错，按您自己的判断选。

### Build System `*`（下拉框）

可选值只有两个：

```
GitHub Actions
GitLab CI/CD
```

选：

```
GitHub Actions
```

> 我们的构建全部在 `.github/workflows/build-windows.yml` 里跑，且不需要自建 runner
> （SignPath 对 OSS 项目要求所有 job 使用 GitHub 托管 runner，本项目满足）。

---

## 四、联系人

### First Name `*` / Last Name `*`

> 表单提示：*The name of the user account that will be created in SignPath.*

填您的名字（会用于创建 SignPath 账号）。中英文均可，建议用英文或拼音，便于对方处理。

### Email `*`

```
（您的邮箱）
```

> 表单提示：账号与申请通知都会发到这个地址，**填常用的那个**。

### Company Name（非必填）

留空（个人项目）。

### Primary Discovery Channel `*`（下拉框）

可选值：

```
Organic search / AI, LLM tools / Developer platforms (e.g. GitHub) /
Community platforms / Social media / Events / Referral / Direct contact
```

选：

```
Developer platforms (e.g. GitHub)
```

> 备选：如果您其实是从别处知道的（比如某个项目 README 里看到的），按实际选。
> **这一项只影响 SignPath 自己的市场统计，不影响审核结果**，如实填即可。

### Please specify the exact source（可选，单行文本）

```
（如选 GitHub，可填：Seen in the README of another SignPath Foundation project）
```

> 示例里的原话是 *"For example: Google search, ChatGPT, GitHub repository, Reddit,
> conference name, blog article URL, etc."* —— 照实写一句即可。

---

## 五、页面底部的复选框

- ☑ **I have read and agree to the SignPath Foundation Code of Conduct…**（必勾）
- ☐ I agree to receive other communications from SignPath.（**可不勾**）
- ☑ **I agree to allow SignPath to store and process my personal data.**（必勾）

底部有 reCAPTCHA 验证，最后点 **Submit**。

---

## 六、提交前最后核对

1. **GitHub 账号已开启两步验证（2FA）。** 条款要求所有项目成员对 SignPath 与代码仓库访问
   都启用 MFA —— 这是唯一一项我无法替您核实的。
2. **README 的下载区里有「SignPath Foundation」字样**（`Download URL` 那一栏的硬性要求），
   且仓库已推送到 `master`。**这一项当前不满足** —— 申请被拒后该字样已从两份 README 的
   下载区删除（commit `8407bcc`），重申前需先加回去。
3. `Reputation` 里的下载量数字与仓库现状一致。

## 七、提交之后

审核 1–2 周，结果发邮件。

- **通过** → 不要自己乱配，回来告诉我，我按 [`signpath-setup.md`](signpath-setup.md)
  带您建 Project / Trusted Build System / Artifact Configuration / Signing Policy，
  填好 1 个 Secret + 4 个 Variable，然后打一个 tag 验证整条链路。
- **被拒** → 不影响任何现有流程（CI 那三步一直会跳过），拒信允许以后再申请。

> 各字段的完整英文成文版本另见 [`signpath-application.md`](signpath-application.md)。
