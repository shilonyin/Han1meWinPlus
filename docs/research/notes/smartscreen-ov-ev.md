# OV 与 EV 代码签名证书在 SmartScreen 上的待遇差异

调研时点：2026-10。取证方式：直取 Microsoft Learn 官方文档原文。
来源标注约定：**【官方】**= Microsoft 官方文档；**【二手】**= 第三方转述。

---

## 1. 结论

**OV 与 EV 在 SmartScreen 上的待遇已经趋同，两者都不再享有「首次下载即无警告」的特权。**

- **历史上**（约 2024 年之前）：EV 证书签名后**立即**获得 SmartScreen 信誉，用户首次下载即不弹警告；OV 需靠下载量慢慢累积。
- **现在**（2024 年起）：**EV 的即时信誉特权已被移除**，OV 与 EV 待遇相同，都靠下载量累积信誉，首次下载都会出现警告。
- **因此：为了绕过 SmartScreen 警告而多付 EV 溢价，已不再有正当理由。**（Microsoft 官方原文即为这个口径）

---

## 2. Microsoft 官方文档原文（**最权威来源**）

### 2.1 `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation`

文档日期 `ms.date: 2026-05-04`。

**签名类型 vs SmartScreen 行为对照表**（原文）：

| 签名类型 | SmartScreen 行为 |
|---|---|
| `Valid Certificate (OV/EV)` | `⚠️ Warning — app flagged as unrecognized until reputation accumulates; verified publisher name is displayed` |
| `Microsoft Store` | `✅ No warning` |
| `No signature` | `⚠️ Warning — "Windows protected your PC"` |
| `Self-signed Certificate` | `⚠️ Warning — Same behavior as no signature` |

**关于 EV 的关键段落**（原文，逐字）：

> `EV certificates no longer bypass SmartScreen. Years ago, signing files with an Extended Validation (EV) code signing certificate would result in positive SmartScreen reputation by default, but this behavior no longer exists. EV certificates may matter for enterprise procurement, but they no longer impact SmartScreen behavior. Paying a premium for EV solely to avoid SmartScreen warnings is no longer justified.`

**信誉如何累积**（原文）：

> `There is no exact threshold, but it can take several weeks and hundreds of clean installs from a wide audience.`

SmartScreen 使用两个独立信号（原文）：`Publisher reputation` 与 `File hash reputation`。

### 2.2 `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options`

文档日期 `2026-08-29`。**签名方案对照表**（原文）：

| 方案 | 成本 | 适用范围 | SmartScreen |
|---|---|---|---|
| `Azure Artifact Signing (formerly Trusted Signing)` | `~$9.99/month` | `Organizations: USA, Canada, EU, UK. Individuals: USA and Canada only` | `⚠️ Reputation builds over time; initial warnings expected` |
| `OV certificate (from a CA such as DigiCert, Sectigo)` | `$150–300/year` | `Worldwide` | `⚠️ Same as Azure Artifact Signing — reputation builds over time` |
| `EV certificate` | `$400+/year` | `Worldwide` | `⚠️ Same as OV since 2024 — no longer instant bypass` |

同页原文：

> `EV certificates previously bypassed SmartScreen entirely on first download... That behavior was removed in 2024.`

> `As of June 2023, the CA/Browser Forum requires private keys for OV certificates to be stored on a hardware security module (HSM) or hardware token.`

**→ 这两句是本次调研中最关键的两条行业事实**：
1. EV 的 SmartScreen 即时绕过在 2024 年被移除，OV 与 EV 现在同等对待。
2. 自 2023 年 6 月起 **OV 证书私钥也必须存储在 HSM 或硬件令牌**中——这意味着**买 OV 也躲不掉硬件成本**（这一点与多个 CA 页面互相印证，见下）。

### 2.3 中文官方页 `https://learn.microsoft.com/zh-cn/windows/apps/package-and-deploy/distribution-feature-status` 原文

> 「**SmartScreen 信誉度：EV 证书不再提供直接绕过的权限**  状态：2024 年的行为已更改」

> 「Microsoft 在 2024 年更新了受信任根计划的要求，删除了特定于 EV 的 OID。无论证书类型（OV 或 EV）如何，SmartScreen 信誉现在都是基于哈希的」

→ 机制层面说明：EV 的 OID 已从受信任根计划要求中删除，信誉判定改为**基于哈希**，与证书类型脱钩。

---

## 3. 反例与冲突记录（**须标注为过时**）

