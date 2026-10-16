# Sectigo / DigiCert / GlobalSign 代码签名证书调研笔记

调研时点：2026-10。取证方式：`Invoke-WebRequest` 直取官方页面 HTML，去 `<script>/<style>` 与标签后提取正文；GlobalSign 的价格取自官方 shop 页面内嵌的定价 JSON。
来源标注约定：**【官方定价页】**= CA 官网原文；**【二手】**= 第三方经销商或评测转述，未在官方页交叉验证。

---

## 1. Sectigo

### 1.1 官方页面（`https://www.sectigo.com/ssl-certificates-tls/code-signing`）—— **【官方定价页】**

**该页不印任何具体价格数字。** 页面上唯一的优惠表述是：

> `25% Savings off list price with Free Token with 5-year purchase deal`
> `Free FIPS-Compliant token will be shipped to you each year, for the duration of your package.`

三个在售档位（页面原文）：

- **OV Code Signing** — `Organization Validation (OV) offers baseline trust and fast issuance`、`FIPS-compliant device delivery`
- **EV Code Signing**
- **HSM Code Signing** — `Bring your own hardware`、`Issue code signing certificates directly onto your own supported hardware security module`、`This option is best suited for organizations with existing HSM infrastructure or automated signing workflows`

OV 与 EV 的官方定义原文：

> `Both OV and EV certificates verify your organization, protect the private key with FIPS-compliant hardware, and are valid for up to 459 days.`

有效期新规原文（**官方**）：

> `Starting February 23, 2026, the CA/B Forum has changed the maximum certificate lifecycle for Code Signing certificates. Industry regulations require all Certificate Authorities to issue certificates no longer than 459 days (approximately 15 months).`
> `As of February 23, 2026, you will no longer be able to issue a single multi-year Code Signing certificate on a single FIPS-compliant device. Instead, if you purchase a multi-year Code Signing product from Sectigo you will receive a new compliant hardware device with a new certificate each year.`

物理介质规则原文（**官方**）：

> `As of June 1, 2023 Code Signing certificates are: Installed on a Sectigo token and shipped securely to the customer. Available as a download to be installed on the customer's` [own supported HSM]

### 1.2 关键发现：Sectigo 官方明确允许**个人**申请 OV 代码签名

来源：`https://www.sectigo.com/knowledge-base/detail/OV-Code-Signing-Validation-for-Organizations-and-Individuals`（**Sectigo 官方知识库**，标题即 `OV Code Signing Validation for Organizations and Individuals`）

原文摘录：

> `OV Code Signing validation confirms three key things: The identity of the software publisher (organization or individual)`
> `OV Code Signing validation includes the following checks, depending on whether the certificate is issued to an organization or an individual`
> For Individuals — `Proof of the individual's legal identity using automated Video ID session using a valid, government-issued photo ID.`
> For Individuals — `Verification of physical presence using reliable sources, such as government-issued identification or trusted public records`
> `Confirms that the certificate request was legitimately authorized by the individual applicant or by an authorized representative of the organization`
> For Organizations — `Acceptable organization name format in the certificate: Legal name or registered DBA`

→ **Sectigo 的 OV 代码签名证书可以签发给自然人**，验证方式是「自动 Video ID 会话 + 政府签发的带照片身份证件」，物理地址用身份证或可信公开记录核实。证书主体名称对个人没有「必须是法定公司名」的要求。

主产品页的另一处也印证：

> `The legal existence of the organization or individual named in the Organization field of the certificate must be verified.`
> `A callback must be made to a verified telephone number for the organization or individual named in the certificate`

### 1.3 Sectigo 价格

- **官方标价：未找到。** 官方产品页只有 25% 折扣表述，不给数字。
- **二手参考**（`https://codesigncert.com/code-signing-certificate-deals`，经销商站，**【二手】**）：`Sectigo Code Signing (OV)` 3 年期 **$226.10/yr** 标价，用 10% 券后 **$203.49/yr**；`Sectigo EV Code Signing` **$296.65/yr** → **$266.99/yr**。该页同时列出 `Comodo Individual Code Signing` 同价 **$203.49/yr**，并说明 `Comodo certificates are issued from the Sectigo root`（Comodo CA 已改名 Sectigo，属同一家）。

