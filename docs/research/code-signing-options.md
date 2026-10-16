# 除 SignPath Foundation 之外的代码签名证书购买选项调研

调研时点：**2026-10**
目标读者场景：**中国大陆的个人开发者**，维护**开源的 Windows 桌面应用**（Flutter，GitHub 公开仓库，AGPL-3.0，**个人维护，无公司/无营业执照**），SignPath Foundation 免费签名申请被拒，现评估自购证书。

**来源标注约定（全文统一）**

| 标记 | 含义 | 可信度 |
|---|---|---|
| **【官方】** | 厂商官网 / 商品页 / 支持文档 / 法律条款页的原文 | 高。价格与资格以此为准 |
| **【官方·M】** | Microsoft Learn 官方文档 | 高。SmartScreen 与行业规则的权威来源 |
| **【二手】** | 第三方经销商、评测博客、论坛、目录站转述 | 低。仅作旁证，**不可作为定价依据** |
| **【过时】** | 厂商仍在页面上、但已被官方新文档取代的营销口径 | 不可采信，仅作警示 |

**取数纪律**：本文所有价格数字均来自**本次调研中实际打开并读到原文的页面**，每处附 URL。凡未打开到、或页面上确实没有的，一律写「**未找到**」，**不使用训练数据中的旧价格**。

---

## 一、先给结论：对这位申请者，哪几条路真的走得通

按可行性排序：

| 排名 | 方案 | 到手成本（1 年，官方价） | 为什么可行 / 为什么不行 |
|---|---|---|---|
| **1** | **Certum Open Source Code Signing in the Cloud** | **€49**（免税价，无硬件） | **唯一同时满足**：官方明文「只发给自然人」+ 云端交付无需硬件 + 官方配送政策覆盖大陆（云端档无寄送）+ 面向开源项目。**推荐首选** |
| **2** | **Certum Open Source Code Signing set（实体卡版）** | **€69 + 运费 €35 = €104**（另可能有关税） | 同样只发给自然人，实体卡+读卡器已含在 €69 内。缺点：跨境寄送 7+5 工作日、卡不可退、可能要补税务居民证明 |
| **3** | **SSL.com IV（Individual Validation）** | **$129**（+ 可能的令牌费） | 官方写明 `Business entity required: No`，面向 `Independent developers, open source maintainers`。缺点：**是否有面向开源的折扣未找到**；隐藏成本重（令牌 $379 / 隔夜快递 $599） |
| **4** | **Sectigo OV** | 官方无标价，**未找到** | 官方知识库明确**个人可申请**，但官方页不给价格，且需通过经销商或官方销售询价；token 需邮寄 |
| **5** | **OSSign（免费代签）** | **€0** | 免费，但**当前暂停受理**，且要求 6 个月以上活跃度与运营方可信度风险 |
| **✗** | DigiCert / GlobalSign | — | 官方无个人档（DigiCert）；区域选择以公司注册地为准且 token 不跨区寄送、区域列表无中国大陆（GlobalSign） |
| **✗** | 中国国内 CA（沃通、上海 CA） | — | 证书 O 字段必须填营业执照上的中文名称 → **个人过不了主体资格** |
| **✗** | Azure Trusted Signing | — | Microsoft 官方表格：`Individuals: USA and Canada only` → **大陆个人不可用** |

**一句话**：**Certum 开源档（云端版 €49 或实体版 €69）是这位申请者最现实的路线；SSL.com IV（$129）是第二选择；其余要么没有个人档，要么主体资格卡死。**

---

## 二、五类方案总对比表

### 2.1 价格与资格

| 方案 | 档位 | 价格（官方原文） | 个人（无公司）能否申请 | 大陆居民能否申请 | 交付方式 | 来源性质 |
|---|---|---|---|---|---|---|
| **Certum** | Open Source **in the Cloud** | **from €49.00 / 年** | **能**（`issued only for individuals`） | **能**（云端无寄送） | 云端 SimplySign | 【官方】 |
| **Certum** | Open Source **set** | **from €69.00 / 年** | **能** | **能**（配送表含 China，运费 €35.00） | 加密卡 + 读卡器，邮寄 | 【官方】 |
| **Certum** | Open Source **code** | **from €25.00 / 年** | 能（但需已有卡+读卡器） | 能 | 电子激活码 | 【官方】 |
| **Certum** | Standard in the Cloud | from €209.00 | 未找到（标准档区分个人/组织） | 能 | 云端 | 【官方】 |
| **Certum** | EV Code Signing | from €359.00（set）/ €379.00（cloud） | **不能**（`EV ... cannot be issued for an individual`） | — | — | 【官方】 |
| **SSL.com** | **IV**（Individual Validation） | **$129.00 / yr**（2 年 $116.10/yr，3 年 $109.65/yr） | **能**（`Business entity required: No`） | **未找到**明确限制（见 §4.3） | 云端 eSigner 或硬件令牌 | 【官方】 |
| **SSL.com** | OV | $129.00 / yr | **不能**（`Business entity required: Yes`） | 同上 | — | 【官方】 |
| **SSL.com** | EV | $349.00 / yr（3 年 $249.00/yr） | **不能**（`Business entity required: Yes`） | 同上 | — | 【官方】 |
| **SSL.com** | EV Sole Proprietor | $359.00 / yr（3 年 $254.89/yr） | **能**（`individual developers without a registered business entity`） | 同上 | — | 【官方】 |
| **Sectigo** | OV Code Signing | **官方未标价——【未找到】** | **能**（官方知识库专章讲 organization **or individual**） | **未找到** | FIPS 令牌邮寄 / 自带 HSM | 【官方】 |
| **Sectigo** | EV Code Signing | **未找到** | 未找到 | 未找到 | 同上 | 【官方】 |
| **Sectigo** | HSM Code Signing | **未找到** | 未找到 | 未找到 | 自带 HSM | 【官方】 |
| **DigiCert** | Organization Validated | `Starting at $44 / month / certificate`、`subscription $696.00`（口径存疑，见 §6.2） | **不能**（Validation 维度只有 OV / EV，无 Individual） | **未找到** | KeyLocker 云 / 硬件令牌 / 自带 HSM | 【官方】 |
| **DigiCert** | Extended Validation | `$62 / month / certificate`、`subscription $972.00` | **不能** | 未找到 | 同上 | 【官方】 |
| **GlobalSign** | OV Code Signing | **$529（1 年）/ $623（2 年）/ $715（3 年）** | **未确定**，官方前提指向公司 | **官方路径受阻**（见 §6.3） | USB Token 或 HSM（HSM 不提供） | 【官方】 |
| **GlobalSign** | EV Code Signing | **$669 / $879 / $950** | 未确定 | 同上 | 同上 | 【官方】 |
| **GlobalSign** | OV HSM 版 | **$289** | — | 同上 | 自带 HSM | 【官方】 |
| **OSSign** | 免费代签 | **€0** | 能（不需要真名上证书） | 未找到 | 纯线上 | 【官方】 |
| **沃通 WoSign** | 标准（OV） | ￥3588 / ￥4888 / ￥3488 每年 | **不能** | 地理可以，主体不行 | 硬件安全设备 | 【官方】 |
| **沃通 WoSign** | EV | ￥4288 / ￥5880 / ￥6888 每年 | **不能** | 同上 | 硬件安全设备 | 【官方】 |
| **上海 CA** | 代码签名 | **￥2880 / 年** | **不能**（证书显示组织名称） | 同上 | 安全令牌介质 | 【官方】 |
| **上海 CA** | 增强型 | **￥4280 / 年** | **不能** | 同上 | 安全令牌介质 | 【官方】 |
| **天威诚信** | EV / 普通型 | **【未找到】**（页面无价格） | **未找到** | 未找到 | 符合标准的加密设备 | 【官方】 |
| **CFCA** | — | 官网未列该产品 | — | — | — | 【官方】核查后否定 |
| **Azure Trusted Signing** | — | `~$9.99/month` | **不能**（`Individuals: USA and Canada only`） | **不能** | 云端 | 【官方·M】 |

### 2.2 三问速答

