# 最终结论 —— Azure Trusted Signing / Artifact Signing 对本申请者是否可用

**结论出具时间**：2026-10-16
**结论对象**：中国大陆个人开发者，维护 AGPL-3.0 开源 Flutter Windows 桌面应用，无公司实体、无营业执照，GitHub Releases 分发（Inno Setup 单文件 exe + 免安装 zip）
**依据报告**：`docs/research/azure-artifact-signing.md`（589 行）
**来源核对**：`docs/research/_source-check.md`　**结论摘录**：`docs/research/_answers-check.md`

---

## 一、结论

> ## ❌ 不可用
>
> **Azure Trusted Signing（现名 Azure Artifact Signing）的 Public Trust 路径对该申请者当前不可用。**
>
> **这不是「材料准备不足」的问题，而是写在资格层的地理限制**：官方文档一致要求 Public Trust 证书的**个人开发者必须位于美国或加拿大**；中国大陆不在任何一份官方支持列表中，且 2025-04-02 起个人开发者 onboarding 本身处于暂停状态。

三条可行路径逐一封死：

| 路径 | 判定 | 卡在哪 |
|---|---|---|
| Public Trust · 个人开发者 | ❌ 不可用 | 「Individual developers must be located in the **United States or Canada**」（官方 quickstart）；2025-04-02 起个人 onboarding 暂停（官方博客） |
| Public Trust · 组织 | ❌ 不可用 | 申请者无企业实体；且组织可用名单也不含中国大陆 |
| Private Trust | ❌ 不适用 | 仅限组织；且其证书在任何根程序与 Windows 中**默认不被信任**，只能用于企业内 WDAC，**无法用于公网分发** |

**适用范围**：中国大陆的个人开发者；结论基于 **2026-10-16** 实际抓取到的官方文档（其中 quickstart 页面更新日期为 2026-09-11）。若微软未来同时满足「恢复个人 onboarding」且「把中国大陆加入个人支持地区」两个条件，结论才会改变——本轮**未找到**任何朝这个方向变化的迹象。

---

## 二、支撑结论的关键依据（每条附来源）

1. **地理限制**——官方 quickstart 原文：`Individual developers must be located in the United States or Canada.`
   来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

2. **同一限制的第二份官方文档**——对比表写 `Individuals: USA and Canada only`，并注明 Artifact Signing「formerly Trusted Signing」。
   来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

3. **2025-04-02 起暂停个人 onboarding**——微软官方博客《Trusted Signing Public Preview Update》原文：新客户订阅仅限「US and Canada-based organizations with 3 years or more of verifiable history」，`Onboarding for individual developers and all other organizations will not be directly available for the remainder of the preview`。
   来源：<https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713>

4. **个人路径的设计确实存在**（推翻「必须开公司」的旧说法）——官方提供 Organization 与 Individual 两条身份验证路径，个人路径要求 Azure 计费账户类型为 Individual、法定姓名与 sold-to 地址与政府证件一致。**卡点是地理，不是主体资格。**
   来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart>

5. **未恢复的直接旁证**——2026-09-11 更新的官方 quickstart 仍写个人限美加；本轮**未找到**任何恢复公告。

---

## 三、即使资格问题解决，也应知道的三个硬事实

对申请者后续选型仍然有用，均已官方确认：

1. **SmartScreen 不会立即信任。** 官方原文：`Azure Artifact Signing does not provide instant SmartScreen trust, but signing consecutive releases with a consistent publisher/signing identity lets publisher reputation build over time.` 与普通 OV 证书**同一套声誉积累模型**；EV 的「首次下载即绕过」能力**已于 2024 年移除**。
   来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

2. **价格便宜但不是零成本、且从建号起就计费。** Basic **9.99 USD/月**（含 5,000 次/月）、Premium **99.99 USD/月**（含 100,000 次/月）、超额 **0.005 USD/签名**；**创建账户即开始计费，且不按比例折算**；免费/试用/赞助订阅不支持。两个官方渠道（定价页与零售价 API）数值完全一致。
   来源：<https://azure.microsoft.com/en-us/pricing/details/artifact-signing/>、<https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')>

