# Azure Trusted Signing（现名 Azure Artifact Signing）可行性调研

**调研对象**：微软 Azure Trusted Signing（2026 年官方文档中已更名为 **Azure Artifact Signing**）作为代码签名方案的可行性。

**申请者画像**：中国大陆的个人开发者，维护一个开源的 Windows 桌面应用（Flutter、GitHub 公开仓库、AGPL-3.0、个人维护、无公司实体、无营业执照）。此前申请 SignPath Foundation 免费开源签名被拒。分发方式为 GitHub Releases，产物为 Inno Setup 单文件安装包 exe + 免安装 zip。

**本轮抓取时间**：2026-10-16（下文所有「官方文档已确认」均指该时点抓取到的页面内容）。

**阅读约定**：
- ✅ **官方文档已确认** = 内容来自微软官方站点（learn.microsoft.com / azure.microsoft.com / techcommunity.microsoft.com 微软官方博客 / prices.azure.com），本轮实际抓取。
- 💬 **社区转述 / 个人经验** = 来自第三方博客、社区论坛、Microsoft Q&A 的普通用户帖（Q&A 上微软员工的回复单独标注）。
- ❌ **未找到** = 本轮抓取范围内没有可打开的来源，不做推测。

---

## 结论速览（面向该申请者）

| 问题 | 结论 | 可信度 |
| --- | --- | --- |
| 中国大陆个人能否注册使用 | **不能。** 官方文档一致要求 Public Trust 证书的个人开发者必须位于**美国或加拿大**；中国大陆不在任何一份官方列表内 | 高（三份官方文档一致） |
| 是否有个人成功案例 | 有，但**全部早于 2025-04-02**。中国大陆个人用身份证通过验证的教程停留在 2025-02 | 中（社区单一来源） |
| 2025-04-02 起的政策 | 微软官方博客宣布**暂停个人开发者 onboarding**，新客户订阅仅限「美国/加拿大、且有 3 年以上可验证历史的组织」 | 高（微软官方博客原文） |
| 2026 年是否恢复 | **未找到**任何微软公告宣布个人 onboarding 恢复或地理范围扩大。本轮（2026-10-16）抓取到的官方快速入门仍写个人限美加 | 中（以最新文档倒推，非正面声明） |
| SmartScreen 是否立即信任 | **否。** 官方明确写「Artifact Signing 不提供即时 SmartScreen 信任」，与 OV 证书同一套声誉积累模型 | 高（官方原文，且与社区说法相反） |

**对该申请者的直接判断**：以当前官方文档为准，Azure Artifact Signing 的 Public Trust 路径对「中国大陆个人开发者」**不可用**，且这不是需要准备材料就能绕过的门槛——地理限制写在资格层，且 2025-04-02 起个人通道本身处于暂停状态。下文第 3 节给出全部依据，第 9 节给出替代方向。

---

## 1. 当前定价

### ✅ 官方文档已确认

**基础价格与配额**（来源：<https://azure.microsoft.com/en-us/pricing/details/artifact-signing/>，本轮抓取页面源码，价格数据在 `data-amount` 属性中，所有区域取值一致）：

| 项目 | Basic | Premium |
| --- | --- | --- |
| 月费（Base price, monthly） | **9.99 USD** | **99.99 USD** |
| 配额（Quota, signatures/month） | **5,000** | **100,000** |
| 超出配额后单价（Price after quota is reached） | **0.005 USD / 签名** | **0.005 USD / 签名** |
| 包含（Includes） | Public / Private 各 1 个证书配置文件类型 | Public / Private 各 10 个证书配置文件类型 |

**计费规则**（同一页面 FAQ 区）：
- 服务在你**创建 Artifact Signing 账户时立即开始计费**，与你何时开始实际使用无关。
- 定价**不按比例（not pro-rated）**：账单按你创建账户时选择的 SKU 全额开具。
- 免费、试用或赞助（sponsored）Azure 订阅**不支持**该服务；必须有付费订阅（即用即付或企业协议）。（来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>，原文 "No. Artifact Signing doesn't support free, trial, or sponsored Azure subscriptions."）
- 签名配额**跨证书配置文件统一计算**（FAQ 原文："The signing quota encompasses all signing activities across any certificate profile..."）。

### ✅ 两处官方来源交叉验证（一致）

同一服务的两个微软官方渠道给出的价格**完全一致**：

| 来源 | Basic 月费 | Premium 月费 | 超额单价 | 抓取方式 |
| --- | --- | --- | --- | --- |
| Azure 定价页 <https://azure.microsoft.com/en-us/pricing/details/artifact-signing/> | 9.99 USD | 99.99 USD | **0.005 USD** | 页面源码 `data-amount` 属性（全区域一致） |
| Azure 零售价 API <https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')> | 9.99 USD | 99.99 USD | **0.005 USD** | API JSON 原值，`meterName = Signature Overage`，`meterId = 98b223e3-4e0f-5b59-b57f-5c157d6aaaec`，`effectiveStartDate = 2024-06-01T00:00:00Z`，`unitOfMeasure = 1/Month` |

API 原始响应存盘于 `docs/research/_sources/azure-retail-prices-signing.json`，可重跑复核。

> **一处需要提醒的坑**：用 PowerShell `Format-Table` 直接打印 `unitPrice` 时，`0.005` 会被**显示成 `0.01`**（列宽/小数位舍入），据此曾误判为「两个官方来源冲突」。改为读取 JSON 原值（`ConvertTo-Json`）后连续三次调用均返回 `0.005`。**价格数字不要经 `Format-Table` 读取。**
>
> 另有两点官方表述需要并列，不做调和：
> - 定价页 FAQ 写「不按比例计费（not pro rata）……账单按创建账户时选择的 SKU 全额开具」；
> - 而零售价 API 的 `unitOfMeasure` 写作 `1/Month`、`unitPrice` 为月价。二者描述的是同一件事的两个侧面（月费按月全额），本报告如实并列。

