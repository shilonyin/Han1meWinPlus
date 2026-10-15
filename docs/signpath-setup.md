# SignPath 侧配置清单（申请通过后照做）

> 这份文档对应 `code-signing.md` 第二节展开成可逐步照做的清单。
> **申请通过之前不需要读它** —— 审核通过会给你一个 Organization，那时再回来。

参照实现：`AniBakaBaka/AniBaka`（已通过 SignPath Foundation 的同类项目）。
下面标注「AniBaka 用」的值是**从它的公开仓库配置里读到的**，不是推测，可作为命名参考 ——
但不要照抄它的 Organization ID，那是它自己的。

---

## 一、先理解这套机制怎么运转

SignPath 的免费 OSS 签名不是「给你一张证书去签」，而是：

```
你的 CI 产出未签名文件
        ↓  上传成 GitHub artifact
SignPath 的 Action 提交一个签名请求
        ↓  （它在 HSM 里用 Foundation 证书签，私钥永不出库）
签好的文件回传
        ↓  你的 CI 替换原件
发布
```

三件事因此成立：

1. **必须绑定构建来源**。SignPath 只接受来自「Trusted Build System」的产物 ——
   这是它敢免费签的前提：它知道这个二进制确实是从你那份源码、在你的 CI 上构建出来的，
   而不是某天你随手传上去的。
2. **签名发生在 CI 里，不在你的电脑上**。本地 `flutter build` 出来的 exe 永远签不了。
3. **签完的字节流变了**，所以校验值和压缩包都必须重算/重打（CI 里已经处理）。

---

## 二、控制台里要建的四样东西

登录 SignPath，进入你的 Organization。

### 2.1 Project

新建 Project，名字建议 `Han1meWinPlus`。

**记下它的 slug**（控制台会显示，或看 URL）。AniBaka 用的 slug 就叫 `AniBaka`。

→ 这个值填到 GitHub Variable `SIGNPATH_PROJECT_SLUG`。

### 2.2 Trusted Build System

**这一步是免费签名能成立的关键**，别跳过。

选预置的 **GitHub.com**，然后关联到上面那个 Project。
它会让你确认仓库 —— 填 `shilonyin/Han1meWinPlus`。

> 绑定之后，SignPath 只认「由本仓库的 GitHub Actions 构建并上传」的产物。
> 手动上传的文件会被拒。这正是它的安全模型。

### 2.3 Artifact Configuration

这是**最容易配错**的一步。它告诉 SignPath：拿到一个 zip 之后，该签里面的哪些文件。

我们的 CI 把**两个 exe 打进同一个 artifact** 上传（见 `build-windows.yml` 的
`Upload unsigned artifacts for signing` 步骤），因为 SignPath 一次请求只签一个 artifact。

`actions/upload-artifact` 默认会把文件打成 zip，所以**根元素是 `<zip-file>`**：

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

两处必须对：
- `path` 里的**文件名**要与 CI 上传的实际文件名完全一致
- 根元素必须是 `zip-file`（不是 `pe-file`，也不是 `file`）

> 控制台里有模板，以它的语法为准。上面是按官方 schema 写的形状。
> AniBaka 的 artifact configuration slug 叫 `windows-release`。

**为什么两个 exe 都要签**：安装包是用户双击的那个，被判「未知发布者」的是它；
但免安装版解压后直接跑 `han1me_win_plus.exe`，不签的话那条路照样被拦。

→ slug 填到 GitHub Variable `SIGNPATH_ARTIFACT_SLUG`。

### 2.4 Signing Policy

新建一个 policy，绑定 **Foundation** 证书。

建议 slug 取 `release-signing`。AniBaka 建了两个：
- `release-signing` —— 正式发布用，签出来的是 `CN=SignPath Foundation, ...`
- `test-signing` —— 测试用，签出来的是自签测试证书

**test-signing 值得照做**：它让你能在不消耗正式签名配额的情况下，把整条链路
（上传 → 提交 → 回传 → 替换 → 校验）跑通一遍再发版。

→ slug 填到 GitHub Variable `SIGNPATH_POLICY_SLUG`。

---

## 三、四个值填进 GitHub

仓库 → Settings → Secrets and variables → Actions。

**Secret**（保密，建完读不出来）：

