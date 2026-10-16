# Certum（波兰 CA，Asseco Data Systems）代码签名证书调研笔记

调研时点：2026-10。抓取方式：`web_fetch` 直取 URL + `mcp__exa__web_fetch_exa`。
来源性质标注：**[官方定价页]** = 厂商商店商品页；**[官方支持文档]** = 厂商支持站点；**[官方条款]** = 厂商法律条款页；**[二手]** = 第三方转述。

---

## 1. 产品线与当前官方标价

来源：`https://shop.certum.eu/open-source-code-signing.html` **[官方定价页]**
原文（2026-10 抓取）：

> from €69.00 gross from €69.00 net

> The set includes a Code Signing Certificate, a card reader, and a Certum cryptographic card.

来源：`https://shop.certum.eu/open-source-code-signing-code.html` **[官方定价页]**
原文：

> from €25.00 gross from €25.00 net

> An electronic code allows the certificate activation for customers who have their own cryptoCertum cryptographic card and reader.

→ **€25 档的前提是买家已经持有 cryptoCertum 加密卡与读卡器**，新用户不能只花 €25 拿到可用证书。

来源：`https://shop.certum.eu/open-source-code-signing-on-simplysign.html` **[官方定价页]**
原文：

> from €49.00 gross from €49.00 net

> Using the SimplySign cloud solution eliminates the need to use a physical card and reader.

来源：`https://shop.certum.eu/code-signing.html` **[官方定价页]**（分类页，同一批价格）
Open Source Code Signing in the Cloud from €49.00；Open Source Code Signing - set from €69.00；Open Source Code Signing - code from €25.00。
同页另有 Standard / EV 档：Standard Code Signing in the Cloud from €209.00；EV Code Signing in the Cloud from €379.00；Standard Code Signing - set from €169.00；EV Code Signing - set from €359.00；Standard Code Signing - electronic code from €139.00；EV Code Signing - code from €329.00。

### €30 与 €69 之争的核实结论

- **在当前可打开的所有 Certum 官方页面上，均未出现 €30 这一档标价。** 开源档的在售标价是：**set（含卡+读卡器）€69**、**电子码 €25**、**云端版 €49**。
- €30 很可能是对 **€25 电子码档**的转述讹变，或来自已下线的旧页面／第三方经销商报价——但**本次未找到任何当前官方页面支持 €30**。
- 判定：**网传 €30 不是 Certum 当前官方在售价**。

### 区域定价（同一产品不同币种站点）

- `https://shop.certum.eu/`（€）、`https://certum.store/`（$）、`https://sklep.certum.pl/`（zł）三站并存，价格不同 → 存在区域定价，比价时必须注明币种与站点。

---

## 2. 是否强制捆绑硬件加密卡 / 读卡器

- **实体 set 档（€69）**：含 **Mini cryptographic card cryptoCertum 3.7 IDPrime 940C（SIM 卡大小）** + 读卡器（**ACS ACR39T-A1 或 Omnikey 6121**，视库存而定）。
  来源：`https://shop.certum.eu/open-source-code-signing.html` **[官方定价页]**
  Declaration of Conformity 段落另写明：`cryptoCertum 3.7 card (IDPrime 940C)` 与 `Mini ACR40T-A1 (USB type A)` 读卡器。
  Requirements 列：proCertum CardManager 程序、加密卡读卡器、读卡器驱动、**cryptoCertum 3.6 或 3.7 卡**、initialized common card profile。
- **云端档（€49）**：**不需要实体卡与读卡器**。Requirements 为 SimplySign 手机 App（Android/iOS，生成访问码）+ SimplySign Desktop + 云账号 + 联网。
  来源：`https://shop.certum.eu/open-source-code-signing-on-simplysign.html` **[官方定价页]**
- → **不强制捆绑硬件**：想避开实体卡与读卡器，可选云端档。

### 云端档的限制

同页 Note 原文：

> for Code Signing products in the cloud, there is a certificate usage limit of 5000 signatures per month. Exceeding this limit may result in contacting you to inform you of the exceedance and possible blocking of the product in the month in which the limit was used.