**未找到**：官方渠道没有给出**最低消费**或**年付/年度承诺**的条款；定价页 FAQ 只说明「不按比例、创建即全额计费」。（未找到 ≠ 不存在，仅表示本轮抓取范围内没有可打开的来源写明这些条款。定价页本身有通用免责声明「Prices are estimates only and are not intended as actual price quotes」。）

---

## 2. 资格要求

### ✅ 官方文档已确认

**是否必须是注册公司 / 企业实体？—— 不是。服务本身设计了个人开发者通道，但地理上受限。**

官方快速入门把身份验证分成两条独立路径：**Organization（组织）** 与 **Individual Developer（个人开发者）**。（来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>，章节 "Identity Validation - Individual Developer"）

个人路径的资格约束（quickstart 原文）：
- 必须使用**付费 Azure 订阅**（免费/试用/赞助订阅被拒）。
- 关联的 Azure **计费账户（billing account）账户类型必须为 Individual**。
- 计费账户上的**法定姓名（legal name）与 sold-to 地址必须与政府签发身份证件上的信息一致**；证书使用者（subject）会取用这些信息。
- 该「账户类型必须为个人」的要求**只适用于个人身份验证**；组织身份验证不要求计费账户类型为「组织」。

**证书类型与身份验证路径的对应关系**（quickstart）：
- Public 身份验证 → 仅适用于 Public Trust、Public Trust Test、VBS Enclave 证书配置文件类型。
- Private 身份验证 → 仅适用于 Private Trust、Private Trust CI Policy；且**专用身份验证仅限组织**。

**地理限制**（quickstart 原文；下文「本轮抓取到的版本」指 2026-10-16 抓取的留档 `_sources/learn-artifact-signing-quickstart.md`）：
> Public Trust certificates are available to organizations in the United States, Canada, the European Union, the United Kingdom, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway, and Israel. **Individual developers must be located in the United States or Canada.** These geographic restrictions do not apply to Private Trust certificates.

同一限制在另一份官方文档中以对比表形式重复（来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>）：
> Azure Artifact Signing (formerly Trusted Signing) — Availability: **Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only**

**其他资格相关约束**：
- **不支持免费、试用或赞助订阅**（FAQ）。
- **CN / O 不可自定义**（FAQ 原文："No, you can't use a custom Common Name (CN) or a custom Organization (O) with Artifact Signing."）。证书 CN 必须是经微软验证的法定实体名。
- 公钥证书的 OU 字段**仅** Private Trust / Private Trust CI Policy 可用，Public Trust 不可加 OU（FAQ）。
- 身份验证请求**不能加急**（FAQ 原文："Identity validation requests can't be expedited."）。

### 💬 社区转述 / 个人经验

- 第三方教程（2025-02-13）记录了当时个人开发者通道的实际操作：准备**身份证**即可，表单「除选择的国家和省份外全部使用中文」，且明确提到「英文我们也试了无法通过」。（来源：<https://sign.94xy.com/trusted-signing/>）
- 同一教程称组织验证要求「公司已经成立 3 年以上」并需要域名，中国企业还需邓白氏码（DUNS）；且「起初他们连中国营业执照都不认可」，来回沟通小半个月才通过。（同上 URL）——**这条与微软官方博客对组织资格的描述（美国/加拿大组织 + 3 年历史）在「3 年历史」上吻合，但 DUNS 与中国营业执照的细节属社区经验，官方文档未确认。**

---

## 3. 中国个人是否可用（本调研的核心问题）

### ✅ 官方文档已确认

**1）支持的国家/地区列表中不含中国大陆。**

- 组织可用范围：United States, Canada, European Union, United Kingdom, Australia, New Zealand, Japan, South Korea, Singapore, Switzerland, Norway, Israel。
- 个人开发者可用范围：**United States 或 Canada**。
- 来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>（本轮抓取时间为 **2026-10-16**；此处**不主张**页面自身的最后更新日期——该日期在留档文件中未获证实，报告早前版本曾写成一个具体日期，已更正）

**2）身份验证页面上的国家/地区下拉列表只列出受支持地区，且不可手工填写。**

FAQ 原文把「下拉列表里没有我的国家/地区」直接指向 onboarding 前置条件（pre-requisites）：
> What if my country/region isn't listed in country/region drop-down list on the Identity validation page? — Check Pre-requisites to get the list of supported countries/regions for onboarding.
> 来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**3）身份验证的具体流程与所需证件**（quickstart，"Identity Validation - Individual Developer"）：

| 环节 | 官方要求 |
| --- | --- |
| 触发入口 | Azure 门户 → Artifact Signing 账户 → Identity validations → 选 Organization → 下拉选 **Individual** → New identity → **Public** |
| 前置角色 | 账号需被分配 **Artifact Signing Identity Verifier** 角色，否则「新建身份」按钮灰显 |
| 表单字段 | 名字、姓氏（须与政府签发证件完全一致）；主电子邮件（须与登录 Microsoft 账户的邮箱一致）；街道、城市、国家/地区、州/省、邮政编码（按政府签发身份证件、水电费账单或银行账单上的地址填写） |
| 证书使用者预览 | 城市、州/省、国家/地区会显示在证书上；**电子邮件与街道地址不包含在证书中** |
| 实际验证方式 | 走 **Microsoft Verified ID** 流程，由第三方验证方 **AU10TIX** 执行（页面提示 "Authenticate through our trusted ID verifier"） |
| 接受的证件类型 | 政府颁发的 ID，如**护照、驾驶执照或身份证**（或美国社会保障卡）。官方明确禁止提交私人机构证件（图书卡、学校 ID、俱乐部会员卡等） |
| 补充文档 | 若没有银行账单或水电费账单上的地址，官方要求**务必使用带地址信息的政府签发身份证件**；补充文档接受近三个月内的水电费账单（电/水/气/电话）或显示个人地址的银行/信用卡账单 |
| 计费账户 | 账户类型必须为 Individual，法定姓名与 sold-to 地址须与政府签发 ID 一致 |
| 耗时 | **1 至 20 个工作日**（原文：Processing your identity validation request takes from 1 to 20 business days，如需补充材料可能更长） |
| 尝试次数 | 最多 **3 次**；用尽后官方明确「无法继续 onboarding」 |
| 可否加急 | 不可以 |

