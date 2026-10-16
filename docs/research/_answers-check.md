# 八问结论摘录与判据比对 —— azure-artifact-signing.md

**比对对象**：`docs/research/azure-artifact-signing.md`（589 行 / 48187 字节）
**比对时间**：2026-10-16
**判据**：申请者提出的 8 个问题，每个都要给出可直接使用的答案，含数值、适用条件与来源，并标明证据等级。

---

## 逐问结论

### 问题 1 · 当前定价（报告 L30–L67）

**结论**：Basic **9.99 USD/月**、Premium **99.99 USD/月**；配额分别 **5,000 / 100,000 次签名每月**；超出后 **0.005 USD/签名**（两档同价）；Basic 含 Public/Private 各 1 个证书配置文件类型，Premium 各 10 个。

- 适用条件：**创建账户即开始计费，且不按比例折算**（按月全额）；免费/试用/赞助订阅不支持；配额跨证书配置文件统一计算。
- 来源：`https://azure.microsoft.com/en-us/pricing/details/artifact-signing/`（页面源码 `data-amount`）与 `https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')`（API JSON 原值），**两个官方渠道数值完全一致**。
- 最低消费 / 年付要求：**未找到**（判据要求显式写出，报告 L66 已写）。
- 证据等级：**官方已确认**（双渠道交叉验证）。

### 问题 2 · 资格要求（报告 L70–L104）

**结论**：**不强制要求企业实体**。官方身份验证分 **Organization** 与 **Individual Developer** 两条路径。个人路径的条件是：付费 Azure 订阅 + 关联 **Azure 计费账户类型必须为 Individual** + 计费账户上的法定姓名与 sold-to 地址须与政府签发证件一致。

- 适用条件：个人身份验证只能配 Public Trust 系列证书配置文件；**Private 身份验证仅限组织**。
- 相关约束：CN/O 不可自定义；OU 仅 Private Trust 可用；身份验证不可加急。
- 来源：`https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart`、`https://learn.microsoft.com/en-us/azure/artifact-signing/faq`
- 证据等级：**官方已确认**。
- 注：报告同时纠正了「个人不能单独申请」的旧说法——**个人通道在服务设计上存在**，卡点在地理限制（见问题 3）。

### 问题 3 · 中国个人是否可用（报告 L107–L189）—— 本调研核心

**结论：不可用。** 依据三层：

1. **地理限制（资格层）**：官方 quickstart 原文「**Individual developers must be located in the United States or Canada.**」；组织范围虽更长（美/加/欧盟/英/澳/新西兰/日/韩/新/瑞士/挪威/以色列），**同样不含中国大陆**。同一限制在官方 Windows 文档 `code-signing-options` 的对比表中重复（"Individuals: USA and Canada only"）。
2. **2025-04-02 起的暂停**：微软官方博客宣布新客户订阅仅限「美国/加拿大、有 3 年以上可验证历史的组织」，**个人开发者与其它地区组织的 onboarding 在预览期内不再直接开放**。
3. **2026 年仍未恢复**：2026-09-11 更新的 quickstart 仍写个人限美加。

- 身份验证流程与证件：走 **Microsoft Verified ID**，第三方验证方 **AU10TIX**；接受政府签发的护照 / 驾驶执照 / 身份证（**不接受**私人机构证件）；补充材料可用近三个月的银行或水电账单；若没有账单地址，官方要求用带地址的政府证件。
- 成功/失败案例：中国大陆个人的成功案例**存在但早于 2025-04-02**（社区教程，2025-02，用身份证通过）；2026 年仍有**法国**个人开发者被国家下拉挡住、**美国**个人开发者被 AU10TIX 卡住。**未找到** 2026 年任何中国大陆个人的成功记录。
- 来源：`quickstart`、`code-signing-options`、官方博客 `techcommunity.microsoft.com/.../4399713`（官方）；`learn.microsoft.com/en-us/answers/questions/2238411|5810735|5960832`、`sign.94xy.com/trusted-signing/`（社区）
- 证据等级：地理限制与暂停为**官方已确认**；个案为**社区旁证**。

### 问题 4 · 签名级别与 SmartScreen（报告 L191–L248）

**结论**：**不是 EV**，官方也**未把证书定级为 OV 或 EV**。更关键的是——**Windows SmartScreen 不会立即信任**。

- 官方原文：「Azure Artifact Signing does **not** provide instant SmartScreen trust, but signing consecutive releases with a consistent publisher/signing identity lets publisher reputation build over time.」
- 与普通 OV 的区别：官方对比表把两者的 SmartScreen 行为标为**同一类**（均需声誉积累）；且 **EV 的「首次下载即绕过 SmartScreen」能力已于 2024 年被移除**。
- 适用条件：官方只说「文件哈希累积足够下载历史后提示停止」，**未给出量化阈值**。
- 来源：`https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options`、`https://learn.microsoft.com/en-us/azure/artifact-signing/faq`
- 证据等级：**官方已确认**，且与社区教程「立即获得信誉、效果等同 EV」的说法**直接矛盾，报告以官方为准并在 L234–L242 显式标注冲突**。

### 问题 5 · 支持的产物类型（报告 L251–L283）

**结论**：官方口径是「**You can sign all file types that SignTool supports.**」，**未逐类列举**。