→ **云端档每月最多 5000 次签名**，超限可能当月被封。

### 实体卡的隐藏成本

- 来源：`https://shop.certum.eu/open-source-code-signing.html` **[官方定价页]** Note 原文：

> in case of returning the Open Source Code Signing set, it is not possible to return the cryptographic card and refund for it.

→ 退货时**加密卡不退款**。

---

## 3. 硬件能否寄达中国大陆

来源：`https://shop.certum.eu/payment-shipping` **[官方条款]**（"Payment & shipping"）
原文（非欧盟配送费率表，"Shipping rates outside the European Union"）：

> Albania, Bosnia and Herzegovina, Canada, **China**, Georgia, Gibraltar, Guernsey, Holy See, Iceland, Kosovo, Libya, Liechtenstein, Moldova, Monaco, Montenegro, Norway, Panama, Paraguay, Qatar, San Marino, Serbia, South Korea, Switzerland, Thailand, Turkey, United Arab Emirates, United Kingdom | €35.00

同一表还列了台湾 €60、香港 €65、日本 €63、印度 €94 等。

同页原文：

> Shipments sent outside the EU may be subject to a customs duty that is paid at the time of import by the buyer.

→ **结论：Certum 官方配送费率表明确列出 China，运费净价 €35.00；欧盟外可能另有关税由买家承担。**
→ 电子服务（激活码）**免运费**，发到邮箱或账户。

来源：`https://shop.certum.eu/terms-and-conditions` **[官方条款]** 原文：

> A list of countries to which Products are shipped is available at https://shop.certum.eu/payment-shipping.

> All prices are shown in EUR, including value added tax and other costs due under applicable legislation... in the event the Products or Goods are shipped outside the European Union and a relevant public office charges a customs duty or an excise duty, the costs shall be transferred to the Customer.

> Asseco Data Systems SA may require the Customer to provide a document confirming their tax residence in specific situations.

→ 条款未排除中国大陆；但**保留要求客户提供税务居民证明的权利**（非欧盟买家可能被要求补材料）。

---

## 4. 个人（非公司实体）能否申请

来源：`https://support.certum.eu/en/code-signing-required-documents/` **[官方支持文档]**
原文（Open Source Code Signing 段落的 Note）：

> Open Source Code Signing are issued only for individuals

> Issued certificate will contain „Open Source Developer" phrase added to the Common name field. Organization field will be set to „Open Source Developer".

> If Certum determines that the certificate is being used to sign software distributed commercially, the certificate will be revoked.

同页 Specification（商品页重复同一句）：

> Data in the certificate: natural person data prefixed with "Open Source Developer" phrase

→ **结论：Certum 开源档只面向自然人签发，证书主体是「Open Source Developer + 自然人姓名」，Organization 字段直接填 "Open Source Developer"，不要求企业实体。** 这正是本项目（个人维护的开源应用）的适配档位。
→ **风险条款**：若 Certum 认定证书被用于给商业分发软件签名，证书会被吊销。

### 对比：Certum 的 EV 档明确排除个人

同页 EV Code Signing 段落原文：

> EV Code Signing certificates are issued only for organization – they cannot be issued for an individual

> To issue the certificate, confirmation of having a physical office registered to the organization's data is required

→ Certum 的 **EV 档不接受个人**；Standard 档则区分「个人」与「带组织信息」两种情形（个人情形额外要 utility bill）。

---

## 5. 申请流程与所需材料

来源：`https://support.certum.eu/en/code-signing-required-documents/` **[官方支持文档]**
开源档激活所需的身份验证方式（四选一）：

1. 自动身份验证（推荐）
2. 在 Registration Point / Identity Confirmation Point 当面确认身份
3. 公证确认身份
4. 提交本人手持身份证件的照片（身份证、护照、驾照、永久居留卡），需能比对本人面部与证件照片，证件正反面完整

**另外必需**：

> - utility bill (gas, electricity, water, telephone, etc.), issued for the subscriber
> - website address of the ongoing Open Source project: The project must be publicly available and indicate clearly the subscriber's relationship with the project. If Certum is unable to identify the project based on publicly available information, the certificate will not be issued.

