# Windows 代码签名（SignPath Foundation）

解决「未知发布者」/ SmartScreen 拦截的正式做法：让二进制带上一个 Windows 已经信任的
Authenticode 签名。本项目走 [SignPath Foundation](https://signpath.org/) 的免费开源签名
通道 —— 它对符合条件的公开 OSS 项目免费签发，私钥存在 SignPath 的 HSM 上，不需要自己
买证书、也不需要 USB token。

> 这份文档是**待办清单**，不是已完成记录。截至写下时点，CI 接入已就绪，但**尚未提交申请**，
> 因此仓库里还没有 `SIGNPATH_*` 配置，签名步骤会被自动跳过，发布流程照旧产出未签名包。

---

## 一、当前状态

| 事项 | 状态 |
| --- | --- |
| CI 签名步骤（`.github/workflows/build-windows.yml`） | ✅ 已写好，带门控，未配置时自动跳过 |
| 仓库资格（公开 / OSS 许可 / GH Actions 构建） | ✅ 满足 |
| SignPath 账号与申请 | ❌ **未申请**（需要人来操作） |
| 仓库 Secrets / Variables | ❌ 未配置（等申请通过） |
| SignPath 侧的 Project / 策略 / 产物配置 | ❌ 未配置（等申请通过） |

资格核对的依据：仓库 `shilonyin/Han1meWinPlus` 公开、AGPL-3.0（OSI 认可）、构建全程在
GitHub 托管的 Actions runner 上跑 —— 这三点是 SignPath 对 OSS 项目的核心要求。

## 二、你需要做的（只有账号持有者能做）

### 1. 提交申请

到 <https://signpath.org/apply> 申请 **Foundation（免费 OSS）** 计划，填入：

- 仓库地址 `https://github.com/shilonyin/Han1meWinPlus`
- 许可证：AGPL-3.0
- 项目简介：Windows 桌面客户端（Flutter），替代网页端观看体验
- 维护者身份

审核是人工的，通过后会给你一个 SignPath **Organization**。

### 2. 建好 SignPath 侧的四样东西

登录 SignPath 控制台，在新建的 Organization 里：

1. **Project** —— 记下它的 *slug*
2. **Trusted Build System** —— 选预置的 *GitHub.com*，链接到上面的 Project
   （这一步让 SignPath 认可「产物确实由本仓库的 Actions 构建」，是免费签名能成立的前提）
3. **Artifact Configuration** —— 见下面第三节，**根元素要用 `<zip-file>`**
4. **Signing Policy** —— 绑定 Foundation 证书，例如 slug 取 `release-signing`

### 3. 把四个值填进 GitHub

仓库 → Settings → Secrets and variables → Actions：

**Secrets**（保密，申请后不可再读出）：

| 名称 | 值 |
| --- | --- |
| `SIGNPATH_API_TOKEN` | 在 SignPath 里为 CI 建一个用户，生成 API token |

**Variables**（非保密）：

| 名称 | 值 |
| --- | --- |
| `SIGNPATH_ORGANIZATION_ID` | 组织 id（GUID） |
| `SIGNPATH_PROJECT_SLUG` | 第 2 步的 Project slug |
| `SIGNPATH_POLICY_SLUG` | 签名策略 slug，如 `release-signing` |
| `SIGNPATH_ARTIFACT_SLUG` | 产物配置 slug，如 `windows-artifacts` |

**填完 `SIGNPATH_ORGANIZATION_ID` 的那一刻签名链路就启用了** —— 这正是指令里那个门控
条件。所以四个值要一次填齐，否则会走到签名步骤才报错。

## 三、Artifact Configuration 该怎么写

CI 把两个 exe 放在**同一个** artifact 里上传（SignPath 一次请求只签一个 artifact）：

- `Han1meWinPlus-Setup.exe` —— 安装包，用户双击的就是它
- `han1me_win_plus.exe` —— 主程序，免安装版解压后直接运行它

`actions/upload-artifact` 默认会打成 zip，所以根元素是 `<zip-file>`，在里面按文件名分别
声明 `<pe-file>`。大致形状（具体语法以 SignPath 控制台里的模板为准）：

```xml
<artifact-configuration xmlns="http://signpath.io/artifact-configuration/v1">
  <zip-file>
    <pe-file path="Han1meWinPlus-Setup.exe">
      <authenticode-sign />
    </pe-file>
    <pe-file path="han1me_win_plus.exe">
      <authenticode-sign />
    </pe-file>
  </zip-file>
</artifact-configuration>
```

> Inno Setup 的 `SignTool` 指令是另一条路（编译期签，能连卸载器一起签上）。本项目**没有**
> 走它，原因是它需要本地 `signtool` + 证书文件，而 SignPath 是托管的 HSM，不给导出私钥。
> 两者选一即可，不要同时配 —— 那会导致安装包被签两次或两次签名互相覆盖。

## 四、接上之后会发生什么

打 tag 发布时，CI 的顺序变成：

1. 构建 → 出安装包和免安装压缩包
2. 把两个 exe 上传成一个 artifact
3. 提交给 SignPath 签名，等它完成，取回签好的文件
4. **按文件名**把签好的 exe 放回原位
5. **重新打免安装压缩包**（原来那次是在签名之前打的，里面还是未签名的 exe）
6. **重算 `SHA256SUMS.txt`**（签名改变了字节流，不重算用户核对必然对不上）
7. 用 `Get-AuthenticodeSignature` 校验，**签名无效就直接 fail，不让未签名的包发出去**
8. 创建 Release

第 5、6、7 步是接入时最容易漏的地方，改动里都留了注释说明原因。

## 五、验证签名是否真的生效

用户侧最简单的检查：右键 exe → 属性 → 数字签名，签名者应显示 SignPath Foundation。

命令行：

```powershell
Get-AuthenticodeSignature .\Han1meWinPlus-Setup.exe |
  Select-Object Status, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

`Status` 为 `Valid` 才算成功。`UnknownError` / `NotSigned` 表示没签上。

## 六、如果申请被拒或不想等

- **Azure Trusted Signing** —— 约 $10/月，微软自己的可信签名，需要身份验证，能过
  Smart App Control
- **Certum Open Source Code Signing** —— 约 €30/年的 OSS 优惠 OV 证书
- **自签名** —— 免费但对分发**没用**：Windows 不信任自签根，该拦还是拦

## 七、相关文件

- 签名步骤：[`.github/workflows/build-windows.yml`](../../.github/workflows/build-windows.yml)（搜 `SignPath`）
- 安装包脚本：[`windows/installer.iss`](../../windows/installer.iss)
- 安装器选型调研：[`windows-installer-options.md`](windows-installer-options.md)