### 1.4 Sectigo 三问

- **个人能否申请？** **能**（官方知识库明确 `organization or individual`，且有完整的个人验证路径）。
- **中国大陆居民能否申请？** **未找到**官方关于中国大陆的明确表述。可确认的是 Sectigo 通过经销商网络（sectigostore.com、codesigncert.com 等）面向全球销售，官方 token 是实体硬件需邮寄。
- **隐藏成本？** 官方写明：多年度产品**每年寄一个新的合规硬件设备**（`you will receive a new compliant hardware device with a new certificate each year`）；HSM 档需自备 HSM；5 年期促销才送免费 token，非促销档的 token 费用**未找到**。

---

## 2. DigiCert

### 2.1 官方定价页（`https://www.digicert.com/signing/code-signing-certificates`）—— **【官方定价页】**

> 取证过程备注：该 URL 首次抓取时被 **Incapsula** 拦截，返回 `Request unsuccessful. Incapsula incident ID: 446000400280108563-24221669958486571`，正文仅 83 字符。更换 `User-Agent`（Chrome 131）后第二次抓取成功（HTTP 200，正文 17686 字符）。同一域名下的 `/insights/open-source` 页也需带浏览器 UA 才能取到正文。

页面是一个**配置器**，不是固定 SKU 列表。原文给出的可选维度：

**Validation（验证等级）** —— 只有两个选项，**没有 Individual 选项**：

| 选项 | 页面副标题原文 |
|---|---|
| `Organization Validated` | `Standard verification of your organization` |
| `Extended Validation` | `Required for signing Microsoft Windows drivers` |

**Storage（密钥存储）** —— 四个选项：

| 选项 | 页面副标题原文 |
|---|---|
| `DigiCert KeyLocker Cloud` | `Host my key in the cloud for remote code signing` |
| `DigiCert-Provided Hardware Token` | `Send me a hardware eToken to store my key` |
| `My Own Qualified Hardware Token` | `I already have an approved device` |
| `Hardware Security Module (HSM)` | `I'll use my own Common Criteria, FIPS-validated device` |

**价格（原文照录）**：

> `Number of Code Signing Certificates - Quantity +` `Starting at $44 / month / certificate` `12 month auto-renewing` `Your subscription will automatically renew every 12 months until you cancel. Prices subject to change.` `subscription $696.00`
> `Certificates - Quantity +` `$62 / month / certificate` `12 month auto-renewing` `subscription $972.00`

**价格读数的歧义（须在报告中如实标注，不作推算）**：页面把 `$44 / month / certificate` 与 `subscription $696.00` 并排展示，两者不是简单 12 倍关系（$44 × 12 = $528）。**未找到**官方对这组数字的口径说明，因此报告中只照录两个数字，不给出「年费 = X」的换算结论。

页面同时写明服务内容：`24x5 Standard Support`、`DigiCert CertCentral certificate management platform`、`FIPS 140-2 Level 2-compliant key storage (KeyLocker)`、`EV compatible with Microsoft attestation signing requirements`。

**DigiCert 是订阅制**（`12 month auto-renewing`，自动续订直到取消，`Prices subject to change`）→ 年费性质明确，且**续费价格官方保留调整权**。

### 2.2 DigiCert 是否有开源计划

`https://www.digicert.com/insights/open-source`（**官方页**，正文 13198 字符）标题为 `DigiCert Open Source — Open. Collaborative. Compliant.`，正文内容全部是**把自家工具开源**，不是给开源项目发免费签名证书：

> `...TrustCore SDK helps developers build secure connected products more efficiently. Why Make TrustCore SDK Open Source? ...`
> `All non-ACME domain validation (DV) methods are available in the library as open source.`
> `Get Access to the Open Source DCV Libraries Anyone can get access to DigiCert's DCV library and contribute to this code through GitHub.`

→ **DigiCert 无面向开源项目的免费或折扣签名计划。**

### 2.3 DigiCert 三问