来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart> 与 <https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

### ✅ 官方公告（微软官方博客）：2025-04-02 起暂停个人开发者 onboarding

微软安全博客《Trusted Signing Public Preview Update》（2025-04-02，作者 IanMcMillan_MSFT）原文：
> The limit in new customer subscriptions for Trusted Signing will take effect **Wednesday, April 2, 2025**, and make the service only available to **US and Canada-based organizations with 3 years or more of verifiable history**. **Onboarding for individual developers and all other organizations will not be directly available for the remainder of the preview**, and we look forward to expanding the service availability as we approach GA.
> Note that this announcement does not impact any existing subscribers of Trusted Signing.

来源：<https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713>

### 💬 社区转述 / 个人经验

**（a）微软员工与志愿者版主在 Q&A 上的确认（2025-04）**

Microsoft Q&A 帖「How do I do Trusted Signing identity verification as an individual developer?」中，微软志愿者版主 SrideviM 于 2025-04-09 两次回复同一段文字：
> As of April 2, 2025, Microsoft has limited new customer subscriptions for Trusted Signing during its public preview phase. This change restricts the service's availability to U.S. and Canada-based organizations with at least three years of verifiable history. Consequently, **individual developers outside these regions cannot onboard during this period.**
> Existing subscribers can continue using the service.

同一帖中微软员工 Meha-MSFT 直接给出上述官方博客链接作为答复。
来源：<https://learn.microsoft.com/en-us/answers/questions/2238411/how-do-i-do-trusted-signing-identity-verification>

**（b）2026 年仍有个人开发者被地理限制挡住**

Q&A 帖「Can't create a new Trusted Signing Individual identity because my country is not available」（2026-03-06）：一位法国个人开发者报告国家/地区下拉只有 4 个可选国家，且无法手工填写。该帖被作者采纳的 AI 回答称：
> For individual developers, onboarding has been limited further during the public preview. A recent update states that the service is now restricted to new customer subscriptions from organizations based in the United States and Canada with at least three years of verifiable history, and **individual developer onboarding has been paused**.

来源：<https://learn.microsoft.com/en-us/answers/questions/5810735/cant-create-a-new-trusted-signing-individual-ident>
（注意：这是 Microsoft Q&A 上的 **AI 生成回答**，非微软官方声明，仅作旁证。）

**（c）即使在美国，个人验证也可能被 AU10TIX 卡住**

Q&A 帖「Azure Artifact Signing individual identity verification blocked after AU10TIX license and selfie check」（2026-07-29）：一位**美国**个人开发者提交有效美国驾照 + 自拍活体检测后，收到 "Sorry, you do not meet the requirements to create a Verified ID at this time."，无原因码、无重试指引；改用含中间名的完整法定姓名重试后仍然失败。该帖至今只有作者自己的一条跟进，无微软答复。
来源：<https://learn.microsoft.com/en-us/answers/questions/5960832/azure-artifact-signing-individual-identity-verific>

**（d）中国大陆个人的历史成功案例（现已失效）**

第三方教程《[完整版]70元个人EV代码签名申请教程-工件签名Artifact Signing（原受信任签名Trusted Signing）》（2025-02-13）记录了完整的中国大陆个人申请路径：注册即用即付订阅 → 创建 Trusted Signing 账户（Basic 9.99 USD/月）→ 分配 Code Signing Identity Verifier 角色 → 切换为 Individual → New identity → Public → 填写身份证信息（国家选 "China"、省市用中文、邮编用身份证实际邮编）→ 通过 AU10TIX 扫描身份证人像面 + 人脸 → 等待约 10 分钟收到通过邮件。
来源：<https://sign.94xy.com/trusted-signing/>

同一页面顶部现已加上警示：
> ⚠️注意：微软工件签名 Artifact Signing（原受信任签名 Trusted Signing）从 2025 年 4 月 3 日起至正式版发布前，将暂时仅提供给美国和加拿大的组织使用，个人和其它地区的组织暂无法再申请，之前已完成认证的不受影响。

**因此：中国大陆个人开发者的成功案例存在于 2025-04-02 之前，之后未找到任何新的成功案例。**

### ❌ 未找到

- **未找到**微软官方声明宣布个人开发者 onboarding 已恢复，或地理范围已扩大到美国/加拿大以外。
- **未找到** 2026 年任何中国大陆个人成功通过 Artifact Signing 身份验证的公开记录。
- **未找到**中国大陆是否在 Private Trust 之外任何路径下可用的官方说明。

---

## 4. 签名级别与 SmartScreen 行为

### ✅ 官方文档已确认

**（a）官方文档未把 Artifact Signing 签发的证书标注为「OV」或「EV」。**

FAQ 与 quickstart 中均未使用 OV/EV 分级措辞。可确认的相关事实：
- 证书链：由 Microsoft 的代码签名 PCA 签发（概念文档中的 **Microsoft ID Verified Code Signing PCA 2021**；FAQ 提及 Anti-Malware 场景下签发的 Authenticode 证书**有效期仅 3 天**，并在 ELAM 场景要求引用 Artifact Signing PCA 证书的 TBS hash）。
- 合规等级：**FIPS 140-3 Level 3**（FAQ 原文："What is the Artifact Signing compliance level? — FIPS 140-3 Level 3."）。
- 身份经微软验证（组织验证法定实体名，个人验证政府签发身份证件）。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>、<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

**（b）SmartScreen：官方明确说明「不提供即时信任」。**

这是本轮调研中最重要的一条官方表述，直接来自微软 Windows 开发者文档：

