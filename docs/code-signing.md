# Windows 代码签名（SignPath Foundation）

解决「未知发布者」/ SmartScreen 拦截的正式做法：让二进制带上一个 Windows 已经信任的
Authenticode 签名。本项目走 [SignPath Foundation](https://signpath.org/) 的免费开源签名
通道 —— 它对符合条件的公开 OSS 项目免费签发，私钥存在 SignPath 的 HSM 上，不需要自己
买证书、也不需要 USB token。

> **申请已提交并被拒绝**（2026 年）。拒信理由是项目缺少外部可验证的知名度 —— 评估维度
> 包括社区采纳度、独立引用或讨论、外部文章或机构背书、持续活跃与用户参与的证据。条款中
> **没有等待期，也没有申请次数限制**，项目知名度提高后可以重申。
>
> 依据说明：拒信是 SignPath Foundation 发给申请人的**邮件通知**，本仓库不含该邮件的副本，
> 因此「已申请、被拒、理由为知名度不足」这一条是**申请人的转述**，不是仓库内可复核的物证。
> 仓库内可独立复核的只有「当前未签名」这一半（见下表）。若日后要引用本次申请结果，请以
> 申请人邮箱中的原信为准。
>
> 因此本仓库当前**没有任何签名**：所有发行产物 `Get-AuthenticodeSignature` 均为
> `NotSigned`，CI 里也没有 `SIGNPATH_*` 配置，签名步骤被门控自动跳过。
>
> 文档第二、三节保留为**重申时的操作手册**（CI 侧接入已就绪，重新获批后照做即可）；
> 第六节列出已核实过的其他途径及其排除理由。

---

## 一、当前状态

| 事项 | 状态 |
| --- | --- |
| CI 签名步骤（`.github/workflows/build-windows.yml`） | ✅ 已写好，带门控，未配置时自动跳过 |
| 仓库资格（公开 / OSS 许可 / GH Actions 构建） | ✅ 满足 |
| 审核先例与门槛 | ✅ 已明确：**卡的是外部可验证的知名度**，非资格、非项目类型 |
| SignPath 账号与申请 | ❌ **已提交，未通过**（2026 年） |
| 当前发行产物签名 | ❌ 未签名（`Get-AuthenticodeSignature` = `NotSigned`） |
| 仓库 Secrets / Variables | ❌ 未配置（无签名通道可接） |
| SignPath 侧的 Project / 策略 / 产物配置 | ❌ 未配置 |

资格核对的依据：仓库 `shilonyin/Han1meWinPlus` 公开、AGPL-3.0（OSI 认可）、构建全程在
GitHub 托管的 Actions runner 上跑 —— 这三点是 SignPath 对 OSS 项目的核心要求。

### 审核门槛：已由本项目的实际申请结果确认

**结论先说**：卡的不是资格，也不是项目类型，而是**外部可验证的知名度**。这一条不是推测 ——
本项目在 2026 年提交申请后被拒，拒信给出的正是这个理由，与下面那份被拒样本揭示的评估维度
完全一致。

下面把三块材料分开摆：**本项目自己的被拒结果**、一份**公开的被拒样本**、一个**已通过的
先例**。

#### 本项目的申请结果（第一手）

- 申请时间：2026 年
- 结果：**未通过**
- 理由：项目缺少**外部可验证的声誉信号**（external verification signals）
- 重申条件：条款中无等待期、无申请次数限制；知名度提高后可重新申请

#### 那份公开样本揭示的评估维度

同一套维度在一份 2026-06 被拒申请的官方回信原文里写得更细：

> Community adoption (e.g., GitHub stars, forks, contributors)
> Independent references or discussions (Reddit, Stack Overflow, YouTube, etc.)
> External articles, blog posts, or institutional backing
> Evidence of sustained activity and user engagement
>
> …your project does not yet provide sufficient external verification signals for us to
> issue a Foundation certificate in our name. Please note that this is not a judgment on
> the quality or potential of your work. The Foundation program is designed specifically
> for projects that have already established a certain level of public trust and visibility.

（来源：2026-06 被拒申请的公开记录，[v2ex.com/t/1218906](https://v2ex.com/t/1218906)）

这份样本与本项目的被拒结果指向同一组维度，两者的措辞几乎可以相互替换。

#### 一个已通过的先例：AniBaka

以下全部是**从它的公开仓库配置里直接读到的**，不是推测：

| 参数 | 值 |
| --- | --- |
| 项目 | `AniBakaBaka/AniBaka`（GPL-3.0，Dart/Flutter，动漫播放器，约 638 star） |
| 证书主题 | `CN=SignPath Foundation, O=SignPath Foundation, C=US, S=DE, L=Lewes` |
| Organization ID | `ad88b2e9-2cf4-4984-b56b-4f4d2e575e15` |
| Project slug | `AniBaka` |
| Artifact Configuration slug | `windows-release` |
| Signing Policy | `release-signing`（另有 `test-signing` 策略，用于自签测试证书） |
| 使用的 Action | `signpath/github-action-submit-signing-request@v2` |

它把 Organization ID 这类**非保密值直接硬编码在 workflow 里**，只有 API token 放 Secret。

它的签名链路（可作为我们的对照参考）：Fastforge 打包出 exe + msix + zip → 放进
`signpath-input/` → 上传 artifact → 提交 SignPath 签名请求（`wait-for-completion: true`）
→ 取回后用 `verify-windows-signing.ps1` 校验证书与签名，通过后才进 staging。
它还用 `windows_signing_policy` 这个手动输入选项在三档策略之间切换。

**它证明的事**：这条路是走得通的，同类项目拿到过 Foundation 证书。
**它不能证明的事**：它的体量（638 star）比我们大得多 —— 对照本项目被拒的结果，可以看出
**门槛落在知名度这一侧**，而不在资格或项目类型那一侧。

#### 项目类型不是障碍（已核对）

SignPath 的[已收录项目清单](https://signpath.org/projects)里有大量同类项目：游戏启动器
（Bloxstrap、Heroic Games Launcher、Starward、TwintailLauncher、Collapse Launcher）、
游戏工具与 Mod 管理器（Genshin FPS Unlocker、DLSS Swapper、Balatro Mod Manager、
Satisfactory Modding）、以及众多 B站 / Steam / 网易云相关的第三方客户端
（HyPlayer、Spicetify、Millennium）。清单固定展示约 300 个项目，横跨二十多个类别 ——
其中**「第三方客户端」是占比很大的一类**，这也是与本项目最接近的一类。

**从公开清单能读出的只有「这类软件没有被一刀切排除」**，至于某一类内容领域的具体项目
是否会因内容性质被拒，公开资料里没有反例也没有正例可查 —— 这一点仍是未知，不要把它
说成「已确认没问题」。清单能支持的说法只有「审核卡的更像是『有多少人能证实它在被真实
使用』，而不是『这算什么类型的软件』」。

#### 我们的现状（申请被拒的实际数据）

以下数据取自 `gh` 实测（2026-10-16），也正是被拒时项目所处的状态：

| 指标 | 本项目 |
| --- | --- |
| GitHub star | 4 |
| fork | 0 |
| watcher | 0 |
| 仓库年龄 | 约 1 个月（创建于 2026-09-13） |
| 累计 Release 下载 | 259（19 个版本，最多的一版 46 次） |
| 外部讨论 / 文章 / 背书 | 未检索到 |

（对照那份公开样本的处境：回信里提到「fork 数，star 数太惨淡了」「其他社区也没有什么
公开讨论」—— 同一类信号的强弱。）

#### 重申之前，先把这些证据凑齐

拒信与条款都没有给出量化门槛，但从评估维度反推，下列证据是直接对应的（**反推关系明确，
具体到多少才够仍是未知**）：

- 外部讨论：Reddit / 贴吧 / 论坛 / B站 / YouTube 上提过这个项目的帖子或视频（链接）
- 文章或博客介绍；任何机构、社群、Up 主的推荐
- 持续活跃的证据：issue 与 PR（哪怕是别人的）、历史版本下载量的增长
- 真实的用户反馈截图或讨论串

> 提交本身没有代价 —— 条款里没有等待期与次数限制，拒信也写明欢迎在知名度提高后重申。
> 但**在证据没变的情况下重复提交只会再收到同一封拒信**，所以重申前应当先让上面的信号发生
> 变化。

## 二、你需要做的（只有账号持有者能做）

### 0. 提交前必须满足的硬性条件（已逐条核对条款）

SignPath 的[条款页](https://signpath.org/terms)写了**申请前就必须成立**的条件，不是通过后再补。
下面是把条款逐条对照本项目的结果。**来源分两类，别混为一谈**：多数行出自[条款页](https://signpath.org/terms)；
标了「表单」的行出自申请表单里对应字段的说明文字 —— 前者是「申请前就必须成立」，后者是
「那一栏要求你填的页面长什么样」，两者都是硬性要求但出处不同：

| 要求 | 出处 | 本项目 | 状态 |
| --- | --- | --- | --- |
| 不含恶意软件 / 潜在不受欢迎程序 | 条款 | — | ✅ |
| OSI 认可许可，无商业双授权 | 条款 | AGPL-3.0 | ✅ |
| 不含专有代码 | 条款 | 全部源码公开 | ✅ |
| 持续维护中 | 条款 | 一个月内 19 个版本 | ✅ |
| 已发布（即要签的形态已存在） | 条款 | 19 个 Release | ✅ |
| 下载页说明功能 | 条款 | README | ✅ |
| **下载页出现 SignPath Foundation 字样** | 表单（`Download URL` 字段说明；字段本身非必填） | README 下载一节 | ✅ |
| **主页写明「Code signing policy」** | 条款 | README「代码签名政策」一节 | ✅ |
| **隐私政策** | 条款 | README「代码签名政策 → 隐私政策」 | ✅ |
| **指定 Authors / Reviewers / Approvers** | 条款 | README 角色表（单人项目，三角色同一人） | ✅ |
| 只签自己的项目与二进制 | 条款 | 构建产物全部来自本仓库 | ✅ |
| 不修改系统配置而不告知 | 条款 | 只写 `%APPDATA%` / `%LOCALAPPDATA%` | ✅ |
| 提供卸载 | 条款 | 安装包自带卸载器 | ✅ |
| **所有成员启用 MFA** | 条款 | GitHub 账号 | ⚠️ **请自行确认已开启两步验证** |
| **产物元数据 product name / version 一致** | 条款 | `ProductName=Han1meWinPlus`、两份二进制 `ProductVersion` 相同 | ✅ |

> 条款原文里「Specify a code signing policy」要求主页出现 **Code signing policy** 这个词，
> 并在同一处给出「Free code signing provided by SignPath.io, certificate by SignPath
> Foundation」这句原话、团队角色、以及隐私政策 —— 这三样现在都在 `README.md` 的
> 「代码签名政策」一节里。改动 README 时别把这一节删掉。

> 另外条款提到「Approvers：每次签名请求都要由团队内被信任的成员批准」，
> 以及「每个 release 都需要人工批准签名」。单人项目即由你自己批准每一次发布。

### 1. 提交申请

到 <https://signpath.org/apply> 申请 **Foundation（免费 OSS）** 计划。页面内嵌一个
HubSpot 表单，**逐字段该填什么见 [`signpath-apply-checklist.md`](signpath-apply-checklist.md)**。

表单共 20 项，几个容易踩的点先记在这里：

- **`Download URL` 有硬性要求**：表单原话 *"This page must mention that the project uses
  the SignPath Foundation for code signing."* —— 下载页必须提到 SignPath Foundation。
  `README.md` / `README.en.md` 的下载一节已补上这句，**别删**。
- **`Category` 下拉只有 10 个值**，没有「视频 / 媒体播放器」类，选 `Other`。
- **`Build System` 下拉只有两个值**：`GitHub Actions` / `GitLab CI/CD`。选前者。
- **`Tagline` 可能被公开展示**在 SignPath 官网上，写成中性准确的一句话。
- **`Reputation` 是唯一拿不出强证据的字段**，如实写 + 附上能给的量化数据，不要编。
- 表单**没有** License 字段、没有产物清单字段、没有条款自检字段 —— 那些内容只作为
  邮件追问时的备查材料留在 `signpath-application.md` 第 14 节。

审核是人工的，通过后会给你一个 SignPath **Organization**。

### 2. 建好 SignPath 侧的四样东西

登录 SignPath 控制台，在新建的 Organization 里：

1. **Project** —— 记下它的 *slug*（AniBaka 用的是 `AniBaka`，即与仓库名同名）
2. **Trusted Build System** —— 选预置的 *GitHub.com*，链接到上面的 Project
   （这一步让 SignPath 认可「产物确实由本仓库的 Actions 构建」，是免费签名能成立的前提）
3. **Artifact Configuration** —— 见下面第三节，**根元素要用 `<zip-file>`**
   （AniBaka 把它的 slug 取作 `windows-release`，含义是「面向 Windows 发布的产物集」）
4. **Signing Policy** —— 绑定 Foundation 证书，例如 slug 取 `release-signing`
   （AniBaka 就是 `release-signing`，另配了一个 `test-signing` 用于自签测试证书）

### 3. 把四个值填进 GitHub

仓库 → Settings → Secrets and variables → Actions：

**Secrets**（保密，申请后不可再读出）：

| 名称 | 值 |
| --- | --- |
| `SIGNPATH_API_TOKEN` | 在 SignPath 里为 CI 建一个用户，生成 API token |

**Variables**（非保密）：

| 名称 | 值 |
| --- | --- |
| `SIGNPATH_ORGANIZATION_ID` | 组织 id（GUID） |
| `SIGNPATH_PROJECT_SLUG` | 第 2 步的 Project slug |
| `SIGNPATH_POLICY_SLUG` | 签名策略 slug，`release-signing` |
| `SIGNPATH_ARTIFACT_SLUG` | 产物配置 slug，可参考 AniBaka 的 `windows-release` |

**填完 `SIGNPATH_API_TOKEN` 的那一刻签名链路就启用了** —— 这正是指令里那个门控条件。
四个 Variables 缺任何一个都会让 SignPath 那一步报错，所以确认要一次填齐；但**它们不启用
链路**，只填 Variables 不会触发签名。

## 三、Artifact Configuration 该怎么写

CI 把两个 exe 放在**同一个** artifact 里上传（SignPath 一次请求只签一个 artifact）：

- `Han1meWinPlus-Setup.exe` —— 安装包，用户双击的就是它
- `han1me_win_plus.exe` —— 主程序，免安装版解压后直接运行它

`actions/upload-artifact` 默认会打成 zip，所以根元素是 `<zip-file>`，在里面按文件名分别
声明 `<pe-file>`。大致形状（具体语法以 SignPath 控制台里的模板为准）：

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <zip-file>
    <pe-file path="Han1meWinPlus-Setup.exe">
      <authenticode-sign />
    </pe-file>
    <pe-file path="han1me_win_plus.exe">
      <authenticode-sign />
    </pe-file>
  </zip-file>
</artifact-configuration>
```

> Inno Setup 的 `SignTool` 指令是另一条路（编译期签，能连卸载器一起签上）。本项目**没有**
> 走它，原因是它需要本地 `signtool` + 证书文件，而 SignPath 是托管的 HSM，不给导出私钥。
> 两者选一即可，不要同时配 —— 那会导致安装包被签两次或两次签名互相覆盖。
>
> 我们的方案是 **CI 侧签名（非编译期）**：编译产出未签名的 exe，打包之后再把产物交给
> SignPath 签，签完放回原位。这与上面 AniBaka 的做法一致 —— 它同样是先用 Fastforge
> 打包出 exe/msix/zip，再走 `signpath/github-action-submit-signing-request@v2` 提交签名。
> 所以「CI 侧 Action 签名」不是我们退而求其次的将就，而是同类项目已经在用的常见形态。

## 四、接上之后会发生什么

打 tag 发布时，CI 的顺序变成：

1. 构建 → 出安装包和免安装压缩包
2. 把两个 exe 上传成一个 artifact
3. 提交给 SignPath 签名，等它完成，取回签好的文件
4. **按文件名**把签好的 exe 放回原位
5. **重新打免安装压缩包**（原来那次是在签名之前打的，里面还是未签名的 exe）
6. **重算 `SHA256SUMS.txt`**（签名改变了字节流，不重算用户核对必然对不上）
7. 用 `Get-AuthenticodeSignature` 校验，**签名无效就直接 fail，不让未签名的包发出去**
8. 创建 Release

第 5、6、7 步是接入时最容易漏的地方，改动里都留了注释说明原因。

## 五、验证签名是否真的生效

用户侧最简单的检查：右键 exe → 属性 → 数字签名，签名者应显示 SignPath Foundation。

命令行：

```powershell
Get-AuthenticodeSignature .\Han1meWinPlus-Setup.exe |
  Select-Object Status, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

`Status` 为 `Valid` 才算成功。`UnknownError` / `NotSigned` 表示没签上。

## 六、申请被拒之后的其他途径

以下每一条的价格都取自**本次实际打开的官方页面原文**，不是二手估算或训练数据里的旧价。
完整来源清单（含每条 URL 与官方/二手/过时标注）见
[`research/code-signing-options.md`](research/code-signing-options.md)。

**物证留存情况（如实说明，勿高估）**：仓库内留有原始页面副本的**只有 Microsoft / Azure 那
一部分** —— `docs/research/_sources/` 下 28 份文件（官方 learn 页面 markdown、定价页 HTML、
零售价 API JSON）。Certum、SSL.com、OSSign、DigiCert、GlobalSign、沃通这几家的核实过程记在
`docs/research/notes/` 的六份取证笔记里（含引用的原文句子与 URL），**未留存原始页面副本** ——
这些站点价格与条款变动频繁，要复核请照笔记里的 URL 重取。

### 6.1 可行

| 途径 | 到手成本（1 年，官方价） | 说明 |
| --- | --- | --- |
| **Certum Open Source Code Signing in the Cloud** | **€49** | **首选**。官方明文 `Open Source Code Signing are issued only for individuals`，组织字段填 `Open Source Developer`；云端交付，无需硬件、无跨境寄送。每月 5000 次签名上限，证书 459 天后需重签发，不得用于商业分发软件 |
| Certum Open Source Code Signing set（实体卡版） | €69 + 运费 €35 = **€104** | 同样只发给自然人，加密卡与读卡器含在 €69 内。代价是跨境寄送（官方配送表逐字含 `China €35.00`）、卡不可退、可能产生关税 |
| SSL.com IV（Individual Validation） | **$129** | 官方写 `Business entity required: No`，面向 `Independent developers, open source maintainers`。**下单前须确认是否强制搭配 $379 的硬件令牌** —— 若强制，实际首年成本是 $508 |
| OSSign（`ossign.org`） | **€0** | 除 SignPath 外唯一找到的免费同类计划，但**当前暂停受理**（`Applications are currently suspended due to a high workload and large backlog`），且要求 6 个月以上活跃度；运营方身份未公开，信任锚在该组织而非项目方 |

### 6.2 已排除

| 途径 | 排除理由 |
| --- | --- |
| **EV 档（任何 CA）** | Microsoft 官方文档明写 `EV certificates no longer bypass SmartScreen`、`Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified`。OV 与 EV 在 SmartScreen 上待遇已趋同（`Same as OV since 2024 — no longer instant bypass`），多付钱没有额外收益 |
| **Azure Trusted Signing** | Microsoft 官方表格 `Individuals: USA and Canada only` —— 中国大陆个人不可用；且 2025-04-02 起个人开发者 onboarding 本身已暂停 |
| **DigiCert** | 官方配置器的 Validation 维度只有 OV / EV，**没有个人档**；`Starting at $44 / month / certificate` |
| **GlobalSign** | 区域选项以公司法定注册地为据，列表无中国大陆，且官方明文 `Tokens will not be shipped outside of the Region you select`；OV 标价 $529/年 |
| **中国国内 CA**（沃通、上海 CA 等） | 证书组织字段必须填营业执照上的中文名称 —— 沃通官方原文 `中文版的软件发行商名称为公司中文名称,也就是营业执照上的中文名称`，个人过不了主体资格 |
| **自签名** | 免费但对分发**没用**：Windows 不信任自签根，该拦还是拦 |

### 6.3 收益预期要调低

**任何证书都不能消除首次下载时的 SmartScreen 警告。** 官方口径是靠时间与下载量累积信誉
（`several weeks and hundreds of clean installs`）。付费证书买到的是「发布者身份可验证」——
把「未知发布者」换成可识别的名字，这与 SignPath 免费证书的收益完全相同。

> 顺带纠正一条常见误解：CA/B Forum 自 2023-06 起要求 **OV 的私钥也存于 HSM / 硬件令牌**，
> 所以「买 OV 可以省掉硬件」也是错的。免硬件的唯一路径是云端签名服务（如 Certum 的
> in the Cloud 档或 SSL.com 的 eSigner）。

## 七、相关文件

- 签名步骤：[`.github/workflows/build-windows.yml`](../../.github/workflows/build-windows.yml)（搜 `SignPath`）
- 安装包脚本：[`windows/installer.iss`](../../windows/installer.iss)
- 安装器选型调研：[`windows-installer-options.md`](windows-installer-options.md)
- 申请表逐字段填写清单：[`signpath-apply-checklist.md`](signpath-apply-checklist.md)
- 申请正文成文版：[`signpath-application.md`](signpath-application.md)
- 通过后的控制台配置步骤：[`signpath-setup.md`](signpath-setup.md)