| 方案 | ① 个人（非公司实体）能否申请？ | ② 中国大陆居民能否申请？ | ③ 隐藏成本？ |
|---|---|---|---|
| **Certum 开源档** | **能**（`Open Source Code Signing are issued only for individuals`） | **能**：配送费率表明列 China，运费 **€35.00** 净价；PayPal 可付；条款未排除中国大陆 | 加密卡退货不退款；云端档 **每月 5000 次签名上限**；运费 €35 + 可能关税；需自备**本人名下**水电账单 + 公开可查的开源项目页；需提供税务居民证明的保留条款 |
| **SSL.com IV** | **能**（`Business entity required: No`） | **未找到**明确限制，但也**未找到**可配送国家清单 | YubiKey 令牌 **+$379**；令牌隔夜快递 **+$599**（仅美国本土）；AWS CloudHSM 认证 **$1,500**；Google Cloud HSM 认证 **$500**；自带云 HSM 起步 $500 |
| **Sectigo OV** | **能**（官方知识库给出个人完整验证路径） | **未找到** | 多年度产品**每年寄一个新硬件设备**；HSM 档需自备 HSM；非促销档 token 费用未找到 |
| **DigiCert** | **不能**（无 Individual 档） | **未找到** | 【二手】token 国际运费 $130、加急 $120、美加 $90 |
| **GlobalSign** | **未确定**（官方前提指向公司） | **官方路径受阻**：区域按公司注册地选，token 不跨区寄送，区域列表无中国大陆 | `HSM's are not provided`；token 运费金额未找到；官方公告称现仅售 1 年期 |
| **OSSign** | **能**（且不要求真名上证书） | **未找到** | 名义免费，**隐性代价是信任锚在 OSSign**（用其自有证书代签），运营方背景不透明 |
| **中国国内 CA** | **不能**（沃通、上海 CA） | 地理无障碍，但主体资格卡死 | 硬件强制；邮寄费/加急费/续费涨价条款均**未找到** |
| **Azure Trusted Signing** | **不能**（个人仅 USA / Canada） | **不能** | — |

---

## 三、核心结论：Certum 的 €30 与 €69 之争

**问题**：网上关于 Certum 开源优惠价有 €30 和 €69 两种说法，哪个是真的？

**核实结论（2026-10）**：

> **Certum 当前官方在售的开源档标价是三个，均无 €30 这一档：**
> - **Open Source Code Signing - set：€69.00**（含加密卡 + 读卡器）
> - **Open Source Code Signing - code：€25.00**（电子激活码，**前提是买家已有 cryptoCertum 卡与读卡器**）
> - **Open Source Code Signing in the Cloud：€49.00**（SimplySign 云端交付，无需实体卡）
>
> **在本次调研中打开的所有 Certum 官方页面上，均未出现 €30 这一档标价。**

**€30 的可能来源（推测，需标注为推测）**：€30 很可能是对 **€25 电子码档**的转述讹变，或来自已下线的旧页面／第三方经销商报价。**本次未找到任何当前官方页面支持 €30。**

**官方原文（【官方】，`https://shop.certum.eu/open-source-code-signing.html`）**：

> `from €69.00 gross from €69.00 net`
> `The set includes a Code Signing Certificate, a card reader, and a Certum cryptographic card.`

**官方原文（【官方】，`https://shop.certum.eu/open-source-code-signing-code.html`）**：

> `from €25.00 gross from €25.00 net`
> `An electronic code allows the certificate activation for customers who have their own cryptoCertum cryptographic card and reader.`

**官方原文（【官方】，`https://shop.certum.eu/open-source-code-signing-on-simplysign.html`）**：

> `from €49.00 gross from €49.00 net`
> `Using the SimplySign cloud solution eliminates the need to use a physical card and reader.`

**⚠️ 重要提示**：`€25` 不是「便宜的开源证书」——它的定价前提是买家**已经持有** cryptoCertum 加密卡与读卡器。对首次购买者，真实入门价是 **€49（云端）或 €69（实体 set）**。

**⚠️ 区域定价**：Certum 有三个区域站点，价格不同，比价时必须注明币种与站点：`https://shop.certum.eu/`（€）、`https://certum.store/`（$）、`https://sklep.certum.pl/`（zł）。波兰站开源档为 `od 244,77 zł brutto / 199,00 zł netto`。

### 3.1 Certum 是否强制捆绑硬件卡 / 读卡器？硬件必须邮寄吗？

| 档位 | 是否强制硬件 | 硬件是否邮寄 | 官方原文 |
|---|---|---|---|
| **set（€69）** | **是**，含卡与读卡器 | **是**，`Card activation courier delivery` | set 含 **Mini cryptographic card cryptoCertum 3.7 IDPrime 940C（SIM 卡大小）** + 读卡器（**ACS ACR39T-A1 或 Omnikey 6121**，视库存）；Declaration of Conformity 另写 `cryptoCertum 3.7 card (IDPrime 940C)` 与 `Mini ACR40T-A1 (USB type A)` |
| **code（€25）** | **是**（买家自备） | 否（电子激活码） | `An electronic code allows the certificate activation for customers who have their own cryptoCertum cryptographic card and reader.` |
| **in the Cloud（€49）** | **否** | **否** | `Using the SimplySign cloud solution eliminates the need to use a physical card and reader.` 要求仅为：SimplySign 手机 App + SimplySign Desktop + 云账号 + 联网 |

> **答案：不强制。想完全避开实体卡与读卡器，选 €49 云端档即可。** 这是 Certum 相对大多数 CA 的关键优势——绝大多数 CA 的 OV 档都强制硬件令牌（见 §七）。

**硬件规格（set 档，【官方】）**：RSA 3072 bit、密钥存储 `CC EAL6+`；Requirements 列 proCertum CardManager 程序、读卡器驱动、**cryptoCertum 3.6 或 3.7 卡**、initialized common card profile。

### 3.2 硬件能否寄达中国大陆？

**能。** 来源：`https://shop.certum.eu/payment-shipping`（**【官方】条款页**）。非欧盟配送费率表原文（逐字）：

> `Albania, Bosnia and Herzegovina, Canada, **China**, Georgia, Gibraltar, Guernsey, Holy See, Iceland, Kosovo, Libya, Liechtenstein, Moldova, Monaco, Montenegro, Norway, Panama, Paraguay, Qatar, San Marino, Serbia, South Korea, Switzerland, Thailand, Turkey, United Arab Emirates, United Kingdom | €35.00`

同表另列：台湾 €60、香港 €65、日本 €63、印度 €94。

同页原文：

> `Shipments sent outside the EU may be subject to a customs duty that is paid at the time of import by the buyer.`

条款页 `https://shop.certum.eu/terms-and-conditions`（**【官方】**）：

> `All prices are shown in EUR, including value added tax and other costs due under applicable legislation... in the event the Products or Goods are shipped outside the European Union and a relevant public office charges a customs duty or an excise duty, the costs shall be transferred to the Customer.`
> `Asseco Data Systems SA may require the Customer to provide a document confirming their tax residence in specific situations.`

→ **中国大陆在配送范围内，运费 €35.00（净价）；欧盟外可能另有关税，由买家承担；Certum 保留要求客户提供税务居民证明的权利。** 条款未排除中国大陆。

### 3.3 Certum 是否面向个人（非公司）销售？

**是，且开源档明确「只发给自然人」。** 来源：`https://support.certum.eu/en/code-signing-required-documents/`（**【官方支持文档】**）原文：

> `Open Source Code Signing are issued only for individuals`
> `Issued certificate will contain „Open Source Developer" phrase added to the Common name field. Organization field will be set to „Open Source Developer".`
> `If Certum determines that the certificate is being used to sign software distributed commercially, the certificate will be revoked.`

商品页 Specification 重复同一句：`Data in the certificate: natural person data prefixed with "Open Source Developer" phrase`。

**对比：Certum 的 EV 档明确排除个人**（同页原文）：

> `EV Code Signing certificates are issued only for organization – they cannot be issued for an individual`
> `To issue the certificate, confirmation of having a physical office registered to the organization's data is required`

→ **开源档是自然人专属档位，O 字段直接填 `Open Source Developer`，不需要营业执照。** 这正是本项目（个人维护的开源应用）的适配档位。**风险条款**：若 Certum 认定证书被用于给商业分发软件签名，证书会被吊销。

### 3.4 Certum 申请流程与耗时

**流程**（`https://support.certum.eu/en/how-to-buy-code-signing/`，**【官方】**）：

> `Choose in the store the Code Signing certificate and add it to the shopping cart`
> `Create a new account or log in`
> `Provide the address information and make sure the data is entered correctly. The data to be included in the certificate you will provide during the certificate activation process`
> `Choose the payment method: Quick transfer / Standard transfer`
> `After payment is received, the certificate will be available for activation in My account/Data security products.`

