# Windows 代码签名（SignPath Foundation）

解决「未知发布者」/ SmartScreen 拦截的正式做法：让二进制带上一个 Windows 已经信任的
Authenticode 签名。本项目走 [SignPath Foundation](https://signpath.org/) 的免费开源签名
通道 —— 它对符合条件的公开 OSS 项目免费签发，私钥存在 SignPath 的 HSM 上，不需要自己
买证书、也不需要 USB token。

> 这份文档是**待办清单**，不是已完成记录。截至写下时点，CI 接入已就绪（含手动验签开关），
> 但**申请尚未提交**，因此仓库里还没有 `SIGNPATH_*` 配置，签名步骤会被自动跳过，
> 发布流程照旧产出未签名包。

---

## 一、当前状态

| 事项 | 状态 |
| --- | --- |
| CI 签名步骤（`.github/workflows/build-windows.yml`） | ✅ 已写好，带门控，未配置时自动跳过 |
| 仓库资格（公开 / OSS 许可 / GH Actions 构建） | ✅ 满足 |
| 审核先例与门槛 | ⚠️ 无公开量化标准；已有同类项目通过（见下一节） |
| SignPath 账号与申请 | ❌ **未提交**（需要账号持有人操作） |
| 仓库 Secrets / Variables | ❌ 未配置（等申请通过） |
| SignPath 侧的 Project / 策略 / 产物配置 | ❌ 未配置（等申请通过） |

资格核对的依据：仓库 `shilonyin/Han1meWinPlus` 公开、AGPL-3.0（OSI 认可）、构建全程在
GitHub 托管的 Actions runner 上跑 —— 这三点是 SignPath 对 OSS 项目的核心要求。

### 审核标准未知，但有已通过的先例，且项目类型不是障碍

**先说事实层面能确定的部分**：SignPath Foundation 明面上只写了「公开 OSS 项目」这类条件，
**它实际用什么样的门槛去筛，公开资料里没有量化标准**。所以任何「我们能不能过」的判断
都只能是推测，不该被写成结论。

下面把这个题目里的三块材料分开摆：一份**被拒**的样本、一个**已通过**的先例、以及
**我们自己的现状数据**。

#### 一份被拒样本揭示的审核维度

一份 2026-06 被拒申请的官方回信原文，列出了它评估时看的东西：

> Community adoption (e.g., GitHub stars, forks, contributors)
> Independent references or discussions (Reddit, Stack Overflow, YouTube, etc.)
> External articles, blog posts, or institutional backing
> Evidence of sustained activity and user engagement
>
> …your project does not yet provide sufficient external verification signals for us to
> issue a Foundation certificate in our name. Please note that this is not a judgment on
> the quality or potential of your work. The Foundation program is designed specifically
> for projects that have already established a certain level of public trust and visibility.

（来源：**一份** 2026-06 被拒申请的公开记录，[v2ex.com/t/1218906](https://v2ex.com/t/1218906)）

**这是 n=1 的样本**，只能说明「外部可证实的声誉」确实是它看重的维度之一，
**不能用来估计通过率**。用它推出「我们大概率被拒」是把单点样本当成了分布。

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
**它不能证明的事**：它的体量（638 star）比我们大得多，**所以它通过不等于我们能通过** ——
它只说明「门槛存在但可达」，不说明门槛在哪。

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

#### 我们的现状（事实陈述，不是被拒的论据）

以下是本项目在写下时点的实际数据。它们**只描述现状**，不构成对审核结果的推断：

| 指标 | 本项目 |
| --- | --- |
| GitHub star | 4 |
| fork | 0 |
| 仓库年龄 | 约 1 个月（创建于 2026-09-13） |
| 累计 Release 下载 | 212（19 个版本，最多的一版 73 次） |
| 外部讨论 / 文章 / 背书 | 未检索到 |

（对照那份被拒样本的处境：回信里提到「fork 数，star 数太惨淡了」「其他社区也没有什么
公开讨论」—— 两边描述的是同一类信号的强弱，但样本量仍是 1。）

#### 如果决定申请，先把这些证据凑齐

申请表单会问「声誉证据」，能拿出下面任意几项会实质提高通过率（**这一条是推测性建议，
不是已核实的标准**）：

- 外部讨论：Reddit / 贴吧 / 论坛 / B站 / YouTube 上提过这个项目的帖子或视频（链接）
- 文章或博客介绍；任何机构、社群、Up 主的推荐
- 持续活跃的证据：issue 与 PR（哪怕是别人的）、历史版本下载量的增长
- 真实的用户反馈截图或讨论串

> 这一节的意义不是劝退，而是把「提交了但被拒」和「按标准看确实还不够」区分开 ——
> 后者不该被当成意外，也不该反复重提。**拒信允许以后再申请，所以提交本身没有代价。**

## 二、你需要做的（只有账号持有者能做）

### 0. 提交前必须满足的硬性条件（已逐条核对条款）

SignPath 的[条款页](https://signpath.org/terms)写了**申请前就必须成立**的条件，不是通过后再补。
下面是把条款逐条对照本项目的结果：

| 条款要求 | 本项目 | 状态 |
| --- | --- | --- |
| 不含恶意软件 / 潜在不受欢迎程序 | — | ✅ |
| OSI 认可许可，无商业双授权 | AGPL-3.0 | ✅ |
| 不含专有代码 | 全部源码公开 | ✅ |
| 持续维护中 | 一个月内 19 个版本 | ✅ |
| 已发布（即要签的形态已存在） | 19 个 Release | ✅ |
| 下载页说明功能 | README | ✅ |
| **下载页出现 SignPath Foundation 字样** | README 下载一节（表单 `Download URL` 的硬性要求） | ✅ |
| **主页写明「Code signing policy」** | README「代码签名政策」一节 | ✅ |
| **隐私政策** | README「代码签名政策 → 隐私政策」 | ✅ |
| **指定 Authors / Reviewers / Approvers** | README 角色表（单人项目，三角色同一人） | ✅ |
| 只签自己的项目与二进制 | 构建产物全部来自本仓库 | ✅ |
| 不修改系统配置而不告知 | 只写 `%APPDATA%` / `%LOCALAPPDATA%` | ✅ |
| 提供卸载 | 安装包自带卸载器 | ✅ |
| **所有成员启用 MFA** | GitHub 账号 | ⚠️ **请自行确认已开启两步验证** |
| **产物元数据 product name / version 一致** | `ProductName=Han1meWinPlus`、两份二进制 `ProductVersion` 相同 | ✅ |

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

## 六、如果申请被拒或不想等

- **Azure Trusted Signing** —— 约 $10/月，微软自己的可信签名，需要身份验证，能过
  Smart App Control
- **Certum Open Source Code Signing** —— 约 €30/年的 OSS 优惠 OV 证书
- **自签名** —— 免费但对分发**没用**：Windows 不信任自签根，该拦还是拦

## 七、相关文件

- 签名步骤：[`.github/workflows/build-windows.yml`](../../.github/workflows/build-windows.yml)（搜 `SignPath`）
- 安装包脚本：[`windows/installer.iss`](../../windows/installer.iss)
- 安装器选型调研：[`windows-installer-options.md`](windows-installer-options.md)
- 申请表逐字段填写清单：[`signpath-apply-checklist.md`](signpath-apply-checklist.md)
- 申请正文成文版：[`signpath-application.md`](signpath-application.md)
- 通过后的控制台配置步骤：[`signpath-setup.md`](signpath-setup.md)