| 出处 | 原文 | 定性 |
|---|---|---|
| `https://learn.microsoft.com/en-us/answers/questions/417016/...`（Microsoft Q&A，**2021 年**回答） | `An EV code signing certificate offers an immediate reputation with Microsoft SmartScreen` | **过时**。虽是 Microsoft 域名，但为 2021 年社区回答，已被上述 2026 年官方文档取代。**不可采信** |
| 沃通 `https://www.wosign.com/Products/code_signing.htm` | EV 档列 `SmartScreen即时信誉`，OV 档列 `累计下载获得` | **过时营销口径**，与 Microsoft 官方文档直接冲突 |
| 天威诚信 `https://www.itrus.com.cn/code.html` | `可直接获得微软SmartScreen过滤器的即时信誉` | **过时营销口径** |
| 上海 CA `https://www.sheca.com/assets/wwx/page2.html` | 增强型「获得 Microsoft Smartcreen」 | 表述模糊（未说「即时」），不构成冲突但含混 |
| SSL.com `https://www.ssl.com/certificates/ev-code-signing/` | `Immediate Extended Validation reputation with Microsoft SmartScreen®` | **过时**。与 SSL.com **自家**概览页 `https://www.ssl.com/certificates/code-signing/` 的 `EV and OV are treated equally since March 2024` 自相矛盾 |
| SSL.com 概览页 | `EV (Extended Validation) provides SmartScreen reputation (built over time through download volume — EV and OV are treated equally since March 2024)` | **与 Microsoft 官方一致**，可采信 |

**规律**：几乎所有 CA 的 **EV 产品页**仍保留「即时信誉」的旧文案（因为对它们的销量有利），而 CA 的**通用说明页**和 **Microsoft 官方文档**都已更新。**采信顺序：Microsoft 官方文档 > CA 通用说明页 > CA 的 EV 产品页。**

---

## 4. 对本次调研场景的具体含义

申请者情况：中国大陆个人开发者、开源 Flutter Windows 桌面应用、无公司实体。

1. **买 EV 不解决首次下载警告。** 无论买 OV 还是 EV，首次下载都会被 SmartScreen 标记为「未识别的应用」，需要靠下载量（`several weeks and hundreds of clean installs`）逐步累积信誉。
2. **买证书的真实价值在于「显示已验证的发布者名称」**，而不是消除警告。官方表格 `Valid Certificate (OV/EV)` 一行写的是 `verified publisher name is displayed`——用户看到的从「未知发布者」变成你的名字/组织名，这本身是信任提升，但仍伴随 ⚠️ 警告。
3. **OV 也需要硬件令牌**（CA/B Forum 自 2023-06 起强制），所以「买 OV 可以省掉硬件成本」是**错的**。想要免硬件的唯一路径是**云端签名服务**——例如 Certum 的 SimplySign 云端档（原文 `Using the SimplySign cloud solution eliminates the need to use a physical card and reader.`）、SSL.com 的 eSigner、DigiCert 的 KeyLocker。
4. **Azure Artifact Signing 这条「$9.99/月、无需硬件令牌」的便宜路线，对本次申请者不可用**：Microsoft 官方表格明确 `Individuals: USA and Canada only`——中国大陆个人不在其列。

---

## 5. 来源清单

| URL | 性质 |
|---|---|
| `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation` | 【官方】Microsoft，ms.date 2026-05-04（EV 不再绕过 SmartScreen 的权威原文） |
| `https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options` | 【官方】Microsoft，2026-08-29（签名方案成本表 + EV 特权 2024 年移除） |
| `https://learn.microsoft.com/zh-cn/windows/apps/package-and-deploy/distribution-feature-status` | 【官方·中文】Microsoft（EV OID 删除、信誉改为基于哈希） |
| `https://learn.microsoft.com/en-us/answers/questions/417016/...` | **【过时】** Microsoft Q&A 2021 年回答（保留作反例） |
| `https://www.ssl.com/certificates/code-signing/` | SSL.com 概览页（与官方一致） |
| `https://www.ssl.com/certificates/ev-code-signing/` | SSL.com 旧 EV 页（过时，自相矛盾） |
| `https://www.wosign.com/Products/code_signing.htm` | 沃通过时口径 |
| `https://www.itrus.com.cn/code.html` | 天威诚信过时口径 |

## 6. 未找到项

- SmartScreen 信誉累积的**确切阈值**（Microsoft 官方原文即写 `There is no exact threshold`）
- `Publisher reputation` 与 `File hash reputation` 两个信号各自的**权重或算法细节** —— **未找到**（微软未公开）
- OV 与 EV 在**企业采购/准入要求**上的具体差异清单 —— 官方只说 `EV certificates may matter for enterprise procurement`，未展开，**未找到**
