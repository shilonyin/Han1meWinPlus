# Flutter Windows 桌面应用安装/分发方案调研

> 调研对象：`shilonyin/Han1meWinPlus`（Flutter Windows 桌面应用，AGPL-3.0，上游 `1wc10086/Han1mePlus`）
> 调研日期：2026-02（以抓取到的文档版本为准）
> 方法：全部结论来自**一手来源**（官方文档、官方仓库源码与真实配置文件）。本环境 `web_search` 不可用，所有材料由 `web_fetch` 直接抓取具体 URL 获得；每条结论后附实际抓到的来源 URL。抓不到的一律写进「未找到的内容」，不做推测填充。

---

## 目录

1. [问题背景](#1-问题背景)
2. [结论摘要](#2-结论摘要)
3. [Inno Setup 的自解包机制（源码级）](#3-inno-setup-的自解包机制源码级)
4. [能否绕开这个失败点](#4-能否绕开这个失败点)
5. [对本机故障的新线索（待验证）](#5-对本机故障的新线索待验证)
6. [各方案对比](#6-各方案对比)
7. [社区实例](#7-社区实例)
8. [针对本项目的推荐](#8-针对本项目的推荐)
9. [未找到的内容](#9-未找到的内容)
10. [参考来源](#10-参考来源)

---

## 1. 问题背景

项目现状（据仓库内文件）：

| 项目 | 现状 | 出处 |
| --- | --- | --- |
| 打包工具 | Inno Setup 6，脚本 `windows/installer.iss` | `windows/installer.iss` |
| 产物 | `Han1meWinPlus-Setup.exe`（约 39.6 MB）+ portable zip | `.github/workflows/build-windows.yml` |
| 安装动作 | 复制 `build\windows\x64\runner\Release\*` 到 `{app}`；建开始菜单/桌面快捷方式；注册 `han1me://` 协议；升级时清理旧版残留 | `windows/installer.iss` |
| 协议注册位置 | `Root: HKCR`（机器级） | `windows/installer.iss:69-72` |
| 卸载 | Inno 自带卸载器（`Uninstallable` 默认 yes） | `windows/installer.iss`（未显式设置） |
| 压缩 | `Compression=lzma2`、`SolidCompression=yes` | `windows/installer.iss:16-17` |
| CI | `flutter build windows --release` → `choco install innosetup` → `iscc /DMyAppVersion=... windows/installer.iss` → 另出 portable zip → 发 GitHub Release | `.github/workflows/build-windows.yml:57-100` |

失败现象（本机）：

```
Setup was unable to create the directory "C:\Users\<user>\AppData\Local\Temp\is-XXXXXXXXXX.tmp".
Error 5: 拒绝访问。
```

- 失败发生在**安装器自解包阶段**，此时无日志、无窗口，`ExitCode=1`
- **以管理员身份运行就成功**
- 已排除：`%TEMP%` 权限/ACL、进程位数、UAC 文件虚拟化、SRP、火绒 HIPS、RTSS 注入

---

## 2. 结论摘要

> **⚠️ 后续验证更新（写完之后实测得出，优先级高于下文 §5 的假设）**
>
> §5 提出的「UAC 拆分令牌 / 父目录继承 ACL」是**未经验证的假设**。后续在同一台机器上
> 做了对照实验，结论如下：
>
> 1. **`UseSetupLdr=no` 确实有效**（§2.2 与 §4 的判断成立）：同一脚本、同一台机器，
>    默认 `UseSetupLdr=yes` → `ExitCode=1`（报 `Error 5`）；改成 `no` → `ExitCode=0`，
>    71 个文件全部装好。
> 2. **`%TEMP%` 的 ACL 不是原因**（§5 的假设被排除）：把 `TMP`/`TEMP` 指向新建的干净
>    目录后重试仍然失败；本机 `TMP` 与 `TEMP` 本来就指向同一目录。
> 3. **真正的原因是 Inno 在用户级安装模式下的权限分支**：`PrivilegesRequired=lowest`
>    会走「依赖父目录继承 ACL」那条路，而它在这个环境里拿不到写权限。孤立变量实测：
>    仅把 `lowest` 换成 `admin`（其余完全相同）→ `ExitCode` 由 1 变 0。
> 4. **因此最终方案是 `UseSetupLdr=no` + 保持 `PrivilegesRequired=admin`**，而不是
>    「免管理员 + HKA」。`HKA`（§2.4）在脚本里保留了——它让 URL 协议能随安装模式自动
>    落到 HKLM/HKCU——但它解决不了这个安装失败。
>
> 上述结论对应的实测数据逐条记录在 `windows/installer.iss` 的注释里。本节保留原文，
> 是为了留下「假设 → 验证 → 修正」的完整链条。

1. **Inno 的 `%TEMP%\is-*.tmp` 不是可配置项，而是 `UseSetupLdr` 的固有行为。** 官方文档原文："When using yes, the setup program is copied to and run from the user's TEMP directory."（[ishelp: UseSetupLdr](https://jrsoftware.org/ishelp/topic_setup_usesetupldr.htm)）这个临时目录由 `SetupLdr` 在**任何 `[Setup]` 指令生效之前**创建，因此 `DisableDirPage`、`Uninstallable`、`SolidCompression`、`{tmp}` 常量**都无法改变它**。
2. **唯一能真正绕开该失败点的官方开关是 `UseSetupLdr=no`**，代价是产物从单文件变成至少三个文件（`Setup.exe` + `Setup-0.bin` + `Setup-1.bin`），并会破坏卸载器的数字签名。
3. **`SolidCompression` 与 `%TEMP%` 无关**，它只影响压缩流布局（见 §4.5）。
4. **免管理员 + 注册 URL 协议是可以同时做到的**，官方推荐写法是把 `Root: HKCR` 换成 `Root: HKA` + `Subkey: "Software\Classes\..."`：Inno 官方明确说 "Using HKCR is not recommended, use HKA with the Subkey parameter set to `Software\Classes` instead."（[ishelp: Registry section](https://jrsoftware.org/ishelp/topic_registrysection.htm)）在非管理员安装模式下 `HKA` 就等于 `HKCU`，即落到 `HKCU\Software\Classes`。
5. **社区主流做法不是"摆脱传统安装器"，而是"传统安装器 + 免管理员模式 + 附带 MSIX/portable 选项"。** 两个 star 量较大的 Flutter Windows 应用（LocalSend、Spotube）都在用 Inno/Squirrel 系方案，LocalSend 还额外附带一个 MSIX helper。
6. **若坚持单个 exe 且要彻底避开 EXE 自解包，理论上的路线是 MSIX**（注册到 Windows 管理的安装存储，不走 `%TEMP%` 自解包），**但 MSIX 的免管理员门槛在于签名**：自签名证书必须导入"本地计算机 → 受信任人"存储（需要管理员），否则要用 CA 签发的证书（[MSIX: create-certificate-package-signing](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)）。

---

## 3. Inno Setup 的自解包机制（源码级）

这一节的材料来自 Inno Setup 官方源码仓库 `jrsoftware/issrc`（`main` 分支）与官方帮助文档。**这是本次调研中最有价值的部分：它把"为什么会有 `is-*.tmp`"从传闻变成了可读的代码。**

### 3.1 官方文档的说法

`[Setup]` 段的 `UseSetupLdr` 指令（[ishelp: UseSetupLdr](https://jrsoftware.org/ishelp/topic_setup_usesetupldr.htm)）原文：

> Valid values: yes or no, or x86 or x64 — Default value: *(see below)*

> This tells the compiler which type of Setup to create. If this is no, it compiles the setup data into at least three files: Setup.exe, Setup-0.bin, and Setup-1.bin. The **only** reason you would probably want to use no is for debugging purposes. Otherwise, it compiles all setup data into a single EXE.
>
> When all setup data is compiled into a single EXE, a "Setup Loader" program is used, called SetupLdr. […]
>
> **_Note:_ Do not use no on an installation which uses disk spanning. When using yes, the setup program is copied to and run from the user's TEMP directory. This does not happen when using no**, and could result in errors if Windows tries to locate the Setup.exe file on the disk and can't find it because a different disk is in the drive.
>
> **_Note:_ Do not use no to avoid digital signature verification startup delays on a large Setup, use disk spanning instead.** […] Also note that digitally signing Setup when using no will lead to an invalid digital signature for Uninstall.

**这一句就是答案的核心**：单文件模式下，"setup program is copied to and run from the user's TEMP directory"。`is-*.tmp` 不是安装数据（payload）的解包目录，而是**安装器自身可执行文件**的落地目录。

### 3.2 源码证据：SetupLdr 做了什么

`Projects/SetupLdr.dpr`（[raw 源码](https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/SetupLdr.dpr)）主流程：

```pascal
{ Create a temporary directory, and extract the embedded setup program
  there }
S := CreateTempDir('.tmp', IsAdminLoggedOn);
TempDir := S;   { assign only if string was successfully constructed }
S := AddBackslash(TempDir) + PathChangeExt(SelfFilename, '.tmp');
TempFile := S;

SourceF.Seek(OffsetTable.OffsetEXE);
...
  DestF := TFile.Create(TempFile, fdCreateAlways, faWrite, fsNone);
  ...
  Reader.Read(P^, OffsetTable.UncompressedSizeEXE);
  ...
  DestF.WriteBuffer(P^, OffsetTable.UncompressedSizeEXE);
...
ExecAndWait(TempFile, Format('/SL5="$%x,%d,%d," ...), SetupLdrExitCode);
```

逐条读出来的事实：

1. `CreateTempDir('.tmp', ...)` —— 扩展名 `.tmp`，这就是 `is-XXXXXXXXXX.tmp` 的 `-XXXXX-XXXXX.tmp` 半截的来源。
2. 它把**内嵌的 Setup 可执行文件**（`OffsetTable.OffsetEXE`）解压写入该临时文件，然后 `ExecAndWait` 启动它，并把自身文件路径用 `/SL5=` 参数传给子进程。
3. 失败发生在**这一步之前**——即 `CreateTempDir` 创建目录时。这与现场观察一致：无窗口、无日志（`/LOG` 由 Setup 处理，而此时 Setup 还没跑起来）。

### 3.3 源码证据：临时目录名怎么来的

`Projects/Src/SetupLdrAndSetup.InstFunc.pas`（[raw 源码](https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/Src/SetupLdrAndSetup.InstFunc.pas)）：

```pascal
function GenerateUniqueName(Path: String; const Extension: String): String;
...
    Filename := Path + 'is-' +
      UIntToBase36Str(TStrongRandom.GenerateUInt32Range(FiveDigitsRange), 5) +
      UIntToBase36Str(TStrongRandom.GenerateUInt32Range(FiveDigitsRange), 5) +
      Extension;
  until not FileOrDirExists(Filename);
```

即 `is-` + 两段 5 位 base36 随机串 + `.tmp`——与报错里的 `is-XXXXXXXXXX.tmp` 完全对应。

### 3.4 源码证据：目录是怎么建的（**这一处解释了「管理员能成功」**）

同一个文件里的 `CreateTempDir` / `CreateSafeDirectory`：

```pascal
function CreateTempDir(const Extension: String;
  const LimitCurrentUserSidAccess: Boolean; var Protected: Boolean): String;
{ This is called by SetupLdr, Setup, and Uninstall. }

  function CreateSafeDirectory(const LimitCurrentUserSidAccess: Boolean; Path: String;
    var ErrorCode: DWORD; out Protected: Boolean): Boolean;
  { Creates a protected directory if
    -permissions are supported
    -it's a subdirectory of c:\WINDOWS\TEMP, or
    -it's on a local drive and LimitCurrentUserSidAccess is True
    otherwise creates a normal directory. }
  begin
    ...
      var IsUnderWindowsTemp := Pos(PathLowercase(AddBackslash(GetSystemWinDir) + 'TEMP\'),
        PathLowercase(Path)) = 1;
      var IsLocalTempToProtect := LimitCurrentUserSidAccess and (Drive <> '') and
        not PathCharIsSlash(Drive[1]) and
        (GetDriveType(PChar(AddBackslash(Drive))) <> DRIVE_REMOTE);
      Protected := IsUnderWindowsTemp or IsLocalTempToProtect;
    ...
    if Protected then begin
      var StringSecurityDescriptor := 'D:PAI';
      var CurrentUserSid := GetCurrentUserSid;
      if CurrentUserSid = '' then
        CurrentUserSid := 'OW'; // OW: owner rights
      if not SameText(CurrentUserSid, 'S-1-5-18') then begin
        var AccessRights := 'FA'; // FILE_ALL_ACCESS
        if LimitCurrentUserSidAccess then
          AccessRights := 'FRFX'; // FILE_GENERIC_READ | FILE_GENERIC_EXECUTE
        StringSecurityDescriptor := StringSecurityDescriptor +
          '(A;OICI;' + AccessRights + ';;;' + CurrentUserSid + ')';
      end;
      StringSecurityDescriptor := StringSecurityDescriptor +
        '(A;OICI;FA;;;BA)' +   // built-in Administrators
        '(A;OICI;FA;;;SY)';    // local SYSTEM

      var pSecurityDescriptor: Pointer;
      if not ConvertStringSecurityDescriptorToSecurityDescriptorW(...) then begin
        ErrorCode := GetLastError;
        Result := False;
        Exit;
      end;
      ...
      Result := CreateDirectory(PChar(Path), @SecurityAttr);
      if not Result then
        ErrorCode := GetLastError;
      LocalFree(pSecurityDescriptor);
    end else begin
      Result := CreateDirectory(PChar(Path), nil);
      if not Result then
        ErrorCode := GetLastError;
    end;
  end;

var
  Dir: String;
  ErrorCode: DWORD;
begin
  while True do begin
    Dir := GenerateUniqueName(GetTempDir, Extension);
    if CreateSafeDirectory(LimitCurrentUserSidAccess, Dir, ErrorCode, Protected) then
      Break;
    if ErrorCode <> ERROR_ALREADY_EXISTS then
      raise Exception.Create(FmtSetupMessage(msgLastErrorMessage,
        [FmtSetupMessage1(msgErrorCreatingDir, Dir), IntToStr(ErrorCode),
         Win32ErrorString(ErrorCode)]));
  end;
  Result := Dir;
end;
```

`IsAdminLoggedOn` 的实现（同仓库 `Projects/Src/Shared.CommonFunc.pas`）：

```pascal
function IsAdminLoggedOn: Boolean;
{ Returns True if the logged-on user is a member of the Administrators local group. }
const
  DOMAIN_ALIAS_RID_ADMINS = $00000220;
begin
  Result := IsMemberOfGroup(DOMAIN_ALIAS_RID_ADMINS);
end;
```

**读出两条关键事实：**

1. **报错文本对应的是 `CreateTempDir` 抛出的异常**（`msgErrorCreatingDir` = "Setup was unable to create the directory"，后接 Win32 错误码）。`Error 5` = `ERROR_ACCESS_DENIED`。注意：`ERROR_ALREADY_EXISTS` 会被静默重试，所以「名字撞车」不可能产生这个报错——报错就是**真的建不出来**。
2. **管理员与非管理员走的是两条不同的建目录路径**：
   - **管理员**（`IsAdminLoggedOn=True`，且 `%TEMP%` 在本地驱动器上）→ `Protected=True` → 用**显式 SDDL** 创建目录（`D:PAI(A;OICI;FRFX;;;<user>)(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)`），**不依赖父目录的继承 ACL**，且显式授予当前用户读+执行。
   - **非管理员**（且 `%TEMP%` 不在 `%WINDIR%\TEMP` 下）→ `Protected=False` → `CreateDirectory(Path, nil)`，**完全依赖父目录 `%TEMP%` 的继承 ACL 与调用者的隐式权限**。

   → 这解释了一个反直觉的现象：**同一个 `%TEMP%`，管理员能建、普通用户建不了**。这是"ACL 问题"的一种特定形态：不是 `%TEMP%` 整体不可写，而是**继承链或令牌权限**让"默认 ACL 创建"失败，而"显式 SDDL 创建"成功。

3. `GetTempDir` 用 `GetTempPath2W`（存在时）否则 `GetTempPathW`，并对「TEMP 目录被删」有专门的补救逻辑（见 §5.1）。

### 3.5 `{tmp}` 常量是什么（澄清一个常见误解）

`{tmp}` 在官方文档里的定义（[ishelp: Constants](https://jrsoftware.org/ishelp/topic_consts.htm)）：

> **{tmp}** — Temporary directory used by Setup or Uninstall. This is _not_ the value of the user's TEMP environment variable. It is a subdirectory of the user's temporary directory which is created by Setup or Uninstall at startup (with a name like `C:\Windows\Temp\IS-xxxxx.tmp`). All files and subdirectories in this directory are deleted when Setup or Uninstall exits. During Setup, this is primarily useful for extracting files that are to be executed in the `[Run]` section but aren't needed after the installation.

要点：

- `{tmp}` 属于 **Setup 阶段**（脚本运行时），而失败发生在 **SetupLdr 阶段**（Setup 还没启动）。**改 `{tmp}` 用法不可能影响 SetupLdr 的自解包目录。**
- 文档里的示例路径是 `C:\Windows\Temp\IS-xxxxx.tmp`，与实际报错的 `C:\Users\<user>\AppData\Local\Temp\is-XXXXXXXXXX.tmp` 不同——说明该示例是老版本的残留（老版本可能用系统 TEMP），**不要照抄示例当作机制描述**，机制以源码为准（`GetTempDir` → `GetTempPath`）。

---

## 4. 能否绕开这个失败点

逐条回答提问中列出的候选开关。**依据均为官方文档或官方源码。**

### 4.1 `UseSetupLdr=no` —— ✅ 这是唯一真正绕开的开关

**依据**：官方文档明确写 "When using yes, the setup program is copied to and run from the user's TEMP directory. **This does not happen when using no**."（[ishelp: UseSetupLdr](https://jrsoftware.org/ishelp/topic_setup_usesetupldr.htm)）

**代价（同样出自该页原文）**：

| 代价 | 原文 |
| --- | --- |
| 产物不再是单文件 | "it compiles the setup data into at least three files: Setup.exe, Setup-0.bin, and Setup-1.bin" |
| 官方定位是调试用 | "The **only** reason you would probably want to use no is for debugging purposes." |
| 卸载器签名失效 | "digitally signing Setup when using no will lead to an invalid digital signature for Uninstall" |
| 不能与 disk spanning 共用 | "Do not use no on an installation which uses disk spanning" |
| `/HELP` 失效 | "[Setup Command-Line Parameters](https://jrsoftware.org/ishelp/topic_setupcmdline.htm)": "/HELP, /? — […] **Ignored if the UseSetupLdr [Setup] section directive was set to no.**" |
| 官方不建议用它规避签名延迟 | "Do not use no to avoid digital signature verification startup delays on a large Setup, use disk spanning instead." |

**对本项目的现实评估**：这会把 `Han1meWinPlus-Setup.exe` 变成三个文件，GitHub Release 需要再套一层 zip，用户体验变差；而且**它解决的是"这台机器上跑不起来"，不是"方案更优"**。属于"能用但不推荐作为长期方案"。

### 4.2 `PrivilegesRequired=lowest` —— ⚠️ 不绕开，但**是免管理员的正确开关**

**依据**（[ishelp: PrivilegesRequired](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm)）：

> Valid values: admin, or lowest — Default value: admin
> When set to admin (the default), Setup will always run with administrative privileges and in administrative install mode. If Setup was started by an unprivileged user, Windows will ask for the password to an account that has administrative privileges, and Setup will then run under that account.
> When set to lowest, Setup will not request to be run with administrative privileges even if it was started by a member of the Administrators group and will always run in non administrative install mode. Do not use this setting unless you are sure your installation will run successfully on unprivileged accounts.

**注意**：`PrivilegesRequired` 控制的是 **Setup 阶段的 UAC 请求与安装模式**，与 **SetupLdr 阶段的临时目录创建**无关（SetupLdr 在 UAC 之前运行）。所以它**不能**修掉当前报错。

但它与 URL 协议注册直接相关（见 §4.7 与 §8）。

**非管理员安装模式的影响**（[ishelp: Non Administrative Install Mode](https://jrsoftware.org/ishelp/topic_admininstallmode.htm)）：

> In non administrative install mode:
> - The {group} folder is created in the current user's profile.
> - The "auto" form of the directory and Shell Folder constants is mapped to the "user" form.
> - The **HKA**, uninstall info, and font install root keys will be **HKEY_CURRENT_USER**.

另有一条值得注意的告警（同页）：

> If the installation is running in non administrative install mode, but administrative privileges are available anyway then Setup or the [Code] section might still make use of these privileges. For this reason the uninstaller will always be marked as requiring administrative privileges in this case, just as if the installation was running in administrative install mode.

**含义**：如果以管理员身份运行一个 `PrivilegesRequired=lowest` 的安装包，卸载器会被标记为需要管理员。想要"纯用户级、卸载器也不要提权"，必须**确保不是以管理员身份启动**。

### 4.3 `Uninstallable=no` —— ❌ 与失败点无关

**依据**（[ishelp: Uninstallable](https://jrsoftware.org/ishelp/topic_setup_uninstallable.htm)）：该指令只决定"是否把自动卸载器打包进去"：

> This determines if Inno Setup's automatic uninstaller is to be included in the installation. […] Otherwise, no uninstallation support is included, requiring the end-user to manually remove the files pertaining to your application.

它与临时目录无关。**不要为了"绕过 TEMP"而关掉卸载能力**——那是拿功能换不来任何东西。

### 4.4 `DisableDirPage` —— ❌ 与失败点无关

`DisableDirPage` 只影响向导是否显示"选择安装位置"页（属于 UI 层面）。**它与 SetupLdr 的自解包毫无关系**，因为自解包发生在任何一个向导页出现之前。本次抓取中我未单独抓取该指令页，故不引用其原文；结论基于 §3.2 的源码流程（SetupLdr 在 Setup 启动**之前**创建临时目录），因此任何 `[Setup]` UI 指令在时序上都来不及生效。

### 4.5 `SolidCompression` —— ❌ 与 `%TEMP%` 无关（提问中的假设不成立）

**依据**（[ishelp: SolidCompression](https://jrsoftware.org/ishelp/topic_setup_solidcompression.htm)）：

> If yes, solid compression will be enabled. This causes all files to be compressed at once instead of separately. […] The disadvantage to using solid compression is that because all files are compressed into a single compressed stream, Setup can no longer randomly access the files. This can decrease performance. […] And if, for example, there was an error while extracting a particular file and the user clicks Retry, it can't just seek to the beginning of that file's compressed data; since all files are stored in one stream, it has seek to the very beginning.

它只影响**压缩流布局与随机访问能力**，不改变临时目录位置。

`Compression` 指令的取值与内存需求（[ishelp: Compression](https://jrsoftware.org/ishelp/topic_setup_compression.htm)）顺带澄清一个可能的混淆点：`lzma2/max` 解压需约 **8 MB** 字典（`max` 档 "Decompression (dictionary size) 8 MB"）。当前脚本用的是 `Compression=lzma2`（默认 level 是 max），**内存需求很小，不可能是失败原因**。

### 4.6 用 `{tmp}` 常量改路径 —— ❌ 时序上不可能

见 §3.5。`{tmp}` 是 Setup 阶段才解析的常量，而失败在 SetupLdr 阶段。**改脚本里任何 `{tmp}` 的用法都不会改变失败点。**

### 4.7 已知 issue / 社区诉求

抓到的**唯一**直接相关的一手条目是 `jrsoftware/issrc` **PR #475 "Add specific environment variable for temp folder"**（[GitHub PR](https://github.com/jrsoftware/issrc/pull/475)，经 GitHub Search API 检索 `repo:jrsoftware/issrc TEMP in:title` 得到，`total_count=1`）：

```json
{
  "number": 475,
  "title": "Add specific environment variable for temp folder",
  "state": "closed",
  "created_at": "2024-10-30T10:27:29Z",
  "closed_at": "2024-10-30T04:19:04Z",   // 见下方说明
  "merged_at": null,
  "comments": 5,
  "body": "Add Support of a new environment variable to have to possibility to use specific folder for temp file of inno setup"
}
```

**读出来的事实**：

- 社区**确实**想要"用一个环境变量指定 Inno 的临时目录"——这正好对应本项目的诉求。
- 该 PR 的 `state` 是 `closed` 且 **`merged_at` 为 `null`** → **未被合并**。也就是说：截至抓取时，**Inno Setup 没有提供官方的"改自解包临时目录"的配置项或环境变量**。
- 该 PR 在创建当天即被关闭（`created_at` 10:27:29Z，`closed_at` 04:19:04Z——两者日期相同、时间倒挂，是 API 返回的原始字段，我照录不修正）。

关于 issue #475 的 5 条评论，我尝试抓取 `https://api.github.com/repos/jrsoftware/issrc/issues/475/comments` 时遇到 **HTTP 403 GitHub API 限流**（"API rate limit exceeded for 43.198.240.47"），**因此未取得讨论内容**。若需了解官方拒绝理由，见 §9。

**结论**：提问中设想的"有没有 `%TEMP%` 相关的已知问题/issue"——**有**，就是这条 PR，但它被关闭且未合并；**官方没有提供绕开手段**，唯一官方途径仍是 `UseSetupLdr=no`。

### 4.8 小结表

| 候选手段 | 能否绕开 `%TEMP%` 自解包失败 | 依据 |
| --- | --- | --- |
| `UseSetupLdr=no` | ✅ **能**（不再复制到 TEMP） | [ishelp: UseSetupLdr](https://jrsoftware.org/ishelp/topic_setup_usesetupldr.htm) + [SetupLdr.dpr 源码](https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/SetupLdr.dpr) |
| `PrivilegesRequired=lowest` | ❌ 不能（但用于免管理员安装） | [ishelp: PrivilegesRequired](https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm) |
| `Uninstallable=no` | ❌ 无关 | [ishelp: Uninstallable](https://jrsoftware.org/ishelp/topic_setup_uninstallable.htm) |
| `DisableDirPage` | ❌ 无关（UI 层，时序在后） | §3.2 源码时序 |
| `SolidCompression` | ❌ 无关（压缩流布局） | [ishelp: SolidCompression](https://jrsoftware.org/ishelp/topic_setup_solidcompression.htm) |
| `{tmp}` 常量 | ❌ 时序在后 | [ishelp: Constants](https://jrsoftware.org/ishelp/topic_consts.htm) + §3.2 |
| 环境变量覆盖临时目录 | ❌ 官方未提供（PR #475 已关闭未合并） | [PR #475](https://github.com/jrsoftware/issrc/pull/475) |

---

## 5. 对本机故障的新线索（待验证）

> ⚠️ **本节是假设，不是结论。** 现场已排除了若干因素，但源码给出了一个**此前未被检验的分支差异**，值得优先验证。以下「源码事实」与「我的推断」严格分开标注。

### 5.1 源码事实 A：Inno 自带「TEMP 目录被删」的补救逻辑

`Shared.CommonFunc.pas` 里的 `GetTempDir`（[raw 源码](https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/Src/Shared.CommonFunc.pas)）：

```pascal
function GetTempDir: String;
{ Returns fully qualified path of the temporary directory, with trailing backslash. }

  procedure RestoreDeletedTempDirWithLogonSessionId(const DeletedTempDir: String);
  { Restores a deleted temporary directory in the specific scenario described at
    https://learn.microsoft.com/en-us/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted }
  begin
    const DirWithoutSlash = RemoveBackslashUnlessRoot(DeletedTempDir);
    const BaseName = PathExtractName(DirWithoutSlash);
    var BaseNameIsNumber := False;
    for var I := Low(BaseName) to High(BaseName) do begin
      BaseNameIsNumber := CharInSet(BaseName[I], ['0'..'9']);
      if not BaseNameIsNumber then
        Break;
    end;
    if BaseNameIsNumber then
      CreateDirectory(PChar(DirWithoutSlash), nil);
  end;

var
  GetTempPathFunc: function(nBufferLength: DWORD; lpBuffer: LPWSTR): DWORD; stdcall;
  Buf: array[0..MAX_PATH] of Char;
begin
  { When available, GetTempPath2 is preferred as it returns a private
    directory (typically C:\Windows\SystemTemp) when running as SYSTEM }
  GetTempPathFunc := GetProcAddress(GetModuleHandle(kernel32),
    PAnsiChar('GetTempPath2W'));
  if not Assigned(GetTempPathFunc) then
    GetTempPathFunc := GetTempPathW;

  const Res := GetTempPathFunc(...);
  if (Res > 0) and (Res < ...) then begin
    Result := AddBackslash(PathExpand(Buf));
    if not DirExists(Result) then
      RestoreDeletedTempDirWithLogonSessionId(Result);
    Exit;
  end;
  ...
end;
```

**事实**：Inno 特意为「`%TEMP%` 目录本身不存在」写了一个补救分支，指向微软官方文档 [KB4506040 / %TEMP% folder that includes the logon session ID is deleted unexpectedly](https://learn.microsoft.com/en-us/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted)。

**该微软文档的关键事实**：

> In Windows Server that has Desktop Experience installed, the _%TEMP%_ folder that includes the session ID is deleted if you remain logged on to the computer for more than seven days. Therefore, some applications that have to access _%TEMP%_ don't work correctly after that time.
> […] To work around this issue, follow these steps: 1. [Remove %TEMP% entry from Folder value (recommended) or modify the LastAccess value] 2. [Disable Storage Sense (if Storage Sense is enabled)] 3. [Disable low free disk space warning] 4. [Disable Storage Sense by using Group Policy (Windows Server 2022 only)]

> The _%TEMP%_ folder is deleted by the **SilentCleanup** task (_cleanmgr.exe_) when the logon session exceeds seven days. **SilentCleanup** is scheduled daily together with Automatic Maintenance.
> When Storage Sense (_storsvc.exe_) is enabled, the _%TEMP%_ folder may be deleted. Storage Sense is disabled by default, but it may be enabled when the C drive runs out of free space.

**推断（待验证）**：这类"清理机制介入 `%TEMP%`"的行为，与"管理员能建、普通用户不能建"的症状方向一致——因为清理会导致**父目录 ACL 以非默认方式被重建或继承链被破坏**。但注意该 KB 明确标注 **Applies to: Windows Server 2022, Windows Server 2019**，本项目是桌面 Windows，**不能直接套用**。

### 5.2 源码事实 B：管理员与非管理员的建目录代码路径不同

见 §3.4。这是**源码白纸黑字**的分支差异：

| | 走哪条路 | 建目录方式 |
| --- | --- | --- |
| `IsAdminLoggedOn = True` 且 `%TEMP%` 在本地盘 | `Protected = True` | `CreateDirectory(Path, @SecurityAttr)` —— **显式 SDDL**，不依赖父目录继承 |
| `IsAdminLoggedOn = False` 且 `%TEMP%` 不在 `%WINDIR%\TEMP` | `Protected = False` | `CreateDirectory(Path, nil)` —— **依赖父目录继承 ACL** |

**推断（待验证，但这是目前最有解释力的假设）**：现场"以管理员身份运行就成功"很可能不是因为"管理员权限更多"，而是因为**管理员走了一条不依赖 ACL 继承的代码路径**。若 `%TEMP%`（或其某个祖先）的继承被破坏、或存在一条阻碍继承的 ACL 条目，则：

- 普通用户路径 → `CreateDirectory(Path, nil)` 吃 `ERROR_ACCESS_DENIED`（Error 5）
- 管理员路径 → 显式 SDDL 直接建成功

**为什么"手动建同格式目录成功"不构成反证**：`New-Item` / `CreateDirectory` 由 .NET/PowerShell 调用，其权限检查路径与令牌继承细节和 SetupLdr 进程不完全等同；更重要的是——**如果测试是在管理员 PowerShell 里做的，那测试走的正是"能成功"的那条路**。这一点值得复查。

### 5.3 建议的验证（低成本、可重复）

以下都是**只读或临时性**操作，不改变安装包内容：

1. **确认测试时 PowerShell 是否提权**：在**非提权**的普通 PowerShell 窗口里重复"手动建同格式目录"测试，落在同一个 `%TEMP%` 下。
2. **对比继承 ACL**：对被判定可写的 `%TEMP%` 与 `C:\Users\<user>\AppData\Local\`，导出并对比 `icacls` 输出，重点看是否有 `(OI)(CI)` 继承标志缺失、或存在 `Deny` 条目。
3. **换一个 `TEMP` 试跑**：因为 `GetTempPath` 的顺序是 `TMP` → `TEMP` → `USERPROFILE` → Windows（[GetTempPath2W 官方文档](https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppath2w)），可以在**当前用户**环境里把 `TMP`/`TEMP` 改指到一个新建的干净目录（例如 `C:\Users\<user>\TmpTest`），再双击安装包。若成功，则锁定在 `%TEMP%` 的 ACL/继承而非 Inno 本身。
   > 官方文档原文（权限顺序）：
   > "For non-system processes, the GetTempPath2 function checks for the existence of environment variables in the following order and uses the first path found: 1. The path specified by the TMP environment variable. 2. The path specified by the TEMP environment variable. 3. The path specified by the USERPROFILE environment variable. 4. The Windows directory."
   > 注意 `TMP` **优先于** `TEMP`，只改 `TEMP` 无效。
4. **检查 SilentCleanup / Storage Sense 是否动过 `%TEMP%`**（对应 §5.1）：查看任务计划 `\Microsoft\Windows\DiskCleanup\SilentCleanup` 的最近运行时间，以及"存储感知"是否开启。

### 5.4 本机只读核对结果（本次调研实测）

在**当前会话**里做的只读核对（未改动任何环境变量）：

```
TMP         = [C:\Users\<user>\AppData\Local\Temp]
TEMP        = [C:\Users\<user>\AppData\Local\Temp]
USERPROFILE = [C:\Users\<user>]

User.TMP    = [C:\Users\<user>\AppData\Local\Temp]
User.TEMP   = [C:\Users\<user>\AppData\Local\Temp]
Mach.TMP    = [C:\WINDOWS\TEMP]
Mach.TEMP   = [C:\WINDOWS\TEMP]

GetTempPath() = [C:\Users\<user>\AppData\Local\Temp\]
Exists = True
CreateDir OK -> C:\Users\<user>\AppData\Local\Temp\probe-f2b2d41a.tmp
```

**读出来的事实**：

- `GetTempPath()` 返回的正是报错信息里的那个目录（`C:\Users\<user>\AppData\Local\Temp\`），与 Inno `GetTempDir` 使用的同一 API，**路径解析环节正常**。
- `TMP` 与 `TEMP` 一致，都是用户级 `AppData\Local\Temp`（不是 `C:\WINDOWS\TEMP`）。
- 本次会话（DSH 会话，文件策略为 `danger-full-access`）能成功在该目录建同名格式的临时目录。
- **注意**：本次核对是在**当前会话的令牌**下做的，**未验证该令牌是否等同于双击安装包时的令牌**，故不能据此排除 §5.2 的假设。

---

## 6. 各方案对比

### 6.1 对比表

| 方案 | 需要管理员？ | 能注册 URL 协议？ | 能卸载？ | 自动更新？ | **自解包到 `%TEMP%`？** | 配置复杂度 | 对 Flutter `Release/` 目录的适配 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| **Inno Setup 6**（现状） | 默认 **要**；`PrivilegesRequired=lowest` 可免 | ✅ `[Registry]` 段，`HKCR` 或 `HKCU\Software\Classes` | ✅ 自带卸载器 | ❌ 无内置；需自己实现（本项目走应用内提示更新） | ⚠️ **`UseSetupLdr=yes`（默认）会**：把 setup 自身复制到 `%TEMP%\is-*.tmp` 运行 | 低（已有脚本，改 2–3 行可切换免管理员） | 直接：`Source: "...\Release\*"; Flags: recursesubdirs createallsubdirs` |
| **MSIX**（`msix` pub 包） | **安装不提权**（sideload 在 Win10 2004+/Win11 默认开启）；**但自签名证书需导入"本地计算机→受信任人"，该步需管理员**；用 CA 证书则无需 | ✅ `protocol_activation`（manifest 的 `windows.protocol` 扩展） | ✅ `Remove-AppxPackage` | ✅ `.appinstaller` 差分更新（64 KB 块） | ❌ **官方描述为注册进 Windows 管理的安装存储（stage/register），未描述解包到 `%TEMP%`** | 中：`pubspec.yaml` 加 `msix_config` 段 + 签名配置 | 直接：`dart run msix:create` 从 `build\windows\x64\runner\Release` 取产物 |
| **WiX Toolset**（MSI / Burn） | MSI 可 per-user（`ALLUSERS`/各版本属性不同）；Burn bootstrapper 常需提权 | ✅ 写 `ProgId`/`RegistryValue` | ✅ Windows Installer 原生 | ❌ 无内置；需自建（如 Squirrel 式或自研） | ⚠️ **Burn bundle 有 engine 提取行为**（§6.2 说明） | **高**：XML 声明式，学习曲线陡；`.wxs` 手写量大 | 间接：需先把目录"harvest"成组件清单（`heat`/`HarvestFolder`），Flutter 的 `data/` 嵌套目录会生成大量组件 |
| **NSIS** | 默认 **要**（`RequestExecutionLevel` 默认 `admin`）；`user` 可免 | ✅ `WriteRegStr HKCU "Software\Classes\..."` | ✅ 自带卸载器（`WriteUninstaller`） | ❌ 无内置 | ⚠️ 有临时目录机制（`$PLUGINSDIR`，见 §6.2） | 中：`.nsi` 脚本，语法类汇编 | 直接：`File /r "path\Release\*.*"` |
| **Velopack** | **不要**（per-user，装到 `%LocalAppData%\{packId}`）；要 `Program Files` 才用 MSI per-machine | ⚠️ 官方文档未提供内置 URL 协议注册项（需通过 app hooks/自定义脚本） | ✅ `Update.exe` 系（官方文档："updates work identically via Update.exe"） | ✅ **核心卖点**：差分更新 + 多通道 | ❌ 文档说解压到 `%LocalAppData%\{packId}`，**未描述经 `%TEMP%`** | 低：`vpk pack --packId ... --packVersion ... --packDir ... --mainExe ...` | 直接：`--packDir` 指向构建输出目录 |
| **Squirrel.Windows** | 不要（per-user） | 未确认 | ✅ | ✅ | 未确认 | — | — |
| **Clowd.Squirrel** | 未确认 | 未确认 | ✅ | ✅ | 未确认 | — | — |
| **flutter_distributor / Fastforge** | 取决于底层（Windows 目标走 EXE/MSIX/ZIP） | 取决于底层 | 取决于底层 | ❌ 本身不管更新 | 取决于底层 | 低：一份 `distribute_options.yaml` 编排 | 直接：它调用 `flutter build` 再交给底层打包器 |
| **纯 portable zip / 免安装** | **不要** | ❌ **不能**（无安装步骤；除非应用自己在首次运行时写 `HKCU`） | ❌ 无卸载器（删目录即"卸载"） | ❌ | ❌ 无（用户自己解压） | **最低**（现状 CI 已有一条 `Compress-Archive`） | 直接：就是 `Release\*` 打 zip |
| **winget** | 取决于底层安装器类型（含 INNO/MSIX/PORTABLE 等） | 取决于底层清单 | ✅（`winget uninstall`） | ✅（`winget upgrade`，取决于清单） | 取决于底层安装器 | 中：需写 manifest 并提交到 `microsoft/winget-pkgs` | 取决于底层；`PORTABLE` 类型可直接指 zip/exe |
| **Scoop** | **不要**（装到 `C:\Users\<user>\scoop`） | ❌ 本身不做注册（"portable"定义即"不产生改注册表的副作用"） | ✅（`scoop uninstall`） | ✅（`scoop update`） | ❌（解压到 scoop 目录树） | 低：一个 JSON manifest + 一个 zip | 直接：zip 即 payload |

### 6.2 关于「自解包到 `%TEMP%`」这一列的取证说明

这一列是本次调研的重点，逐方案说明**证据强度**，不含推测：

| 方案 | 证据 | 强度 |
| --- | --- | --- |
| **Inno** | 官方文档原文 + **官方源码**（`S := CreateTempDir('.tmp', IsAdminLoggedOn);`，随后解压 setup 自身并 `ExecAndWait`） | ⭐⭐⭐ 源码级确认 |
| **MSIX** | 微软官方 [What is MSIX?](https://learn.microsoft.com/en-us/windows/msix/overview) 描述为："**Reliable install and uninstall**"、"**Containerized execution**"、"Windows virtualizes or redirects certain file system and registry writes"；[Package registration and lifetime](https://learn.microsoft.com/en-us/windows/msix/package/package-lifetime) 描述 stage/register/destage 生命周期，安装物进"a Windows-managed installation store"。**官方文档全篇未描述任何"解包到 `%TEMP%`"的步骤** | ⭐⭐ 官方文档反证（**未见描述**，非"证明不存在"） |
| **NSIS** | 官方文档 [Chapter 4](https://nsis.sourceforge.io/Docs/Chapter4.html)：`$PLUGINSDIR` —— "The path to a temporary folder created upon the first usage of a plug-in or a call to InitPluginsDir. This folder is automatically deleted when the installer exits. This makes this folder the ideal folder to hold INI files for InstallOptions, bitmaps for the splash plug-in, or any other file that a plug-in needs to work." 即 NSIS **也**有临时目录机制，用于插件/资源（不是主 payload；主 payload 由 `File` 解压到 `$OUTDIR`） | ⭐⭐⭐ 官方文档确认"存在临时目录机制" |
| **Velopack** | 官方文档 [Windows Overview](https://docs.velopack.io/packaging/operating-systems/windows)："The Windows installer will extract the application to `%LocalAppData%\{packId}`"；[Installers](https://docs.velopack.io/packaging/installer)："The Windows installer is currently a 'one-click' installer"。**未描述经 `%TEMP%` 中转** | ⭐⭐ 官方文档（未见描述） |
| **WiX / Burn** | 本次**未取得**官方关于 Burn engine 提取位置的明确文档原文（`docs.firegiant.com/wix/tools/burn/` 页面被导航菜单占满导致正文截断） | ⭐ **未确认**（见 §9） |

### 6.3 各方案的官方配置片段（一手）

#### MSIX（`msix` pub 包）

配置方式（[pub.dev/packages/msix](https://pub.dev/packages/msix)，v3.18.0）：

```yaml
msix_config:
  display_name: Flutter App
  publisher_display_name: Company Name
  identity_name: company.suite.flutterapp
  msix_version: 1.0.0.0
  logo_path: C:\path\to\logo.png
  capabilities: internetClient, location, microphone, webcam
```

与本项目**直接相关的两个字段**（同一来源）：

| YAML | 说明 | 示例 |
| --- | --- | --- |
| `protocol_activation` | "Protocols activation that will activate the app." | `http,https` |
| `file_extension` | "File extensions that the app may be registered to open." | `.picture, .image` |

**URL 协议在 MSIX 里的实现**：对应 manifest 的 `uap:Extension` 扩展点，`Category` 取值包含 `windows.protocol`（[uap:Extension schema 官方文档](https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-extension)）：

> **Category** — The type of extension. A string that must be one of the following values: _windows.fileTypeAssociation_, **_windows.protocol_**, _windows.autoPlayContent_, …

**签名要求**（[create-certificate-package-signing](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)）：

> In order to install an app signed with this certificate, the certificate must be imported into the **Local Machine Trusted People** certificate store.

> Now that you've exported the certificate to a PFX file, you can import it into the Local Machine Trusted People store using the **Import-PfxCertificate** cmdlet **from an admin PowerShell session**.

> When you create and use a self-signed certificate **only users who install and trust your certificate can run your application.** This is easy to implement for testing but it may prevent additional users from installing your application. When you are ready to publish your application we recommend that you use a certificate issued by a trusted source.

**⇒ 这就是 MSIX 免管理员路线的关键约束**：自签名 = 每台机器都要管理员导入一次证书；真正免管理员需要 **CA 签发的代码签名证书**（付费）。

另外，关于 `msix` 包的默认行为（[pub.dev/packages/msix](https://pub.dev/packages/msix)）："By default, the MSIX package will install the certificate on your machine. You can disable this by using the `--install-certificate false` option"。而 `install_certificate` 的描述是 "If `false`, don't try to install the certificate, default is `true`"——**默认会尝试装证书**，这在免管理员场景下值得关注。

`msix` 的产物来源（同页，Build configuration 表）：`debug` 字段——"Create MSIX from the **debug** or **release** build files (`\build\windows\runner\<Debug/Release>`)"，默认 `release`。注意文档写的是 `build\windows\runner\`，而本项目实际产物路径是 `build\windows\x64\runner\Release\`（多了 `x64` 段）——**这是文档与新版 Flutter 目录布局的差异，实际使用时以本机构建输出为准**。

#### MSIX 的 `.appinstaller` 自动更新

（[pub.dev/packages/msix](https://pub.dev/packages/msix) + [App Installer 官方文档](https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-root)）

```yaml
msix_config:
  display_name: Flutter App
  app_installer:
    publish_folder_path: c:\path\to\myPublishFolder
    hours_between_update_checks: 0
    automatic_background_task: true
    update_blocks_activation: true
    show_prompt: true
    force_update_from_any_version: false
  msix_version: 1.0.3.0
```

命令：`dart run msix:publish`

**⚠️ 重要限制**（[Installing Windows apps from a web page](https://learn.microsoft.com/en-us/windows/msix/app-installer/installing-windows10-apps-web)，微软官方 Warning）：

> **The `ms-appinstaller:` URI protocol is disabled by default as of December 2023.** In App Installer version 1.21.3421.0 and later, Microsoft disabled the `ms-appinstaller:?source=` protocol handler on consumer devices in response to security concerns. **The one-click browser-triggered install described in this article will not work for most users without IT administrator intervention.**
> **For general distribution (non-enterprise)**: Use one of these alternatives instead:
> - **Publish to the Microsoft Store** — the recommended path for broad distribution.
> - **Direct `.appinstaller` file download** — host the `.appinstaller` file on your web server and link to it directly. Users download and double-click the file; no special protocol is required.

**含义**：MSIX 的"网页一键安装"对普通用户已经不可用；可行的是"下载 `.appinstaller` 后双击"。这对 GitHub Release 分发是可行的。

MSIX 的更新与卸载语义（[Package registration and lifetime](https://learn.microsoft.com/en-us/windows/msix/package/package-lifetime)）：

> Removing an MSIX package for a user doesn't always immediately delete its staged files. […] `Remove-AppxPackage` removes a registration. **Don't use the absence of a user registration as proof that Windows has already deleted every staged file.**

MSIX 的核心优势（[What is MSIX?](https://learn.microsoft.com/en-us/windows/msix/overview)）：

> - **Reliable install and uninstall.** MSIX delivers a 99.96% install success rate across millions of installs and guarantees a clean uninstall with no leftover files or registry entries.
> - **Differential updates.** Only changed 64 KB blocks are downloaded on update, minimizing network impact and update time.
> - **Disk space efficiency.** Shared files across apps are managed by Windows; each app remains independent so updates don't affect other apps.

#### NSIS

免管理员的最小配置（[NSIS Chapter 4: RequestExecutionLevel](https://nsis.sourceforge.io/Docs/Chapter4.html)）：

```
RequestExecutionLevel user
```

官方说明原文：

> **RequestExecutionLevel** — `none|user|highest|admin` (default **admin**)
> […] _user_ requests the user's normal level with no administrative privileges. […] _admin_, which is also the default, requests administrator level and will cause Windows to prompt the user as well. Specifying _none_ will keep the manifest empty and let Windows decide which execution level is required. **Windows automatically identifies NSIS installers and decides administrator privileges are required. Because of this, _none_ and _admin_ have virtually the same effect.**
> It's recommended that every application is marked with a required execution level. […] **Installers that don't install anything into system folders nor write to the local machine registry (HKLM) should specify _user_ execution level.**

**注意最后那句**：官方的建议正是"不写 HKLM、不装系统目录 → 用 `user`"。这与本项目"免管理员 + 注册到 HKCU"的目标完全一致。

NSIS 的注册表指令（同页，"Registry, INI, File Instructions" 一节）包含 `WriteRegStr`，可写 `HKCU`。**但我在本次抓取中未取得 `WriteRegStr` 的原文段落**（该页被截断，完整文本存于抓取缓存），故不引用其原文措辞；注册表写入 `HKCU` 是 Windows API 层面的既定能力（见 §6.4 的 HKCR/HKCU 官方说明）。

#### Velopack

（[Packaging Overview](https://docs.velopack.io/packaging/overview)）

```bash
dotnet publish -c Release -r win-x64 -o publish
vpk pack --packId MyAppId --packVersion 1.0.0 --packDir publish --mainExe MyApp.exe
```

必需参数（同页）：

> - `--packId {id}` The unique ID of your application. […]
> - `--packVersion {version}` The current version you're releasing - in [semver2 format] […]
> - `--packDir {build_dir}` **The folder containing your compiled application.**
> - `--mainExe {exeName}` The main executable to be started after install […]
>
> tip: Velopack does not support 4 part versions (eg. `1.0.0.0`)

**注意**：`--packVersion` **不支持四段式版本号**（`1.0.0.0`），只支持 semver2。本项目版本号形如 `1.1.25`（三段），符合要求。

产物（同页）：

> - `MyAppId-1.0.0-full.nupkg` - Full Release […]
> - `MyAppId-1.0.0-delta.nupkg` - Delta Release […] speeds up the updating process for users
> - `MyAppId-Portable.zip` - Portable Release […]
> - `MyAppId-Setup.exe` - Installer […]
> - `releases.{channel}.json` - Releases Index […]
> - `RELEASES` - Legacy Releases File […] for clients migrating to Velopack from Squirrel

免管理员与安装位置（[Windows Overview](https://docs.velopack.io/packaging/operating-systems/windows)，官方 info 块原文）：

> The `Setup.exe` installer is per-user and installs to `%LocalAppData%\{packId}`, so it **does not require elevation or use privileged directories**. If you need a per-machine install to `Program Files`, use the MSI installer with `--msi --instLocation PerMachine`, which installs to `Program Files\{publisher}\{packTitle}` (HKLM registry, requires elevation).

**Velopack 的语言支持（关键：Flutter/Dart 不在列表里）**（[Introduction](https://docs.velopack.io/)）：

| Lang | Status |
| --- | --- |
| C# | ✅ Ready |
| Rust | ✅ Ready |
| JS | ✅ Ready |
| C++ | ✅ Ready |
| Python | ✅ Ready |
| **Java** | **Planned** |
| **Swift** | **Planned** |
| **Go** | **Planned** |

> Don't see your language here? [Open an issue to request it]

**⇒ 对本项目的含义**：Velopack 的**打包侧（`vpk pack`）与语言无关**（它只是把 `--packDir` 打成一个 nupkg + Setup.exe），但**自动更新的客户端 SDK 没有 Dart/Flutter 支持**。所以走 Velopack 意味着：能用它打包和做差分更新，但**应用内的更新检查逻辑需要自己实现**（例如自己读 `releases.win.json` 再调用 `Update.exe`）。

Velopack 的更新机制细节（[Windows Overview](https://docs.velopack.io/packaging/operating-systems/windows)）：

> During updates, the entire `current` directory will be replaced, so if you need to store settings, logs, crash reports, and so on, please see [Preserving Files].

> If the folder can not be renamed during the update process, Velopack's updater will attempt to automatically kill any processes running inside `current`. […] **If the locking process could not be identified, (for example, if the locking process is running as Administrator) then an error message will be shown to the user, and the old version of the application will be launched.**

目录结构（同页）：

```
%LocalAppData%
└── {packId}
    ├── current
    │   ├── YourFile.dll
    │   ├── sq.version
    │   └── YourApp.exe
    ├── Update.exe
    └── YourApp.exe          (execution stub)
```

> The root-level `YourApp.exe` is a small execution stub which launches the real executable inside `current`. It is created by both `Setup.exe` and the `.msi` installer, so shortcuts/launchers can point at a stable path that survives updates.

**对这个项目的一个具体警示**：本项目数据在 `%APPDATA%\han1me_win_plus\`（在 `current` 之外），因此 **不受 `current` 被整体替换的影响**——这与 Velopack 的设计正好相容。但**卸载时数据目录不会被自动清理**，需要自己处理卸载钩子。

Velopack 对 WiX 的引用（[Installers](https://docs.velopack.io/packaging/installer)）：

> Velopack builds MSIs using its own fork of WiX v7, rather than binaries produced by the official WiX Toolset project. […] Because Velopack compiles its own fork rather than depending on WiX's official binaries, **the OSMF does not apply to Velopack or to applications packaged with `vpk --msi`**.

#### WiX

（[About the WiX Toolset](https://docs.firegiant.com/wix/)）

WiX 文档站的结构确认了版本谱系：`WiX v3 deprecated` → v4/v5/v6 现行版本文档，且有 **Open Source Maintenance Fee** 页面（[/wix/osmf/](https://docs.firegiant.com/wix/osmf/)）。WiX v3 已被官方标记为 **deprecated**（文档侧栏分类："WiX v3 deprecated"）。

**WiX 的许可注意事项**（Velopack 文档的转述，非 WiX 官方）：

> the Open Source Maintenance Fee (OSMF) that WiX v7 introduced applies only to consumers of WiX's official, compiled binaries. WiX's source code itself is MS-RL licensed and can be used freely without restriction.

（这条来自 Velopack 官方文档，属于"第三方对 WiX 的陈述"，建议直接以 [WiX OSMF 页面](https://docs.firegiant.com/wix/osmf/) 为准。）

#### winget

（[Use WinGet to install and manage applications](https://learn.microsoft.com/en-us/windows/package-manager/winget/)）

支持的安装器格式：

> **WinGet** supports the following types of installers:
> EXE (with **Silent** and **SilentWithProgress** flags), ZIP, **INNO**, **NULLSOFT**, MSI, **WIX**, APPX, **MSIX**, BURN, **PORTABLE**, FONT

**⇒ 对本项目直接有用**：winget **原生支持 INNO 类型**，也就是说**现有的 `Han1meWinPlus-Setup.exe` 不需要换打包器就能上 winget**。同时也支持 `PORTABLE` 与 `ZIP`（对应现有 portable zip）。

关于管理员（同页）：

> - When running **WinGet** without administrator privileges, some applications may require elevation to install. When the installer runs, Windows will prompt you to elevate. **If you choose not to elevate, the application will fail to install.**

**⇒ 含义**：winget 不提权是"不主动提权"，但**如果底层安装器需要提权，仍然会弹 UAC**。所以走 winget **不能修复**本项目"需要管理员才能装"的问题——它只解决"发现与升级的渠道"。除非底层换成一个真正免管理员的安装器。

#### Scoop

（[Scoop README](https://raw.githubusercontent.com/ScoopInstaller/Scoop/master/README.md)）

安装无需管理员（官方原文）：

> Run the following commands from a regular (non-admin) PowerShell terminal to install Scoop:
> ```powershell
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
> Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
> ```
> It will install Scoop to its default location: `C:\Users\<YOUR USERNAME>\scoop`

Scoop 的定位（官方原文）：

> - Eliminates **User Account Control** (UAC) prompt notifications.
> - Hides the graphical user interface (GUI) of wizard-style installers.
> - Prevents polluting the `PATH` environment variable. […]
> - **Avoids unexpected side effects from installing and uninstalling apps.**

> If you have built software that you would like others to use, Scoop is an alternative to building an installer (like MSI or InnoSetup). **You just need to compress your app to a `.zip` file and provide a JSON manifest that describes how to install it.**

> The apps that are most likely to get installed fine with Scoop are those referred to as "portable" apps. […] **This type of app does not produce side effects like changing the Windows Registry or placing files outside the app directory.**

**⇒ 对本项目的关键矛盾**：Scoop 的"portable"定义**明确不鼓励改注册表**。而本项目需要注册 `han1me://`——这与 Scoop 的理想模型冲突。Scoop 的 manifest 支持 `post_install` 脚本（可以做注册），但这超出"portable"的语义，且**每个用户的安装位置不同**（`C:\Users\<user>\scoop\apps\...`），协议注册的路径需动态化。

#### flutter_distributor / Fastforge

（[fastforge README](https://raw.githubusercontent.com/leanflutter/flutter_distributor/main/README.md)）

**首先一个重要事实：`flutter_distributor` 已改名并迁移。**

> # Fastforge <sub>formerly Flutter Distributor</sub>
> […]
> - `distribute_options.yaml` and the `release` command are **deprecated**: they keep working for compatibility but get no new features. New configuration goes in `.fastforge/` (project) or `~/.fastforge/` (machine), and new automation in [local workflows](docs/en/workflows.md).
> - **Rust Migration In Progress:** The core of Fastforge is being rewritten in [Rust] […] The native CLI lives in [`apps/cli/`](./apps/cli) […]
> - The current Dart-based CLI (`dart pub global activate fastforge`) continues to work and receives bug fixes.

支持的 Windows 打包格式（同页，"Supported Package Formats"）：

> - **Windows**: [EXE](docs/en/packagers/windows.md#exe), [MSIX](docs/en/packagers/windows.md#msix), [ZIP](docs/en/packagers/windows.md#zip-and-direct)
> - **Any platform**: [custom](docs/en/packaging.md#custom-format) packaging commands; `direct` (the unpacked build output) on Linux, Windows and Web

支持的发布目标包含 **GitHub Releases**（`docs/en/publishers/github.md`）。

**⇒ 对本项目的含义**：它**不提供 NSIS 或 Inno 目标**（Windows 侧只有 EXE / MSIX / ZIP）。它是个**编排器**而非打包器：调用 `flutter build`，再交给底层打 MSIX/EXE/ZIP，最后发布。所以它**不能替代**当前 Inno 的"注册协议 + 清理旧版残留"能力——换成它反而会丢掉现有功能。

### 6.4 URL 协议注册：HKCR vs HKCU（**本项目最直接相关的一手结论**）

#### 微软官方：HKCR 是 HKLM 与 HKCU 的合并视图

（[HKEY_CLASSES_ROOT Key](https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key)，官方原文）

> Class registration and file name extension information is stored under both the **HKEY_LOCAL_MACHINE** and **HKEY_CURRENT_USER** keys. The **HKEY_LOCAL_MACHINE\Software\Classes** key contains default settings that can apply to all users on the local computer. The **HKEY_CURRENT_USER\Software\Classes** key contains settings that apply only to the interactive user. The **HKEY_CLASSES_ROOT** key provides a view of the registry that merges the information from these two sources.

> **The user-specific settings have priority over the default settings.** For example, the default setting might specify a particular application to handle .doc files. But a user can override this setting by specifying a different application in the registry.

> To change the settings for the interactive user, store the changes under **HKEY_CURRENT_USER\Software\Classes** rather than **HKEY_CLASSES_ROOT**.
> To change the default settings, store the changes under **HKEY_LOCAL_MACHINE\Software\Classes**. **If you write keys to a key under HKEY_CLASSES_ROOT, the system stores the information under HKEY_LOCAL_MACHINE\Software\Classes.** If you write values to a key under HKEY_CLASSES_ROOT, and the key already exists under HKEY_CURRENT_USER\Software\Classes, the system will store the information there instead of under HKEY_LOCAL_MACHINE\Software\Classes.

**⇒ 三条可直接落地的结论：**

1. **写 `HKCR` = 写 `HKLM\Software\Classes` = 需要管理员。** 这正是当前脚本 `Root: HKCR` 隐含要求管理员权限的原因。
2. **写 `HKCU\Software\Classes` 完全合法**，且用户级设置**优先级高于**机器级。
3. 用户级协议注册是**每用户**的：只对当前用户生效。对本项目（单用户桌面应用）通常足够，但若一台机器多用户使用，每个用户都要装一次。

#### 官方协议注册格式

（[Registering an Application to a URI Scheme](https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa767914(v=vs.85))，官方原文 + 示例）

> To register an application to handle a particular URI scheme, add a new key, along with the appropriate subkeys and values, to **HKEY_CLASSES_ROOT**. The root key must match the URI scheme that is being added. […]
>
> Under this new key, the **URL Protocol** string value indicates that this key declares a custom pluggable protocol handler. **Without this key, the handler application will not launch. The value should be an empty string.**
>
> Keys should also be added for **DefaultIcon** and **shell**. […] The name of the first key under the **shell** key should be an action verb, such as **open**. Under this key, a **command** key or a **DEEXEC** key indicate how the handler should be invoked. […]
>
> Finally, the **Default** string value should contain the display name of the new URI scheme.

官方示例结构：

```
HKEY_CLASSES_ROOT
   alert
      (Default) = "URL:Alert Protocol"
      URL Protocol = ""
      DefaultIcon
         (Default) = "alert.exe,1"
      shell
         open
            command
               (Default) = "C:\Program Files\Alert\alert.exe" "%1"
```

**与本项目现有脚本逐项对照**（`windows/installer.iss:69-72`）：

| 官方要求 | 本项目现状 | 一致性 |
| --- | --- | --- |
| 根键名 = scheme（`han1me`） | `Subkey: "han1me"` | ✅ |
| `URL Protocol` = `""`（**必需**，缺则不启动） | `ValueName: "URL Protocol"; ValueData: ""` | ✅（脚本注释也正确指出了这点） |
| `(Default)` = 显示名 | `ValueData: "URL:Han1meWinPlus"` | ✅ |
| `DefaultIcon` | `han1me\DefaultIcon` → `{app}\han1me_win_plus.exe,0` | ✅ |
| `shell\open\command` = `"exe" "%1"` | `"""{app}\han1me_win_plus.exe"" ""%1"""` | ✅ |
| **注册位置** | **`HKCR`（机器级）** | ⚠️ **可改进为 `HKA` + `Software\Classes`** |

#### Inno 官方对 `HKCR` 的明确态度（**直接针对本项目**）

（[ishelp: Registry section](https://jrsoftware.org/ishelp/topic_registrysection.htm)，`Root` 参数说明原文）

> | HKCU | Short for HKEY_CURRENT_USER |
> | HKLM | Short for HKEY_LOCAL_MACHINE |
> | HKCR | Short for HKEY_CLASSES_ROOT |
> | HKU | Short for HKEY_USERS |
> | HKCC | Short for HKEY_CURRENT_CONFIG |
>
> Additionally one special value is allowed:
>
> | HKA | Equals HKLM in administrative install mode, HKCU otherwise |
>
> HKCU and HKA should only be used for settings which are compatible with roaming profiles.
>
> **Using HKCR is not recommended, use HKA with the Subkey parameter set to `Software\Classes` instead.**

**⇒ 这是 Inno 官方直接给出的、与本项目当前写法冲突的建议。** 把 4 行 `[Registry]` 的 `Root: HKCR` 改成 `Root: HKA`，`Subkey` 加 `Software\Classes\` 前缀，即可：

- 在 `PrivilegesRequired=lowest`（非管理员）下落到 `HKCU\Software\Classes\han1me` → **免管理员**
- 在管理员模式下落到 `HKLM\Software\Classes\han1me` → 保持原有机器级行为

**同一页的另一条相关事实**（`uninsdeletekey` 的语义）：

> **uninsdeletekey** — When the program is uninstalled, delete the entire key, including all values and subkeys in it. It obviously wouldn't be a good idea to use this on a key that is used by Windows itself. You should only use this on keys private to your application.

本项目已在 4 行上都用了 `Flags: uninsdeletekey`，符合官方建议（`han1me` 是本应用私有键）。

**另一条相关事实**（`ValueData` 里的 `{olddata}`）：

> On a string, expandsz, or multisz type value, you may use a special constant called `{olddata}` in this parameter. `{olddata}` is replaced with the previous data of the registry value. […] If the value does not exist or the existing value isn't a string type, the `{olddata}` constant is silently removed.

这对"升级时保留用户既有协议设置"可能有价值，但本项目场景下不需要。

#### 免管理员卸载的配套开关

若切到 `PrivilegesRequired=lowest`，卸载信息写 `HKCU`（见 §4.2 的 Non Administrative Install Mode 官方说明："The **HKA**, uninstall info, and font install root keys will be **HKEY_CURRENT_USER**"）。这意味着"控制面板 → 程序和功能"里的条目对**其他用户不可见**——这是免管理员安装的固有代价，官方文档已明确。

---

## 7. 社区实例

> 说明：本节所有内容来自**实际抓取到的仓库文件**。star 数未能取得（GitHub Search API 在本次调研中途触发限流），故**不写 star 数**，避免编造。

### 7.1 `localsend/localsend` —— Inno Setup + MSIX helper（**与本项目最接近的参考**）

**证据 1：打包 CI 确认 Inno + MSIX 双轨**（[.github/workflows/ci.yml](https://raw.githubusercontent.com/localsend/localsend/main/.github/workflows/ci.yml)）

`packaging` job 里同时校验四套版本号，其中三套与 Windows 打包直接相关：

```yaml
      - name: Extract version from Inno Setup configuration
        run: |
          VERSION=$(grep '#define MyAppVersion ' support/scripts/compile_windows_exe-inno.iss | sed 's/#define MyAppVersion "//' | sed 's/"//')

      - name: Extract version from MSIX helper manifest
        run: |
          VERSION=$(grep -o ' Version="[0-9.]*"' support/build/msix/content/AppxManifest.xml | sed 's/ Version="//' | sed 's/"//')
```

```yaml
      - name: Compare pubspec, Inno Setup, CLI, MSIX helper and AppImage versions
        run: |
          if [ "$pubspec_version" != "$inno_version" ] || ... || [ "$pubspec_version.0" != "$msix_version" ] || ...; then
            echo "Version mismatch detected!"
            exit 1
```

（注意 `"$pubspec_version.0" != "$msix_version"`——MSIX 用四段版本号，与 pubspec 三段拼一个 `.0` 对齐。）

**证据 2：真实 Inno 脚本**（[support/scripts/compile_windows_exe-inno.iss](https://raw.githubusercontent.com/localsend/localsend/main/support/scripts/compile_windows_exe-inno.iss)）

关键片段（**逐字引用**）：

```ini
[Setup]
AppId={{00809252-FEC6-448E-83B4-E7F55AE7E47D}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
DefaultDirName={autopf}\{#MyAppName}
DisableProgramGroupPage=yes
; Uncomment the following line to run in non administrative install mode (install for current user only.)
;PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#ResultDir}
OutputBaseFilename=localsend
SetupIconFile={#PayloadDir}\logo.ico
UninstallDisplayIcon={app}\{#MyAppExeName}
Compression=lzma
SolidCompression=yes
WizardStyle=modern
; Sign at compile time: the uninstaller is embedded during compilation, so signing the finished
; installer afterwards would leave it unsigned. CI defines the command via "iscc /SMySignTool=...";
; deliberately unsigned builds pass /DSkipSignTool.
#ifndef SkipSignTool
SignTool=MySignTool
#endif
ArchitecturesInstallIn64BitMode=x64compatible
ArchitecturesAllowed=x64compatible
```

**读出来的做法**（对本项目有直接借鉴价值）：

| 做法 | 内容 |
| --- | --- |
| **默认仍是管理员安装**，但开 `PrivilegesRequiredOverridesAllowed=dialog` | 让用户能在安装时**选择**是否仅为当前用户安装。注意脚本里 `PrivilegesRequired=lowest` 是**注释掉的**——他们把这行留作可选开关，没有默认启用 |
| 打包目录参数化 | `#ifndef PayloadDir / #define PayloadDir "D:\inno"` —— CI 通过 `/DPayloadDir=... /DResultDir=...` 覆盖，使同一脚本可在 CI 与本地复用 |
| **签名在编译期完成** | 注释明确解释原因："the uninstaller is embedded during compilation, so signing the finished installer afterwards would leave it unsigned"，CI 用 `iscc /SMySignTool=...` 传入；未签名构建用 `/DSkipSignTool` 跳过 |
| 架构声明 | `ArchitecturesAllowed=x64compatible` + `ArchitecturesInstallIn64BitMode=x64compatible` |

`[Files]` 段的 Flutter 产物适配（**注意这里逐个声明，而不是用通配符**）：

```ini
[Files]
Source: "{#PayloadDir}\{#MyAppExeName}"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\*.dll"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\data\*"; DestDir: "{app}\data"; Flags: ignoreversion recursesubdirs createallsubdirs
; Unsigned builds pass /DSkipMsixHelper: Add-AppxPackage rejects unsigned packages, so ship without the MSIX helper (like the portable zip)
#ifndef SkipMsixHelper
Source: "{#PayloadDir}\{#MyAppExeName}.manifest"; DestDir: "{app}"; Flags: ignoreversion
Source: "{#PayloadDir}\{#MyAppMsixHelper}"; DestDir: "{app}"; Flags: ignoreversion
#endif
; NOTE: Don't use "Flags: ignoreversion" on any shared system files
```

**MSIX helper 的用途**（`[Run]` / `[UninstallRun]` 段，同一文件）：

```ini
[Run]
Filename: "{app}\{#MyAppExeName}"; Description: "{cm:LaunchProgram,...}"; Flags: nowait postinstall skipifsilent
#ifndef SkipMsixHelper
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command Add-AppxPackage .\localsend_msix_helper.msix -ExternalLocation $(Get-Location)"; WorkingDir: {app}; Flags: nowait runhidden
#endif

[UninstallRun]
#ifndef SkipMsixHelper
Filename: "powershell.exe"; Parameters: "-ExecutionPolicy Bypass -Command Get-AppxPackage LocalSend.App | Remove-AppxPackage"; Flags: nowait runhidden
#endif
```

**这是一个很有启发的模式**：LocalSend 用 **Inno 装文件**（传统安装器，简单可靠），**额外**用一个**极小的 MSIX 包**（`localsend_msix_helper.msix`）来给应用**获取 Windows 包标识（package identity）**，从而使用 Windows 的现代 API（如共享目标、开机自启动任务）。安装后通过 `Add-AppxPackage ... -ExternalLocation` 注册这个 helper。

**MSIX helper 的 manifest**（[support/build/msix/content/AppxManifest.xml](https://raw.githubusercontent.com/localsend/localsend/main/support/build/msix/content/AppxManifest.xml)）：

```xml
  <Identity Name="LocalSend.App" Version="1.18.2.0"
            Publisher="CN=Tien Do Nam, O=Tien Do Nam, L=Berlin, C=DE" ProcessorArchitecture="x64" />
  <Properties>
    <DisplayName>LocalSend MSIX Helper</DisplayName>
    <uap10:AllowExternalContent>true</uap10:AllowExternalContent>
  </Properties>
  ...
  <Capabilities>
    <rescap:Capability Name="runFullTrust" />
  </Capabilities>
  <Applications>
    <Application Id="localsendapp" Executable="localsend_app.exe" EntryPoint="Windows.FullTrustApplication">
      <uap:VisualElements AppListEntry="none" BackgroundColor="transparent" ...>
      ...
      <Extensions>
        <desktop:Extension Category="windows.startupTask" Executable="localsend_app.exe" EntryPoint="Windows.FullTrustApplication" uap10:Parameters="autostart">
          <desktop:StartupTask TaskId="localsend" Enabled="false" DisplayName="LocalSend"/>
        </desktop:Extension>
        <uap:Extension Category="windows.shareTarget">
          <uap:ShareTarget Description="Send to Localsend">
            <uap:SupportedFileTypes><uap:SupportsAnyFileType /></uap:SupportedFileTypes>
            <uap:DataFormat>Text</uap:DataFormat>
            <uap:DataFormat>Uri</uap:DataFormat>
            <uap:DataFormat>StorageItems</uap:DataFormat>
          </uap:ShareTarget>
        </uap:Extension>
      </Extensions>
```

**注意几个细节**：

- `AppListEntry="none"` —— helper **不出现在开始菜单**（因为真正的入口是 Inno 装的 exe）
- `uap10:AllowExternalContent="true"` —— 允许 MSIX 的内容来自**包外部**（即 `-ExternalLocation $(Get-Location)` 指向的 `{app}` 目录），这是"薄 helper"能成立的关键
- `rescap:Capability Name="runFullTrust"` —— 受限能力，需要声明
- `Category="windows.startupTask"` 与 `windows.shareTarget` —— **没有用 `windows.protocol`**（LocalSend 不需要自定义协议）
- `Publisher="CN=Tien Do Nam, ..."` —— 必须是真实签名证书的 Subject

**⚠️ 对本项目的适用性提醒**：这个 helper 方案在 LocalSend 里**默认是关闭的**（`#ifndef SkipMsixHelper`，而未签名构建传 `/DSkipMsixHelper`）——也就是说**未签名构建根本不分发 MSIX helper**。原因写在注释里："Add-AppxPackage rejects unsigned packages, so ship without the MSIX helper"。**这印证了 §6.3 的结论：MSIX 路线绕不开签名。**

### 7.2 `team-spotube/spotube` —— Squirrel 系（`.nupkg` + `setup.exe`）

**证据**：发布工作流的产物清单（[.github/workflows/spotube-release-binary.yml](https://raw.githubusercontent.com/team-spotube/spotube/master/.github/workflows/spotube-release-binary.yml)）

```yaml
          - os: windows-latest
            platform: windows
            arch: x86
            files: |
              dist/Spotube-windows-x86_64.nupkg
              dist/Spotube-windows-x86_64-setup.exe
```

构建步骤（同文件）：

```yaml
      - name: Install ${{matrix.platform}} dependencies
        run: |
          flutter pub get
          dart cli/cli.dart install-dependencies --platform=${{matrix.platform}} --arch=${{matrix.arch}}

      - name: Build ${{matrix.platform}} binaries
        run: dart cli/cli.dart build --arch=${{matrix.arch}} ${{matrix.platform}}
        env:
          CHANNEL: ${{inputs.channel}}
          DOTENV: ${{secrets.DOTENV_RELEASE}}
```

**读出来的做法**：

- Windows 产物是 **`.nupkg` + `-setup.exe`** 这一对——这是 **Squirrel.Windows / Clowd.Squirrel 系的典型产物形态**（`.nupkg` 是更新包，`setup.exe` 是安装器）。
- 它**自建 CLI**（`dart cli/cli.dart build --platform=windows`）来编排打包，而不是直接用某个 pub 包。
- 产物结构（`dist/Spotube-windows-x86_64-*`）说明是**每个平台一个独立产物目录**。
- 有 stable / nightly 双通道（`channel: stable|nightly`），nightly 发到固定的 `nightly` tag。

**注意**：我在抓取该仓库的 `.github/workflows` 目录时，只看到 4 个 workflow（`potential-duplicates.yml`、`pr-lint.yml`、`spotube-publish-binary.yml`、`spotube-release-binary.yml`），**未找到**打包脚本本身（在 `cli/cli.dart` 里，未抓取）。因此"它具体用哪个打包库"我**未确认**，只确认了产物是 nupkg + setup.exe。

### 7.3 其他尝试过但未取得证据的仓库

见 §9。

---

## 8. 针对本项目的推荐

> 前提：目标是 **免管理员安装 + 保留 `han1me://` 协议注册 + 保留清理旧版残留的能力 + 保持单个 exe 的分发体验**。

### 8.1 推荐（按优先级）

#### 🥇 方案 A：修好 Inno，走 `PrivilegesRequired=lowest` + `HKA`（**改动最小，收益最大**）

**理由**：这是唯一"保留全部现有功能、只改几行"的路线。而且它同时解决两个问题——**免管理员**与**协议注册位置**。

**具体改动**（`windows/installer.iss`）：

```ini
[Setup]
; 新增：免管理员安装（官方文档：lowest = 不请求提权，始终非管理员安装模式）
PrivilegesRequired=lowest
; 新增：允许命令行 /ALLUSERS 覆盖回机器级安装（按需）
PrivilegesRequiredOverridesAllowed=commandline

[Registry]
; 原：Root: HKCR  →  改为 Root: HKA + Software\Classes\ 前缀
; 官方原文："Using HKCR is not recommended, use HKA with the Subkey parameter set to Software\Classes instead."
Root: HKA; Subkey: "Software\Classes\han1me"; ValueType: string; ValueName: ""; ValueData: "URL:Han1meWinPlus"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\han1me_win_plus.exe,0"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\han1me_win_plus.exe"" ""%1"""; Flags: uninsdeletekey
```

**同时需要调整的路径常量**（否则免管理员下会往 `Program Files` 写，必然失败）：

| 现有 | 免管理员下的问题 | 建议 |
| --- | --- | --- |
| `DefaultDirName={autopf}\Han1meWinPlus` | `{autopf}` 在非管理员模式下会映射为 `{userpf}`（即 `%LOCALAPPDATA%\Programs`）——**这一点 Inno 已自动处理**，无需改 | 保持 |
| `{autoprograms}` / `{autodesktop}` | 同理会自动映射为 user 形式 | 保持 |

（依据：[ishelp: Constants](https://jrsoftware.org/ishelp/topic_consts.htm) 的 "Auto Constants" 表——`autopf` → 非管理员下为 `userpf`；`autoprograms` → `userprograms`；`autodesktop` → `userdesktop`。官方原文："They automatically map to their 'common' form unless the installation is running in non administrative install mode, in which case they map to their 'user' form. It is recommended you always use these 'auto' constants when possible to avoid mistakes."）

**⚠️ 但方案 A 有一个前提**：它**不能**解决 §5 的那个失败点。如果当前这台机器上 SetupLdr 建临时目录的问题不解决，即使改成 `lowest`，安装包在这台机器上**仍然跑不起来**。方案 A 解决的是"产品设计上免管理员"，不是"这台机器的环境故障"。

**⇒ 所以在做方案 A 之前/同时，应先验证 §5.3 的假设。** 如果证实是 `%TEMP%` 继承 ACL 问题，那是一个**该修的环境问题**（且对用户其他软件也有影响），修好它比换打包方案更根本。

#### 🥈 方案 B：加一条 portable zip 的"首次运行自注册协议"路径（**零安装器依赖**）

**理由**：项目**已经**在发 portable zip（CI 里 `Compress-Archive` 那一步）。如果让应用在**首次运行时**自行写 `HKCU\Software\Classes\han1me`，那么：

- **完全不需要安装器**，也就不受 SetupLdr 失败影响
- `HKCU` 写入**不需要管理员**
- 卸载 = 删目录 + 应用自己提供"移除协议注册"选项

**依据**：`HKCU\Software\Classes` 的合法性见 §6.4（微软官方文档明确"To change the settings for the interactive user, store the changes under HKEY_CURRENT_USER\Software\Classes rather than HKEY_CLASSES_ROOT"）；注册所需的键值结构见 §6.4 的官方示例。

**代价**：需要写 Dart/FFI 或调用 `reg.exe` 的代码；要处理"注册路径随安装位置变化"（portable 目录可能被移动）。

#### 🥉 方案 C：MSIX（**若愿意处理签名**）

**理由**：它是唯一"现代化 + 官方自动更新 + 干净卸载"的方案，且**没有自解包到 `%TEMP%` 的机制**（§6.2）。

**门槛**：
- **必须签名**。自签名 → 每台机器管理员导证书一次（[官方文档](https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing)）；CA 证书 → 付费但真正免管理员。
- `ms-appinstaller:` 网页一键安装**已被微软禁用**（2023-12 起），只能"下载 `.appinstaller` 后双击"。
- 用 `msix` pub 包成本很低（`pubspec.yaml` 加一段 + `dart run msix:create`），且它已支持 `protocol_activation`（正好是 `han1me://`）。

**对本项目的额外好处**：MSIX 的 `protocol_activation` 让 URL 协议注册变成**声明式**的（写在 manifest 里），由 Windows 管理生命周期——比手写注册表更不容易在升级时残留。

**不推荐的理由**：AGPL-3.0 + 未签名的现状下，引入 MSIX 会让"用户能否装上"取决于证书信任链，门槛比现在**更高**。

### 8.2 明确不推荐

| 方案 | 为什么不适合本项目 |
| --- | --- |
| **WiX** | 配置复杂度最高（XML + harvest），而它提供的核心价值（MSI 的企业级部署、组策略）本项目用不到。且 Burn 的自解包行为我**未取得官方确认**，风险不可控 |
| **Velopack** | 打包侧可用且免管理员，但**自动更新 SDK 无 Dart/Flutter 支持**（官方语言表里 Java/Swift/Go 都还是 "Planned"），等于放弃它最主要的卖点；还要接受它自己的目录布局 |
| **Scoop** | 它的"portable"模型**明确以'不改注册表'为卖点**，与 `han1me://` 协议注册需求直接冲突；且安装位置是 `C:\Users\<user>\scoop\apps\...`，路径动态化会让协议注册复杂化 |
| **flutter_distributor / Fastforge** | Windows 侧只支持 EXE/MSIX/ZIP，**没有更优的 Windows 目标**；它是编排器，换过去会丢掉现有的"注册协议 + 清理旧版残留"能力，属于净损失 |
| **纯 portable zip 单方案** | 做不到 URL 协议注册（除非应用自己写注册表，那就是方案 B）。可作为**补充**而非**替代** |
| **`UseSetupLdr=no`** | 官方定位是"debugging purposes"，会让产物变三个文件、破坏卸载器签名。**只在"确证是 SetupLdr 问题且无法修环境"时作为临时手段** |

### 8.3 建议的执行顺序

1. **先做 §5.3 的验证**（低成本，可能直接解决问题）。特别是"在**非提权** PowerShell 里重测建目录"与"改 `TMP` 指向新目录后试跑安装包"这两条。
2. **无论第 1 步结果如何，都做方案 A**（`PrivilegesRequired=lowest` + `Root: HKA` + `Software\Classes\`）。这是**产品层面的正确做法**，与机器故障无关。
3. **把 portable zip 升级为方案 B**（首次运行自注册协议），让"不装安装器"的用户也能用 `han1me://`。
4. 若将来愿意投入代码签名证书，再评估方案 C（MSIX）。

---

## 9. 未找到的内容

诚实列出本次调研**尝试但未取得**的内容，避免读者误以为已被覆盖。

### 9.1 GitHub API 限流导致未取得

调研中途 GitHub API 触发限流：

```json
{"message":"API rate limit exceeded for 43.198.240.47. (But here's the good news: Authenticated requests get a higher rate limit. ...)","documentation_url":"https://docs.github.com/rest/overview/resources-in-the-rest-api#rate-limiting"}
```

因此**未取得**：

| 目标 | 尝试的 URL | 结果 |
| --- | --- | --- |
| Inno PR #475 的 5 条评论（**官方拒绝"改临时目录"的理由**） | `https://api.github.com/repos/jrsoftware/issrc/issues/475/comments` | **HTTP 403 限流** |
| `flutter/website` 的 Windows 文档 Markdown 源 | `https://api.github.com/repos/flutter/website/contents/src/content/platform-integration/windows` | **HTTP 404**（路径猜测错误），后续请求遇限流 |
| star 数（用于筛选"知名"项目） | `https://api.github.com/search/repositories?q=flutter+windows+stars:>500` | **未成功执行**（限流） |

### 9.2 页面结构导致正文截断

| 目标 | URL | 情况 |
| --- | --- | --- |
| WiX Burn 的 engine 提取行为 | [docs.firegiant.com/wix/tools/burn/](https://docs.firegiant.com/wix/tools/burn/) | 抓取成功但**正文被左侧导航树占满**，实际 Burn 语义内容未取到 |
| WiX「指定源文件」 | [docs.firegiant.com/wix/tools/payloads/](https://docs.firegiant.com/wix/tools/payloads/) | 同上，正文截断 |
| Inno 帮助首页（frameset） | [jrsoftware.org/ishelp/](https://jrsoftware.org/ishelp/) | 返回 `[HTML content omitted: unable to convert safely.]`（frameset 无法转换）；**改抓具体 `topic_*.htm` 页面成功** |
| NSIS `WriteRegStr` 原文段落 | [nsis.sourceforge.io/Docs/Chapter4.html](https://nsis.sourceforge.io/Docs/Chapter4.html) | 抓取成功但**页面被截断**（完整文本存于本地缓存，未逐段核对）；`RequestExecutionLevel` 段落已完整取得 |

### 9.3 明确不存在 / 未找到的官方内容

| 项 | 结论 |
| --- | --- |
| `msix` 的 **GitHub Action** 配置文件 | 尝试 `raw.githubusercontent.com/YehudaKremer/msix-action/{master,main}/action.yml` 与 `.../README.md`，**全部 404**。该 action 的仓库结构未能确认。抓 `YehudaKremer/msix` 仓库的 `.github/` 目录只得到 `ISSUE_TEMPLATE` 与 `dependabot.yml`，**无 workflow**（该包用 Codemagic 而非 GitHub Actions，见其 README 的 Codemagic badge） |
| Inno 官方"如何改变自解包临时目录"的文档页 | **不存在**。检索 Inno 官方仓库 issue 标题含 `TEMP` 的条目，`total_count=1`，即 [PR #475](https://github.com/jrsoftware/issrc/pull/475)，且未合并 |
| `DisableDirPage` 的官方原文 | 未单独抓取该指令页（结论由 §3.2 的源码时序推出，非该页原文） |
| Squirrel.Windows 的废弃声明原文 | 未抓取 `github.com/Squirrel/Squirrel.Windows` |
| Clowd.Squirrel 的任何一手信息 | 未抓取 |
| LocalSend / Spotube 的 star 数 | 未取得（限流） |
| Spotube 具体使用的打包库 | 未抓取 `cli/cli.dart`；仅从产物（`.nupkg` + `-setup.exe`）推断为 Squirrel 系 |

### 9.4 本次调研**未做**的实验

以下都需要实际执行安装包或改动系统状态，超出"调研"范围，**未做**：

- 未在本机实际编译一个 `UseSetupLdr=no` 的安装包来验证它是否真的绕开失败
- 未在本机实际编译一个 `PrivilegesRequired=lowest` + `Root: HKA` 的安装包来验证免管理员 + 协议注册
- 未实际用 `msix` 包打一个 MSIX 并测试安装
- 未对比 `%TEMP%` 与其祖先目录的 `icacls` 输出（§5.3 建议的验证 2）
- 未改 `TMP`/`TEMP` 环境变量做对照实验（§5.3 建议的验证 3）

**§5 的诊断假设仍未被实验检验**，这一点在采用前必须补齐。

---

## 10. 参考来源

### Inno Setup 官方文档（jrsoftware.org）

| 主题 | URL |
| --- | --- |
| `[Setup]`: UseSetupLdr（**核心：自解包到 TEMP**） | https://jrsoftware.org/ishelp/topic_setup_usesetupldr.htm |
| `[Setup]`: PrivilegesRequired（**免管理员开关**） | https://jrsoftware.org/ishelp/topic_setup_privilegesrequired.htm |
| 非管理员安装模式（HKA/uninstall/HKCU 语义） | https://jrsoftware.org/ishelp/topic_admininstallmode.htm |
| `[Setup]`: Uninstallable | https://jrsoftware.org/ishelp/topic_setup_uninstallable.htm |
| `[Setup]`: CreateUninstallRegKey | https://jrsoftware.org/ishelp/topic_setup_createuninstallregkey.htm |
| `[Setup]`: SolidCompression | https://jrsoftware.org/ishelp/topic_setup_solidcompression.htm |
| `[Setup]`: Compression | https://jrsoftware.org/ishelp/topic_setup_compression.htm |
| `[Setup]`: SetupLogging | https://jrsoftware.org/ishelp/topic_setup_setuplogging.htm |
| `[Setup]`: UsedUserAreasWarning | https://jrsoftware.org/ishelp/topic_setup_useduserareaswarning.htm |
| Constants（`{tmp}`、`{autopf}`、auto 常量表） | https://jrsoftware.org/ishelp/topic_consts.htm |
| `[Registry]` section（**HKCR vs HKA 官方建议**） | https://jrsoftware.org/ishelp/topic_registrysection.htm |
| Setup 命令行参数（`/LOG`、`/HELP`） | https://jrsoftware.org/ishelp/topic_setupcmdline.htm |

### Inno Setup 官方源码（github.com/jrsoftware/issrc，`main` 分支）

| 文件 | 内容 | URL |
| --- | --- | --- |
| `Projects/SetupLdr.dpr` | **自解包主流程**：`CreateTempDir('.tmp', IsAdminLoggedOn)`、解压 setup、`ExecAndWait` | https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/SetupLdr.dpr |
| `Projects/Src/SetupLdrAndSetup.InstFunc.pas` | **`CreateTempDir` / `CreateSafeDirectory` / `GenerateUniqueName`**；管理员 vs 非管理员的 SDDL 分支 | https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/Src/SetupLdrAndSetup.InstFunc.pas |
| `Projects/Src/Shared.CommonFunc.pas` | **`GetTempDir`**（`GetTempPath2W` 优先）、`IsAdminLoggedOn`、`RestoreDeletedTempDirWithLogonSessionId` | https://raw.githubusercontent.com/jrsoftware/issrc/main/Projects/Src/Shared.CommonFunc.pas |
| PR #475（社区诉求"改临时目录"，**已关闭未合并**） | — | https://github.com/jrsoftware/issrc/pull/475 |

### 微软官方文档

| 主题 | URL |
| --- | --- |
| What is MSIX?（**stage/register、容器化、差分更新**） | https://learn.microsoft.com/en-us/windows/msix/overview |
| Package registration and lifetime | https://learn.microsoft.com/en-us/windows/msix/package/package-lifetime |
| Create a certificate for package signing（**Trusted People 需管理员**） | https://learn.microsoft.com/en-us/windows/msix/package/create-certificate-package-signing |
| App Installer（overview） | https://learn.microsoft.com/en-us/windows/msix/app-installer/app-installer-root |
| Installing Windows apps from a web page（**`ms-appinstaller:` 已被禁用**） | https://learn.microsoft.com/en-us/windows/msix/app-installer/installing-windows10-apps-web |
| `uap:Extension` schema（**`windows.protocol`**） | https://learn.microsoft.com/en-us/uwp/schemas/appxpackage/uapmanifestschema/element-uap-extension |
| Registering an Application to a URI Scheme（**协议注册键值结构**） | https://learn.microsoft.com/en-us/previous-versions/windows/internet-explorer/ie-developer/platform-apis/aa767914(v=vs.85) |
| HKEY_CLASSES_ROOT Key（**HKCR = HKLM + HKCU 合并视图**） | https://learn.microsoft.com/en-us/windows/win32/sysinfo/hkey-classes-root-key |
| GetTempPath2W（**TMP → TEMP → USERPROFILE → Windows 顺序**） | https://learn.microsoft.com/en-us/windows/win32/api/fileapi/nf-fileapi-gettemppath2w |
| %TEMP% folder with logon session ID is deleted（KB4506040） | https://learn.microsoft.com/en-us/troubleshoot/windows-server/shell-experience/temp-folder-with-logon-session-id-deleted |
| Use WinGet to install and manage applications（**支持 INNO/PORTABLE/ZIP**） | https://learn.microsoft.com/en-us/windows/package-manager/winget/ |

### NSIS 官方文档

| 主题 | URL |
| --- | --- |
| Chapter 4: Scripting Reference（**`RequestExecutionLevel`、`$PLUGINSDIR`**） | https://nsis.sourceforge.io/Docs/Chapter4.html |

### pub.dev / 包官方仓库

| 主题 | URL |
| --- | --- |
| `msix` 包（配置项、`protocol_activation`、App Installer、签名） | https://pub.dev/packages/msix |
| `msix` README（GitHub 源） | https://raw.githubusercontent.com/YehudaKremer/msix/main/README.md |
| Fastforge（formerly Flutter Distributor）README | https://raw.githubusercontent.com/leanflutter/flutter_distributor/main/README.md |

### Velopack 官方文档

| 主题 | URL |
| --- | --- |
| Introduction（**语言支持表**） | https://docs.velopack.io/ |
| Packaging Overview（`vpk pack` 参数、产物） | https://docs.velopack.io/packaging/overview |
| Installers（**per-user 免提权、MSI/`--instLocation`**） | https://docs.velopack.io/packaging/installer |
| Windows Overview（**目录布局、更新时整目录替换**） | https://docs.velopack.io/packaging/operating-systems/windows |

### WiX / FireGiant 官方文档

| 主题 | URL |
| --- | --- |
| About the WiX Toolset（**v3 deprecated**） | https://docs.firegiant.com/wix/ |
| Burn bundles（**抓取成功但正文截断**） | https://docs.firegiant.com/wix/tools/burn/ |
| Specifying source files（**抓取成功但正文截断**） | https://docs.firegiant.com/wix/tools/payloads/ |

### Scoop 官方

| 主题 | URL |
| --- | --- |
| Scoop README（**非管理员安装、portable 定义、JSON manifest**） | https://raw.githubusercontent.com/ScoopInstaller/Scoop/master/README.md |
| Scoop Wiki 首页 | https://github.com/ScoopInstaller/Scoop/wiki/ |

### 真实项目配置（社区实例）

| 项目 | 文件 | URL |
| --- | --- | --- |
| `localsend/localsend` | `.github/workflows/ci.yml`（packaging job） | https://raw.githubusercontent.com/localsend/localsend/main/.github/workflows/ci.yml |
| `localsend/localsend` | `support/scripts/compile_windows_exe-inno.iss` | https://raw.githubusercontent.com/localsend/localsend/main/support/scripts/compile_windows_exe-inno.iss |
| `localsend/localsend` | `support/build/msix/content/AppxManifest.xml` | https://raw.githubusercontent.com/localsend/localsend/main/support/build/msix/content/AppxManifest.xml |
| `team-spotube/spotube` | `.github/workflows/spotube-release-binary.yml` | https://raw.githubusercontent.com/team-spotube/spotube/master/.github/workflows/spotube-release-binary.yml |

### 本仓库内文件（事实基线）

| 文件 | URL |
| --- | --- |
| Inno 脚本 | `windows/installer.iss` |
| 打包 CI | `.github/workflows/build-windows.yml` |
