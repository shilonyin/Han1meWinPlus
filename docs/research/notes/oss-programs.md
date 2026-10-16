# 除 SignPath Foundation 之外的开源代码签名计划调研笔记

调研时点：2026-10。取证方式：`Invoke-WebRequest` 直取页面（含 SPA 的 JS bundle 文本提取）、`https://html.duckduckgo.com/html/?q=` 搜索、RDAP 域名注册信息查询。
来源标注约定：**【官方】**= 该组织/CA 官网原文；**【二手】**= 第三方目录站、经销商或评测转述。

---

## 1. 结论速览

| 计划 | 性质 | 是否对个人开放 | 当前可否申请 | 来源性质 |
|---|---|---|---|---|
| **OSSign**（ossign.org） | 免费（由 OSSign 自有证书代签） | 面向开源项目，不要求个人真实姓名上证书 | **暂停受理** | 【官方】 |
| **Certum Open Source Code Signing** | 付费折扣档（非免费） | **仅面向自然人** | 可购 | 【官方】 |
| SSL.com | **不存在** OSS 计划 | — | — | 【官方】核查后否定 |
| DigiCert | **不存在** OSS 计划（只开源自家工具） | — | — | 【官方】核查后否定 |
| SignPath Foundation | 免费（用户已被拒，作为基准对照） | 面向项目 | 用户已被拒 | 已有背景 |
| Sigstore / Fulcio | 免费签名，**但不产生 Windows 信任签名** | — | 不适用于本场景 | 【二手】 |
| Azure Trusted Signing | $9.99/月起，非 OSS 计划 | **个人仅限 USA / Canada** | 大陆个人不可用 | 【官方】 |

→ 对「存在其他OSS计划」这条判断：**成立，但可用性很差**。除 SignPath 外确实存在至少一个同类组织（OSSign），但它**当前暂停受理申请**；另一个可用的开源折扣渠道（Certum OSS）是**付费**而非免费。

---

## 2. OSSign（`https://ossign.org/`）—— **【官方】**

### 2.1 取证方式说明

`https://ossign.org/` 是一个 React SPA（原始 HTML 仅 1578 字节，`<div id="root">` 空容器），正文全部打包在 `/assets/index-D2_uN95z.js`（356013 字节）中。本节所有引文均从该 JS bundle 的字符串常量中提取。

### 2.2 定位与机制

- 站点标题：`OSSign - Code Signing for Open Source`
- meta description：`OSSign provides free code signing for qualifying open source projects and affordable certificate solutions for indididuals and businesses.`（原文拼写即如此，`indididuals` 为原站笔误）
- 首页原文：`Free signatures for open source projects`、`Apply for Free Signing`
- 机制：**由 OSSign 用自己的证书代签**，不是把证书发给项目方。FAQ 原文：
  > `Do I have to put my personal name on the certificate?`
  > `No, since we sign the binaries with our certificates your real name does not have to appear anywhere on the certificate, signature or binary if you do not want it to.`
- 另有付费延伸：`* EV certificates and attestation signing available for select projects where necessary. Contact us for more information.`

### 2.3 当前状态：**暂停受理**（对用户最关键的一条）

申请页原文（醒目提示框）：

> `Applications are currently suspended due to a high workload and large backlog while we focus on assessing and responding to the applications in the queue. Please check back in a few weeks.`

联系页原文补充：

> `You can still contact us about ongoing applications or general questions, but the response time might be longer than usual.`
> `We are not accepting applications for code signing through this contact form`

### 2.4 资格要求（申请页原文）

| 要求 | 原文 |
|---|---|
| 许可证 | `The majority of your project must be published under an OSI-approved open source license (MIT, Apache, GPL, etc.). All the code included in the final release must be available for public review.` |
| 活跃度 | `Your project should be actively maintained and have a demonstrable user base or community.` |
| **账号年限（硬门槛）** | `There is an absolute minimum of 6 months of activity on your account, organization and project. This also applies to forks of existing projects where the forking user or organization was not active for at least 6 months in the original development of the project.` |
| 构建流水线 | `Your repository needs to have a build pipeline configured, where the entire build process is clearly verifiable and the source for each build is directly linked to the resulting release binaries. This pipeline should include code quality checks.` |
| 商业项目 | `The primary focus of OSSign is to provide code signing for projects and developers that volunteer their time and create free software for other users. We are able to consider providing signatures for projects of a commercial nature with an open source license, but we do have some requirements around this.` |
| 排除项 | `Political or controversial projects` — `We are not able to provide signatures to software or other tools that have a clear political or controversial purpose. This includes, but is not limited to, tools used primarily for offensive security research.` |