| 名称 | 值 | 怎么拿 |
| --- | --- | --- |
| `SIGNPATH_API_TOKEN` | CI 用户的 API token | 在 SignPath 里建一个专供 CI 的用户，给它生成 token |

**Variables**（非保密）：

| 名称 | 值 |
| --- | --- |
| `SIGNPATH_ORGANIZATION_ID` | 组织 id（GUID） |
| `SIGNPATH_PROJECT_SLUG` | 第 2.1 步的 slug |
| `SIGNPATH_POLICY_SLUG` | `release-signing` |
| `SIGNPATH_ARTIFACT_SLUG` | 第 2.3 步的 slug |

> **Variables 不启用链路**：签名是否执行只看 `SIGNPATH_API_TOKEN` 在不在。四个 Variables
> 仍要一次填齐 —— 缺任何一个都会让 SignPath 那一步报错，但不会提前跳过。

> AniBaka 的做法是把 Organization ID、project slug、artifact slug **硬编码在 workflow
> 里**（这些值本来就不保密，公开仓库里能直接看到），只把 API token 放 Secret。
> 我们选择全部走 Variables，好处是换组织时不用改代码。

---

## 四、先跑 test-signing 验证链路

**不要第一次就用正式策略打 tag。**

配好之后，到 Actions 页面手动 Run workflow，把签名策略选成 `test-signing`：

```
Actions → Build Windows → Run workflow → signing_policy: test-signing
```

> 手动触发走的是分支 ref，签名步骤照样会执行 —— 门控看的是 `signing_policy`
> 这个输入（`none` 才跳过），不再看 ref。所以**在分支上就能验签，不必打测试 tag**。
> 正式发布仍然由 tag 触发自动走 `release-signing`。

检查这几处：

1. 上传 artifact 的步骤绿了，且 artifact 名里带了 `run_id`/`run_attempt`
2. 「Sign artifacts via SignPath」返回一个 **signing request web URL** —— 记下它，
   签名失败时要去那个页面看原因（CI 日志只显示到超时为止）
3. 「Replace artifacts with signed ones」里打印的 `状态: Valid` 和签名者
   —— **test-signing 时签名者是自签测试证书，不是 SignPath Foundation，这是正常的**

## 五、切正式签名

把策略换成 `release-signing`：

```
Actions → Build Windows → Run workflow → signing_policy: release-signing
```

或直接打正式 tag（tag 触发时自动走 `release-signing`）。

签名者应显示：

```
CN=SignPath Foundation, O=SignPath Foundation, C=US, S=DE, L=Lewes
```

这是 AniBaka 安装包里实际写着的主题 —— 拿来对照即可。

## 六、用户侧怎么看出来

右键 `Han1meWinPlus-Setup.exe` → 属性 → **数字签名** 标签页 →
签名者列表应显示 `SignPath Foundation`，且没有黄色警告。

命令行：

```powershell
Get-AuthenticodeSignature .\Han1meWinPlus-Setup.exe |
  Select-Object Status, @{n='Signer';e={$_.SignerCertificate.Subject}}
```

`Status` 为 `Valid` 才算成功。

> **签了名 ≠ 没有 SmartScreen 提示。** 新证书需要积累下载声誉，前期仍可能提示，
> 但「未知发布者」会消失。这一点不要对用户过度承诺。

---

## 七、出问题先看哪里

| 症状 | 先查 |
| --- | --- |
| 签名步骤超时 | **signing request web URL**（CI 日志看不到真正原因） |
| 报找不到文件 / 不签 | Artifact Configuration 里的 `path` 与实际文件名是否一字不差 |
| 报 artifact 格式不对 | 根元素是不是 `<zip-file>`；CI 上传时有没有加 `archive: false`（**不能加**，加了就不是 zip 了） |
| 签出来是自签证书 | 策略选成了 `test-signing` |
| 校验值对不上 | 「重算 SHA256」那一步有没有跑（签名改了字节流） |
| 用户报「文件已损坏」 | 免安装 zip 是否在**签名后**重打的（签名前的 zip 里是未签名的 exe） |

---

## 八、相关文件

- 总体方案与申请：[`code-signing.md`](code-signing.md)
- 申请材料草稿：[`signpath-application.md`](signpath-application.md)
- CI 签名步骤：[`.github/workflows/build-windows.yml`](../../.github/workflows/build-windows.yml)
- 安装包脚本：[`windows/installer.iss`](../../windows/installer.iss)