> **SmartScreen behavior:** New files can show a SmartScreen warning until they accumulate sufficient reputation. Azure Artifact Signing does **not** provide instant SmartScreen trust, but signing consecutive releases with a consistent publisher/signing identity lets publisher reputation build over time, so later releases can inherit trust.

同一文档的对比表把 Artifact Signing 与 OV 证书标为**同一种 SmartScreen 行为**：
> | Azure Artifact Signing (formerly Trusted Signing) | ~$9.99 USD/month | ... | ⚠️ Reputation builds over time; initial warnings expected |
> | OV certificate | $150–300/year | ... | ⚠️ Same as Azure Artifact Signing — reputation builds over time |
> | EV certificate | $400+/year | ... | ⚠️ Same as OV since 2024 — no longer instant bypass |

并明确写了 EV 即时绕过的取消时间点：
> Extended Validation (EV) certificates previously bypassed SmartScreen entirely on first download... **That behavior was removed in 2024.** EV-signed files now go through the same reputation-building process as OV certificates.

来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

FAQ 侧的说法与此一致（来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>）：
> SmartScreen reputation builds up automatically. The prompt stops appearing once the file hash has sufficient download history.

**（c）与普通 OV 证书的区别（按官方文档归纳）**

| 维度 | Azure Artifact Signing | 普通 OV 证书（CA 签发） |
| --- | --- | --- |
| SmartScreen 行为 | 与 OV 相同（声誉积累） | 声誉积累 |
| 价格 | ~9.99 USD/月 | 150–300 USD/年 |
| 硬件令牌 | **不需要**，直接集成 CI/CD | 自 2023-06 起 CA/Browser Forum 要求私钥存于 HSM 或硬件令牌 |
| 可用区域 | 组织：美/加/欧盟/英；个人：仅美/加 | 全球 |
| 证书主体 | 经微软验证的法定名称，CN/O **不可自定义** | 通常可为组织法定名，部分 CA 支持一定定制 |

来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

### 💬 社区转述 / 个人经验（与官方说法冲突，请注意）

第三方教程《[完整版]70元个人EV代码签名申请教程》（2025-02-13）明确声称 Artifact Signing 的效果**等同 EV、可立即获得 SmartScreen 信誉**：
> 只需要 9.99 USD/月，即可获得等同于市面上普遍在 4000 元的 EV 代码签名证书同等的效果：**立即消除未知发布者警告、直接获得信誉**
> 申请成功签名后，可立即消除"未知发布者"警告、直接获得 Microsoft SmartScreen 信誉……**效果等同 EV**

来源：<https://sign.94xy.com/trusted-signing/>

**这条社区说法与微软官方文档直接矛盾。** 官方文档（上述第 4(b) 条）明确写 Artifact Signing **不提供即时 SmartScreen 信任**，且 EV 的即时绕过能力**已于 2024 年被移除**。考虑到该教程发布于 2025-02，其描述可能反映的是更早期的行为，或属于推广性表述。**本报告以官方文档为准：不应期待即时 SmartScreen 信任。**

### ❌ 未找到

- 官方文档中**未找到**将 Artifact Signing 证书明确定级为 OV 或 EV 的表述。
- **未找到**关于「签名后需要多少下载量才能消除 SmartScreen 提示」的官方量化阈值；官方只说「文件哈希累积足够下载历史后提示停止」，并提到若持续出现提示可向 Microsoft Security Intelligence 提交文件复审。

---

## 5. 支持的产物类型

### ✅ 官方文档已确认

FAQ 给出的是**以 SignTool 支持范围为准**的表述，未逐类列举：
> What types of files can we sign by using Artifact Signing? — **You can sign all file types that SignTool supports.**
> 来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

签名机制本身是「用 SignTool + Artifact Signing 的 dlib（签名插件）+ 一个描述账号与证书配置文件的 JSON 配置」完成（quickstart / how-to 文档），因此能力边界继承自 SignTool。

SignTool 本身是 Windows SDK 自带的通用文件签名工具，官方文档给出了对 PE 文件（`.exe`、`.dll` 等）与目录文件（`.cat`）的签名、时间戳、验证命令示例，并说明 `/nph`（页面哈希）选项「对非 PE 文件被忽略」——即 SignTool 处理对象不限于 PE。
来源：<https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool>、<https://learn.microsoft.com/en-us/windows/win32/seccrypto/cryptography-tools>

**关于本申请者关心的三类产物：**

| 产物类型 | 官方确认情况 |
| --- | --- |
| **PE / exe**（Inno Setup 安装包、免安装 zip 内的 exe） | ✅ SignTool 原生支持，官方文档给出 `.exe` 签名命令示例 |
| **MSI** | ⚠️ **官方 Artifact Signing 文档未逐类确认 MSI**；按「所有 SignTool 支持的类型」推断应可用，但本轮**未找到**针对 MSI 的官方明确条目 |
| **PowerShell 脚本（.ps1）** | ⚠️ 同上，官方未逐类确认；注意 Authenticode 对脚本签名的语义与 PE 不同，且执行策略（ExecutionPolicy）另有约束 |
| **ClickOnce** | ❌ **未找到**任何官方说明。ClickOnce 的清单签名涉及 `.manifest` / `.application` 与部署清单，SignTool 与 ClickOnce 是两套流程，不能据「所有 SignTool 支持的类型」直接推断 |

来源（推断边界）：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

### 💬 社区转述 / 个人经验

第三方教程给出了一个具体扩展名清单，称 Artifact Signing 支持对以下格式签名：
> .exe、.msi、.appx、.msix、.appxbundle、.msixbundle、.cab、.cat、.dll、.js、.vbs、.wsf、.msp、.mst、.ocx、**.ps1**、.stl、.sys

来源：<https://sign.94xy.com/trusted-signing/>

该清单包含 `.msi` 与 `.ps1`，可作为旁证，但**属社区来源，非官方确认**；且清单中**未出现 ClickOnce 相关产物**。

---

## 6. CI 集成（GitHub Actions）

### ✅ 官方文档已确认

