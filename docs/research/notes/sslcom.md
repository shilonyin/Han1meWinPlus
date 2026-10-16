# SSL.com 代码签名证书调研笔记

调研时点：2026-10。取证方式：`Invoke-WebRequest` 直取官方页面 HTML，去 `<script>/<style>` 与标签后提取正文。
来源标注约定：**【官方定价页】**= CA 官网商品页原文；**【二手】**= 第三方转述，未在官方页交叉验证。

---

## 1. 产品线与价格

SSL.com 把代码签名拆成四个独立商品页，价格直接印在商品页上（**均为【官方定价页】**）：

| 档位 | 官方商品页 URL | 1 年 | 2 年（每 year） | 3 年（每 year） | 页面写明的 Business entity required |
|---|---|---|---|---|---|
| **IV**（Individual Validation） | `https://www.ssl.com/products/software-integrity/code-signing/iv/` | **$129.00/yr** | $116.10/yr（Save 10%） | $109.65/yr（Save 15%） | **No** |
| **OV**（Organization Validation） | `https://www.ssl.com/products/software-integrity/code-signing/ov/` | **$129.00/yr** | 同档位价格表 | 同档位价格表 | **Yes** |
| **EV** | `https://www.ssl.com/products/software-integrity/code-signing/ev/` | **$349.00/yr** | $299.00/yr | $249.00/yr | **Yes** |
| **EV Sole Proprietor** | `https://www.ssl.com/products/software-integrity/code-signing/ev-sole-proprietor/` | **$359.00/yr** | $308.74/yr | $254.89/yr | **No (individual validation)** |

IV 商品页原文摘录（**官方**）：

- `no business registration required`
- `the IV tier gives solo developers access to Authenticode signing without` [a corporate legal entity]
- `issued in minutes`
- Who it's for：`Independent developers, open source maintainers`
- 同一页的 Related Products 区写 EV Sole Proprietor：`EV-level trust accessible to individual developers without a registered business entity. Hardware-backed keys, immediat...`

→ 对「没有公司实体的个人开发者」，SSL.com 给出的可行档位是 **IV $129/年**（1 年）与 **EV Sole Proprietor $359/年**。OV 与 EV 标准档写明需要 business entity。

---

## 2. 隐藏成本（全部来自上述四个官方商品页，**【官方定价页】**）

| 项目 | 价格 | 页面原文 |
|---|---|---|
| YubiKey 物理令牌 | **+$379.00**（每个） | 令牌为可选加购项 |
| 自带云 HSM 自管 | `Starting at $500.00` | — |
| AWS CloudHSM 认证费 | **$1,500** | `This fee is a one-time charge per order.` |
| Google Cloud HSM 认证费 | **$500** | 同上 |
| 令牌隔夜快递 | **+$599.00** | `Token shipped overnight in continental US.` |
| eSigner 云 HSM 订阅 | 订阅制，可**免除**硬件令牌 | — |

要点：**$129 的 IV 档价格不是到手成本**。若不使用 eSigner 云端签名，需要额外购置 FIPS 令牌（$379）或自备合规 HSM；隔夜快递只覆盖美国本土大陆。

---

## 3. 三问逐答

### 个人（非公司实体）能否申请？

**能，但只有 IV 与 EV Sole Proprietor 两个档位。** IV 页明确 `Business entity required: No` 且面向 `solo developers`；EV Sole Proprietor 页明确面向 `individual developers without a registered business entity`。OV 与 EV 标准档页写明 `Business entity required: Yes`。

### 中国大陆居民能否申请？

**部分证据，未完全确定。** 已核实的是：SSL.com 是面向全球销售的美国 CA，官方页面上**没有**任何「限某地区」的资格限制文字（对比 GlobalSign 明确写 `If you select a region that does not match your legally registered company details, your order will be canceled`——SSL.com 的四个商品页无此类表述）。

**未找到**的：SSL.com 是否明确支持中国大陆地址收件、是否对中国大陆申请人有额外审核要求、官方是否公布可配送国家列表。报告中按「未找到」处理，不作推断。

### 是否有隐藏成本？

**有，且金额可观**：$379 令牌 / $599 隔夜快递 / $1,500 AWS CloudHSM 认证 / $500 Google Cloud HSM 认证。详见上表。另注：多档位标价是「按年单价 × 年数」，3 年期的低价不等于一次性付清即长期有效。