支付方式：Quick transfer（eCard 卡支付、电子转账、**PayPal**、Blik、Google Pay）、Standard transfer（网银/银行网点/邮局汇款）→ **PayPal 对中国大陆用户友好。**

**所需的额外材料**（同支持文档，**这一条最容易卡住申请**）：

> `utility bill (gas, electricity, water, telephone, etc.), issued for the subscriber`
> `website address of the ongoing Open Source project: The project must be publicly available and indicate clearly the subscriber's relationship with the project. If Certum is unable to identify the project based on publicly available information, the certificate will not be issued.`

→ 需要 **① 开在申请人本人名下的水电/电话账单** + **② 开源项目网址，且项目页面须清楚表明申请人与该项目的关系**。若 Certum 无法从公开信息确认项目归属，**不予签发**。
身份验证四选一：自动身份验证（推荐）／注册点当面确认／公证确认／**提交本人手持身份证件照片**（身份证、护照、驾照、永久居留卡，需能比对本人面部与证件照片，证件正反面完整）。

**耗时**（`https://shop.certum.eu/terms-and-conditions`，**【官方】**）：

> `A regular time of completion of an order is 7 Business Days, counting from the ... of receipt of ... by the Customer.`
> `Delivery time is up to 5 Business Days from a shipping date.`
> `the time of delivery by a courier company in the case of delivery outside the European Union may be longer in situations completely beyond the Vendor's control, for example in the case of a customs inspection.`

→ **官方数字：订单处理通常 7 个工作日 + 配送最多 5 个工作日**（实体 set 档）。欧盟外可能因海关更久。
→ **注意：这 7 个工作日是「订单处理」时间，不含证书激活所需的身份验证耗时。官方未给出身份验证环节的时限——未找到该时限的官方数字。**
→ 云端档（€49）无配送环节，理论上更快，但官方同样未给出激活时限。

### 3.5 Certum 的其他隐藏成本

| 项目 | 情况 | 来源 |
|---|---|---|
| 加密卡退货 | **不退款**：`in case of returning the Open Source Code Signing set, it is not possible to return the cryptographic card and refund for it.` | 【官方】商品页 Note |
| 云端档签名次数 | **每月上限 5000 次**：`for Code Signing products in the cloud, there is a certificate usage limit of 5000 signatures per month. Exceeding this limit may result in contacting you to inform you of the exceedance and possible blocking of the product in the month in which the limit was used.` | 【官方】云端商品页 Note |
| 运费 | **€35.00**（中国大陆，净价，实体档） | 【官方】配送页 |
| 关税 | 欧盟外可能被征，**由买家承担** | 【官方】条款页 |
| 证书有效期新规 | 自 **2026-02-27** 起单个 Code Signing 证书最长有效期降为 **459 天**；2/3 年期产品在有效期内需**免费重签发**一次或多次 | 【官方】商品页公告 |
| 域名/IP | `Open Source Code Signing certificates cannot contain domain names or IP addresses` | 【官方】支持文档 |
| 商业分发 | 若被认定用于商业分发软件，**证书会被吊销** | 【官方】支持文档 |

---

## 四、SSL.com

### 4.1 价格（**【官方定价页】**，四个独立商品页）

| 档位 | 商品页 URL | 1 年 | 2 年（每年） | 3 年（每年） | `Business entity required` |
|---|---|---|---|---|---|
| **IV**（Individual Validation） | `https://www.ssl.com/products/software-integrity/code-signing/iv/` | **$129.00/yr** | $116.10/yr（Save 10%） | $109.65/yr（Save 15%） | **No** |
| **OV** | `.../code-signing/ov/` | **$129.00/yr** | 同档位表 | 同档位表 | **Yes** |
| **EV** | `.../code-signing/ev/` | **$349.00/yr** | $299.00/yr | $249.00/yr | **Yes** |
| **EV Sole Proprietor** | `.../code-signing/ev-sole-proprietor/` | **$359.00/yr** | $308.74/yr | $254.89/yr | **No (individual validation)** |

IV 页原文（**【官方】**）：

> `no business registration required`
> `the IV tier gives solo developers access to Authenticode signing without` [a corporate legal entity]
> `issued in minutes`
> Who it's for：`Independent developers, open source maintainers`

EV Sole Proprietor 页原文：面向 `individual developers without a registered business entity`。

### 4.2 是否有面向开源项目或个人开发者的优惠计划？

**结论：SSL.com 没有面向开源项目的免费或折扣计划——「SSLcom有OSS计划」这条判断被推翻。**

已核查的三条独立路径（均**【官方】**）：

| 核查动作 | 结果 |
|---|---|
| `https://www.ssl.com/?s=open+source+code+signing`（站内搜索） | HTTP 200，正文 11169 字符，**无任何开源计划条目** |
| `https://www.ssl.com/faqs/`（FAQ 索引） | HTTP 200，正文 9562 字符，匹配 `open source` 上下文 **0 条** |
| `https://www.ssl.com/?s=open+source` | HTTP 200，扫描全部 **59 条**站内链接，无一命中 `open-source` / `open_source` / `oss` / `nonprofit` / `non-profit` |

**最接近「开源友好」的只有 IV 档**：它对个人开放、无企业实体要求，价格 $129/年，且商品页把 `open source maintainers` 列为目标人群——但它是**普通在售商品档位**，没有面向开源项目的免费额度、折扣或申请流程。

### 4.3 三问

- **个人能否申请？** **能，但只有 IV 与 EV Sole Proprietor 两个档位。** OV 与 EV 标准档页写明 `Business entity required: Yes`。
- **中国大陆居民能否申请？** **部分证据，未完全确定。** 已核实的是：SSL.com 是面向全球销售的美国 CA，四个商品页上**没有**任何「限某地区」的资格限制文字（对比 GlobalSign 明确写 `If you select a region that does not match your legally registered company details, your order will be canceled`）。**未找到**：SSL.com 是否明确支持中国大陆地址收件、是否对中国大陆申请人有额外审核要求、官方是否公布可配送国家列表。
- **隐藏成本？** **有，且金额可观**：

| 项目 | 价格 | 页面原文 |
|---|---|---|
| YubiKey 物理令牌 | **+$379.00**（每个） | 令牌为可选加购项 |
| 自带云 HSM 自管 | `Starting at $500.00` | — |
| AWS CloudHSM 认证费 | **$1,500** | `This fee is a one-time charge per order.` |
| Google Cloud HSM 认证费 | **$500** | 同上 |
| 令牌隔夜快递 | **+$599.00** | `Token shipped overnight in continental US.` |
| eSigner 云 HSM 订阅 | 订阅制，可**免除**硬件令牌 | — |

→ **$129 的 IV 档价格不是到手成本。** 若不使用 eSigner 云端签名，需额外购置 FIPS 令牌（$379）或自备合规 HSM。**未找到**「不使用 eSigner 时令牌为必选」的明文，商品页把 YubiKey 列为加购项。

### 4.4 有效期新规（**【官方】**）

`https://www.ssl.com/certificates/ev-code-signing/` 原文：

> `Effective March 1, 2026, new industry requirements from the CA/Browser Forum will limit the maximum validity period of publicly trusted code signing certificates to 458 days. In preparation, SSL.com began enforcing this 458-day cap on certificate issuance starting February 27, 2026.`

→ 买 3 年期**不等于**拿到一张 3 年有效的证书，而是 3 年内**多次重签发**（每次最长 458 天）。

---

## 五、Sectigo / DigiCert / GlobalSign

### 5.1 三家横向对比（对应「三大CA需企业」判断）

原判断：「Sectigo、DigiCert、GlobalSign 的 OV 代码签名证书要求申请者为组织，个人无法以自然人身份购买。」

**核查结论：该判断被推翻，但不均匀——三家必须拆开表述。**

| CA | 个人能否申请 OV 代码签名 | 官方标价 | 依据 |
|---|---|---|---|
| **Sectigo** | **能** | **官方页不给价格**【未找到】 | 官方知识库专页 `OV Code Signing Validation for Organizations and Individuals` |
| **DigiCert** | **未见个人档** | `Starting at $44 / month / certificate`、`subscription $696.00` | 官方配置器 Validation 维度只有 OV / EV，OV 副标题 `Standard verification of your organization` |
| **GlobalSign** | **未确定，官方前提指向公司** | OV **$529 / $623 / $715**；EV **$669 / $879 / $950**；OV HSM **$289**；EV HSM **$410** | 产品等级只有 OV；购买页以 `your Company is legally registered` 为前提 |