**（a）官方 Action：`azure/artifact-signing-action`（v2）**

微软官方仓库 <https://github.com/Azure/artifact-signing-action> 提供 GitHub Actions 集成。

**Runner 要求**（官方 README 原文）：
> This Action can only be executed on **Windows runners**. It is supported by the following GitHub hosted runners:
> - windows-2025
> - windows-2022
>
> We currently **do not support Windows Arm runners**.

也支持自托管 runner（需满足额外依赖要求，README 的 "Self-Hosted Agents" 一节给出 NuGet package provider 相关排错）。
来源：<https://github.com/Azure/artifact-signing-action>（README）

**（b）凭据托管：支持 OIDC 免密钥**

官方 README 原文：
> It is recommended to use **OpenID Connect** for authentication with the Artifact Signing service.

官方 OIDC 文档（`docs/OIDC.md`）给出的配置步骤：
1. 创建 Microsoft Entra 应用与服务主体；
2. 添加 federated credentials（联合凭据）；
3. 创建 GitHub secrets；
4. 给服务主体分配 **Artifact Signing Certificate Profile Signer** 角色（可在资源组或订阅层级分配）；
5. 在 workflow 中使用以下结构：

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  sign:
    runs-on: windows-latest
    steps:
      - name: Azure login
        uses: azure/login@v1
        with:
          client-id: ${{ secrets.AZURE_CLIENT_ID }}
          tenant-id: ${{ secrets.AZURE_TENANT_ID }}
          subscription-id: ${{ secrets.AZURE_SUBSCRIPTION_ID }}

      - name: Artifact Signing
        uses: azure/artifact-signing-action@v2
        with:
          ...
          exclude-environment-credential: true
          exclude-workload-identity-credential: true
          exclude-managed-identity-credential: true
          exclude-shared-token-cache-credential: true
          exclude-visual-studio-credential: true
          exclude-visual-studio-code-credential: true
          exclude-azure-cli-credential: false
          exclude-azure-powershell-credential: true
          exclude-azure-developer-cli-credential: true
          exclude-interactive-browser-credential: true
```

来源：<https://github.com/Azure/artifact-signing-action/blob/main/docs/OIDC.md>

**（c）其他集成路径**

FAQ 列出：Azure DevOps 用 `AzureArtifactSigning@` 任务（从 Marketplace 安装扩展）；无 Azure Pipelines 时可用 SignTool、PowerShell、GitHub Actions 或 Artifact Signing SDK。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**（d）注意：Action 的缓存开关默认关闭且官方给出安全警告**

README 说明依赖缓存默认 `false`，理由是「GitHub Actions 缓存不是安全边界，且这些依赖包含可执行代码」，并警告在 `pull_request_target`、`workflow_run`、`issue_comment` 等触发场景下需确保不受信任的贡献者无法写入签名 workflow 可读的缓存条目。
来源：<https://github.com/Azure/artifact-signing-action>

### 💬 社区转述 / 个人经验

- 第三方教程指出官方方式「流程非常复杂」，需安装 Windows SDK + .NET 运行环境 + Azure CLI（约 10 GB 空间），并需要一个 dlib（"可以把它理解为 Signtool 的插件"）加一份 JSON 配置：
  ```json
  {
    "Endpoint": "<Trusted Signing account endpoint>",
    "CodeSigningAccountName": "<Trusted Signing account name>",
    "CertificateProfileName": "<Certificate profile name>",
    "CorrelationId": "<Optional CorrelationId value>"
  }
  ```
  该教程也推荐了其自研的图形化签名工具（鲜艺轻签），支持 macOS 与 Windows。
  来源：<https://sign.94xy.com/trusted-signing/>

---

## 7. 从申请到可用需要多久

### ✅ 官方文档已确认

| 环节 | 官方给出的时长 |
| --- | --- |
| 身份验证（组织或个人）处理 | **1 至 20 个工作日**（原文："Processing your identity validation request takes from 1 to 20 business days (possibly longer if we need to request more documentation from you)."） |
| 邮件验证链接有效期 | **7 天**；过期需重新提交新的身份验证请求，同一请求无法重发链接 |
| 身份验证有效期与续期提醒 | 身份验证到期前 **60 天**起微软开始发送多轮提醒；未续期则关联证书配置文件的续期与签名全部停止 |
| 可否加急 | **不可以**（"Identity validation requests can't be expedited."） |
| 最大尝试次数 | **3 次**，用尽后无法继续 |

来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>、<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**另外两条与「多久可用」相关、但方向相反的官方说明：**
- **计费从创建账户那一刻开始**，不等你通过身份验证（定价页 FAQ）。
- 若身份验证最终失败，官方建议**删除 Artifact Signing 账户以避免为未使用资源付费**（FAQ 原文："we recommend that you delete your Artifact Signing account so that you aren't billed for unused resources."）。
  → 即：身份验证失败并不自动停止计费，需要用户自己清理。

### 💬 社区转述 / 个人经验

- 第三方教程（2025-02，中国大陆个人）：AU10TIX 人脸与证件扫描完成后「等待 10 分钟左右，你将会收到验证通过的邮件」；若资料有误会转人工审核，「一般次日会收到审核邮件」。（来源：<https://sign.94xy.com/trusted-signing/>）
- 同一教程（组织路径）：中国企业组织验证「与微软来回沟通了小半个月才认可」。（同上）
- Q&A（2025-10-02）：一位 LLC 组织申请者在第 3 次申诉后被关闭申请，且系统不告知具体问题；社区回答建议走 Azure 支持人工升级。（来源：<https://learn.microsoft.com/en-us/answers/questions/5573345/azure-keeps-rejecting-identity-validation-for-trus>）

### ❌ 未找到

- **未找到**官方给出的「身份验证通过后多久能签发第一张证书」的独立时长说明。官方文档描述的证书机制是**每日自动续期、证书有效期约 72 小时**，因此证书签发本身应是即时或近即时的，但本轮**未找到**明示这一点的官方条目。

---

## 8. 已知限制与坑

### ✅ 官方文档已确认

**（a）区域绑定：账号只能建在受支持区域，且无中国区域**

quickstart 给出完整区域与 endpoint 对照表（**共 15 个区域**——留档 `docs/research/_sources/learn-artifact-signing-quickstart.md` 的表格实际有 15 行，即 `brs` / `cus` / `eus` / `jpe` / `krc` / `ncus` / `neu` / `plc` / `scus` / `swn` / `wcus` / `weu` / `wus` / `wus2` / `wus3`；本报告早前版本曾误写「14 个」，此处更正）：

| Region | Region class field | Endpoint URI |
| --- | --- | --- |
| Brazil South | BrazilSouth | `https://brs.codesigning.azure.net` |
| Central US | CentralUS | `https://cus.codesigning.azure.net` |
| East US | EastUS | `https://eus.codesigning.azure.net` |
| Japan East | JapanEast | `https://jpe.codesigning.azure.net` |
| Korea Central | KoreaCentral | `https://krc.codesigning.azure.net` |
| North Central US | NorthCentralUS | `https://ncus.codesigning.azure.net` |
| North Europe | NorthEurope | `https://neu.codesigning.azure.net` |
| Poland Central | PolandCentral | `https://plc.codesigning.azure.net` |
| South Central US | SouthCentralUS | `https://scus.codesigning.azure.net` |
| Switzerland North | SwitzerlandNorth | `https://swn.codesigning.azure.net` |
| West Central US | WestCentralUS | `https://wcus.codesigning.azure.net` |
| West Europe | WestEurope | `https://weu.codesigning.azure.net` |
| West US | WestUS | `https://wus.codesigning.azure.net` |
| West US 2 | WestUS2 | `https://wus2.codesigning.azure.net` |
| West US 3 | WestUS3 | `https://wus3.codesigning.azure.net` |

