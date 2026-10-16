# 未签名 Windows 应用的 SmartScreen 摩擦调研

> **调研对象**：Han1meWinPlus（Flutter 桌面应用，个人开源开发者，GitHub Releases 分发，产物为 Inno Setup 单文件安装包 `Han1meWinPlus-Setup.exe` + 免安装 zip）
> **调研日期**：2026 年（材料抓取时间见各条来源）
> **方法**：本环境 `web_search` 不可用（DeepSeek 端点返回 `no web_search_tool_result blocks`，Exa MCP 触发限流，Bing/Google 检索页经抓取工具返回无关内容）。所有材料均由 `web_fetch` 直接抓取具体 URL 获得，每条结论后附实际抓到的来源 URL。抓不到的一律写进「未找到的内容」，不做推测填充。
> **证据分级**：🔵 **官方** = 微软/Chocolatey/SignPath 等当事方自己的文档或仓库发言；🟡 **社区** = 第三方项目、开发者自述、实测记录，可信度显著低于官方；⚪ **未找到** = 该问题没有找到可靠来源，不作推断。

---

## 目录

1. [SmartScreen 对未签名 exe 的判定机制](#1-smartscreen-对未签名-exe-的判定机制)
2. [触发警告的具体条件：Mark of the Web / Zone.Identifier](#2-触发警告的具体条件mark-of-the-web--zoneidentifier)
3. [winget 分发](#3-winget-分发)
4. [Scoop / Chocolatey 分发](#4-scoop--chocolatey-分发)
5. [Windows 11 的 Smart App Control](#5-windows-11-的-smart-app-control)
6. [其他减少摩擦的技术手段，实际是否有效](#6-其他减少摩擦的技术手段实际是否有效)
7. [重新申请 SignPath Foundation 的条件](#7-重新申请-signpath-foundation-的条件)
8. [结论汇总与本项目的可执行建议](#8-结论汇总与本项目的可执行建议)
9. [未找到的内容](#9-未找到的内容)
10. [参考来源](#10-参考来源)

---

## 1. SmartScreen 对未签名 exe 的判定机制

### 1.1 「下载量累积就会自动放行」——**这个说法有官方依据，但成立范围被严格限定**

这是本次调研中最需要纠正的常见误传。流传的说法是「**未签名的 exe 下载够多就不报了**」。实际的官方说法是**两条**，必须合起来看：

**（a）信誉确实会随下载量累积，且这一条明确包括未签名文件。** 🔵 官方

微软开发者文档原文：

> "**As downloads accumulate:** SmartScreen reputation builds up automatically. The prompt will stop appearing once the file hash has sufficient download history. **There is no exact threshold, but it can take several weeks and hundreds of clean installs from a wide audience.**
> There is no need (or mechanism) to manually submit a file for SmartScreen reputation review for consumer endpoints. Reputation builds organically through download volume."

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

**（b）但未签名文件的信誉是「一次性」的，每个新版本从零开始。** 🔵 官方

同一页面原文：

> "**When a file is not signed, SmartScreen reputation must build for each new version of your files, starting with zero reputation. Reputation cannot transfer from previous versions unless both were signed using the same publisher identity.**"

以及「发布新版本时会发生什么」一条：

> "**Unsigned files must build reputation anew with every update.**"

— 同上；另见 https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status

**因此对第 1 问的明确判定**：

| 说法 | 判定 | 依据 |
| --- | --- | --- |
| 「未签名的 exe 会因为下载量累积而**最终不再报警**」 | **部分成立（单版本内）** | 官方明确说信誉「builds up automatically」且未签名文件也走这条路；但**没有给出阈值**，「several weeks and hundreds of clean installs」是官方能给的唯一量级描述 |
| 「下载够多就一劳永逸」 | **不成立** | 官方明确说未签名文件**每次更新都必须从零重建信誉**，不能从旧版本继承 |
| 「这个机制只对已签名的 OV 证书生效」 | **不成立** | 取证结论正好相反：**签名证书的信誉可以跨版本继承，未签名文件不能**。证书是让信誉「攒得住」的手段，不是参与累积的前提条件 |

**（c）「几百次干净安装」「几周」不是门槛，只是量级描述。** 🔵 官方

原文用的是 "There is no exact threshold"，即**微软官方拒绝给出任何阈值**。流传的各类具体数字（比如「下载 1000 次就放行」）均无官方依据。

补一条侧证：Zettlr 作者在 issue 里的原话可作对照——"in order to get rid of ALL warnings, we need **a certain amount of downloads and installations**. However, **Microsoft remains silent as to the actual amount needed**, so all we can do here is pray." 🟡 社区（https://github.com/Zettlr/Zettlr/issues/473）。这条与官方表述完全一致，可视为对「微软不公开阈值」的独立印证。

### 1.2 未签名文件在首次下载时的实际后果 🔵 官方

微软开发者文档给出的证书类型对照表：

| 分发方式 | 首次下载行为 |
| --- | --- |
| Microsoft Store | ✅ 无警告（Store 用自己的证书重新签名） |
| 有效证书（OV / EV） | ⚠️ 警告，标为 unrecognized，直到信誉累积；显示已验证的发布者名 |
| **无签名** | ⚠️ **「Windows protected your PC」，用户必须点 "Run anyway"** |
| 自签名 | ⚠️ 与无签名相同 |
| 企业策略 | 可完全阻止用户继续 |

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

另一页更直接地把无签名标为强阻止：

> "Unsigned apps and self-signed apps trigger **strong** SmartScreen warnings, and some enterprise environments will block them entirely."

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app

签名选项对比页把「No signature」标为 ❌ Strong SmartScreen block，并注明 "Not recommended for public distribution"。— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options

### 1.3 EV 证书 2024 年起不再自动放行 🔵 官方

> "**EV certificates no longer bypass SmartScreen.** That behavior was removed in 2024. SmartScreen reputation now accumulates over time rather than being granted instantly by certificate type."

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status

这条对本项目有实际意义：**即使将来拿到了普通 OV 证书，首次下载仍会警告**，只是警告形态从「未知发布者」变成「已识别的发布者但尚未建立信誉」，且信誉可以跨版本继承。所以「签名」解决的是「口碑能不能攒住」，不是「首次下载要不要点 Run anyway」。

### 1.4 机制的另一半：黑名单与信誉是两个独立检查 🔵 官方

SmartScreen 概述页原文：

> "Checking downloaded files against a list of reported malicious software sites and programs known to be unsafe... **Checking downloaded files against a list of files that are well known and downloaded frequently. If the file isn't on that list, Microsoft Defender SmartScreen shows a warning, advising caution.**"

> "**Reputation-based URL and app protection:** ... It also provides reputation checks for apps, checking downloaded programs **and the digital signature used to sign a file**. If a URL, a file, an app, or a certificate has an established reputation, users don't see any warnings. If there's no reputation, the item is marked as a higher risk and presents a warning to the user."

— https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/

重要边界（同页）：

> "SmartScreen protects against malicious files from the internet. **It doesn't protect against malicious files on internal locations or network shares, such as shared folders with UNC paths or SMB/CIFS shares.**"

误报可经 https://www.microsoft.com/wdsi/filesubmission/ 提交复核（产品菜单需选 Microsoft Defender SmartScreen）。🔵 官方

---

## 2. 触发警告的具体条件：Mark of the Web / Zone.Identifier

### 2.1 Mark of the Web 的官方定义 🔵 官方

微软支持页《Information about the Attachment Manager in Microsoft Windows》（Applies To: Windows 11, Windows 10）原文：

> "Attachment Manager helps protect your device by identifying files that were downloaded from the internet or received from other potentially unsafe locations. **Windows uses security information, sometimes called Mark of the Web (MOTW), to determine whether a file should display a security warning before it's opened.**"

来源分类（官方只给出三类）：

> - The internet
> - **Another computer**
> - **A restricted or untrusted location**

打开时 Windows 可能：`Display a warning before opening the file` / `Block the file from opening automatically` / `Apply additional protection in apps such as Microsoft Office or Microsoft Edge`。

官方提供的用户侧解除方式：资源管理器 → 右键文件 → **Properties** → **General** 标签底部安全提示 → **Unblock** → Apply > OK。

— https://support.microsoft.com/en-us/windows/security/information-about-the-attachment-manager-in-microsoft-windows

### 2.2 MOTW 与 SmartScreen 的因果关系 🟡 权威第三方

MITRE ATT&CK T1553.005 原文：

> "In Windows, when files are downloaded from the Internet, they are tagged with a hidden NTFS Alternate Data Stream (ADS) named `Zone.Identifier` with a specific value known as the MOTW... **Executables tagged with the MOTW will be processed by Windows Defender SmartScreen that compares files with an allowlist of well-known executables. If the file is not known/trusted, SmartScreen will prevent the execution and warn the user not to run it.**"

— https://attack.mitre.org/techniques/T1553/005/

MOTW 的实现细节（🟡 第三方，非官方）：使用 NTFS 备用数据流（ADS）；`Zone.Identifier` 内容自 Windows 10 起是 INI 风格键值，含 `HostIpAddress`、`HostUrl`、`ReferrerUrl`；**拷到 FAT32 / Ext4 等非 NTFS 分区会丢掉 ADS，从而丢掉标记**；用户覆盖警告后标记会被移除，以免每次重复提示；相关漏洞 CVE-2022-41091、CVE-2022-44698、CVE-2023-36584、CVE-2024-38217。

— https://en.wikipedia.org/wiki/Mark_of_the_Web

一条容易被忽略的争议细节：SmartScreen 自 2022 年 3 月起改为在 `Zone.Identifier` **之外**另写一个 `:SmartScreen` 备用流（含文本 `Anaheim`），不再修改 `Zone.Identifier`；2023 年 2 月起，Windows 11 从 Shell 成功执行程序后，AppRep 检查通过会**移除** `Zone.Identifier` 流。🟡 社区（https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/ ，作者为前 Microsoft Edge 工程师，属业内权威但**非官方文档**）。

注：另有博客称该 `SmartScreen` 流含 `Anaheim` 意味着「文件已被判定为不安全」（https://diecknet.de/en/2024/08/30/powershell-ntfs-alternate-data-streams/ ），与上述说明方向相反。**两说冲突，此处不采信任何一方**。

### 2.3 浏览器 / 下载工具 / 局域网 / 网盘的差异

| 获取途径 | 是否留下 MOTW | 证据等级 |
| --- | --- | --- |
| 浏览器直接下载 | 是（MOTW，ZoneId=3 = Internet） | 🔵 官方（Attachment Manager 页：「Files downloaded from websites, email messages, or messaging apps might display warnings」）；🟡 MITRE 补充 ZoneId 机制 |
| 通过第三方下载工具 | **官方未找到逐条说明**。官方排障页反而把「第三方下载管理器」列为可能导致**持续警告**的因素之一，建议「Temporarily disable third-party download managers or security software only for testing purposes」 | 🔵 官方仅此一句；⚪ 其余未找到 |
| 局域网 / 网络共享（UNC、SMB/CIFS） | SmartScreen **不检查**此类位置 | 🔵 官方（SmartScreen 概述页：「It doesn't protect against malicious files on internal locations or network shares, such as shared folders with UNC paths or SMB/CIFS shares.」） |
| 网盘客户端 | ⚪ **未找到**任何官方或权威第三方说明 | ⚪ 未找到 |
| 「从另一台电脑拷过来」 | 会被标为「Another computer」类别 | 🔵 官方（Attachment Manager 页来源分类） |

**这里的实务含义**：走局域网/内网共享分发（如企业域内的文件服务器）确实绕开 SmartScreen，但这是**企业 IT 场景**的手段，对面向公众的 GitHub Releases 分发不适用。官方文档另有一句可直接引用：

> 企业可以从 Trusted Intranet 位置分发以避开 SmartScreen 审查；企业 IT 管理员可通过 WDSI 提交文件以加速信任（**仅限内部/托管部署**）。

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

### 2.4 「先解压 zip 再运行」能不能去掉 MOTW——**取决于解压工具，不能无条件成立**

这是第 6 问里最容易被误传的一条，正反两面证据都存在，必须并列：

**支持「解压后不带 MOTW」** 🟡 权威第三方（MITRE ATT&CK）：

> "Container files downloaded from the Internet will be marked with MOTW **but the files within may not inherit the MOTW after the container files are extracted and/or mounted**. MOTW is a NTFS feature and many container files do not support NTFS alternative data streams. After a container file is extracted and/or mounted, the files contained within them may be treated as local files on disk and run without protections."

— https://attack.mitre.org/techniques/T1553/005/

同页的检测项 DET0257 正是针对这类绕过行为："Detects extraction or mounting of container/archive files (e.g., .iso, .vhd, .zip) that originated from the Internet but **whose contained files lack Zone.Identifier MOTW tagging**."

**反对「解压一定去掉 MOTW」** 🟡 权威第三方（SANS ISC，Didier Stevens，2025-03-03）：

> "This MoTW is propagated when a file is copied (to another NTFS disk). **It is also propagated by various applications that handle container formats. For example, many archiving utilities will copy the MoTW from a download ZIP file to the extracted files. Sometimes this needs to be configured, like with 7-Zip. WinRAR is also a bit special.**"

— https://isc.sans.edu/diary/31732

**判读**：MITRE 说的是「**may not** inherit」（可能不继承），SANS 说的是「many archiving utilities **will** propagate」（很多工具会传播）。两者不冲突，合起来是：**解压是否去掉 MOTW 由具体解压工具决定**，7-Zip 需要配置、WinRAR 行为特殊、部分工具直接传播。因此「先解压再运行」**不能作为可靠手段**对用户承诺；它有可能生效，也有可能不生效。⚪ 官方文档中**未找到**任何关于「解压 zip 是否传播 MOTW」的说明。

---

## 3. winget 分发

### 3.1 winget 是否绕过 SmartScreen——**证据矛盾，不宣称一定绕过**

**正面证据（微软自家仓库中的一手陈述）** 🟡 社区仓库 + 🔵 官方人员发言：

winget-cli issue #3111 正文原文：

> "SmartScreen is good, but unfortunately sometimes it can be annoying due to network and other problems. **`winget` now skips SmartScreen for default sources**, and we wish to apply the same magic to custom sources that are trusted by the user."

微软 winget 团队成员 **denelon** 于 2024-08-02 在同一个 issue 中回复：

> "The latest version of WinGet allows you to specify the source as \"trusted\"."

并附上 `winget source add -?` 的实际输出（Windows Package Manager (Preview) v1.9.1981-preview），其中含选项：

```
--trust-level   Trust level of the source (none or trusted)
```

— https://github.com/microsoft/winget-cli/issues/3111

另一条实现层面的旁证（winget-cli issue #703）：

> "**Recent changes were made to the zone for an installer after it has been downloaded by the Windows Package Manager.**"（附 v0.2.3162-preview 发布链接）

即 winget 会在下载后主动处理安装器的 zone 信息（MOTW）——这正是它「跳过 SmartScreen」的实现线索。同 issue 中发帖人定位到：

> "The 'flag' seems to come from the **zone information** that is tagged to the file. In my case I can bypass the dialog by using `set SEE_MASK_NOZONECHECKS=1`."

— https://github.com/microsoft/winget-cli/issues/703

**反面证据（一手实测，必须并列）** 🟡 社区：

1. vim-win32-installer issue #319（2023-08-02）：

> "when I download the exe file (`gvim_9.0.1672_x64.exe`) and run it from the web browser or Windows file manager, I do get an error message -- the following popup, and the only option is a button that says \"Don't run\""
> 弹窗内容：`Windows protected your PC / Microsoft Defender SmartScreen prevented an unrecognized app from starting... App: gvim_9.0.1672_x64.exe / Publisher: Unknown publisher`
> **"So winget fails because the executable is blocked."**
> "The unsigned installers keep being blocked by Microsoft Defender SmartScreen. All the signed installers seem to work normally."

维护者回复："There is nothing we can do here to convince Defender to run the installer unfortunately."

— https://github.com/vim/vim-win32-installer/issues/319

2. winget-pkgs discussion #3335（2020-08-31）：用本地新建 manifest 安装 RunJS 时收到同样弹窗；回复：

> "There is no way to unblock it other than waiting for the Microsoft Team to clear it. For very good reasons. The dev need to sign the software to not go trough this process every time."

— https://github.com/microsoft/winget-pkgs/discussions/3335

3. 官方文档侧的一条佐证（说明 winget 不是「绕过」，而是「延后」）🟡 社区：

> "Winget is an official installation path, but it is not a replacement for Authenticode signing... **Windows SmartScreen may still show a warning for a validly signed installer while publisher or file reputation is being established.** Authenticode signature validation and SmartScreen reputation are related but separate checks."

— https://github.com/shm11C3/HardwareVisualizer/blob/develop/CODE_SIGNING_POLICY.md

**判读**：winget **默认源**确实被设计为跳过 SmartScreen（这是微软自家仓库里的陈述 + 官方人员确认的 `--trust-level trusted` 选项），社区也有成功经验（如 https://www.reddit.com/r/buildinpublic/comments/1w7tcov/ 的作者说 "The one thing that dodges it properly is winget... No browser involved, so there's nothing to block."）。但存在 2 条一手反例显示 winget 安装未签名 exe **仍被 SmartScreen 拦住**。合理的表述是：**winget 显著降低了遇到 SmartScreen 的概率，但不是有保证的绕过通道；且它不能消除 UAC 提权提示。** 微软**没有**在任何正式文档中承诺 winget 绕过 SmartScreen。

另需澄清一条**错误的社区说法**：多处社区文章称 "winget refuses unsigned installers outright"（如 https://github.com/serjdrej/trimitdown/commit/f79a3899ae0fb64116d5bc5335693a2ac9df5849 ）。这与官方问答直接冲突，**是错的**——见 3.2。

### 3.2 提交到 winget 仓库的要求 🔵 官方

**提交方式**：向开源仓库 https://github.com/microsoft/winget-pkgs 提 PR。整个流程是：PR → 自动校验 manifest 是否符合 Windows Package Manager policies、是否已知恶意 → 可能再经人工复核 → 通过后进入公开仓库。原文明示「Microsoft reserves the right to refuse a submission for any reason.」— https://learn.microsoft.com/en-us/windows/package-manager/package/repository

**技术形态要求**（与本项目直接相关）：

- 支持的安装器格式明确包含 **EXE（Silent / SilentWithProgress）、ZIP、INNO、NULLSOFT、MSI、WIX、APPX、MSIX、BURN、PORTABLE、FONT**。本项目的 Inno Setup 单文件 exe 与免安装 zip **都在支持列表内**。— https://learn.microsoft.com/en-us/windows/package-manager/winget/
- winget-pkgs 首页 IMPORTANT：「At this time installers must be MSIX, MSI, APPX, MSIXBundle, APPXBundle, or .exe application installers. Font files... **Script-based installers are not currently supported.**」— https://github.com/microsoft/winget-pkgs
- 必须使用 multi-file manifest（至少 version + defaultLocale + installer 三个 YAML）；推荐用 `wingetcreate new` 生成并自动提 PR。— https://github.com/microsoft/winget-pkgs/blob/master/doc/Authoring.md
- 目录结构 `manifests/<首字母小写>/<publisher>/<application>/<version>`；**每个 PR 只允许一个包版本**。— https://learn.microsoft.com/en-us/windows/package-manager/package/repository

**门槛（Submission expectations）** 🔵 官方：

- manifest 符合 schema
- 所有 URL 指向安全站点（强制 HTTPS）
- 安装器与应用无病毒
- **安装与卸载对管理员和非管理员都要正常**
- **安装器必须支持非交互（静默）模式** — 「Packages submitted to the community repository must install without requiring user interaction.」
- manifest 各项准确不误导
- **InstallerUrl 必须直接来自发布者的官方位置**：「The InstallerUrl must be the ISV's release location for the Product. **Products from download websites will not be allowed.**」、「The URLs in manifests should come from official sources/publishers」
- 首次贡献者需先看 first-time contributor checklist，并签署 CLA（https://cla.opensource.microsoft.com）

— https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md 、https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md 、https://learn.microsoft.com/en-us/windows/package-manager/package/windows-package-manager-policies

**严格的 PUA 政策** 🔵 官方：

> "Because of the security position this repository is placed in, there is a strict policy against Potentially Unwanted Applications (PUA) and potentially malicious software. **If a package is flagged by any of the security scans in the validation pipeline, it cannot be accepted into the repository, regardless of the application's legitimacy or intent.**"

失败会带 `Binary-Validation-Error` 标签，对应的测试说明是：「This test is designed to ensure that the application installs on all environments **without warnings**」，提交会跑多个杀毒引擎（含 PUA 判定）。若厂商无法确认是误报则**不能加入仓库**。

— https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md 、https://learn.microsoft.com/en-us/windows/package-manager/package/repository

**对个人开源项目最关键的一条**：**未签名安装器可以被接受**。🔵 官方（微软人员在 winget-pkgs 仓库中的回复）

issue #2701「Can I submit a package without a signed installer?」，提问者说明自己是业余时间写的免费开源应用、不愿买证书，微软方回复原文：

> "in order of preference: MSIX, MSI, EXE... **Some formats do require a signature, but we don't require a signature in the repository here. If you have an unsigned EXE installer, that's OK. It may just take some extra time for our static analysis to complete, and for the installer to gain sufficient reputation to be approved. That is generally on the order of days.**"

— https://github.com/microsoft/winget-pkgs/issues/2701

另一条官方口径（winget-cli discussion #4327，「Is code signing necessary?」，2024-03-29）微软方回复：

> "**WinGet doesn't require code signing**, but some users are likely to be concerned about unsigned installers."
> "Currently, not from WinGet. We're gradually beefing up the UX to include more things related to security, but for now, **those checks happen during validation, and aren't blocking**."

— https://github.com/microsoft/winget-cli/discussions/4327

**有没有个人开源项目的先例？有，而且是普遍现象** 🟡 社区：同一 discussion #4327 中一位开发者说：

> "I reviewed 5 similar open source projects (including act and crush) on winget and noticed that **they do not sign their exe**. They are distributed with .zip + unsigned exe to prevent malware blocking."

这与本项目的产物形态（安装包 exe + 免安装 zip）完全一致。

### 3.3 winget 的实际副作用（本项目需权衡）🔵 官方 + 🟡 社区

- **UAC 提权提示仍在**：非管理员运行某些应用会触发提权提示，拒绝则安装失败；以管理员运行则不显示提权提示。— https://learn.microsoft.com/en-us/windows/package-manager/winget/
- **Defender 误报会挡住整个安装**：winget 的验证流水线含多引擎扫描，误报会直接导致 `Binary-Validation-Error` 而无法入库。— https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md

---

## 4. Scoop / Chocolatey 分发

### 4.1 Scoop

**官方关于 SmartScreen 的说明：⚪ 未找到。** Scoop 仓库的 discussion #6153（「What measures does scoop take to keep malware out of its packages?」）只讲了下载来源与哈希校验：「Scoop downloads the contents of packages from official distribution channels」「Scoop will check hashes before installing / after downloading」，**全文未提 SmartScreen 或 MOTW**。— https://github.com/ScoopInstaller/Scoop/discussions/6153

**支持「Scoop 不触发警告」的社区实测** 🟡：

1. 一份自称「Measured, not assumed」的实测记录原文：

> "**installing through scoop leaves no Mark-of-the-Web on the executable, so SmartScreen has nothing to warn about.** winget refuses unsigned installers outright, and Homebrew propagates quarantine. Until there is a certificate this is the channel that works."
> "Proven by installing it: the manifest resolves, the hash matches, the shortcut appears, **no Zone.Identifier on the file**, and the installed build launches under double-click conditions"

— https://github.com/serjdrej/trimitdown/commit/f79a3899ae0fb64116d5bc5335693a2ac9df5849
（注：其中「winget refuses unsigned installers outright」一句是**错的**，见 3.2。）

2. 另一个项目的 README 改动记录（基于用户反馈）：

> "the MSI shows SmartScreen warnings (Pouch isn't code-signed yet)"
> "Reorders the README Windows install section so **Scoop comes first (PowerShell-based, never triggers SmartScreen)** with MSI after."

— https://github.com/leaker/pouch/commit/a38081177bd9c84c6d6b5fea1b5b464b1c5be427

3. 某应用安装页：

> "**Scoop and winget never touch the browser, so no warning appears at all.** They also verify the checksum for you."

— https://windowpin.com/en/install

**反例（必须并列）** 🟡：Espanso 的官方安装文档在给出 Scoop 命令后仍写着：

> "Given that Espanso's digital signature is still relatively new, **you may experience a warning from Windows Smartscreen**. In this case, just click on \"More info\" (1) and then on \"Run anyway\" (2)"

— https://espanso.org/docs/install/win/

**另一类拦截与 SmartScreen 无关，但会同样打断安装** 🟡：Scoop 下载的 `innounp` 被 Microsoft Defender 直接拦住，报错原文：

```
Get-Content : Operation did not complete successfully because the file contains a virus or potentially unwanted software.
```

并导致 `ERROR Hash check failed!` — https://github.com/ScoopInstaller/Main/issues/7537

**判读**：Scoop 路径（PowerShell 直接下载+解压，不经浏览器）**通常**不产生 MOTW，因此**通常**不触发 SmartScreen，社区实测支持这一点；但①Scoop 官方从未承诺此事，②有第三方项目官方文档记录 Scoop 安装后仍见警告。**属于有效但非保证的手段。** 另需注意 Defender 杀毒拦截是独立于 SmartScreen 的另一层机制，包管理器路径**规避不了**它。

### 4.2 Chocolatey

**官方关于 SmartScreen 的说明：⚪ 未找到。** Chocolatey 官方文档中未找到任何关于「是否绕过 SmartScreen」的表述。

**官方的收录门槛** 🔵：

> "The community feed... is a moderated feed. That means **all new versions of packages are human reviewed prior to approval** to check for safety, quality, and correctness. There are also trusted packages, which only go through automated moderation review and bypass human review as they are coming from trusted sources and/or the software vendors themselves."
> "By safety - we check that the package scripts do not do anything devious and that you get the software that the package indicates you are getting."

— https://docs.chocolatey.org/en-us/community-repository/moderation/

审核体系：validator（质量）/ verifier（安装卸载正确性，每两周复检）/ scanner / cleaner / cacher；规则编号 CPMR0001–CPMR0076。人工审核员只能基于 **Requirements** 阻塞包，不能仅凭 Guidelines 阻塞。包被拒后无法安装。

— 同上；https://docs.chocolatey.org/en-us/faqs/

安全页原文：

> "Every package submitted to the community package repository since October 2014 undergoes a rigorous moderation process before it becomes live. Yes, every package, every version of a package is moderated and approved before they become live."
> "All packages versions are run through VirusTotal to determine if there are any flagging items."
> "Chocolatey v0.10.0+ enforces a checksum requirement for non-secure locations by default"
> "Only en-US installers are tested by default via Chocolatey's Package Scanner."

— https://docs.chocolatey.org/en-us/information/security/

**门槛判读**：Chocolatey 社区源对**包脚本**做人工审核，但**不要求包本身或内含二进制加密签名**（官方原文：「We don't require cryptographically signing packages yet」，同上安全页）。也就是说，个人开源项目提交 unsigned exe 的包在政策上**可行**。

**「Chocolatey 是否绕过警告」的社区证据（正反并存）** 🟡：

- 正面：Zettlr 用户评论「I find installing Zettlr using **Chocolatey** solves this issue. Primarily because you have to login using an Administrative PowerShell to install both Chocolatey and Zettlr.」— https://github.com/Zettlr/Zettlr/issues/473
- 反面（同帖）：立刻有人指出「And it's exactly there (at work) that I was trying to install Zettlr」——即企业环境不适用。
- 反面（Chocolatey 自身）：choco CLI 安装时本身会弹出不受信任发布者提示，原文 `Do you want to run software from this untrusted publisher? ... CN="Chocolatey Software, Inc." ... is not trusted on your system.` — https://github.com/chocolatey/choco/issues/3302 ；同类问题 https://github.com/chocolatey/choco/issues/1508 （维护者以「不想改动用户自己的安全设置」为由关闭）

**判读**：Chocolatey 路径「绕过」的机制与 Scoop 类似（不经浏览器 → 无 MOTW），但**它自己就会弹不受信任发布者提示**，且需要管理员 PowerShell。对本项目而言，Chocolatey 相比 Scoop/winget **没有明显优势，且多一层自己的提示**。

---

## 5. Windows 11 的 Smart App Control

### 5.1 对未签名程序的影响：默认阻止 🔵 官方（三处独立文档一致）

官方文档原文：

> "Smart App Control is an app execution control feature that combines Microsoft app intelligence services and Windows code integrity features to protect users from untrusted or potentially dangerous code."
> "**Malware, Potentially Unwanted Apps (PUA), and unknown, unsigned code are blocked by default.**"
> "In *enforcement mode*, Smart App Control is actively protecting your device. **Apps cannot be run unless they are recognized by Microsoft's app intelligence services, or they are signed with a trusted certificate.**"
> "If the app intelligence service is unable to make a prediction, then Smart App Control will still allow an app to run **if it is signed with a certificate issued by a certificate authority (CA) within the Trusted Root Program**."

— https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview

FAQ 页原文：

> "If the security service is unable to make a confident prediction about the app, then Smart App Control checks to see if the app has a valid signature. If the app has a valid signature, Smart App Control will let it run. **If the app is unsigned, or the signature is invalid, Smart App Control will consider it untrusted and block it for your protection.**"

— https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions

App Control for Business 文档原文：

> "Starting in Windows 11 version 22H2, Smart App Control brings robust application control to consumers... Smart App Control ensures only signed code runs or code predicted to be safe by our intelligent cloud-powered security service. **When code is unsigned and the service is unable to predict with confidence that it's safe to run, then we block it.**"

— https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol

**关键区别（对本项目尤其重要）** 🔵 官方：SmartScreen 只检查**入口程序**，而 Smart App Control 的签名检查**检查所有可执行文件**：

> "Smart App Control signature checks apply to all executable files, **not just those downloaded from the Internet**."

— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation

也就是说：**SAC 强制模式下，MOTW、Scoop、winget、解压 zip 全部无效**——因为它不看文件来源，只看签名与云端情报。

### 5.2 用户能否关闭？关闭后有什么后果？🔵 官方

关闭方式（FAQ 页原文）：

> "**You are able to disable Smart App Control in the Windows Security App settings.** **Recent Windows updates allow Smart App Control to be re-enabled without requiring a clean installation.**"

无法对单个应用放行（同页原文）：

> "**There is currently no way to bypass Smart App Control protection for individual apps.** You can turn Smart App Control off, or (better yet), contact the developer of the app and encourage them to sign their app with a valid signature."

微软给开发者的直白答复（同页）："The simple answer is, **sign your app with a valid certificate**."

**关于「关闭后能否重开」——官方文档之间存在表面冲突，需并列**：

| 出处 | 说法 |
| --- | --- |
| Smart App Control FAQ 🔵 | 「Recent Windows updates allow Smart App Control to be **re-enabled without requiring a clean installation**」（近期更新允许无需重装即可重新启用） |
| App & Browser Control in Windows Security 🔵 | 「**Smart App Control can be used on new Windows 11 installs only.** If you received it as part of a Windows update on an already running device, you won't be able to turn it on unless you reset your PC or re-install Windows.」；「**Evaluation mode**... Once the evaluation is complete, or if you manually switch Smart App Control on or off, **you won't be able to return to evaluation mode unless you reinstall or reset Windows**.」 |
| 开发者文档 🔵 | 「**Configuring Smart App Control to Off or On (enforcement) is a one-way operation. You can't change modes by using Windows Settings unless the current setting is Evaluation.**」 |

— 三处分别为：https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions 、https://support.microsoft.com/en-us/windows/security/windows-security/app-browser-control-in-the-windows-security-app 、https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/test-your-app-with-smart-app-control

**判读**：可以确定的是——(1) 用户**能**在 Windows 安全中心关闭 SAC；(2) 关闭后**不能**回到 evaluation 模式，除非重置/重装；(3) 能否重新开启到 enforcement，FAQ 说可以、另两处说不行，**官方文档自相矛盾，本报告不做裁定**。对分发侧的实务结论是：**不能向用户承诺「关掉还能随时恢复」**，因为至少有一份官方文档说这条路是单向的。

### 5.3 SAC 的适用面（决定它对本项目影响有多大）🔵 官方

- 仅 Windows 11 有；「**Smart App Control is not available in Windows 10.**」— https://support.microsoft.com/en-us/windows/security/windows-security/app-browser-control-in-the-windows-security-app
- 需要 Windows 11 **全新安装**才可能启用（升级上来的设备除非重置/重装不能开启）— 同上
- 初始为 evaluation 模式，评估期间不阻止任何东西 — https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
- **企业托管设备 48 小时内自动关闭** — https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol
- 若用户关闭了**可选诊断数据**，SAC 也无法开启（需重置/重装并在安装时选择「发送可选诊断数据」）— https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions
- 企业侧可用注册表强制：`HKLM\SYSTEM\CurrentControlSet\Control\CI\Policy` 的 `VerifiedAndReputablePolicyState`（DWORD，0=Off / 1=Enforce / 2=Evaluation），改后需 `CiTool.exe -r` — https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol

**配置状态对照**：Settings > Windows Security > App and Browser Control；`On` = 强制模式，`Evaluation` = 评估模式，`Off` = 未运行；进入强制模式会发 Toast 通知。— https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview

---

## 6. 其他减少摩擦的技术手段，实际是否有效

### 6.1 「让用户先解压 zip 再运行」——**不可靠，不能作为主推手段**

见 2.4。MITRE 说内部文件「may not inherit」MOTW，SANS 说很多解压工具「will propagate」。**结论：效果取决于用户用哪个解压工具，无法承诺。** ⚪ 微软官方文档中未找到关于 zip 解压与 MOTW 关系的任何说明。

### 6.2 提供 SHA256 校验——**对 SmartScreen 无直接作用，但仍然是应当做的事**

⚪ **未找到**任何官方文档说明「提供 SHA256 校验能减少 SmartScreen 警告」。从机制上讲，SmartScreen 检查的是文件信誉与签名，**SHA256 是给用户自己核对完整性的，不参与 SmartScreen 判定**。

社区侧的可引用表述（明确区分两者）🟡：

> "Winget is an official installation path, but it is not a replacement for Authenticode signing, **SHA-256 checksums, or GitHub Artifact Attestations.** Windows SmartScreen may still show a warning for a validly signed installer while publisher or file reputation is being established. **Authenticode signature validation and SmartScreen reputation are related but separate checks.**"

— https://github.com/shm11C3/HardwareVisualizer/blob/develop/CODE_SIGNING_POLICY.md

**判读**：SHA256 的价值是给用户一个「可验证来源」的抓手，**不减少警告次数**。作为降低「用户不信任感」的配套措施仍然值得做，但不应把它写成「能减少 SmartScreen 警告」。

### 6.3 在下载页写清操作步骤——**官方明确建议这样做** 🔵 官方

微软开发者文档「与早期用户沟通」一条原文：

> "**Communicate with early adopters** — for new apps, let beta users know they may see a SmartScreen prompt on first download, and that they should only proceed after verifying the publisher and confirming they trust the download source."

另一页给早期用户的话术模板原文：

> "You may see a SmartScreen prompt on first run — this is normal for new apps; click 'More info' then 'Run anyway'."

— 分别是 https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation 与 https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app

**判读**：这是**唯一有官方背书**的「降低摩擦」手段——它不减少警告，但把「未知发布者」从一个可疑信号转成「已知且可解释的行为」，降低用户流失。多个项目已在实际执行这一做法 🟡：如 https://github.com/nishiuriraku/easy-cursor-swap/pull/7 （README 写入 "More info → Run anyway"）、https://github.com/antigerme/wilson-reborn/pull/97 （README 声明无签名 + 提供 `SHA256SUMS.txt`）。

### 6.4 「用户手动解除锁定（Unblock）」——**官方方法，但需要用户先信任你** 🔵 官方

官方步骤：资源管理器 → 右键文件 → Properties → General 标签底部 → **Unblock** → Apply > OK。

— https://support.microsoft.com/en-us/windows/security/information-about-the-attachment-manager-in-microsoft-windows

同页警告：「Only unblock files from trusted sources.」这意味着**必须先在下载页建立信任说明，用户才会去点这个按钮**。另可用 `Unblock-File` 或 `HideZoneInfoOnProperties` 策略管理（🟡 社区，https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/ ）。

### 6.5 走微软 WDSI 提交误报——**有效，但只解决「被标记为恶意」，不解决「无信誉」** 🔵 官方 + 🟡 社区

官方入口：https://www.microsoft.com/wdsi/filesubmission/ （产品菜单需选 Microsoft Defender SmartScreen）。— 🔵 https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/

一份开发者实测记录的区分很值得引用 🟡：

> "VirusTotal flagged the installer on a couple of engines, Microsoft's included. I submitted it through WDSI and they cleared it in about a week. **That got Edge to stop blocking the download**, which was a nice surprise, and it costs nothing. **Chrome still blocks it though.** Chrome runs Google Safe Browsing and nothing Microsoft does touches that. And **Windows still shows 'Windows protected your PC' on first run, because that one is about the file having no reputation rather than being flagged. Two different things.**"

— https://www.reddit.com/r/buildinpublic/comments/1w7tcov/

**判读**：这条把三件事彻底分清了——**杀软误报（可申诉清除）、浏览器 Safe Browsing 拦截（微软管不到 Chrome）、SmartScreen 无信誉警告（申诉无用，只能攒下载量）**。对本项目的直接含义：即使通过 WDSI 清掉 Defender 误报，SmartScreen 的「未知发布者」警告**不会因此消失**。

### 6.6 其他（未在本次调研中取得证据的）手段

- ⚪ 用 GitHub Artifact Attestations / Sigstore 类无证书签名的**能否影响 SmartScreen**：**未找到**任何官方或权威说明。
- ⚪ 让用户通过 `winget install` 而非浏览器下载：见第 3 节，**有效但非保证**。
- ⚪ 把主推渠道放到 Scoop：见 4.1，**有效但非保证且无官方承诺**。

---

## 7. 重新申请 SignPath Foundation 的条件

### 7.1 能否再次申请？——**能，官方拒绝邮件明确写了欢迎重申** 🟡（SignPath 发出的原文邮件，由多个申请人独立贴出，文字一致）

拒绝邮件原文（多家项目收到的模板完全一致）：

> "After a review of your submission, we regret to inform you that we cannot approve your application at this time.
> When evaluating projects for the SignPath Foundation program, we look at a combination of factors that help us verify a project's reputation and standing. These typically include signals such as:
> - **Community adoption (e.g., GitHub stars, forks, contributors)**
> - **Independent references or discussions (Reddit, Stack Overflow, YouTube, etc.)**
> - **External articles, blog posts, or institutional backing**
> - **Evidence of sustained activity and user engagement**
> At the moment, your project does not yet provide sufficient external verification signals for us to issue a Foundation certificate in our name. Please note that this is not a judgment on the quality or potential of your work. The Foundation program is designed specifically for projects that have already established a certain level of public trust and visibility.
> We encourage you to continue developing and growing your project. **Once it has gained broader recognition, you are very welcome to reapply, we would be happy to review it again.**"

### 7.2 有没有等待期或次数限制？——**官方条款中没有任何此类规定** 🟡

SignPath 官方《Code of conduct》（https://signpath.org/terms ）全文**未出现**「等待期」「申请次数上限」「被拒后不得再申请」的任何条款。相关条款只有：

> "SignPath Foundation performs **initial** verification of project reputation and control. **Note that we don't repeat these verifications periodically.**"
> "**We're under no obligation to accept your project, and there is no independent arbitration mechanism.** ... We will listen to arguments about your specific situation, but we generally don't discuss policy. Please don't argue with us, we can only provide this service if we can keep the manual work for each applicant to a minimum."

并明确「误解」栏目中两条与拒绝相关的说明：

> 「Any project can get a SignPath certificate」是误解——因为证书上是 SignPath 的名字，其声誉承担风险，「we cannot sign binaries based on source code that nobody knows. For executable programs that may be downloaded and executed based on our signature, **we require a certain verifiable reputation**.」
> 「Projects have a right to get a certificate」是误解——理由同上（无接受义务）。

— https://signpath.org/terms

**判读**：**没有强制等待期，也没有次数上限**；但 SignPath 明确保留「无义务接受、不做政策讨论」的权利，所以「重申」不等于「迟早能过」。社区自定的重申窗口是**经验值**，非规定：3–6 个月（https://github.com/nishiuriraku/easy-cursor-swap/pull/7 ）或 6–12 个月（https://github.com/i999rri/GhosttyWin32/issues/46 ）。

### 7.3 有没有「被拒后补齐材料再申请成功」的先例？——**未找到成功先例** ⚪

本次调研找到的 6 条一手记录**全部是「被拒 + 计划日后重申」，没有一条记录到「重申成功」的结果**：

| 项目 | 时间 | 结果与后续 |
| --- | --- | --- |
| https://github.com/i999rri/GhosttyWin32/issues/46 | 2026-05-21 | 被拒；计划 6–12 个月后重申；列出替代路径 |
| https://github.com/nishiuriraku/easy-cursor-swap/pull/7 | 2026-05-21 | **deferred**（非质量判断）；roadmap 写「reapply at 3–6 months when 2+ signals meet thresholds」；备选 Certum OSS（€29–€69/yr） |
| https://github.com/Arsarneq/docent/issues/72 | 2026-05-28 | 被 declined，issue 保持 open 等待知名度积累 |
| https://github.com/antigerme/wilson-reborn/pull/97 | 2026-07-01 | 被 declined；选择「继续无签名 + 校验和 + SmartScreen 说明，日后重申」 |
| https://www.v2ex.com/t/1218906 | 2026-06-08 | 中文申请人，同样被拒；结论是「不是项目质量不行，而是知名度不够」 |
| https://github.com/martymcenroe/silphe/issues/18 | — | 转述申请表单字段要求（见 7.4） |

**⚪ 「被拒后补齐材料再申请成功」的具体先例：未找到。** 现有记录的时间跨度都不足以覆盖一次完整的重申周期。

### 7.4 门槛到底是什么：来自申请表单本身的一手转述 🟡

这是本次调研中对「怎么提高重申成功率」最具体的一条证据。一位申请人转述 SignPath 申请表单要求：

> "SignPath Foundation requires an **established** project — the application asks for '**Reputation**' (widely used/trusted, download stats, media/community coverage), that '**a Google search clearly identifies**' the project, and a download page that mentions SignPath."

— https://github.com/martymcenroe/silphe/issues/18

中文社区独立印证（V2EX 帖评论区）🟡：有评论指出 https://signpath.org/projects 里不少已获准项目的 star 数也不高，判断其**更看重「现实中是否真有人在用」**，需要提供文章、推文等外部佐证。— https://www.v2ex.com/t/1218906

**官方条款中与之对应的硬性要求**（拿到资格后必须满足，申请前就应准备好）🔵：

- 无恶意软件 / PUP
- OSI 认可的开源许可证，且**不得对任何组件做商业双许可**
- 不得含专有非开源组件（自有 System Libraries 除外）
- 项目须**活跃维护**
- **须已以要签名的形式发布**
- 功能须在**下载页或应用商店条目中有描述**
- 证书签发给 SignPath Foundation 本身（即 Foundation 是发布者），因此**只能签自己的项目**，且团队须是全部源码与构建脚本的维护者
- **禁止 hacking 工具**（不得含识别或利用漏洞、绕过执行环境安全措施的功能）
- 尊重用户隐私与安全（收集并外传数据须有隐私政策 + 安装时展示 + 可关闭）
- 宣布系统更改；提供卸载途径
- 团队成员 SignPath 与代码仓库**必须启用 MFA**
- 须自组织 **Authors / Reviewers / Approvers** 三种角色，每次签名请求须由 Approver 批准
- **项目主页须写明 "Code signing policy"**，含 "Free code signing provided by SignPath.io, certificate by SignPath Foundation" 字样、团队角色与成员链接、隐私政策
- 签名二进制的 metadata attributes 必须设置并强制（product name = 项目名，product version 每次构建一致）

— https://signpath.org/terms

### 7.5 免费替代路径（社区记录，仅供参考）🟡

- **Azure Trusted Signing（原 Trusted Signing）**：约 **$9.99/月**，无需硬件 token，但**不提供即时 SmartScreen 信任**；机构限 USA/Canada/EU/UK，**个人开发者仅 USA 和 Canada**。— https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options （🔵 官方）
- **Certum Open Source**：€29–€69/年（🟡 社区，https://github.com/nishiuriraku/easy-cursor-swap/pull/7 ）
- 一条待核实的社区记录称「Microsoft Trusted Signing 的 individual onboarding 当前暂停」（同上），与官方页面的地域限制说法需要分别对待。

---

## 8. 结论汇总与本项目的可执行建议

### 8.1 七问速查表

| # | 问题 | 结论 | 证据强度 |
| --- | --- | --- | --- |
| 1 | 未签名 exe 会随下载量/时间自动放行吗？ | **单版本内会**（官方明说 "reputation builds up automatically"，无阈值，量级为「数周 + 数百次干净安装」）；**跨版本不会**（未签名文件每次更新从零重建）；**该机制不只对 OV 生效**——恰恰相反，签名才让信誉能跨版本继承 | 🔵 官方 |
| 2 | MOTW 的作用与不同获取途径的差异 | MOTW 决定是否在打开前警告（官方）；MOTW 的 exe 会被 SmartScreen 处理（MITRE）；浏览器/邮件/消息应用下载会带；局域网/UNC/SMB **不受 SmartScreen 保护**（官方）；**下载工具与网盘未找到官方说明** | 🔵 官方 + 🟡 权威第三方 |
| 3 | winget 是否绕过 SmartScreen | **降低概率但非保证**。微软仓库一手陈述「winget now skips SmartScreen for default sources」+ 官方人员确认 `--trust-level trusted`；但存在 winget 安装未签名 exe 被 SmartScreen 拦住的实测反例。**微软从未在正式文档中承诺绕过** | 🟡 仓库发言（微软方）+ 🟡 反例 |
| 3b | winget 收录门槛与个人开源可行性 | **未签名 EXE 安装器可被接受**（微软方原话："we don't require a signature in the repository here. If you have an unsigned EXE installer, that's OK."）；支持 INNO 与 ZIP；需静默安装、URL 必须是官方发布位置、通过多引擎 PUA 扫描；**个人开源项目有大量先例** | 🔵 官方 |
| 4 | Scoop / Chocolatey | Scoop：**通常不触发**（社区实测 + 机制推理：不经浏览器故无 MOTW），无官方承诺，且有反例；Chocolatey：**未找到官方说明**，且它自身会弹不受信任发布者提示 | 🟡 社区 / ⚪ 官方未找到 |
| 5 | Smart App Control | 未签名代码**默认被阻止**（三处官方文档一致），且检查**所有**可执行文件而非仅下载的；用户**能**关闭；关闭后**不能**回到 evaluation 模式；能否重新开启到 enforcement，官方文档自相矛盾 | 🔵 官方（含一处内部冲突） |
| 6 | 解压 zip / SHA256 / 下载页说明 | 解压 zip：**不可靠**（取决于解压工具，MITRE 与 SANS 证据方向相反）；SHA256：**不影响 SmartScreen**，只是完整性抓手；**下载页写清步骤：官方明确建议**，是唯一有官方背书的降摩擦手段 | 🔵 官方（步骤说明）/ 🟡 解压争议 |
| 7 | SignPath 被拒后能否重申 | **能**。拒绝邮件明确写 "you are very welcome to reapply"；条款中**无等待期、无次数上限**；但「重申成功」的先例**未找到**。门槛是外部可见度信号（stars/引用/文章/持续活跃/「a Google search clearly identifies」） | 🟡 一手邮件 + 官方条款 |

### 8.2 对本项目的具体建议（按性价比排序）

1. **把 `winget` 作为首推安装路径**。产物形态（Inno Setup exe + zip）完全在支持列表内；未签名安装器被官方明确允许；门槛是静默安装 + URL 指向 GitHub Releases 官方位置——这两点本项目应已满足（需核实 `windows/installer.iss` 的 `/SILENT` 支持与 Release 资产直链）。**这是唯一一条能实质减少「未知发布者」出现次数的路径**，但不要对用户承诺「一定不弹」。
2. **下载页/README 写清操作步骤**（微软官方建议）：说明会遇到「未知发布者」，给出「More info → Run anyway」的一步指引，并附 SHA256SUMS。这也是 SignPath 申请表要求「下载页须描述功能」的前置工作。
3. **同时提供 Scoop 渠道**（若维护成本可接受）：社区实测表明它通常不产生 MOTW。
4. **不要指望「先解压 zip」解决问题**：解压工具行为不一，写成用户指引会带来「按说明做了还是被拦」的二次摩擦。
5. **对 SAC 用户无解**：唯一出路是签名。可在 README 中说明 SAC 用户需关闭 SAC，但需注意官方文档对「能否恢复」自相矛盾，措辞应保守。
6. **为重申 SignPath 积累外部信号**：官方与社区证据一致指向「stars/引用/文章/持续活跃」而非代码质量。可执行的积累动作包括：争取第三方文章或视频提及、维护 CHANGELOG 与 release notes 证明持续活跃、在 README 中建设 "Code signing policy" 一节（申请表单要求下载页提及 SignPath）。

---

## 9. 未找到的内容

以下问题在本次调研中**没有找到**可靠来源，明确标注为「未找到」，不做推测填充：

1. ⚪ **SmartScreen 信誉放行的具体数值阈值**：微软官方明确拒绝给出（"There is no exact threshold"）。流传的任何具体下载量数字均无官方依据。
2. ⚪ **下载工具（IDM 等）下载是否携带 MOTW**：官方 Attachment Manager 页只把「第三方下载管理器」列为可能导致持续警告的因素，未给出机制说明。
3. ⚪ **网盘客户端下载是否触发 MOTW / SmartScreen**：无任何官方或权威第三方说明。
4. ⚪ **Scoop 官方关于 SmartScreen 或 MOTW 的任何声明**：Scoop 仓库讨论仅覆盖来源与哈希校验，未涉及 SmartScreen。
5. ⚪ **Chocolatey 官方关于是否绕过 SmartScreen 的任何声明**：已核对 security、moderation、FAQ、create-msi-package 四个页面，均未提及 SmartScreen。
6. ⚪ **微软官方关于「解压 zip 是否传播 MOTW」的说明**：微软文档中未找到；现有一手证据分别来自 MITRE 与 SANS（方向相反）。
7. ⚪ **SignPath 被拒后「补材料重申成功」的具体先例**：找到 6 条被拒记录，均为「计划重申」，无一条记录到成功结果。
8. ⚪ **SignPath 申请次数的系统统计或官方配额说明**：条款中无相关内容。
9. ⚪ **GitHub Artifact Attestations / Sigstore 类无 CA 签名对 SmartScreen 的影响**：无官方说明。
10. ⚪ **`SmartScreen` ADS 中 `Anaheim` 字段的确切含义**：两份来源说法相反（前 Edge 工程师博客 vs 第三方博客），本次不采信任何一方。
11. ⚪ **`winget` 跳过 SmartScreen 的官方功能文档**：仅有仓库 issue 中的陈述与团队回复，learn.microsoft.com 上未找到描述此行为的正式文档。
12. ⚪ **下载页说明是否能降低实际流失率的量化数据**：只有官方定性建议，无实测数据。

---

## 10. 参考来源

### 微软官方（learn.microsoft.com / support.microsoft.com）

1. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation — SmartScreen 信誉机制（下载量累积、未签名每版本归零、EV 2024 失效、SAC 优先于 SmartScreen）
2. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app — 首次发布预期、无签名强警告、与早期用户沟通的建议话术
3. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options — 各签名方案对比、无签名标注为强阻止、Open source: SignPath Foundation
4. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status — EV 不再即时放行（2024 变更）、ms-appinstaller 协议默认禁用
5. https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/ — SmartScreen 检查的两个信号、不保护网络共享、WDSI 误报入口
6. https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview — SAC 阻止未签名代码、两种模式、状态查看路径
7. https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/test-your-app-with-smart-app-control — SAC 模式单向切换
8. https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol — SAC 自 22H2 起、企业设备 48 小时自动关闭、注册表 VerifiedAndReputablePolicyState
9. https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/create-appcontrol-policy-for-lightly-managed-devices — ISG 预测与未签名阻止
10. https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions — SAC FAQ：未签名即拦、可关闭、可重新启用、无法针对单应用放行
11. https://support.microsoft.com/en-us/windows/security/windows-security/app-browser-control-in-the-windows-security-app — SAC 仅限新装 Win11、evaluation 模式不可回退
12. https://support.microsoft.com/en-us/windows/security/information-about-the-attachment-manager-in-microsoft-windows — MOTW 官方定义、三类来源、Unblock 步骤
13. https://learn.microsoft.com/en-us/windows/package-manager/winget/ — winget 支持的安装器格式（含 INNO/ZIP）、hash/validate 命令
14. https://learn.microsoft.com/en-us/windows/package-manager/package/repository — winget 提交与审核流程、目录结构、状态标签
15. https://learn.microsoft.com/en-us/windows/package-manager/package/windows-package-manager-policies — InstallerUrl 必须是 ISV 发布位置
16. https://learn.microsoft.com/en-us/windows/package-manager/package/manifest — winget manifest schema
17. https://www.microsoft.com/wdsi/filesubmission/ — 误报提交入口

### winget 仓库（microsoft/winget-pkgs、microsoft/winget-cli）

18. https://github.com/microsoft/winget-pkgs/issues/2701 — 微软方："we don't require a signature in the repository here. If you have an unsigned EXE installer, that's OK."
19. https://github.com/microsoft/winget-cli/discussions/4327 — 微软方："WinGet doesn't require code signing"；社区：5 个 OSS 项目均为 unsigned exe + zip
20. https://github.com/microsoft/winget-cli/issues/3111 — "winget now skips SmartScreen for default sources" + denelon 确认 `--trust-level trusted`
21. https://github.com/microsoft/winget-cli/issues/703 — winget 下载后修改安装器 zone 信息；`SEE_MASK_NOZONECHECKS`
22. https://github.com/microsoft/winget-pkgs/discussions/3335 — 反例：本地 manifest 安装 RunJS 被 SmartScreen 拦住
23. https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md — 必须静默安装、PUA 严格政策、URL 政策
24. https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md — 首次贡献 checklist、一 PR 一版本
25. https://github.com/microsoft/winget-pkgs/blob/master/doc/Authoring.md — multi-file manifest、wingetcreate
26. https://github.com/microsoft/winget-pkgs — 安装器格式 IMPORTANT 声明

### winget 反例与社区实测

27. https://github.com/vim/vim-win32-installer/issues/319 — 反例：winget 安装未签名 gvim 被 SmartScreen 拦住
28. https://www.reddit.com/r/buildinpublic/comments/1w7tcov/ — 三套系统（VirusTotal/Edge、Chrome Safe Browsing、SmartScreen 无信誉）的实测区分
29. https://github.com/shm11C3/HardwareVisualizer/blob/develop/CODE_SIGNING_POLICY.md — winget 不是签名的替代品；验证与信誉是两项独立检查

### SCOOP / Chocolatey

30. https://github.com/ScoopInstaller/Scoop/discussions/6153 — Scoop 的安全措施（未提 SmartScreen）
31. https://github.com/serjdrej/trimitdown/commit/f79a3899ae0fb64116d5bc5335693a2ac9df5849 — Scoop 安装后无 Zone.Identifier 的实测记录
32. https://github.com/leaker/pouch/commit/a38081177bd9c84c6d6b5fea1b5b464b1c5be427 — README 改为 Scoop 优先，理由是不触发 SmartScreen
33. https://windowpin.com/en/install — "Scoop and winget never touch the browser"
34. https://espanso.org/docs/install/win/ — 反例：Scoop 安装后仍可能见 SmartScreen 警告
35. https://github.com/ScoopInstaller/Main/issues/7537 — 与 SmartScreen 无关的 Defender 拦截
36. https://docs.chocolatey.org/en-us/community-repository/moderation/ — Chocolatey 审核体系
37. https://docs.chocolatey.org/en-us/information/security/ — VirusTotal、校验和、不要求包签名
38. https://docs.chocolatey.org/en-us/faqs/ — 审核与被拒包
39. https://docs.chocolatey.org/en-us/guides/create/create-msi-package/ — Chocolatey 包创建方式
40. https://github.com/chocolatey/choco/issues/3302 — Chocolatey 自身的不受信任发布者提示
41. https://github.com/chocolatey/choco/issues/1508 — 同上，历史重复
42. https://github.com/Zettlr/Zettlr/issues/473 — Chocolatey 作为绕过手段的社区经验 + 反例 + 「微软不公开下载量阈值」

### MOTW 与解压

43. https://attack.mitre.org/techniques/T1553/005/ — MOTW → SmartScreen 的处理链；解压后内部文件可能不继承 MOTW；检测项 DET0257
44. https://isc.sans.edu/diary/31732 — 反证：多数解压工具会把 MOTW 传播给解压出的文件
45. https://en.wikipedia.org/wiki/Mark_of_the_Web — MOTW 实现、非 NTFS 会剥离、相关 CVE
46. https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/ — 前 Edge 工程师：SAC 比 SmartScreen 走得更远；`:SmartScreen` ADS 与 `Anaheim`
47. https://diecknet.de/en/2024/08/30/powershell-ntfs-alternate-data-streams/ — 读取 ADS 的方法（其 `Anaheim` 含义说法与上条冲突）
48. https://github.com/citizenmatt/UnblockZoneIdentifier — Attachment Services 写入 MOTW 的机制

### SignPath Foundation

49. https://signpath.org/ — 官方首页（"No more installation warnings"）
50. https://signpath.org/terms — 官方条款（无重申限制条款、无接受义务、资格条件全文）
51. https://signpath.org/projects — 已受信项目列表
52. https://github.com/i999rri/GhosttyWin32/issues/46 — 被拒先例（含邮件原文），计划 6–12 个月后重申
53. https://github.com/nishiuriraku/easy-cursor-swap/pull/7 — 被 defer 先例，3–6 个月重申路线图，Certum OSS 备选
54. https://github.com/Arsarneq/docent/issues/72 — 被拒先例
55. https://github.com/antigerme/wilson-reborn/pull/97 — 被拒先例，改为无签名 + SHA256SUMS
56. https://www.v2ex.com/t/1218906 — 中文申请人被拒记录与门槛讨论
57. https://github.com/martymcenroe/silphe/issues/18 — 申请表单字段的一手转述