### 5.2 Sectigo（**关键发现：官方明确允许个人申请 OV**）

来源：`https://www.sectigo.com/knowledge-base/detail/OV-Code-Signing-Validation-for-Organizations-and-Individuals`（**【官方知识库】**，标题即 `OV Code Signing Validation for Organizations and Individuals`）原文：

> `OV Code Signing validation confirms three key things: The identity of the software publisher (organization or individual)`
> `OV Code Signing validation includes the following checks, depending on whether the certificate is issued to an organization or an individual`
> For Individuals — `Proof of the individual's legal identity using automated Video ID session using a valid, government-issued photo ID.`
> For Individuals — `Verification of physical presence using reliable sources, such as government-issued identification or trusted public records`
> `Confirms that the certificate request was legitimately authorized by the individual applicant or by an authorized representative of the organization`

→ **Sectigo 的 OV 代码签名证书可以签发给自然人**，验证方式是「自动 Video ID 会话 + 政府签发的带照片身份证件」，物理地址用身份证或可信公开记录核实。证书主体名称对个人没有「必须是法定公司名」的要求。主产品页亦印证：`The legal existence of the organization or individual named in the Organization field of the certificate must be verified.`

**价格**：官方产品页 `https://www.sectigo.com/ssl-certificates-tls/code-signing`（**【官方定价页】**）**不印任何具体价格数字**，唯一优惠表述是：

> `25% Savings off list price with Free Token with 5-year purchase deal`
> `Free FIPS-Compliant token will be shipped to you each year, for the duration of your package.`

→ **Sectigo 官方标价：未找到。** 需询价或走经销商。
**【二手】参考**（`https://codesigncert.com/code-signing-certificate-deals`，经销商站）：`Sectigo Code Signing (OV)` 3 年期 **$226.10/yr** 标价，用 10% 券后 **$203.49/yr**；`Sectigo EV Code Signing` **$296.65/yr** → **$266.99/yr**。该页亦列 `Comodo Individual Code Signing` 同价 **$203.49/yr**，并说明 `Comodo certificates are issued from the Sectigo root`（Comodo CA 已改名 Sectigo，同一家）。

**有效期新规**（**【官方】**）：

> `Starting February 23, 2026, the CA/B Forum has changed the maximum certificate lifecycle for Code Signing certificates. Industry regulations require all Certificate Authorities to issue certificates no longer than 459 days (approximately 15 months).`
> `As of February 23, 2026, you will no longer be able to issue a single multi-year Code Signing certificate on a single FIPS-compliant device. Instead, if you purchase a multi-year Code Signing product from Sectigo you will receive a new compliant hardware device with a new certificate each year.`

物理介质规则：`As of June 1, 2023 Code Signing certificates are: Installed on a Sectigo token and shipped securely to the customer.`

**三问**：个人**能**申请；大陆居民**未找到**官方表述（可通过经销商网络购买，token 是实体硬件需邮寄）；隐藏成本为**多年度产品每年寄一个新硬件设备**、HSM 档需自备 HSM、非促销档 token 费用**未找到**。

### 5.3 DigiCert

来源：`https://www.digicert.com/signing/code-signing-certificates`（**【官方定价页】**，配置器）。
> 取证备注：该 URL 首次抓取被 **Incapsula** 拦截（`Request unsuccessful. Incapsula incident ID: 446000400280108563-24221669958486571`，正文 83 字符）；更换 `User-Agent`（Chrome 131）后第二次抓取成功（HTTP 200，正文 17686 字符）。

**Validation 维度只有两个选项，没有 Individual**：

| 选项 | 页面副标题原文 |
|---|---|
| `Organization Validated` | `Standard verification of your organization` |
| `Extended Validation` | `Required for signing Microsoft Windows drivers` |

**Storage 四选项**：`DigiCert KeyLocker Cloud`（`Host my key in the cloud for remote code signing`）／`DigiCert-Provided Hardware Token`（`Send me a hardware eToken to store my key`）／`My Own Qualified Hardware Token`／`Hardware Security Module (HSM)`。

**价格（原文照录）**：

> `Number of Code Signing Certificates - Quantity +` `Starting at $44 / month / certificate` `12 month auto-renewing` `Your subscription will automatically renew every 12 months until you cancel. Prices subject to change.` `subscription $696.00`
> `Certificates - Quantity +` `$62 / month / certificate` `12 month auto-renewing` `subscription $972.00`

**⚠️ 价格读数的歧义（如实标注，不作推算）**：页面把 `$44 / month / certificate` 与 `subscription $696.00` 并排展示，两者**不是**简单 12 倍关系（$44 × 12 = $528）。**未找到**官方对这组数字的口径说明，因此本文只照录两个数字，**不给出「年费 = X」的换算结论**。

**是否年费**：**是订阅制**，`12 month auto-renewing`，自动续订直到取消，且 `Prices subject to change` → **官方保留调价权**。

**是否有开源计划**：`https://www.digicert.com/insights/open-source`（**【官方】**，正文 13198 字符）标题 `DigiCert Open Source — Open. Collaborative. Compliant.`，内容全部是**把自家工具开源**（TrustCore SDK、DCV 库），**不是**给开源项目发免费签名证书 → **无**。

**三问**：个人**不能**（无 Individual 档）；大陆居民**未找到**官方表述；隐藏成本 **【二手】** token 国际运费 **$130**（`Secure delivery outside the US and Canada.`）、加急 $120、美加 $90，另称签发耗时 `3 to 5 business days once validation clears`，但该页**未列可寄送国家清单**，中国大陆是否在内**未找到**。

### 5.4 GlobalSign（**对大陆用户存在硬门槛**）

来源：`https://shop.globalsign.com/en/code-signing`（**【官方定价页】**）。价格不在可见正文，而嵌在页面定价 JSON 中：

| JSON 键 | 含义 | USD | EUR |
|---|---|---|---|
| `cs_one_yr` | OV 代码签名 1 年 | **$529** | 470 € |
| `cs_two_yr` | OV 2 年 | **$623** | 561 € |
| `cs_three_yr` | OV 3 年 | **$715** | 647 € |
| `ev_cs_one_yr` | EV 1 年 | **$669** | 487 € |
| `ev_cs_two_yr` | EV 2 年 | **$879** | 687 € |
| `ev_cs_three_yr` | EV 3 年 | **$950** | 779 € |
| `cs_hsm_one_yr` | OV HSM 版 1 年 | **$289** | 249 € |
| `ev_cs_hsm_one_yr` | EV HSM 版 1 年 | **$410** | 309 € |

**⚠️ 同一批 JSON 内还含 SSL 证书价格**（`dv_ssl_one_yr` $249、`ov_ssl_one_yr` $349、`ev_ssl_one_yr` $611），**不要与代码签名价格混淆**；上表只取 `cs_*` / `ev_cs_*` 键。

**⚠️ 与官方公告冲突**：`https://www.globalsign.com/en/code-signing-certificate` 原文写 `Only 1-year (366-day) Code Signing Certificates are now available.`，但 shop 定价 JSON 仍保留 2/3 年价格键 → **两处并存**，下单前应以后者实际结算为准。**是年费性质**（按年定价）。

**对大陆用户的硬门槛（官方购买流程页原文）**：

> `Select the correct region based on where your Company is legally registered. If you select a region that does not match your legally registered company details, your order will be canceled.`
> `Note for Token-based orders – Tokens will not be shipped outside of the Region you select when ordering.`

可选区域列表原文：`North America, South America & Canada` / `United Kingdom` / `Europe and Africa` / `Middle East` / `Asia & Pacific` / `Japan` —— **列表中没有中国大陆**。页面另有货币选项包含 `CNY - Yuan Renminbi`，页脚有 `沪ICP备08025378号`（说明在中国境内有备案实体）。

→ **购买流程以「公司法定注册地」为区域选择依据，且 token 只在所选区域内寄送。区域列表无中国大陆，因此大陆个人通过官方 shop 直接下单的路径未打通。**