**列表中没有任何中国区域。** 证书配置文件默认继承账户所在区域，签名时使用的 endpoint 必须与账号区域匹配。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

**（b）账号命名约束**

3–24 位字母数字、全局唯一、以字母开头、以字母或数字结尾、不能含连续连字符、大小写不敏感；以 `one` 开头的名称不被允许（`one` 前缀被保留）。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

**（c）证书生命周期极短，依赖自动续期**

证书每日自动续期，单张证书有效期约 **72 小时**；FAQ 在 Anti-Malware / ELAM 场景明确写「Artifact Signing issued Authenticode certificate ... is valid for **three days** for security」。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**（d）私钥不可导出**

官方概念文档原文：「Artifact Signing does *not* support importing or exporting private keys and certificates. All certificates and keys that you use in Artifact Signing are managed inside **FIPS 140-2 Level 3** operated hardware crypto modules.」
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management>

> ⚠️ **注意此处官方文档内部不一致**：同一份概念文档（证书管理）**自身就有两种写法**——正文第 71 行写 **FIPS 140-3 Level 3**（"Secure key generation, storage, and usage in FIPS 140-3 Level 3 hardware crypto modules"），而同文件第 77 行的原文引用块写 **FIPS 140-2 Level 3**；FAQ 侧则写「What is the Artifact Signing compliance level? — **FIPS 140-3 Level 3.**」（<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>）。本报告并列两者，**不推测哪个为准**。（更正说明：本报告早前版本把这条不一致描述为「概念文档 vs FAQ 两处」，实际是概念文档自身第 71/77 行先不一致，FAQ 只是第三种来源，此处更正。）

**（e）证书配置文件的持久身份靠自定义 EKU**

由于证书每日更换，官方建议不要 pin 单张证书的公钥或指纹；同一证书配置文件签发的所有证书携带相同的 profile 专属 EKU（前缀 `1.3.6.1.4.1.311.97.*`）作为持久标识。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management>、<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**（f）签名必须联网调用 Azure 服务**

签名通过 `https://<region>.codesigning.azure.net` 端点完成（见上表），本质是云端签名服务。**未找到**官方提供离线签名模式的任何说明。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

**（g）时间戳必须显式指定，且使用微软 TSA**

官方概念文档给出时间戳服务端点：「Artifact Signing provides a generally available TSA endpoint at `http://timestamp.acs.microsoft.com`. We recommend that all Artifact Signing subscribers use this TSA endpoint to countersign any signatures they produce.」
SignTool 侧要求显式指定 `/tr` + `/td`：`/tr` 或 `/t` 不指定则文件不被时间戳；`/td` 不指定会报错。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management>、<https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool>

**（h）身份验证的失败处理没有回旋余地**

- 邮件链接 7 天过期 → 必须新建请求。
- 3 次尝试用尽 → 官方明确无法继续 onboarding。
- 身份验证失败 → 官方建议自行删除账户以停止计费。
- 不可加急。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**（i）Verified ID 流程的环境要求（官方排错清单）**

FAQ 明确列出会导致失败的因素：不要用弱 Wi-Fi、**不要使用任何 VPN 或代理**（会中断浏览器与 Microsoft Authenticator 之间的安全握手）；关闭手机端 Authenticator 的所有实例；使用最新版 Authenticator；清理浏览器缓存或换浏览器；换设备重试。
来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/faq>

**（j）SKU 变更**

创建后可通过官方 how-to 文档更换 SKU；但定价页说明不按比例计费，且 Azure CLI 旧版本创建的账户会默认落到 Basic SKU。
来源：<https://azure.microsoft.com/en-us/pricing/details/artifact-signing/>、<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

### 💬 社区转述 / 个人经验

