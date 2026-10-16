# Trusted Signing Public Preview Update

- **URL**: <https://techcommunity.microsoft.com/blog/microsoft-security-blog/trusted-signing-public-preview-update/4399713>
- **发布**: 2025-04-02（页面显示 Updated Apr 01, 2025）
- **作者**: IanMcMillan_MSFT
- **栏目**: Microsoft Community Hub / Microsoft Security Blog
- **抓取方式**: 经 Exa 内容抓取通道（`mcp__exa__web_fetch_exa`）获得全文
  —— 直连 `Invoke-WebRequest` 与 `web_fetch` 均返回 **HTTP 403**（Azure WAF 拦截），故改用该通道。
- **本地留存**: 本文件

---

## 原文（全文照录）

Nearly a year ago we announced the Public Preview of Trusted Signing with availability for organizations with 3 years or more of verifiable history to onboard to the service to get a fully managed code signing experience to simplify the efforts for Windows app developers. Over the past year, we've announced new features including the Preview support for Individual Developers, and we highlighted how the service contributes to the Windows Security story at Microsoft BUILD 2024 in the Unleash Windows App Security & Reputation with Trusted Signing session.

During the Public Preview, we have obtained valuable insights on the service features from our customers, and insights into the developer experience as well as experience for Windows users. As we incorporate this feedback and learning into our General Availability (GA) release, we are limiting new customer subscriptions as part of the public preview. This approach will allow us to focus on refining the service based on the feedback and data collected during the preview phase. The limit in new customer subscriptions for Trusted Signing will take effect **Wednesday, April 2, 2025**, and make the service only available to **US and Canada-based organizations with 3 years or more of verifiable history**. **Onboarding for individual developers and all other organizations will not be directly available for the remainder of the preview**, and we look forward to expanding the service availability as we approach GA.

Note that this announcement does not impact any existing subscribers of Trusted Signing, and the service will continue to be available for these subscribers as it has been throughout the Public Preview.

For additional information about Trusted Signing please refer to Trusted Signing documentation | Microsoft Learn and Trusted Signing FAQ | Microsoft Learn.

---

## 要点摘出

| # | 原文要点 | 对本调研的意义 |
| --- | --- | --- |
| 1 | 新客户订阅限制自 **2025-04-02** 起生效 | 个人 onboarding 暂停的时间点 |
| 2 | 服务「only available to **US and Canada-based organizations with 3 years or more of verifiable history**」 | 组织也被限到美加 + 3 年可验证历史 |
| 3 | 「**Onboarding for individual developers and all other organizations will not be directly available for the remainder of the preview**」 | **个人开发者 onboarding 明确关闭**，且措辞是「for the remainder of the preview」 |
| 4 | 「we look forward to expanding the service availability **as we approach GA**」 | 恢复与否挂钩 GA，未给时间表 |
| 5 | 「does not impact any existing subscribers」 | 已有订阅者不受影响 |
| 6 | 文中用词仍是 **Public Preview**（2025-04-02 时点） | 与 2026 年文档改名为 Artifact Signing 形成对照 |