**三问**：个人**未确定**——官方页在 USB Token 描述里出现 `Ideal for individuals or small teams`，但产品等级只有 `Organization Validation (OV)`，且购买页反复以 `your Company is legally registered` 为前提，**官方没有**像 Sectigo 那样给出明确的个人验证路径；大陆居民**官方路径受阻**；隐藏成本 `HSM's are not provided`、token 运费金额**未找到**。

---

## 六、其他面向开源项目的免费或折扣代码签名计划

### 6.1 汇总

| 计划 | 性质 | 对个人开放 | 当前可否申请 | 来源性质 |
|---|---|---|---|---|
| **OSSign**（ossign.org） | 免费（由 OSSign 自有证书代签） | 面向项目，**不要求真名上证书** | **暂停受理** | 【官方】 |
| **Certum Open Source Code Signing** | 付费折扣档（**非免费**），€49 / €69 | **仅面向自然人** | 可购 | 【官方】 |
| **SignPath Foundation** | 免费（用户已被拒，作为基准对照） | 面向项目 | 用户已被拒 | 已有背景 |
| SSL.com | **不存在** OSS 计划 | — | — | 【官方】核查后否定 |
| DigiCert | **不存在** OSS 计划 | — | — | 【官方】核查后否定 |
| Sigstore / Fulcio | 免费签名，**但不产生 Windows 信任签名** | — | 不适用 | 【二手】 |
| Azure Trusted Signing | $9.99/月起，**非** OSS 计划 | **个人仅限 USA / Canada** | 大陆个人不可用 | 【官方·M】 |

→ 对「存在其他OSS计划」这条判断：**成立，但可用性很差**。除 SignPath 外确实存在至少一个同类组织（OSSign），但它**当前暂停受理申请**；另一个可用的开源折扣渠道（Certum OSS）是**付费**而非免费。

### 6.2 OSSign（`https://ossign.org/`）—— 除 SignPath 外**唯一**找到的同类免费计划

> 取证说明：`https://ossign.org/` 是 React SPA（原始 HTML 仅 1578 字节，`<div id="root">` 空容器），正文全部打包在 `/assets/index-D2_uN95z.js`（356013 字节）。以下引文均从该 JS bundle 的字符串常量中提取，**【官方】**。

**定位与机制**：

- 站点标题：`OSSign - Code Signing for Open Source`
- 首页原文：`Free signatures for open source projects`、`Apply for Free Signing`
- 机制：**由 OSSign 用自己的证书代签**，不是把证书发给项目方。FAQ 原文：

> `Do I have to put my personal name on the certificate?`
> `No, since we sign the binaries with our certificates your real name does not have to appear anywhere on the certificate, signature or binary if you do not want it to.`

- 另有付费延伸：`* EV certificates and attestation signing available for select projects where necessary.`

**⚠️ 当前状态：暂停受理（对用户最关键的一条）**。申请页原文：

> `Applications are currently suspended due to a high workload and large backlog while we focus on assessing and responding to the applications in the queue. Please check back in a few weeks.`

联系页补充：`You can still contact us about ongoing applications or general questions, but the response time might be longer than usual.`、`We are not accepting applications for code signing through this contact form`

**资格要求（申请页原文）**：

| 要求 | 原文 |
|---|---|
| 许可证 | `The majority of your project must be published under an OSI-approved open source license (MIT, Apache, GPL, etc.). All the code included in the final release must be available for public review.` |
| 活跃度 | `Your project should be actively maintained and have a demonstrable user base or community.` |
| **账号年限（硬门槛）** | `There is an absolute minimum of 6 months of activity on your account, organization and project.` |
| 构建流水线 | `Your repository needs to have a build pipeline configured, where the entire build process is clearly verifiable and the source for each build is directly linked to the resulting release binaries. This pipeline should include code quality checks.` |
| 排除项 | `Political or controversial projects` |

→ **注意 6 个月门槛**：本项目仓库创建于 2026-09-13（见 `docs/code-signing.md` 背景），到 2026-10 时点**不足 6 个月**。即使 OSSign 恢复受理，按此条也暂不符合。

**⚠️ 运营方可信度风险（须提示）**。RDAP 查询 `https://rdap.org/domain/ossign.org`（HTTP 200）：

| 字段 | 值 |
|---|---|
| 注册时间 | `03/11/2025 09:25:08` |
| 到期时间 | `03/11/2027 09:25:08` |
| 最后变更 | `08/12/2026 09:51:02` |
| 状态 | `client transfer prohibited` |
| 注册商 | `Hosting Concepts B.V. d/b/a Registrar.eu` |
| 注册人信息 | **未公开**（whois 隐私保护） |

→ **该域名 2025 年 3 月才注册，运营方身份在公开注册信息中不可见，页面上也没有可核验的法人主体、基金会背景或审计信息。** 「用自有证书代签」的模式意味着**签名信任锚在 OSSign 而非项目方**，一旦其证书被吊销或服务终止，已签名版本的信任链随之失效。**未找到**任何第三方对其资质的独立评价。

**⚠️ 名称易混淆**：`https://github.com/OSSign/OSSign` 是**另一个东西**——一个用 Go 写的跨平台代码签名 CLI（`Open Source cross-platform code signing`，`AGPL-3.0 license`，基于 Relic，支持 `PE/COFF MSI JAR APK DMG`）。它与 `ossign.org` 的免费代签服务**不是同一项服务**。

### 6.3 Certum Open Source 档（付费折扣，非免费）

严格说这不是「免费计划」，但它是**唯一一个面向个人的开源折扣档位**，价格远低于商业 OV 档。要点：官方支持文档原文 `Open Source Code Signing are issued only for individuals`、`Organization field will be set to „Open Source Developer"`；商业用途限制 `If Certum determines that the certificate is being used to sign software distributed commercially, the certificate will be revoked.`；价格 set €69 / cloud €49 / code €25。

**【二手】旁证**（`https://my-ssl.com/learn/open-source-code-signing-certificate`，经销商站）：该页称 `My-SSL sells Certum's Standard and EV code signing certificates, not the Open Source tier, which Certum sells directly.`，并给出自家 Certum 标准档 **$99 / year** 的报价。
→ **该 $99 是经销商自家标准档价格，不是 Certum 官方开源档价格，不可混用。**

### 6.4 已核查并否定的候选

| 对象 | 核查结论 | 依据 |
|---|---|---|
| **SSL.com** | 无开源计划 | 站内搜索 + FAQ + 59 条站内链接全扫（见 §4.2） |
| **DigiCert** | 无开源签名计划 | `https://www.digicert.com/insights/open-source` 是开源自家工具（见 §5.3） |
| **Sigstore / Fulcio** | **不适用于 Windows 桌面应用签名** | 【二手】`https://comparecheapssl.com/free-code-signing-certificate-and-how-to-get-it/` 原文：`it does not produce signatures that Windows SmartScreen trusts for .exe, .dll, .msi`；`Fulcio's root isn't in the Microsoft Trusted Root Program, and the signature sits in a separate bundle file Windows never opens.` |
| **Azure Trusted Signing** | 不是 OSS 计划，且**大陆个人不可用** | 【官方·M】`https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options`：`Azure Artifact Signing (formerly Trusted Signing) | ~$9.99/month | Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only` |
| **Apache / Linux Foundation / NLnet 等基金会类计划** | 多轮检索后**未找到** | 见下 |

**检索记录**：多轮检索（`free code signing certificate for open source projects program`、`"open source" code signing certificate discount CA program 2026`、`DigiCert open source code signing program free`、`GlobalSign open source code signing program`、`Sectigo open source code signing discount`）返回的候选**全部**是：SignPath、OSSign、Certum OSS、以及第三方评测/经销商页 → **除 OSSign 外，未找到其他同类组织。**

**目录站线索（未能取到完整内容）**：

| 站点 | 情况 |
|---|---|
| `https://www.ossperks.com/programs/signpath` | 目录站，可正常打开（正文 2810 字符），但收录内容**只有 SignPath 一家**的 code signing 条目；`https://www.ossperks.com/programs` 列表页为 JS 渲染（正文仅 713 字符），**未取到完整计划清单** |
| `https://foropensource.com/company/certum/`、`https://foropensource.com/company/signpath/` | 第三方目录站，属**【二手】**，本轮未逐页核实 |

---

## 七、中国国内的 CA

### 7.1 汇总