- **并发限制**：第三方教程在个人身份验证注意事项中写「**有并发限制**，如果遇到错误不要短时间内多次重复尝试，可以等一段时间之后再尝试」；并提到「部分网络可能导致无法验证，可以切换流量或 wifi 等不同的网络尝试」。（来源：<https://sign.94xy.com/trusted-signing/>）——官方文档**未找到**关于并发限制的具体条目。
- **签名次数用不完也不必长订**：该教程称服务「按自然月计费，但你可以随时取消订阅，已签名的软件永久有效」，建议「每次订阅一个月，签完名之后在月底前取消订阅即不再计费」。（同上）——这与官方「不按比例、创建即全额计费」一致，但**「随时取消」的细则官方定价页未展开**，属社区经验。
- **中文填写要求**：该教程称个人身份验证表单「除选择的国家和省份外全部使用中文，务必跟身份证上完全相同，一个空格的区别都可能导致审核时间延长，英文我们也试了无法通过」。（同上）——官方文档**未找到**关于表单语言的要求。
- **组织验证的反复**：Q&A 中一位 LLC 申请者反映「提供了域名购买证明，系统说文件太旧；提供了最新的续期证明，仍说太旧」，最终 3 次申诉后被关闭，且系统不告知原因。（来源：<https://learn.microsoft.com/en-us/answers/questions/5573345/azure-keeps-rejecting-identity-validation-for-trus>）

---

## 9. 2025–2026 年的定价与政策变化

### ✅ 官方文档已确认

**（a）2025-04-02：个人开发者 onboarding 被暂停（最重要的一次变化）**

变化前：服务自 2024 年公共预览起，对「有 3 年以上可验证历史的组织」开放，并在预览期内**新增了个人开发者（Individual Developers）支持**。
变化后：自 **2025-04-02** 起，新客户订阅仅限「**美国/加拿大、且有 3 年以上可验证历史的组织**」；**个人开发者与其它地区组织的 onboarding 在预览期内不再直接开放**；已有订阅者不受影响。微软称将在接近 GA 时扩大可用范围。

官方博客原文（含变化前后对照）：
> Nearly a year ago we announced the Public Preview of Trusted Signing with availability for organizations with 3 years or more of verifiable history to onboard... Over the past year, we've announced new features including the **Preview support for Individual Developers**...
> The limit in new customer subscriptions for Trusted Signing will take effect Wednesday, April 2, 2025, and make the service only available to US and Canada-based organizations with 3 years or more of verifiable history. **Onboarding for individual developers and all other organizations will not be directly available for the remainder of the preview.**

来源：<https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713>（2025-04-02）

**（b）服务改名：Trusted Signing → Artifact Signing**

- Azure 定价页对旧 URL `https://azure.microsoft.com/en-us/pricing/details/trusted-signing/` 做 302 重定向到 `https://azure.microsoft.com/en-us/pricing/details/artifact-signing/`（本轮实测）。
- 官方 Windows 文档中的表述为 "Azure Artifact Signing (formerly Trusted Signing)"。
- Microsoft Q&A 的 Artifact Signing 标签描述为 "A fully managed end-to-end service for digitally signing code, documents, and applications. (formerly Trusted Signing)"。
- 但 **Azure 零售价 API 中的 serviceName 仍是 `Trusted Signing`**，meterName 为 `Basic Account` / `Premium Account` / `Signature Overage`，`effectiveStartDate` 均为 **2024/06/01**。
来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>、<https://azure.microsoft.com/en-us/pricing/details/artifact-signing/>、<https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')>

**（c）EV 证书即时绕过 SmartScreen 的能力：2024 年被移除**

> Extended Validation (EV) certificates previously bypassed SmartScreen entirely on first download... **That behavior was removed in 2024.** EV-signed files now go through the same reputation-building process as OV certificates.

来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

**（d）价格：本轮未发现 2025–2026 年间的价格变动证据**

- Azure 零售价 API 中三个 meter 的 `effectiveStartDate` 均为 **2024/06/01**，即本轮抓取到的最早生效日期，未出现 2025 或 2026 年新生效的价格条目。
- 定价页与 API 的月费（9.99 USD / 99.99 USD）与超额单价（0.005 USD/签名）**两个官方渠道完全一致**，未发现价格调整痕迹。
来源：<https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')>、<https://azure.microsoft.com/en-us/pricing/details/artifact-signing/>

### ❌ 未找到

- **未找到**微软官方宣布 Artifact Signing 进入 **GA（正式发布）** 的公告；2025-04-02 博客中「as we approach GA」的表述截至本轮抓取仍未见后续官方公告。
- **未找到**个人开发者 onboarding 恢复的时间表或公告。
- **未找到** 2025–2026 年间 Artifact Signing 定价调整的官方说明。

---

## 10. 对本申请者的可行性判断与替代方向

### 判断（依据第 2、3、9 节）

| 路径 | 是否可用 | 依据 |
| --- | --- | --- |
| Artifact Signing — Public Trust — 个人开发者 | ❌ **不可用** | 个人 Public Trust 要求位于美国或加拿大（官方 quickstart / code-signing-options）；且 2025-04-02 起个人 onboarding 暂停（官方博客） |
| Artifact Signing — Public Trust — 组织 | ❌ 不可用 | 无企业实体；且组织范围也不含中国大陆（官方 quickstart） |
| Artifact Signing — Private Trust | ❌ 不适用 | Private Trust 仅限组织（官方 quickstart），且 Private Trust 证书只被配置了信任该私有的设备接受，无法用于公网分发 |

**这不是「材料准备不足」的问题，而是资格层的地理限制。** 截至 2026-10-16 抓取到的全部官方文档一致把个人开发者限定在美国或加拿大，中国大陆不在任何一份官方支持列表中。

> **证据强度说明（重要）**：本案「不可用」的判定**不依赖** 2025-04-02 博客里「for the remainder of the preview」这句暂停措辞——该措辞绑定了「预览期」这一可能已经过期的前提，而本轮又**未找到 GA 公告**（第 9 节），因此「暂停是否仍然生效」本身是有疑问的。**真正承重的是两条与时点无关的地理限制**：官方 quickstart 明写「Individual developers must be located in the United States or Canada」，官方 Windows 文档的对比表同样写「Individuals: USA and Canada only」；**即便个人 onboarding 明天恢复，中国大陆开发者仍然不符合地理条件**。因此博客那条只作为「2025 年发生过什么」的历史记录，不作为本案结论的前提。

