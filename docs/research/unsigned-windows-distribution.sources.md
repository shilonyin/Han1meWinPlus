# 未签名 Windows 应用 SmartScreen 摩擦调研 — 内容清单与来源索引

> 本文件是 `docs/research/unsigned-windows-distribution.md` 的索引与清点结果，由脚本从正文抽取生成，内容与正文一致。

## 结构清点

| 项目 | 数值 |
| --- | --- |
| 正文字节数 | 65112 |
| 正文行数 | 723 |
| 二级小节数 | 11 |
| 不同来源 URL 数 | 59 |
| 官方标注（🔵） | 38 |
| 社区标注（🟡） | 34 |
| 未找到标注（⚪） | 27 |

## 七个问题小节（含附带小节）

1. 目录
2. 1. SmartScreen 对未签名 exe 的判定机制
3. 2. 触发警告的具体条件：Mark of the Web / Zone.Identifier
4. 3. winget 分发
5. 4. Scoop / Chocolatey 分发
6. 5. Windows 11 的 Smart App Control
7. 6. 其他减少摩擦的技术手段，实际是否有效
8. 7. 重新申请 SignPath Foundation 的条件
9. 8. 结论汇总与本项目的可执行建议
10. 9. 未找到的内容
11. 10. 参考来源

## 来源 URL 索引（脚本抽取，去重排序）

1. https://attack.mitre.org/techniques/T1553/005/
2. https://cla.opensource.microsoft.com）
3. https://diecknet.de/en/2024/08/30/powershell-ntfs-alternate-data-streams/
4. https://docs.chocolatey.org/en-us/community-repository/moderation/
5. https://docs.chocolatey.org/en-us/faqs/
6. https://docs.chocolatey.org/en-us/guides/create/create-msi-package/
7. https://docs.chocolatey.org/en-us/information/security/
8. https://en.wikipedia.org/wiki/Mark_of_the_Web
9. https://espanso.org/docs/install/win/
10. https://github.com/antigerme/wilson-reborn/pull/97
11. https://github.com/Arsarneq/docent/issues/72
12. https://github.com/chocolatey/choco/issues/1508
13. https://github.com/chocolatey/choco/issues/3302
14. https://github.com/citizenmatt/UnblockZoneIdentifier
15. https://github.com/i999rri/GhosttyWin32/issues/46
16. https://github.com/leaker/pouch/commit/a38081177bd9c84c6d6b5fea1b5b464b1c5be427
17. https://github.com/martymcenroe/silphe/issues/18
18. https://github.com/microsoft/winget-cli/discussions/4327
19. https://github.com/microsoft/winget-cli/issues/3111
20. https://github.com/microsoft/winget-cli/issues/703
21. https://github.com/microsoft/winget-pkgs
22. https://github.com/microsoft/winget-pkgs/blob/master/CONTRIBUTING.md
23. https://github.com/microsoft/winget-pkgs/blob/master/doc/Authoring.md
24. https://github.com/microsoft/winget-pkgs/blob/master/doc/Policies.md
25. https://github.com/microsoft/winget-pkgs/discussions/3335
26. https://github.com/microsoft/winget-pkgs/issues/2701
27. https://github.com/nishiuriraku/easy-cursor-swap/pull/7
28. https://github.com/ScoopInstaller/Main/issues/7537
29. https://github.com/ScoopInstaller/Scoop/discussions/6153
30. https://github.com/serjdrej/trimitdown/commit/f79a3899ae0fb64116d5bc5335693a2ac9df5849
31. https://github.com/shm11C3/HardwareVisualizer/blob/develop/CODE_SIGNING_POLICY.md
32. https://github.com/vim/vim-win32-installer/issues/319
33. https://github.com/Zettlr/Zettlr/issues/473
34. https://github.com/Zettlr/Zettlr/issues/473）。这条与官方表述完全一致，可视为对「微软不公开阈值」的独立印证。
35. https://isc.sans.edu/diary/31732
36. https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/overview
37. https://learn.microsoft.com/en-us/windows/apps/develop/smart-app-control/test-your-app-with-smart-app-control
38. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/code-signing-options
39. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/distribution-feature-status
40. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/publish-first-app
41. https://learn.microsoft.com/en-us/windows/apps/package-and-deploy/smartscreen-reputation
42. https://learn.microsoft.com/en-us/windows/package-manager/package/manifest
43. https://learn.microsoft.com/en-us/windows/package-manager/package/repository
44. https://learn.microsoft.com/en-us/windows/package-manager/package/windows-package-manager-policies
45. https://learn.microsoft.com/en-us/windows/package-manager/winget/
46. https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/appcontrol
47. https://learn.microsoft.com/en-us/windows/security/application-security/application-control/app-control-for-business/design/create-appcontrol-policy-for-lightly-managed-devices
48. https://learn.microsoft.com/en-us/windows/security/operating-system-security/virus-and-threat-protection/microsoft-defender-smartscreen/
49. https://signpath.org/
50. https://signpath.org/projects
51. https://signpath.org/terms
52. https://support.microsoft.com/en-us/windows/security/information-about-the-attachment-manager-in-microsoft-windows
53. https://support.microsoft.com/en-us/windows/security/threat-malware-protection/smart-app-control-frequently-asked-questions
54. https://support.microsoft.com/en-us/windows/security/windows-security/app-browser-control-in-the-windows-security-app
55. https://textslashplain.com/2016/04/04/downloads-and-the-mark-of-the-web/
56. https://windowpin.com/en/install
57. https://www.microsoft.com/wdsi/filesubmission/
58. https://www.reddit.com/r/buildinpublic/comments/1w7tcov/
59. https://www.v2ex.com/t/1218906

## 关键判定摘录

**「下载量累积即自动放行」的判定**（正文第 1.1 节）：单版本内**部分成立**——官方原文 "As downloads accumulate: SmartScreen reputation builds up automatically. The prompt will stop appearing once the file hash has sufficient download history."；跨版本**不成立**——"Unsigned files must build reputation anew with every update."；「该机制只对已签名 OV 证书生效」的说法与官方相反。

**「未找到的内容」共 12 条**，逐条见正文第 9 节（阈值数值、下载工具/网盘的 MOTW 行为、Scoop 与 Chocolatey 的官方 SmartScreen 声明、官方对 zip 解压是否传播 MOTW 的说明、SignPath 重申成功先例、`Anaheim` 字段含义、winget 跳过 SmartScreen 的正式功能文档等）。

**五条候选判断的检验结果**：下载量放行 = 推翻；winget绕过 = 不确定；MOTW是触发源 = 支持（「解压即去除」部分不支持）；SAC未签名即拦 = 支持；SignPath可重申 = 支持。