**注意 6 个月门槛**：本项目仓库创建于 2026-09-13（见 `docs/code-signing.md` 背景），到 2026-10 时点**不足 6 个月**。即使 OSSign 恢复受理，按此条也暂不符合。

### 2.5 运营方可信度（**须在报告中提示风险**）

RDAP 查询 `ossign.org`（`https://rdap.org/domain/ossign.org`，HTTP 200）：

| 字段 | 值 |
|---|---|
| 注册时间 | `03/11/2025 09:25:08` |
| 到期时间 | `03/11/2027 09:25:08` |
| 最后变更 | `08/12/2026 09:51:02` |
| 状态 | `client transfer prohibited` |
| 注册商 | `Hosting Concepts B.V. d/b/a Registrar.eu`（handle 1647） |
| 注册人信息 | **未公开**（whois 隐私保护，RDAP 未返回注册人实体） |

→ **该域名 2025 年 3 月才注册，运营方身份在公开注册信息中不可见，页面上也没有可核验的法人主体、基金会背景或审计信息。** 报告中应如实提示：这是一个新兴的、背景不透明的服务，其「用自有证书代签」的模式意味着**签名信任锚在 OSSign 而非项目方**，一旦其证书被吊销或服务终止，已签名版本的信任链随之失效。**未找到**任何第三方对其资质的独立评价。

### 2.6 名称易混淆提示

`https://github.com/OSSign/OSSign` 是**另一个东西**：一个用 Go 写的跨平台代码签名 CLI（`About: Open Source cross-platform code signing`，`AGPL-3.0 license`，`OSSign CLI An easy to use CLI code signing tool based on Relic`，支持 `PE/COFF MSI JAR APK DMG`）。它与 `ossign.org` 的免费代签服务**不是同一项服务**，报告中不应混为一谈。

---

## 3. Certum Open Source Code Signing —— **【官方】**（付费折扣，非免费）

严格说这不是「免费计划」，但它是**唯一一个面向个人的开源折扣档位**，且价格远低于商业 OV 档，因此纳入本节。详细价格与资格见 `certum.md`，此处只列与「开源计划」相关的要点：

- 官方支持文档原文：`Open Source Code Signing are issued only for individuals`、`Organization field will be set to „Open Source Developer"`
- 商业用途限制原文：`If Certum determines that the certificate is being used to sign software distributed commercially, the certificate will be revoked.`
- 需提供：`website address of the ongoing Open Source project: ... If Certum is unable to identify the project based on publicly available information, the certificate will not be issued.`
- 价格：set €69 / in the Cloud €49 / code €25（官方页，详见 `certum.md`）

**【二手】旁证**（`https://my-ssl.com/learn/open-source-code-signing-certificate`，经销商站）：该页称 `My-SSL sells Certum's Standard and EV code signing certificates, not the Open Source tier, which Certum sells directly.`，并给出自家 Certum 标准档 **$99 / year** 的报价；同页描述 Certum 开源档的云端交付为 `You install the free SimplySign and SimplySign Desktop apps, and sign with Microsoft's free SignTool. There's nothing physical to order`。**该 $99 是经销商自家标准档价格，不是 Certum 官方开源档价格，不可混用。**

---

## 4. 已核查并**否定**的候选