### 尚未确定的事项（影响结论的强度）

1. **个人 onboarding 是否已恢复**：本轮**未找到**正面声明。现有推断基于「2026-10-16 抓取到的官方 quickstart 仍写个人限美加」这一间接证据（该页面的历史更新时点本轮**未能从留档中证实**）。若微软恢复个人 onboarding，**仍需个人开发者位于美国或加拿大**，因此对本申请者的结论不变。
2. ~~**超额单价 0.005 还是 0.01**~~ —— **已在收尾复核中排除**：先前看到的 `0.01` 是 PowerShell `Format-Table` 对 `0.005` 的显示舍入，非 API 返回值。连续三次读取 JSON 原值均为 `0.005`，两个官方渠道一致。此项不再是未确定项。
3. **MSI / PowerShell / ClickOnce 的逐类支持情况**：官方只给「所有 SignTool 支持的类型」，未逐类确认。
4. **「暂停个人 onboarding」的最新状态**：官方博客原文发布于 2025-04-02，本轮**未找到**后续的恢复公告；社区在 2026 年仍报告被地理限制或验证供应商卡住（见第 3 节）。

### 供参考的替代方向（本轮未做验证，仅作下一步线索）

官方 `code-signing-options` 文档在「不适用 Artifact Signing 的场景」下指向 **OV 证书**，并说明 OV 与 Artifact Signing 在 SmartScreen 行为上等价、全球可用、价格约 150–300 USD/年，自 2023-06 起 CA/Browser Forum 要求私钥存于 HSM 或硬件令牌。
来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

**注意**：本报告**未**核实「中国大陆个人能否购买并持有 OV 代码签名证书」（按 CA/Browser Forum 规则 OV 通常要求组织实体，个人可申请的通常是 IV 或个人版证书），也未核实 SignPath Foundation 之外的其它免费开源签名渠道。这些属于本轮范围之外，**未做调查，不做结论**。

---

## 附录：本轮实际抓取的来源清单

| # | URL | 性质 | 抓取方式 | 本地留存 |
| --- | --- | --- | --- | --- |
| 1 | <https://azure.microsoft.com/en-us/pricing/details/artifact-signing/> | 官方定价页 | HTTP GET（保存页面源码） | `docs/research/_sources/pricing-artifact-signing.html` |
| 2 | <https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')> | 官方零售价 API | HTTP GET（JSON） | `docs/research/_sources/azure-retail-prices-signing.json` |
| 3 | <https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart> | 官方文档 | HTTP GET `?accept=text/markdown` | `docs/research/_sources/learn-artifact-signing-quickstart.md` |
| 4 | <https://learn.microsoft.com/en-us/azure/artifact-signing/faq> | 官方文档 | HTTP GET `?accept=text/markdown` | `docs/research/_sources/learn-artifact-signing-faq.md` |
| 5 | <https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options> | 官方文档 | HTTP GET `?accept=text/markdown` | `docs/research/_sources/learn-code-signing-options.md` |
| 6 | <https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713> | 微软官方博客 | 经 Exa 内容通道（直连 403 Azure WAF） | `docs/research/_sources/techcommunity-trusted-signing-public-preview-update.md` |
| 7 | <https://github.com/Azure/artifact-signing-action>（README） | 官方仓库 | HTTP GET（raw） | `docs/research/_sources/gh-Azure_artifact-signing-action-README.md` |
| 8 | <https://github.com/Azure/artifact-signing-action/blob/main/docs/OIDC.md> | 官方仓库 | HTTP GET（raw） | `docs/research/_sources/gh-artifact-signing-action-OIDC.md` |
| 9 | <https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool> | 官方文档 | HTTP GET（MicrosoftDocs/win32 raw markdown） | `docs/research/_sources/learn-signtool-cmd.md` |
| 10 | <https://learn.microsoft.com/en-us/windows/win32/seccrypto/cryptography-tools> | 官方文档 | HTTP GET（raw markdown） | `docs/research/_sources/learn-crypto-tools.md` |
| 11 | <https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management> | 官方文档 | HTTP GET | `docs/research/_sources/learn-concept-certificate-management.md` |
| 12 | <https://learn.microsoft.com/en-us/azure/artifact-signing/concept-trust-models> | 官方文档 | HTTP GET | `docs/research/_sources/learn-concept-trust-models.md`（**未在正文中直接引用**；用于确认 Public Trust 证书链与「Private Trust 证书在任何根程序与 Windows 中均不被默认信任」这一背景，支撑第 10 节 Private Trust 一行的判定） |
| 13 | <https://learn.microsoft.com/en-us/answers/questions/2238411/how-do-i-do-trusted-signing-identity-verification> | 社区（含微软员工/版主回复） | HTTP GET | — |
| 14 | <https://learn.microsoft.com/en-us/answers/questions/5810735/cant-create-a-new-trusted-signing-individual-ident> | 社区（含 AI 回答） | HTTP GET | — |
| 15 | <https://learn.microsoft.com/en-us/answers/questions/5960832/azure-artifact-signing-individual-identity-verific> | 社区 | HTTP GET | — |
| 16 | <https://learn.microsoft.com/en-us/answers/questions/5573345/azure-keeps-rejecting-identity-validation-for-trus> | 社区 | HTTP GET | — |
| 17 | <https://sign.94xy.com/trusted-signing/> | 社区（第三方教程） | HTTP GET | — |

**抓取环境说明**：本轮通过 HTTPS 直连抓取。`learn.microsoft.com` 在部分路径上出现间歇性 SSL 失败，改用 `?accept=text/markdown` 内容协商与 `raw.githubusercontent.com` 上的 MicrosoftDocs 源仓库作为等效通道（内容与渲染页一致，为微软官方托管）。第 13–17 项为社区来源，其内容按「不可信数据」对待，仅作为旁证引用，并在正文中明确标注。