| CA | 是否提供代码签名证书 | 标价（**【官方】**） | 个人能否申请 |
|---|---|---|---|
| **沃通 WoSign** | 是（EV 3 款 + OV 3 款） | EV ￥4288 / ￥5880 / ￥6888 每年；OV ￥3488 / ￥3588 / ￥4888 每年 | **否**，证书 O 字段显示**营业执照上的中文名称** |
| **上海 CA（sheca）** | 是（2 款） | ￥2880/年、￥4280/年 | **否**，证书显示**组织名称** |
| **天威诚信 iTrusChina** | 是（EV 型 + 普通型） | **未找到**（页面无价格） | **未找到**明确表述 |
| **CFCA** | **官网未列该产品** | — | — |
| 阿里云 / 腾讯云 | **未找到**代码签名产品 | — | — |

→ 对「中国CA需执照」这条判断：**倾向成立**。沃通官方页明确写 O 字段填营业执照中文名称，上海 CA 明确写证书显示「组织名称」；但天威诚信与 CFCA 的个人资格**未能证实也未能证伪**，覆盖边界如实标注。

### 7.2 沃通 WoSign

**价格**（`https://www.wosign.com/Products/code_signing.htm`，**【官方】**）：

| 产品 | 价格 |
|---|---|
| EV 代码签名证书 Pro | **￥6888 / 年** |
| EV 代码签名证书 Pre | **￥5880 / 年** |
| EV 代码签名证书 | **￥4288 / 年** |
| 标准代码签名证书 Pro（OV） | **￥4888 / 年** |
| 标准代码签名证书 Pre（OV） | **￥3488 / 年** |
| 标准代码签名证书（OV） | **￥3588 / 年** |

**多年期**（`https://www.wosign.com/Products/OV_CodeSigning_Pro.htm`）：一年 **￥4888** / 二年 ￥8588 / 三年 **￥12688**（≈￥4229/年，比一年**省约 13%**）。

**个人资格：否（关键原文）**：

> `证书主题中"O"字段(Organization)会显示申请单位的中文名称。`
> `中文版的软件发行商名称为公司中文名称,也就是营业执照上的中文名称。`
> `我们认可中文名称营业执照作为证明文件。`

免责条款：`沃通有权核实用户购买代码签名证书的用途，如发现非本单位使用或有签名恶意软件的意图，有权拒绝颁发。`

产品列表 `https://www.wosign.com/Products/` 中代码签名相关条目为 `代码签名证书 / EV代码签名证书 Pro / 标准代码签名证书 Pro / EV代码签名证书 / 标准代码签名证书 / WHQL徽标认证服务`——**没有任何面向自然人的个人代码签名档位**。

**介质**：`国际标准要求，OV代码签名证书自2023年6月1日起，与EV代码签名证书一样，必须采用硬件安全设备（HSM、USBKey等）存储证书` → 硬件是成本的一部分（**标价是否含硬件未找到**）。

**⚠️ 过时口径**：同页 EV 档写 `SmartScreen即时信誉`，OV 档写 `累计下载获得`——与 Microsoft 官方文档冲突（见 §八）。

### 7.3 上海 CA

`https://www.sheca.com/assets/wwx/page2.html`（**【官方】**）原文摘录：

| 项目 | 代码签名证书 | 增强型代码签名证书 |
|---|---|---|
| **价格** | **￥2880/年** | **￥4280/年** |
| 证书中显示验证信息 | **组织名称** | **组织名称、组织地址、组织类型** |
| Hash 算法 | SHA256 | SHA256 |
| 证书存储介质 | 安全令牌介质，文件 | 安全令牌介质 |
| 特性 | 消除系统"未知发行商"的安全警告 | 支持内核模式代码签名、获得 Microsoft SmartScreen |

同页另有一句影响判断的原文：`在软件安装过程中显示公司名字，提升软件的可信度。` → **明确指向企业主体**。页面**未直接写**「个人不可申请」，但证书显示信息为**组织名称**、营销文案写「显示公司名字」，**没有任何个人档位或自然人路径的表述**。

### 7.4 天威诚信 iTrusChina（信息不完整）

`https://www.itrus.com.cn/code.html`（**【官方】**）页面存在，`<title>` 与栏目为「代码签名证书」，正文要点：

> `EV型代码签名证书 在标准代码签名证书已有的优点基础上，提供更强有力保障…可直接获得微软SmartScreen过滤器的即时信誉。`
> `普通型代码签名证书 针对网上发布控件、应用程序、驱动程序…`

**未找到**：价格数字（全页无 ￥ 或「元/年」标注）；个人能否申请的明确表述（页面只泛称「申请者」「发布者」，无「营业执照」「个人」「身份证」字样）；独立详情页（`https://www.itrus.com.cn/code-sign.html` 与 `https://www.itrus.com.cn/codesign.html` 均返回 **HTTP 500**）。
同页 EV 档写 `可直接获得微软SmartScreen过滤器的即时信誉`——**与 Microsoft 官方文档冲突**，属**【过时】**。

### 7.5 CFCA —— 【官方】核查后否定

`https://www.cfca.com.cn/` 首页（HTTP 200，103170 字节）与全站导航（逐条提取 `<a href>` 后共 100+ 条链接）中：**无「代码签名」字样**（正则 `代码签名|Code Sign` 命中 **0** 条）。数字证书类产品只有 `数字证书`、`设备证书`、`普通服务器证书`、`全球信任体系证书`、`国密服务器证书`、「机构/个人数字证书」（面向电子合同/身份认证，非代码签名）。相关目录页 `/products/`、`/product/`、`/codesign/` 均无该项。

→ **CFCA 官网未列代码签名证书产品。** 这不等于 CFCA 绝对不签发（可能有线下渠道），但**公开可核验的官方页面上没有**，故记为「未找到」，不作为候选方案。

### 7.6 云厂商（阿里云 / 腾讯云）—— 【官方】核查后否定

`https://www.aliyun.com/product/cas`（HTTP 200）与 `https://cloud.tencent.com/product/ssl`（HTTP 200）：正则 `代码签名|Code Sign` 命中均 **0** 条 → 两家的证书产品页均**未列**代码签名证书。

### 7.7 三问逐答（中国国内 CA）

- **个人（非公司实体）能否申请？** 沃通 **否**、上海 CA **否**、天威诚信 **未找到**、CFCA 不适用。
- **中国大陆居民能否申请？** **地理上无障碍**（四家均为中国大陆注册机构，无需跨境购买，硬件国内寄送，无跨境运费或海关问题——对比 Certum 的 China €35.00 运费与可能关税）。**但主体门槛横在个人面前**：沃通与上海 CA 的证书字段要求组织名称/营业执照，**大陆个人即使地理可达也过不了主体资格这一关**。
- **隐藏成本？** 硬件令牌（沃通 OV 与 EV 均强制硬件存储）；邮寄费、加急费、续费涨价条款**均未找到**；多年期折扣：沃通 OV Pro 三年 ￥12688 比一年 ￥4888 **省约 13%**。

---

## 八、OV 与 EV 在 SmartScreen 上的待遇差异（**本调研最反直觉的一条**）

### 8.1 结论

**OV 与 EV 在 SmartScreen 上的待遇已经趋同，两者都不再享有「首次下载即无警告」的特权。**

- **历史上**（约 2024 年之前）：EV 证书签名后**立即**获得 SmartScreen 信誉，用户首次下载即不弹警告；OV 需靠下载量慢慢累积。
- **现在**（2024 年起）：**EV 的即时信誉特权已被移除**，OV 与 EV 待遇相同，都靠下载量累积信誉，首次下载都会警告。
- **因此：为了绕过 SmartScreen 警告而多付 EV 溢价，已不再有正当理由。**（这是 Microsoft 官方的口径）

### 8.2 Microsoft 官方文档原文（**【官方·M】**）

`https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation`（`ms.date: 2026-05-04`）：

| 签名类型 | SmartScreen 行为 |
|---|---|
| `Valid Certificate (OV/EV)` | `⚠️ Warning — app flagged as unrecognized until reputation accumulates; verified publisher name is displayed` |
| `Microsoft Store` | `✅ No warning` |
| `No signature` | `⚠️ Warning — "Windows protected your PC"` |
| `Self-signed Certificate` | `⚠️ Warning — Same behavior as no signature` |

核心段落（逐字）：

> `EV certificates no longer bypass SmartScreen. Years ago, signing files with an Extended Validation (EV) code signing certificate would result in positive SmartScreen reputation by default, but this behavior no longer exists. EV certificates may matter for enterprise procurement, but they no longer impact SmartScreen behavior. Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified.`