| 产物 | 官方确认情况 | 等级 |
|---|---|---|
| PE / exe（含 Inno Setup 安装包） | ✅ SignTool 官方文档给出 `.exe` 签名命令示例 | 官方 |
| MSI | ⚠️ Artifact Signing 文档**未逐类确认**，只能按 SignTool 范围推断 | 未确认 |
| PowerShell `.ps1` | ⚠️ 同上，另有 ExecutionPolicy 约束 | 未确认 |
| ClickOnce | ❌ **未找到**任何官方说明；ClickOnce 清单签名是另一套流程，不能据 SignTool 推断 | 未找到 |

- 旁证：社区教程给出的扩展名清单含 `.msi`、`.ps1`，**不含 ClickOnce**。
- 来源：`https://learn.microsoft.com/en-us/azure/artifact-signing/faq`、`https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool`
- 证据等级：PE/exe 为**官方已确认**；MSI/PS1 为**官方未逐类确认**；ClickOnce 为**未找到**。

### 问题 6 · CI 集成（报告 L286–L374）

**结论**：有**官方** GitHub Action —— `azure/artifact-signing-action@v2`（仓库 `Azure/artifact-signing-action`）。

- **Runner 限制**：**只能在 Windows runner 运行**（官方托管 `windows-2025` / `windows-2022`）；官方明写「We currently do not support Windows Arm runners」；支持自托管。
- **凭据**：**支持 OIDC 免密钥**，官方 README 原文「It is recommended to use OpenID Connect for authentication」；步骤为 Entra 应用 + federated credentials + 分配 **Artifact Signing Certificate Profile Signer** 角色 + workflow 里 `permissions: id-token: write` 与 `azure/login@v1`。也支持 client secret。
- 附带坑：Action 的依赖缓存**默认关闭**，官方理由是「GitHub Actions caches are not a security boundary」；自托管 runner 缺 PowerShell NuGet package provider 会报错。
- 来源：`https://github.com/Azure/artifact-signing-action`、`https://github.com/Azure/artifact-signing-action/blob/main/docs/OIDC.md`
- 证据等级：**官方已确认**。

### 问题 7 · 从申请到可用需要多久（报告 L376–L404）

**结论**：身份验证处理 **1 至 20 个工作日**（原文 "Processing your identity validation request takes from 1 to 20 business days"），需补材料时可能更长。

- 配套时限：邮件验证链接 **7 天**过期（须新建请求，不能重发）；**最多 3 次**尝试，用尽即无法继续 onboarding；**不可加急**；身份验证到期前 **60 天**起提醒，未续期则签名全部停止。
- 方向相反的一条：**计费从创建账户那刻开始**，不等身份验证通过；验证失败需**自行删除账户**才停止计费。
- **未找到**：官方未给出「验证通过后多久能签发第一张证书」的独立说明。
- 来源：`quickstart`、`faq`、定价页
- 证据等级：**官方已确认**。

### 问题 8 · 已知限制与坑（报告 L407–L494）

**官方已确认的**：

- **区域绑定**：账号只能建在 15 个受支持区域（`brs/cus/eus/jpe/krc/ncus/neu/plc/scus/swn/wcus/weu/wus/wus2/wus3`），**无任何中国区域**；签名 endpoint 必须与账号区域匹配，否则常见 403。
- **必须联网**：签名通过云端 endpoint 完成，**未找到离线签名模式的任何官方说明** → 离线构建不可行。
- **私钥不可导出**（官方原文 "does *not* support importing or exporting private keys and certificates"）。
- **证书极短生命周期**：每日自动续期，单张有效期约 **72 小时**；持久身份靠 profile 专属 EKU（`1.3.6.1.4.1.311.97.*`）。
- **时间戳须显式指定**，官方 TSA 端点 `http://timestamp.acs.microsoft.com`。
- **Verified ID 环境要求**：官方明写不要用弱 Wi-Fi、**不要使用任何 VPN 或代理**。
- **官方两处 FIPS 等级表述不一致**：证书管理文档写 **FIPS 140-2 Level 3**，FAQ 写 **FIPS 140-3 Level 3** —— 报告并列不推测。
- 账号命名约束；SKU 可改但需注意不按比例计费。

**社区转述的（官方未找到）**：并发限制（「有并发限制，遇到错误不要短时间内重复尝试」）、中文填写要求、随时取消订阅的细则。

- 来源：`quickstart`、`faq`、`concept-certificate-management`、定价页（官方）；`sign.94xy.com/trusted-signing/`（社区）
- 证据等级：上述官方条目为**官方已确认**；并发限制等为**社区旁证，官方未找到**。

---

## 判据比对小结

| 判据 | 状态 | 证据 |
|---|---|---|
| (1) 文件存在且非空 | ✅ | 48187 字节 / 589 行 |
| (2) 八问各有一个带标题的小节 | ✅ | `## 1.` – `## 8.` 逐条对应（另有结论速览、`## 9.` 政策变化、`## 10.` 可行性判断、附录） |
| (3) 每条事实性结论后紧跟可打开且本轮抓取过的来源 | ✅ | 见 `docs/research/_source-check.md`：12 条官方来源全部对回 `_sources/` 留档原件 |
| (4) 官方与社区在版式上分区标注 | ✅ | `### ✅` 11 处、`### 💬` 8 处，无混写；冲突处（SmartScreen）显式标注并说明以官方为准 |
| (5) 找不到的写「未找到」，无无来源的价格或资格结论 | ✅ | 「未找到」26 处；价格均带单位与来源；资格结论均附官方原文 |
| (6) 含 2025–2026 政策/定价变化节 | ✅ | `## 9.` 写明 2025-04-02 暂停、改名、EV 行为 2024 移除、价格无变动 |

**八问全部有实质答案，无某一问只剩「未找到」的情况。**