→ 需要：**开在申请人本人名下的水电/电话账单** + **开源项目网址，且项目页面须清楚表明申请人与该项目的关系**。若 Certum 无法从公开信息确认项目归属，**不予签发**。

其他限制（同页 Note）：

> Open Source Code Signing certificates cannot contain domain names or IP addresses

购买流程来源：`https://support.certum.eu/en/how-to-buy-code-signing/` **[官方支持文档]** 原文：

> - Choose in the store the Code Signing certificate and add it to the shopping cart
> - Create a new account or log in
> - Provide the address information and make sure the data is entered correctly. The data to be included in the certificate you will provide during the certificate activation process
> - Choose the payment method: Quick transfer / Standard transfer
> - After payment is received, the certificate will be available for activation in My account/Data security products.

支付方式（同页）：Quick transfer（eCard 卡支付、电子转账、**PayPal**、Blik、Google Pay）、Standard transfer（网银/银行网点/邮局汇款）。

---

## 6. 从付款到拿到可用证书的耗时

来源：`https://shop.certum.eu/terms-and-conditions` **[官方条款]** 原文：

> A regular time of completion of an order is 7 Business Days, counting from the ... of receipt of ... by the Customer.

> Delivery time is up to 5 Business Days from a shipping date.

> the time of delivery by a courier company in the case of delivery outside the European Union may be longer in situations completely beyond the Vendor's control, for example in the case of a customs inspection.

→ **官方给出的数字：订单处理通常 7 个工作日 + 配送最多 5 个工作日**，欧盟外可能因海关检查更久。
→ **注意：这 7 个工作日是「订单处理」时间，不含证书激活所需的身份验证耗时。官方未给出身份验证环节的时限——本次未找到该时限的官方数字。**

---

## 7. 证书有效期的新规（2026 起）

来源：`https://shop.certum.eu/standard-code-signing-in-the-cloud.html` **[官方定价页]** 的 Certificate Validity 公告（摘要层，未逐字抓取原文段落）：
自 **2026-02-27** 起单个 Code Signing 证书最长有效期降为 **459 天**（依据 CA/Browser Forum Ballot CSC-31）；2/3 年期产品在有效期内需**免费重签发**一次或多次；若身份核验仍在有效期内可复用。

对照：SSL.com 官方页写同一规则为 **458 天**、生效 **2026-02-27**（CA/B Forum 规则生效日写 **2026-03-01**）；Sectigo 官方页写 **459 天**、生效 **2026-02-23**。三家对同一规则的天数与日期表述不一致 → 见最终报告的异常清单。

---

## 8. 三问速答

| 问题 | 结论 | 依据 |
| --- | --- | --- |
| 个人（非公司实体）能否申请？ | **能**（开源档专为自然人） | `https://support.certum.eu/en/code-signing-required-documents/` **[官方支持文档]**：`Open Source Code Signing are issued only for individuals` |
| 中国大陆居民能否申请？ | **能申请且硬件可寄**：官方配送表列 China，运费 €35.00 净价；付款支持 PayPal；欧盟外关税由买家承担 | `https://shop.certum.eu/payment-shipping` **[官方条款]** |
| 隐藏成本？ | ① 实体 set 档含卡与读卡器（€69 已含），**退货时加密卡不退款**；② 云端档每月限 5000 次签名；③ 运费 €35（中国大陆）+ 可能的进口关税；④ 需自备本人名下水电账单与公开可查的开源项目页，否则不予签发；⑤ 3 年期产品受 459 天新规影响需多次免费重签发 | 见上各节 |

---

## 9. 未找到 / 存疑

- **€30 档位**：未找到任何当前 Certum 官方页面标此价。**未找到**。
- **身份验证环节的官方时限**：官方未给出数字。**未找到**。
- **是否对中国大陆客户有额外限制（如要求税务居民证明）**：条款仅写"可能要求提供税务居民证明"，未明确针对中国。**未找到更具体的说明**。
- 商品页同时渲染 `Product is out of stock` 与 `In stock` 两种字样，疑为模板文本，**无法据此判断真实库存**。
