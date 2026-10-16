# 来源核对表 —— azure-artifact-signing.md 逐条 URL 溯源

**核对对象**：`docs/research/azure-artifact-signing.md`（48187 字节 / 589 行）
**取证目录**：`docs/research/_sources/`（28 个文件）
**核对时间**：2026-10-16
**核对方法**：用正则从报告全文抽出所有 URL，去重后逐条映射到本轮实际落盘的抓取件；再抽查 5 处关键结论，确认结论句后紧跟来源 URL。

---

## 一、URL → 留档抓取件 对应表（共 34 条去重 URL）

### A. 官方文档（可对回留档原件）

| # | 报告内 URL | 留档文件 | 结论等级 |
|---|---|---|---|
| 1 | <https://learn.microsoft.com/en-us/azure/artifact-signing/quickstart> | `learn-artifact-signing-quickstart.md`（40838 B）、`learn-quickstart.md`（41923 B） | 官方 |
| 2 | <https://learn.microsoft.com/en-us/azure/artifact-signing/faq> | `learn-artifact-signing-faq.md`（27745 B）、`learn-faq.yml`（29298 B，源文件） | 官方 |
| 3 | <https://learn.microsoft.com/en-us/azure/artifact-signing/concept-certificate-management> | `learn-concept-certificate-management.md`（9926 B） | 官方 |
| 4 | <https://learn.microsoft.com/en-us/azure/artifact-signing/concept-trust-models> | `learn-concept-trust-models.md`（5586 B） | 官方 |
| 5 | <https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options> | `learn-code-signing-options.md`（11068 B） | 官方 |
| 6 | <https://learn.microsoft.com/en-us/windows/win32/seccrypto/signtool> | `learn-signtool-cmd.md`（18508 B）、`learn-signtool-sign.md`（4145 B） | 官方 |
| 7 | <https://learn.microsoft.com/en-us/windows/win32/seccrypto/cryptography-tools> | `learn-crypto-tools.md`（8765 B） | 官方 |
| 8 | <https://azure.microsoft.com/en-us/pricing/details/artifact-signing/> | `pricing-artifact-signing.html`（477456 B，含 `data-amount` 价格属性） | 官方 |
| 9 | <https://prices.azure.com/api/retail/prices?$filter=contains(serviceName,'Signing')> | `azure-retail-prices-signing.json`（3841 B） | 官方（机器可读，可重跑） |
| 10 | <https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713> | `techcommunity-trusted-signing-public-preview-update.md`（3387 B） | 官方博客（经 Exa 通道取得，直连 403 Azure WAF） |
| 11 | <https://github.com/Azure/artifact-signing-action> | `gh-Azure_artifact-signing-action-README.md`（20901 B）；旧名同仓库留档 `gh-Azure_trusted-signing-action-README.md`（20901 B，内容一致） | 官方仓库 |
| 12 | <https://github.com/Azure/artifact-signing-action/blob/main/docs/OIDC.md> | `gh-artifact-signing-action-OIDC.md`（2650 B） | 官方仓库 |

**另有本轮抓取但报告未直接引为行内 URL 的留档**（作为佐证留存）：
`learn-overview.md`、`learn-concept-resources-roles.md`、`learn-tutorial-assign-roles.md`、`learn-how-to-signing-integrations.md`、`learn-how-to-sign-ci-policy.md`、`learn-how-to-sign-history.md`、`learn-how-to-cert-revocation.md`、`learn-how-to-change-sku.md`、`learn-how-to-renew-identity-validation.md`、`learn-smartscreen-rep.md`、`learn-toc-artifact-signing.json`。

### B. 端点型 URL（文档中引用的服务地址，非抓取对象）

报告内出现的 `https://<region>.codesigning.azure.net` 共 15 个（`brs` / `cus` / `eus` / `jpe` / `krc` / `ncus` / `neu` / `plc` / `scus` / `swn` / `wcus` / `weu` / `wus` / `wus2` / `wus3`）以及 `http://timestamp.acs.microsoft.com`，是官方文档给出的**服务端点**，不是取证来源，无需留档。其来源是 `learn-artifact-signing-quickstart.md` 与 `learn-concept-certificate-management.md`。

### C. 旧 URL（实测跳转，无独立留档）