| 对象 | 核查结论 | 依据 |
|---|---|---|
| **SSL.com** | 无开源计划 | 站内搜索 + FAQ + 59 条站内链接全扫，无 open-source/oss/nonprofit 条目（详见 `sslcom.md`） |
| **DigiCert** | 无开源签名计划 | `https://www.digicert.com/insights/open-source` 的内容是开源自家 TrustCore SDK 与 DCV 库，不是发证书（详见 `big-three.md`） |
| **Sigstore / Fulcio** | **不适用于 Windows 桌面应用签名** | 【二手】`https://comparecheapssl.com/free-code-signing-certificate-and-how-to-get-it/` 原文：`it does not produce signatures that Windows SmartScreen trusts for .exe, .dll, .msi, or oth`[er]；同页：`Fulcio's root isn't in the Microsoft Trusted Root Program, and the signature sits in a separate bundle file Windows never opens.` |
| **Azure Trusted Signing** | 不是 OSS 计划，且**大陆个人不可用** | 【官方】`https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options` 表格原文：`Azure Artifact Signing (formerly Trusted Signing) | ~$9.99/month | Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only` |

---

## 5. 目录站线索（未能取到完整内容）

| 站点 | 情况 |
|---|---|
| `https://www.ossperks.com/programs/signpath` | 目录站，可正常打开（正文 2810 字符），但收录内容**只有 SignPath 一家**的 code signing 条目；`https://www.ossperks.com/programs` 列表页为 JS 渲染（正文仅 713 字符），**未取到完整计划清单** |
| `https://foropensource.com/company/certum/`、`https://foropensource.com/company/signpath/` | 第三方目录站，属**【二手】**，本轮未逐页核实 |

→ 除 OSSign 外，**未找到**其他同类组织。搜索多轮（`free code signing certificate for open source projects program`、`"open source" code signing certificate discount CA program 2026`、`DigiCert open source code signing program free`、`GlobalSign open source code signing program`、`Sectigo open source code signing discount`）返回的候选**全部**是：SignPath、OSSign、Certum OSS、以及第三方评测/经销商页。

---

## 6. 三问逐答（针对「其他 OSS 计划」这一类）

- **个人（非公司实体）能否申请？** **能。** OSSign 面向项目而非公司，且明确允许签名中不出现个人真名；Certum OSS 档更是**只发给自然人**。两者都不要求企业实体。
- **中国大陆居民能否申请？** **未找到**任何一方对中国大陆申请人的明确表述。OSSign 是纯线上流程（无实体硬件），理论上无跨境寄送问题；Certum OSS 档的配送与费用见 `certum.md`（含 China €35.00 运费条目）。
- **隐藏成本？** OSSign 名义免费，但**隐性代价是信任锚归属**——证书签发给 OSSign 而非项目方，且其运营方背景不透明；Certum OSS 档的隐藏成本是硬件/运费（set 版）或每月 5000 次签名上限（云端版），详见 `certum.md`。

---

## 7. 来源清单

| URL | 性质 |
|---|---|
| `https://ossign.org/` 及其 JS bundle `/assets/index-D2_uN95z.js` | 【官方】OSSigN 站点全部文案（正文为 SPA，从 bundle 提取） |
| `https://rdap.org/domain/ossign.org` | RDAP 域名注册数据（注册时间、注册商、隐私状态） |
| `https://support.certum.eu/en/code-signing-required-documents/` | 【官方】Certum 开源档资格 |
| `https://www.ssl.com/?s=open+source` | 【官方】SSL.com 站内搜索（用于否定 OSS 计划） |
| `https://www.digicert.com/insights/open-source` | 【官方】DigiCert 开源页（用于否定 OSS 计划） |
| `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options` | 【官方】Microsoft，Azure Trusted Signing 地区限制 |
| `https://my-ssl.com/learn/open-source-code-signing-certificate` | 【二手】经销商评测 |
| `https://comparecheapssl.com/free-code-signing-certificate-and-how-to-get-it/` | 【二手】评测（Sigstore 不适用于 Windows 签名） |
| `https://www.ossperks.com/programs/signpath` | 【二手】目录站（仅收录 SignPath） |

## 8. 未找到项

- OSSign 的运营方法人主体、资金来源、第三方审计或用户评价 —— **未找到**
- OSSign 恢复受理申请的时间表（官方只说 `Please check back in a few weeks.`）—— **未找到**
- OSSign 是否接受中国大陆申请人 —— **未找到**
- ossperks.com 上是否存在除 SignPath 外的其他 code signing 计划 —— **未取到完整清单**
- 除 OSSign 外是否还有其他「以自有证书代签」的非营利组织 —— 多轮检索**未找到**