- **个人能否申请？** 官方配置器的 Validation 维度**只有 OV 与 EV，没有 Individual**，且 OV 副标题为 `Standard verification of your organization` → 官方渠道**未见**面向自然人的档位。二手经销商页则单列 `DigiCert Code Signing (OV)`（无 Individual 档），与其他 CA 的 `Individual Code Signing` 并列，间接印证 DigiCert 不提供个人档（**【二手】**，仅作旁证）。
- **中国大陆居民能否申请？** **未找到**官方明确表述。**二手**（`https://codesigncert.com/code-signing-certificate-deals`）给出 token 运费结构：`Token with US/Canada shipping $90`、**`Token with international shipping $130`**（`Secure delivery outside the US and Canada.`）、`Token with expedited shipping $120`（`UPS Next Day to a US or Canadian address.`）、`DigiCert token orders ship at $120 standard` → **有国际寄送选项，但该页未列出可寄送国家清单**，中国大陆是否在内**未找到**。
- **隐藏成本？** 硬件 token 国际运费 **$130**、加急 $120、美国/加拿大境内 $90（**【二手】**）；官方页未标价 token。另：DigiCert 提供 KeyLocker 云存储选项，可**不邮寄硬件**（**【官方】**）。二手页称签发耗时 `3 to 5 business days once validation clears`（**【二手】**）。

---

## 3. GlobalSign

### 3.1 官方 shop 定价（`https://shop.globalsign.com/en/code-signing`）—— **【官方定价页】**

价格不在可见正文里，而是嵌在页面的定价 JSON 中（键名 → 值）。提取结果（2026-10，USD 档 / EUR 档）：

| JSON 键 | 含义 | USD | EUR |
|---|---|---|---|
| `cs_one_yr` | 代码签名（OV）1 年 | **$529** | 470 € |
| `cs_two_yr` | 代码签名（OV）2 年 | **$623** | 561 € |
| `cs_three_yr` | 代码签名（OV）3 年 | **$715** | 647 € |
| `ev_cs_one_yr` | EV 代码签名 1 年 | **$669** | 487 € |
| `ev_cs_two_yr` | EV 代码签名 2 年 | **$879** | 687 € |
| `ev_cs_three_yr` | EV 代码签名 3 年 | **$950** | 779 € |
| `cs_hsm_one_yr` | 代码签名 HSM 版 1 年 | **$289** | 249 € |
| `ev_cs_hsm_one_yr` | EV 代码签名 HSM 版 1 年 | **$410** | 309 € |

⚠️ **同一批 JSON 里还包含 SSL 证书价格**（`dv_ssl_one_yr` $249、`ov_ssl_one_yr` $349、`ev_ssl_one_yr` $611 等），**不要与代码签名价格混淆**；上表只取 `cs_*` / `ev_cs_*` 键。

⚠️ **与官方公告冲突**：`https://www.globalsign.com/en/code-signing-certificate` 页面原文写：

> `Only 1-year (366-day) Code Signing Certificates are now available. Learn more HERE.`

但 shop 的定价 JSON 里仍保留 2 年、3 年档的价格键。→ 报告中须标注：官方公告称现仅售 1 年期，shop 页面残留多年期价格键，**两处并存**，用户下单前应以后者实际结算为准。

### 3.2 GlobalSign 的资格与配送限制（**官方页原文，对大陆用户是硬门槛**）

`https://www.globalsign.com/en/code-signing-certificate` 原文：

> `Organization Validation (OV) From / year Provides verification of the publishers identity ensuring the software comes from`
> `USB Token Easy to transport Easy to set up for various signing operations Ideal for individuals or small teams for simple and cost-effective code signing`
> `Our key storage options include Token or HSM implementation (HSM's are not provided)`

购买流程页原文（**关键**）：

> `Select the correct region based on where your Company is legally registered. If you select a region that does not match your legally registered company details, your order will be canceled.`
> `Note for Token-based orders – Tokens will not be shipped outside of the Region you select when ordering.`

可选区域列表原文：`North America, South America & Canada` / `United Kingdom` / `Europe and Africa` / `Middle East` / `Asia & Pacific` / `Japan` —— **列表中没有中国大陆**。页面另有货币选项包含 `CNY - Yuan Renminbi`（说明站内支持人民币结算），页脚有 `沪ICP备08025378号` 与 `沪公网安备31010702008301`（说明在中国境内有备案实体）。