| URL | 处置 |
|---|---|
| <https://azure.microsoft.com/en-us/pricing/details/trusted-signing/> | 本轮实测 **302 跳转**到 `/pricing/details/artifact-signing/`，是「服务已改名」的直接证据；无独立快照留档，报告中已按「实测」标注。 |

### D. 社区来源（不可信数据，仅作旁证）

| # | 报告内 URL | 留档情况 | 结论等级 |
|---|---|---|---|
| 13 | <https://learn.microsoft.com/en-us/answers/questions/5960832/...> | 本轮 `web_fetch` 抓到全文，**未单独落盘** | 社区（微软 Q&A，回答者为社区/AI，非官方声明） |
| 14 | <https://learn.microsoft.com/en-us/answers/questions/2238411/...> | 本轮未留档，仅 URL 引用 | 社区 |
| 15 | <https://learn.microsoft.com/en-us/answers/questions/5573345/...> | 本轮未留档，仅 URL 引用 | 社区 |
| 16 | <https://learn.microsoft.com/en-us/answers/questions/5810735/...> | 本轮未留档，仅 URL 引用 | 社区 |
| 17 | <https://sign.94xy.com/trusted-signing/> | 本轮未留档 | 社区（第三方教程，其「立即获得信誉、等同 EV」的说法与官方文档冲突，报告已标注） |

> 说明：另有 `ddg-test.html`（14300 B）留在 `_sources/`，是早期搜索通道的测试残留，不构成本报告的任何来源。

---

## 二、无来源结论检查

对报告全文做两项扫描：

1. **裸价格数字扫描**：全文价格出现处均已带单位（`9.99 USD` / `99.99 USD` / `0.005 USD / 签名`），未发现无单位的裸价格数字，也未发现无来源的价格陈述。
2. **资格结论扫描**：涉及「个人开发者能否注册」「中国大陆是否可用」的结论句，均紧随 `quickstart` 或 `code-signing-options` 的官方原文引用，或紧随官方博客链接。

抽查 5 处关键结论的邻接性（结论句 → 其后 2 行内是否出现 URL）：

| 结论 | 报告行号 | 后续是否紧跟来源 |
|---|---|---|
| 定价 `9.99 / 99.99 / 0.005 USD` | L38、L55 | ✅ L55 同表内并列两个官方 URL，并注明 API 原值文件 |
| SmartScreen 需声誉积累 | L220（引用块） | ✅ 引用块上方为官方 FAQ 来源，节内标为「官方文档已确认」 |
| 个人开发者限美/加 | L89（引用块） | ✅ 紧随其后 L91 给出第二份官方文档 URL 作为交叉印证 |
| 身份验证 1–20 个工作日 | L135、L382 | ✅ 两句均附官方英文原文，节内标为「官方文档已确认」 |
| 申请者画像（AGPL-3.0、无公司实体） | L5 | ✅ 属申请者自述背景，非需外部来源的事实结论 |

---

## 三、无法对应 / 未留档 的项（逐个列出）

1. **4 条 Microsoft Q&A 链接中，3 条本轮未落盘**（2238411 / 5573345 / 5810735）。它们在报告中被标注为「社区转述」，不承担事实结论，仅用于呈现「是否有个案」的公开迹象。
2. **5960832 抓到了全文但未落盘**。若需复查该条社区案例，需重抓一次。
3. **`sign.94xy.com` 未落盘**。该来源的说法与官方冲突，报告已按「以官方为准」处理。
4. **旧定价 URL 无独立快照**，仅有本轮 302 跳转的实测记录。
5. **Wayback Machine 的 `trusted-signing` 旧页快照未取到**（web.archive.org 端返回 502），因此「改名发生的确切日期」在报告中记为「未找到官方公告日期」。

---

## 四、结论

- 承担**事实性结论**的 12 条官方来源，**全部**能在 `_sources/` 找到本轮实际抓取的留档原件，可直接比对复核。
- 端点型 URL（16 条）不属取证来源，已分类说明。
- 社区来源共 5 条，其中 4 条未留档，但均只作旁证、不承担事实结论，且报告版式上已与官方分区隔离。
- 未发现无来源的价格数字或资格结论。

**因此判据 (3) 与 (5) 在本核对表范围内成立**：每条事实性结论后均有可打开的来源，且这些来源有本轮抓取的实物为凭。