### 有效期新规（**官方**）

`https://www.ssl.com/certificates/ev-code-signing/` 原文：

> `Effective March 1, 2026, new industry requirements from the CA/Browser Forum will limit the maximum validity period of publicly trusted code signing certificates to 458 days. In preparation, SSL.com began enforcing this 458-day cap on certificate issuance starting February 27, 2026.`

→ 买 3 年期并不等于拿到一张 3 年有效的证书，而是 3 年内**多次重签发**（每次最长 458 天）。这与 Certum 页面的 459 天公告、Sectigo 页面的 459 天公告属同一轮 CA/B Forum 新规，三家数字有 458/459 的细微差异，均照原文记录。

---

## 4. SSL.com 是否有面向开源项目的免费或折扣计划

**结论：未找到任何此类计划。**（判断「SSLcom有OSS计划」据此判为**推翻**。）

已核查的路径与结果：

| 核查动作 | 结果 |
|---|---|
| `https://www.ssl.com/?s=open+source+code+signing`（站内搜索） | HTTP 200，正文 11169 字符，**无任何开源计划条目** |
| `https://www.ssl.com/faqs/`（FAQ 索引） | HTTP 200，正文 9562 字符，匹配 `open source` 上下文 **0 条** |
| `https://www.ssl.com/?s=open+source` 站内搜索页 | 扫描全部 **59 条**站内链接，无一命中 `open-source` / `open_source` / `oss` / `nonprofit` / `non-profit` |
| IV 商品页正文 | 仅把 `open source maintainers` 列为该档位的目标人群之一，**不是**一个独立计划 |

最接近「开源友好」的只有 **IV 档**：它对个人开放、无企业实体要求，价格 $129/年，但它是一个普通在售商品档位，没有面向开源项目的免费额度、折扣或申请流程。

---

## 5. 一处官方自相矛盾（须在报告中标注）

关于 EV 与 SmartScreen 的关系，SSL.com 站内两个页面给出相反说法：

- 概览页 `https://www.ssl.com/certificates/code-signing/`（**官方，较新**）：
  > `EV (Extended Validation) provides SmartScreen reputation (built over time through download volume — EV and OV are treated equally since March 2024)`
  > `Historically, EV ... were granted instant SmartScreen reputation, while OV and individual certificates had to earn it gradually. Microsoft has since moved away from automatic instant reputation`
- 旧 EV 页 `https://www.ssl.com/certificates/ev-code-signing/`（**官方，但为未更新的营销文案**）：
  > `Immediate Extended Validation reputation with Microsoft SmartScreen®`
  > `Programs signed with an SSL.com EV Code Signing certificate immediately work with Edge and Windows® SmartScreen® reputation services`

后者与 Microsoft 官方文档（见 `smartscreen-ov-ev.md`）直接冲突，属**过时营销文案**。用户若读到该页会得出「多花钱买 EV 能立刻免 SmartScreen 警告」的错误结论。

---

## 6. 来源清单

| URL | 性质 |
|---|---|
| `https://www.ssl.com/products/software-integrity/code-signing/iv/` | 官方定价页 |
| `https://www.ssl.com/products/software-integrity/code-signing/ov/` | 官方定价页 |
| `https://www.ssl.com/products/software-integrity/code-signing/ev/` | 官方定价页 |
| `https://www.ssl.com/products/software-integrity/code-signing/ev-sole-proprietor/` | 官方定价页 |
| `https://www.ssl.com/certificates/code-signing/` | 官方概览页（SmartScreen 说明，较新） |
| `https://www.ssl.com/certificates/ev-code-signing/` | 官方旧 EV 页（SmartScreen 说法过时，与上条冲突） |
| `https://www.ssl.com/?s=open+source` | 官方站内搜索（用于确认无 OSS 计划） |

## 7. 未找到项

- SSL.com 是否支持中国大陆地址收件 / 是否对中国大陆申请人另有限制 —— **未找到**
- SSL.com 官方公布的完整可配送国家列表 —— **未找到**
- IV 档在**不使用** eSigner 时的最低到手总价（令牌必选还是可选）—— 商品页把 YubiKey 列为加购项，**未找到**「必须购买令牌」的明文