3. **必须联网签名。** 签名经 `https://<region>.codesigning.azure.net` 云端完成，**未找到**离线模式说明；私钥不可导出；证书每日续期、单张有效期约 72 小时。
   来源：<https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management>

**另需注意的社区说法冲突**：第三方教程（`sign.94xy.com`）声称该服务「立即获得信誉、效果等同 EV」，甚至给出「70 元个人 EV 代码签名」的说法。**这与微软官方文档直接矛盾**，报告以官方为准。该教程记录的**中国大陆个人成功案例成立于 2025-02，早于 4 月 2 日的政策暂停，现已失效**。

---

## 四、尚未确定的事项（影响结论的强度，但不改变方向）

| # | 未确定事项 | 若它成立，结论如何变 |
|---|---|---|
| 1 | **个人 onboarding 是否已恢复**——本轮未找到正面声明，仅有「2026-09-11 官方文档仍限美加」的间接证据 | **不变**。即便恢复，官方仍要求个人开发者位于美/加 |
| 2 | **中国大陆是否可能被加入个人支持地区**——无任何官方迹象 | 若成立，结论才需重估；本轮无证据 |
| 3 | **MSI / PowerShell / ClickOnce 的逐类支持情况**——官方只给「所有 SignTool 支持的类型」，未逐类确认 | 不影响本案结论（本案产物为 exe/zip） |
| 4 | **改名确切日期与是否 GA**——定价页旧 URL 302 跳转可证改名；GA 状态未找到官方公告 | 不影响可用性结论 |
| 5 | **服务名在官方价目表里仍是 `Trusted Signing`**——API 的 `serviceName` 未随改名更新 | 属命名滞后，不影响价格 |

---

## 五、待决策事项（需人判断，本轮未做调查）

1. **替代方向首选：OV 代码签名证书。** 官方 `code-signing-options` 文档在不适用 Artifact Signing 的场景下指向 OV，称其与 Artifact Signing 在 **SmartScreen 行为上等价、全球可用、约 150–300 USD/年**，且自 2023-06 起 CA/Browser Forum 要求私钥存于 HSM 或硬件令牌。**注意：官方这段话没有针对「个人开发者」做区分。**
   来源：<https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options>

2. **但「中国大陆个人能否持有 OV 证书」本轮未核实。** 按 CA/Browser Forum 规则 OV 通常要求组织实体，个人可申请的往往是 IV（Individual Validation）或个人版证书。这属于本轮范围之外，**未做调查、不做结论**。

3. **SignPath Foundation 之外的其它免费开源签名渠道本轮未调查。** 申请者此前被 SignPath 拒绝，是否存在可行替代需另做一轮调研。

4. **是否需要重新评估「不签名」路线**：若最终只能走 OV 且个人无法持有，则需回到「未签名分发 + 引导用户信任」的方案权衡。

---

## 六、本次调研可信程度的自我说明

- 承担结论的 **12 条官方来源全部有本轮抓取的实物留档**（见 `_source-check.md`），可逐字节复核；其中定价经**两个独立官方渠道交叉验证**。
- **官方与社区在报告中分区标注**，不混写；冲突处（SmartScreen 说法）显式指出并以官方为准。
- 全文 **26 处显式「未找到」**，未做推测；未使用训练数据中的旧价格。
- 一处已知的官方文档内部不一致已并列呈现、不调和：**FIPS 等级**（证书管理文档写 140-2 Level 3，FAQ 写 140-3 Level 3）。
- 一处工具坑已记录：PowerShell `Format-Table` 会把 `0.005` 显示成 `0.01`，曾据此误判为「官方来源价格冲突」；改读 JSON 原值后连续三次均为 `0.005`。