> `There is no exact threshold, but it can take several weeks and hundreds of clean installs from a wide audience.`

两个独立信号：`Publisher reputation` 与 `File hash reputation`。

`https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options`（`2026-08-29`）：

> `EV certificates previously bypassed SmartScreen entirely on first download... That behavior was removed in 2024.`
> `As of June 2023, the CA/Browser Forum requires private keys for OV certificates to be stored on a hardware security module (HSM) or hardware token.`

中文官方页 `https://learn.microsoft.com/zh-cn/windows/apps/package-and-deploy/distribution-feature-status`：

> 「**SmartScreen 信誉度：EV 证书不再提供直接绕过的权限**  状态：2024 年的行为已更改」
> 「Microsoft 在 2024 年更新了受信任根计划的要求，删除了特定于 EV 的 OID。无论证书类型（OV 或 EV）如何，SmartScreen 信誉现在都是基于哈希的」

### 8.3 过时反例清单（**须警示**）

| 出处 | 原文 | 定性 |
|---|---|---|
| `https://learn.microsoft.com/en-us/answers/questions/417016/...`（Microsoft Q&A，**2021 年**） | `An EV code signing certificate offers an immediate reputation with Microsoft SmartScreen` | **【过时】**。虽是 Microsoft 域名，但为 2021 年社区回答，已被 2026 年官方文档取代。**不可采信** |
| 沃通 `https://www.wosign.com/Products/code_signing.htm` | EV 档 `SmartScreen即时信誉`，OV 档 `累计下载获得` | **【过时】** 营销口径 |
| 天威诚信 `https://www.itrus.com.cn/code.html` | `可直接获得微软SmartScreen过滤器的即时信誉` | **【过时】** 营销口径 |
| 上海 CA `https://www.sheca.com/assets/wwx/page2.html` | 增强型「获得 Microsoft Smartcreen」 | 表述模糊（未说「即时」），不构成冲突但含混 |
| SSL.com `https://www.ssl.com/certificates/ev-code-signing/` | `Immediate Extended Validation reputation with Microsoft SmartScreen®` | **【过时】**。与 SSL.com **自家**概览页的 `EV and OV are treated equally since March 2024` **自相矛盾** |
| SSL.com 概览页 `https://www.ssl.com/certificates/code-signing/` | `EV (Extended Validation) provides SmartScreen reputation (built over time through download volume — EV and OV are treated equally since March 2024)` | 与 Microsoft 官方一致，**可采信** |

**规律**：几乎所有 CA 的 **EV 产品页**仍保留「即时信誉」旧文案（对销量有利），而 CA 的**通用说明页**和 **Microsoft 官方文档**都已更新。
**采信顺序：Microsoft 官方文档 > CA 通用说明页 > CA 的 EV 产品页。**

### 8.4 对本场景的四点含义

1. **买 EV 不能解决首次下载警告。** 无论 OV 还是 EV，首次下载都会被标记为「未识别的应用」，需靠下载量（`several weeks and hundreds of clean installs`）逐步累积信誉。
2. **买证书的真实价值在于「显示已验证的发布者名称」**——用户看到的从「未知发布者」变成你的名字/组织名，这本身是信任提升，**但仍伴随 ⚠️ 警告**。
3. **OV 也强制硬件令牌**（CA/B Forum 自 2023-06 起），所以「买 OV 可以省掉硬件成本」是**错的**。想免硬件的唯一路径是**云端签名服务**——Certum SimplySign（`Using the SimplySign cloud solution eliminates the need to use a physical card and reader.`）、SSL.com eSigner、DigiCert KeyLocker。
4. **Azure Artifact Signing 这条「$9.99/月、无需硬件令牌」的便宜路线对本次申请者不可用**：官方表格明确 `Individuals: USA and Canada only`。

---

## 九、行业规则变化（2026 年前后，影响所有方案）

| 变化 | 内容 | 官方原文出处 |
|---|---|---|
| **证书有效期上限** | 单个 Code Signing 证书最长有效期降至 **458–459 天** | Certum：自 **2026-02-27** 起 **459 天**（CA/B Forum Ballot CSC-31）；SSL.com：自 **2026-02-27** 起 **458 天**，规则 **2026-03-01** 生效；Sectigo：自 **2026-02-23** 起 **459 天** |
| **多年期产品的含义变化** | 买多年期 ≠ 一张长期证书，而是**多次重签发** | Sectigo 原文：`if you purchase a multi-year Code Signing product from Sectigo you will receive a new compliant hardware device with a new certificate each year.` |
| **OV 私钥强制硬件** | 自 **2023-06** 起 OV 证书私钥必须存储在 HSM 或硬件令牌 | 【官方·M】`As of June 2023, the CA/Browser Forum requires private keys for OV certificates to be stored on a hardware security module (HSM) or hardware token.` |
| **EV 的 SmartScreen 特权取消** | 2024 年移除 | 见 §八 |
| **GlobalSign 仅售 1 年期** | `Only 1-year (366-day) Code Signing Certificates are now available.` | GlobalSign 官方页（但 shop JSON 仍保留多年期键，两处并存） |

**⚠️ 三家对同一规则的天数与日期表述不一致**（458/459 天；2026-02-23 / 02-27 / 03-01）→ 见 §十异常清单。

---

## 十、异常与不一致清单（如实记录，不强行调和）

| # | 现象 | 涉及来源 | 处理 |
|---|---|---|---|
| 1 | **同一规则，三家给出的天数与生效日不同**：Certum 459 天/2026-02-27、SSL.com 458 天/2026-02-27（规则 2026-03-01）、Sectigo 459 天/2026-02-23 | 三家官方页 | 全部照原文记录，**不调和**。用户下单前应以所购 CA 的实际证书有效期为准 |
| 2 | **SSL.com 站内自相矛盾**：概览页说 `EV and OV are treated equally since March 2024`，旧 EV 页说 `Immediate Extended Validation reputation` | SSL.com 两个官方页 | 概览页与 Microsoft 官方一致，采信概览页；旧 EV 页标**【过时】** |
| 3 | **GlobalSign 官方公告与 shop 定价 JSON 冲突**：公告称仅售 1 年期，JSON 仍有 2/3 年价格键 | GlobalSign 官方页 + shop JSON | 两处并存，**未找到**调和说明；提示用户以下单时实际结算为准 |
| 4 | **DigiCert 价格口径不明**：`$44 / month / certificate` 与 `subscription $696.00` 并排，非同倍关系（$44×12=$528） | DigiCert 官方配置器 | 只照录两数字，**不换算**，**未找到**口径说明 |
| 5 | **多家 CA 的 EV 产品页仍写「SmartScreen 即时信誉」**，与 Microsoft 官方文档直接冲突 | 沃通、天威诚信、SSL.com（另上海 CA 表述含混） | 标**【过时】**，给出采信顺序（§8.3） |
| 6 | **Certum 商品页同时渲染 `Product is out of stock` 与 `In stock` 两种字样** | Certum 商品页 | 疑为模板文本，**无法据此判断真实库存** |
| 7 | **SSL.com 概览页与 Microsoft 官方对 OV/EV 的说法一致，但与 SSL.com 自己的定价结构不协调**（EV $349 比 IV $129 贵 2.7 倍，却无 SmartScreen 优势） | SSL.com 官方 | 如实记录；对本次申请者意味着**没有必要买 EV** |
| 8 | **沃通标价是否含硬件令牌未找到**，而其官方又写明 OV/EV 均强制硬件存储 | 沃通官方页 | 记为「未找到」，提示询价时确认 |

---

## 十一、来源总清单

### 11.1 【官方】来源