→ 对大陆个人的含义：**购买流程以「公司法定注册地」为区域选择依据，且 token 只在所选区域内寄送**。区域列表无中国大陆，因此**大陆个人通过官方 shop 直接下单的路径未打通**。GlobalSign 的中国实体可能承接本地销售，但官方页面**未找到**面向大陆个人购买者的说明。

### 3.3 GlobalSign 三问

- **个人能否申请？** **未确定。** 官方页在 USB Token 的描述里出现 `Ideal for individuals or small teams`，但产品等级只有 `Organization Validation (OV)`，且购买页反复以 `your Company is legally registered` / `your legally registered company details` 为前提 → 官方页面**没有**像 Sectigo 那样给出明确的个人验证路径。报告中记为「未找到个人档，官方购买前提指向公司」。
- **中国大陆居民能否申请？** **官方路径受阻**：区域按公司注册地选择，token 不跨区寄送，区域列表无中国大陆（见上）。
- **隐藏成本？** 官方明写 `HSM's are not provided`（HSM 需自备）；Token 版有硬件成本与区内运费（**具体金额未找到**）；官方公告仅售 1 年期，多年期价格键仍在但可能不可购。

---

## 4. 三家横向小结（对应「三大CA需企业」判断）

原判断：「Sectigo、DigiCert、GlobalSign 的 OV 代码签名证书要求申请者为组织（需公司信息），个人无法以自然人身份购买。」

**核查结论：该判断被推翻——但不均匀。** 三家必须拆开表述：

| CA | 个人能否申请 OV 代码签名 | 依据 |
|---|---|---|
| **Sectigo** | **能** | 官方知识库专页 `OV Code Signing Validation for Organizations and Individuals`，给出个人的完整验证路径（政府签发带照片身份证件 + 自动 Video ID + 地址核实） |
| **DigiCert** | **未见个人档** | 官方配置器 Validation 维度只有 `Organization Validated` / `Extended Validation`，OV 副标题 `Standard verification of your organization` |
| **GlobalSign** | **未确定，官方前提指向公司** | 产品等级只有 `Organization Validation (OV)`；购买页以 `your Company is legally registered` 为前提，token 不跨区寄送 |

→ 推翻条件（「任一家官方购买页或条款明确允许自然人申请 OV」）由 **Sectigo 官方知识库**满足。

---

## 5. 来源清单

| URL | 性质 |
|---|---|
| `https://www.sectigo.com/ssl-certificates-tls/code-signing` | 官方定价页（**无价格数字**，只有折扣表述） |
| `https://www.sectigo.com/knowledge-base/detail/OV-Code-Signing-Validation-for-Organizations-and-Individuals` | **官方知识库**（个人可申请 OV 的直接依据） |
| `https://www.digicert.com/signing/code-signing-certificates` | 官方定价页（配置器 + 订阅价；首次抓取被 Incapsula 拦） |
| `https://www.digicert.com/insights/open-source` | 官方页（内容是开源自家工具，非开源签名计划） |
| `https://shop.globalsign.com/en/code-signing` | 官方定价页（价格在内嵌 JSON） |
| `https://www.globalsign.com/en/code-signing-certificate` | 官方产品页（资格与区域/寄送限制） |
| `https://codesigncert.com/code-signing-certificate-deals` | **二手**经销商（Sectigo/DigiCert 折扣价、token 运费、签发耗时） |

## 6. 未找到项

- Sectigo 官方标价（只给 25% 折扣表述，无数字）—— **未找到**
- Sectigo 非促销档的 token 费用 —— **未找到**
- DigiCert 官方 token 价格与可寄送国家清单 —— **未找到**
- DigiCert `$44 / month` 与 `subscription $696.00` 的口径换算关系 —— **未找到**
- GlobalSign 个人档是否存在、大陆购买路径 —— **未找到**
- GlobalSign token 运费与硬件费用金额 —— **未找到**
- 三家对中国大陆申请人的官方表述 —— **均未找到**