| URL | 覆盖内容 |
|---|---|
| `https://shop.certum.eu/code-signing.html` | Certum 代码签名分类页（全部档位标价） |
| `https://shop.certum.eu/open-source-code-signing.html` | Certum 开源 set €69、IDPrime 940C 卡、读卡器型号、卡不退款 |
| `https://shop.certum.eu/open-source-code-signing-code.html` | Certum 开源电子码 €25（需自备卡） |
| `https://shop.certum.eu/open-source-code-signing-on-simplysign.html` | Certum 开源云端 €49、免硬件、5000 次/月上限 |
| `https://shop.certum.eu/standard-code-signing-in-the-cloud.html` | Certum Standard 云端 €209、459 天有效期公告 |
| `https://shop.certum.eu/payment-shipping` | **China €35.00** 运费、非欧盟关税条款 |
| `https://shop.certum.eu/terms-and-conditions` | 订单 7 工作日 + 配送 5 工作日、税务居民证明条款 |
| `https://support.certum.eu/en/code-signing-required-documents/` | **`issued only for individuals`**、所需材料、EV 排除个人 |
| `https://support.certum.eu/en/how-to-buy-code-signing/` | 购买流程、支付方式 |
| `https://certum.store/` / `https://sklep.certum.pl/` | 美元区 / 波兰兹罗提区（区域定价） |
| `https://www.ssl.com/products/software-integrity/code-signing/iv/` | SSL.com IV $129/yr、`Business entity required: No` |
| `https://www.ssl.com/products/software-integrity/code-signing/ov/` | SSL.com OV $129/yr |
| `https://www.ssl.com/products/software-integrity/code-signing/ev/` | SSL.com EV $349/yr |
| `https://www.ssl.com/products/software-integrity/code-signing/ev-sole-proprietor/` | SSL.com EV Sole Proprietor $359/yr |
| `https://www.ssl.com/certificates/code-signing/` | SSL.com SmartScreen 说明（与官方一致） |
| `https://www.ssl.com/certificates/ev-code-signing/` | 458 天新规；SmartScreen 说法**【过时】** |
| `https://www.ssl.com/?s=open+source` | 用于否定 SSL.com 存在 OSS 计划 |
| `https://www.sectigo.com/ssl-certificates-tls/code-signing` | Sectigo 三档产品、25% 折扣表述、459 天新规（**无价格数字**） |
| `https://www.sectigo.com/knowledge-base/detail/OV-Code-Signing-Validation-for-Organizations-and-Individuals` | **Sectigo 允许个人申请 OV 的直接依据** |
| `https://www.digicert.com/signing/code-signing-certificates` | DigiCert 配置器价格与 Validation/Storage 维度 |
| `https://www.digicert.com/insights/open-source` | 用于否定 DigiCert 存在 OSS 计划 |
| `https://shop.globalsign.com/en/code-signing` | GlobalSign 定价 JSON |
| `https://www.globalsign.com/en/code-signing-certificate` | GlobalSign 资格、区域与寄送限制、1 年期公告 |
| `https://ossign.org/`（及 `/assets/index-D2_uN95z.js`） | OSSign 全部文案（SPA，从 bundle 提取） |
| `https://www.wosign.com/Products/code_signing.htm` | 沃通全部标价 |
| `https://www.wosign.com/Products/OV_CodeSigning_Pro.htm` | 沃通多年期价、营业执照原文 |
| `https://www.wosign.com/Products/` | 用于确认沃通无个人档 |
| `https://www.sheca.com/assets/wwx/page2.html` | 上海 CA 价格与组织名称 |
| `https://www.itrus.com.cn/code.html` | 天威诚信代码签名页（无价格） |
| `https://www.cfca.com.cn/` | 用于否定 CFCA 官网列有代码签名 |
| `https://www.aliyun.com/product/cas` / `https://cloud.tencent.com/product/ssl` | 用于否定云厂商有代码签名产品 |

### 11.2 【官方·M】Microsoft 来源

| URL | 覆盖内容 |
|---|---|
| `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation` | **EV 不再绕过 SmartScreen 的权威原文** |
| `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options` | 签名方案成本表、EV 特权 2024 年移除、OV 强制硬件 |
| `https://learn.microsoft.com/zh-cn/windows/apps/package-and-deploy/distribution-feature-status` | EV OID 删除、信誉改为基于哈希 |

### 11.3 【二手】来源（仅作旁证，**不可作定价依据**）

| URL | 内容 |
|---|---|
| `https://codesigncert.com/code-signing-certificate-deals` | Sectigo/DigiCert 经销商折扣价、token 运费、签发耗时 |
| `https://my-ssl.com/learn/open-source-code-signing-certificate` | Certum 经销商（称不卖开源档；其 $99 为标准档价） |
| `https://comparecheapssl.com/free-code-signing-certificate-and-how-to-get-it/` | Sigstore 不适用于 Windows 签名 |
| `https://www.ossperks.com/programs/signpath` | 目录站（仅收录 SignPath） |
| `https://foropensource.com/company/certum/`、`/company/signpath/` | 第三方目录站 |
| `https://learn.microsoft.com/en-us/answers/questions/417016/...` | **【过时】** 2021 年回答 |

---

## 十二、「未找到」总清单（诚实边界）

**Certum**
- €30 档位（任何当前官方页面均无）
- 身份验证环节的官方时限
- 是否对中国大陆客户有额外限制（条款仅写「可能要求税务居民证明」）
- 商品页 `Product is out of stock` / `In stock` 并存，无法判断真实库存

**SSL.com**
- 是否明确支持中国大陆地址收件、是否对大陆申请人另有审核要求
- 官方公布的完整可配送国家列表
- IV 档在不使用 eSigner 时令牌是必选还是可选

**Sectigo**
- 官方标价（官方页只给 25% 折扣表述）
- 非促销档的 token 费用
- 对中国大陆申请人的官方表述

**DigiCert**
- 官方 token 价格与可寄送国家清单
- `$44 / month` 与 `subscription $696.00` 的口径换算关系
- 官方对中国大陆申请人的表述

**GlobalSign**
- 个人档是否存在
- 中国大陆购买路径
- token 运费与硬件费用金额

**OSSign**
- 运营方法人主体、资金来源、第三方审计或用户评价
- 恢复受理申请的时间表（官方只说 `Please check back in a few weeks.`）
- 是否接受中国大陆申请人
- `ossperks.com` 上是否存在除 SignPath 外的其他 code signing 计划（列表页 JS 渲染，未取到完整清单）
- 除 OSSign 外是否还有其他「以自有证书代签」的非营利组织（多轮检索未找到）

**中国国内 CA**
- 天威诚信的价格与个人资格
- 沃通/上海 CA 的硬件令牌是否含在标价内
- 各家的邮寄费、加急费、续费涨价条款
- CFCA 是否有线下渠道签发代码签名证书
- **是否有任何中国大陆 CA 提供面向自然人的代码签名证书**（四家逐查后未找到）

**SmartScreen**
- 信誉累积的确切阈值（Microsoft 原文即写 `There is no exact threshold`）
- `Publisher reputation` 与 `File hash reputation` 各自的权重或算法细节
- OV 与 EV 在企业采购/准入要求上的具体差异清单

---

## 十三、给这位申请者的行动建议

**推荐路线（按优先级）**：

1. **首选：Certum Open Source Code Signing in the Cloud，€49/年**
   - 满足全部硬约束：个人可申（`issued only for individuals`）、无硬件、无跨境寄送、可 PayPal 付款。
   - 需提前准备：**本人名下的水电/电话账单**、**能公开表明你与该开源项目关系的项目页**（GitHub 仓库 + 有效链接）。
   - 注意：每月 5000 次签名上限、证书 459 天后需重签发、不得用于商业分发软件。

2. **备选：Certum Open Source Code Signing set，€69 + €35 运费 = €104（首年）**
   - 若你需要离线签名或不愿依赖云端，代价是多付运费、多等 5 个工作日、卡不可退。

3. **第三：SSL.com IV，$129/年**
   - 官方明确对个人开放。但**先确认它是否强制你买 $379 的 YubiKey**——如果强制，实际首年成本是 $508，远高于 Certum。

4. **同时可以试着等：OSSign**
   - 免费，但**当前暂停受理**且要求 6 个月以上活跃度。你的仓库 2026-09-13 创建，到 2026-10 不足 6 个月。可过几周再查。

**应排除**：
- **EV 档（任何 CA）**——SmartScreen 上已无优势，纯属多付钱。
- **DigiCert / GlobalSign**——无个人档 / 官方购买路径对大陆受阻。
- **中国国内 CA**——证书要印营业执照名称，个人过不了。
- **Azure Trusted Signing**——个人仅限 USA / Canada。

**签名的真实收益预期要调低**：拿到证书后，用户首次下载**仍会看到 SmartScreen 警告**，只是「未知发布者」变成你的名字。要消除警告只能靠时间与下载量（官方口径：`several weeks and hundreds of clean installs`）。这与 SignPath 免费证书的收益完全相同——**付费证书买到的是「主体身份可验证」，不是「没有警告」**。
