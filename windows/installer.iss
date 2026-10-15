#ifndef MyAppVersion
; 兜底值，只在手动跑 ISCC 且没传 /DMyAppVersion= 时生效。
; CI 每次都会显式传入（见 .github/workflows/build-windows.yml），所以正常发布的包不受这里影响；
; 手动编译请用 ISCC.exe /DMyAppVersion=<版本> windows\installer.iss 覆盖。
#define MyAppVersion "0.0.0"
#endif

[Setup]
; 独立于上游的 AppId，避免与 Han1mePlus 的安装互相覆盖
AppId={{B7C4E9A2-3D51-4F8C-9E2A-6C7D1F5B8A34}
AppName=Han1meWinPlus
AppVersion={#MyAppVersion}
AppPublisher=Han1meWinPlus
; 安装模式：默认 admin（提权）。
;
; 这里**不能**改成 lowest。免管理员的用户级安装在一类机器上必然失败，原因不在
; 脚本里，而在 Inno 与 UAC 拆分令牌的交互上 —— 完整机制与实测数据见文件末尾
; 「为什么默认是 admin 而不是免管理员」一节。结论：
;   · 默认 admin → 双击后由 Inno 请求提权，正常安装
;   · /CURRENTUSER（不提权）→ 在那些机器上报 "Error 5: 拒绝访问"，装不上
PrivilegesRequired=admin
; 允许用命令行覆盖安装模式，但不弹选择对话框（保持双击即装的体验）：
;   Han1meWinPlus-Setup.exe /ALLUSERS     → 机器级安装（默认行为）
;   Han1meWinPlus-Setup.exe /CURRENTUSER  → 用户级安装（非管理员账户可用）
; 之所以还留着这个开关：上面的失败只发生在「账户属于管理员组、但进程用 UAC 拆分
; 令牌」的情况下（见文末）。纯粹的非管理员账户走的是 Inno 的另一条代码分支，
; 用户级安装对他们是可用的，留这个开关能让他们不必提权。
PrivilegesRequiredOverridesAllowed=commandline
DefaultDirName={autopf}\Han1meWinPlus
DefaultGroupName=Han1meWinPlus
DisableProgramGroupPage=yes
OutputDir=..\build
OutputBaseFilename=Han1meWinPlus-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\han1me_win_plus.exe
; 安装程序自身的图标（与应用图标同一份，路径相对本文件所在目录）
SetupIconFile=runner\resources\app_icon.ico
CloseApplications=yes
RestartApplications=no
; 让安装/卸载器知道「应用正在运行」。
;
; 这两个名字是 runner 里真实持有的互斥体（windows/runner/main.cpp 的
; kInstanceMutexName 与 kPlayWindowMutexName）：主窗口一个、独立播放窗口一个。
; 写上之后 Inno 会在安装/卸载前主动检测它们，并提示用户先关闭应用。
;
; 为什么需要这个：CloseApplications=yes 依赖 Windows 的 Restart Manager 去判断
; 哪些进程占用了待删文件，而 RM 对「没有主窗口的后台进程」和「提权状态不匹配的
; 进程」识别不到 —— 本应用恰好两条都符合：从列表点视频会拉起独立播放窗口进程
; （主窗口关掉后它们仍在后台跑），而安装器是提权运行的、应用是普通权限启动的。
; 实测后果：用户在应用还开着时卸载，19 个被进程加载过的 exe/dll 删不掉、被留在
; 安装目录里（data/ 下的资源文件因为没被锁定，反而删干净了）。
AppMutex=Han1meWinPlus.instance.mutex,Han1meWinPlus.play-window.mutex

; Setup Loader：保持单文件打包（Inno 默认行为）。
;
; ===== 这里曾经设成 no，那是一个基于错误诊断的决定，已撤销 =====
;
; 当初观察到「双击安装报 Error 5: 拒绝访问 / Setup was unable to create the
; directory ...\Temp\is-XXXX.tmp」，于是改成 UseSetupLdr=no（产物拆成
; Setup.exe + Setup-0.bin + Setup-1.bin）来绕开它。后来重新排查发现：
;
; **真正的触发条件是「安装包所在的目录」，与脚本、与包本身都无关。**
; 同一个二进制文件，只是换个位置放，结果完全不同（各测 5 次）：
;
;   F:\Han1meWinPlus\build\    （本仓库工作区）  → 0 成功 / 5 失败
;   F:\h1-loc-test\            （同盘普通目录）  → 5 成功 / 0 失败
;   %TEMP% 下                                  → 全部成功
;   %USERPROFILE%\Downloads 下                  → 全部成功
;
; 工作区目录被开发环境的沙箱加了额外的保护条目（icacls 里能看到
; "Everyone:(CI)(DENY)(DC)" 以及一个解析不出账户名的信任标签 SID
; S-1-4-967507726-224904887），从该目录启动的 SetupLdr 在创建 %TEMP% 子目录时
; 被拒。具体触发点没有完全定位，但上面的对照实验足以确定：**只发生在这个目录下**。
;
; 也就是说，真实用户从下载目录双击安装本来就是正常的 —— 当初的「修复」只是绕开了
; 本机开发环境的怪癖，代价却很实在：Inno 明确规定 SignTool / SignedUninstaller
; **不能**与 UseSetupLdr=no 同时使用（编译器直接拒绝，原文：
; "The SignTool and SignedUninstaller directives may not be set when UseSetupLdr is
; set to \"no\""），于是卸载器永远拿不到数字签名。
;
; 改回单文件后：产物只有 1 个 exe（用户不必再凑齐三个文件），并且可以走
; SignTool + SignedUninstaller 的编译期签名 —— 安装器和卸载器都能签上。
;
; ⚠️ 本地测试提醒：在 F:\Han1meWinPlus\ 下运行本产物**仍会**报 Error 5（沙箱 ACL
;    所致，不是包的问题）。要验证安装，请先把 exe 复制到别的目录（例如 %TEMP%）
;    再双击或静默安装。
UseSetupLdr=yes

[Files]
; Excludes 只在这里出现一次，作用是挡掉 MSVC 链接器的中间产物：
; `han1me_win_plus.exp`（导出表）与 `han1me_win_plus.lib`（导入库）都落在 Release\
; 目录里，是链接 exe 时顺手写下的，运行时一个都用不到。早先没排除，实测它们确实
; 被装进了 {app}（.lib 那份还停留在更早一次构建的日期上）。两者合计 3 KB，体积
; 上无所谓，纯粹是不该出现在成品目录里。
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Excludes: "*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; 升级安装时 Inno 只覆盖、**从不删除**「旧版本装过、新版本已不再分发」的文件，
; 于是它们会永远赖在 {app} 里占地方。这里显式点名清掉。
;
; 本段在 [Files] **之前**执行，所以被删的文件若新版仍需要，会被紧接着重新复制回来，
; 不会因为清理而缺失。（这条顺序是实测过的，不是照文档抄的：造一个只写进本段、
; 不写进 [Files] 的 stale-only.txt 会被删掉，而两边都写的 probe.txt 装完仍在，
; 说明删除确实发生在复制之前。）
; desktop_multi_window 的多引擎方案已放弃（播放窗口改为独立进程），这个插件 DLL
; 早期版本被装进过 {app}，留着既是死代码，也正是当初让主窗口假死的那套实现。
Type: files; Name: "{app}\desktop_multi_window_plugin.dll"
; 字体早先换成 HarmonyOS_Sans_SC.ttf（单文件 19.7 MB，对比 MiSans 静态四档 31 MB）。
; 四档 MiSans 从此不再分发，实测在安装目录残留约 30 MB。
Type: files; Name: "{app}\data\flutter_assets\assets\fonts\MiSans-*.ttf"
; cupertino_icons 依赖已从 pubspec.yaml 移除，这个包整个不再进构建产物。
Type: filesandordirs; Name: "{app}\data\flutter_assets\packages\cupertino_icons"
; 上一轮手工留下的可执行文件回退点（名字带版本号，用通配符一并清掉将来的）。
; 只匹配 `han1me_win_plus.exe.bak-*`，不会碰到正在用的 han1me_win_plus.exe。
Type: files; Name: "{app}\han1me_win_plus.exe.bak-*"
; 标题栏的锁标改用 SVG（assets/logo_lockup_compact.svg），这张位图不再分发。
Type: files; Name: "{app}\data\flutter_assets\assets\logo_lockup_compact.png"
; 链接器中间产物：早先几版（[Files] 尚未加 Excludes 时）被装进过 {app}，
; 升级安装不会自己消失，所以这里显式点名清掉。新装则根本不再分发（见 [Files]）。
Type: files; Name: "{app}\han1me_win_plus.exp"
Type: files; Name: "{app}\han1me_win_plus.lib"

[Icons]
Name: "{autoprograms}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"
Name: "{autodesktop}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\han1me_win_plus.exe"; Description: "Launch Han1meWinPlus"; Flags: nowait postinstall skipifsilent

[Registry]
; 自定义 URL scheme：浏览器里点 han1me://video/xxx 就能唤起本应用。
; URL Protocol 这个空字符串值是 Windows 判定「这是一个可唤起协议」的依据，不能省。
;
; 用 HKA 而不是 HKCR。HKA 是 Inno 的「按安装模式自动选择」根键：机器级安装时等价
; 于 HKLM，用户级安装时等价于 HKCU —— 一个脚本同时适配两种模式，不必写两份。
; 官方文档在 [Registry] 一节里明确建议：「Using HKCR is not recommended, use HKA
; with the Subkey parameter set to Software\Classes instead」（HKCR 是 HKLM 与 HKCU
; 的合并视图，直接写它需要管理员，且会绕过用户级覆盖的优先级）。
; 键路径因此要自己带上 Software\Classes 前缀。
Root: HKA; Subkey: "Software\Classes\han1me"; ValueType: string; ValueName: ""; ValueData: "URL:Han1meWinPlus"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\han1me_win_plus.exe,0"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\han1me\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\han1me_win_plus.exe"" ""%1"""; Flags: uninsdeletekey

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"

; ===========================================================================
; 安装权限：为什么默认 admin（以及一个被推翻的旧结论）
; ===========================================================================
;
; ===== 这段曾经写着「免管理员（lowest）在本机必然失败」，那是错的 =====
;
; 当初把 PrivilegesRequired 改成 lowest 后测出安装失败（同样是 Error 5），
; 于是留下结论「免管理员这条路在当前令牌模型下走不通」。后来查明：那些测试
; 也是在本仓库工作区目录下跑的，而该目录的沙箱 ACL 才是 Error 5 的真正来源
; —— 完整对照实验见本文件 [Setup] 段 UseSetupLdr 附近的说明。
;
; 在普通目录（C:\h1-lowest-test\）重新编译并安装，实测（唯一变量是模式）：
;
;   PrivilegesRequired=lowest（免管理员）      → ExitCode=0，71 个文件全部装好
;   PrivilegesRequired=admin + UseSetupLdr=yes → ExitCode=0，71 个文件全部装好
;
; 两种模式都可用。lowest 从来不是「装不上」，当时的失败是环境造成的。
;
; 当前仍默认 admin，这是**产品选择而非技术限制**：装到 Program Files 更符合
; Windows 惯例，且 /CURRENTUSER 已经给纯标准用户账户留了免管理员的口子（见
; PrivilegesRequiredOverridesAllowed）。若想改成默认免管理员，把这里换成
; lowest 即可，同时需要更新 README 里关于安装权限的说明。
;
; 另外：URL 协议注册用的是 HKA（见 [Registry]），它会随安装模式自动落到
; HKLM 或 HKCU，所以两种模式下协议都能正确注册。

// ===========================================================================
// 卸载时的数据清理
// ===========================================================================
//
// 应用的数据不装在 {app} 里，卸载程序默认不会碰它们。它们分布在四处：
//
//   %APPDATA%\han1me_win_plus\              设置、观看记录、追番、缓存元数据、着色器
//   %APPDATA%\han1me_win_plus\Download\     用户下载的视频（可能很大，且是用户资产）
//   %APPDATA%\Han1meWinPlus\Han1meWinPlus\  更早版本留下的历史目录（见 preferences_store）
//   %LOCALAPPDATA%\Han1meWinPlus\webview2\  WebView2 缓存：登录 cookie、CF 通行证、网页缓存
//
// 前三处是「应用自己的数据」，第四处是「登录态」—— 两者对用户的意义不同：
// 前者删了等于回到出厂设置，后者删了等于退出登录并要重新过 Cloudflare。
// 下载的视频又是第三类：它是用户的文件，绝不该跟着卸载默认被删。
//
// 所以卸载时弹一个对话框，三类分开、默认只勾「设置与记录」，其余由用户决定。

[Code]
var
  // 用户在清理对话框里的选择，由 AskCleanupOptions 填写。
  CleanSettings: Boolean;
  CleanWebview: Boolean;
  CleanDownloads: Boolean;

// 应用数据目录：%APPDATA%\han1me_win_plus（名字钉死在 platform_paths.dart，
// 不随 exe 的版本资源变化）。
function AppDataDir(): string;
begin
  Result := ExpandConstant('{userappdata}\han1me_win_plus');
end;

// 历史遗留目录：加了 VERSIONINFO 之后 path_provider 曾把数据放进
// %APPDATA%\Han1meWinPlus\Han1meWinPlus（见 preferences_store.dart 的说明）。
// 它只是「一次性迁移来源」，主目录里已有同名文件，删掉没有损失。
function LegacyAppDataDir(): string;
begin
  Result := ExpandConstant('{userappdata}\Han1meWinPlus\Han1meWinPlus');
end;

// WebView2 缓存目录：%LOCALAPPDATA%\Han1meWinPlus\webview2。
// 这个路径同时被 runner（SetEnvironmentVariableW WEBVIEW2_USER_DATA_FOLDER）和
// Dart 侧（webview_environment.dart 的 getApplicationSupportDirectory + 'webview2'）
// 使用，两处指向同一位置。
function WebViewDir(): string;
begin
  Result := ExpandConstant('{localappdata}\Han1meWinPlus\webview2');
end;

// 下载目录：正常在 %APPDATA%\han1me_win_plus\Download，但用户可以在设置里
// 改成任意路径。这里只清默认位置；自定义路径不去猜（猜错就是删用户文件）。
function DefaultDownloadDir(): string;
begin
  Result := ExpandConstant('{userappdata}\han1me_win_plus\Download');
end;

// 统计一个目录有多大、多少文件，用于在对话框上告诉用户「将删除多少」。
//
// [SkipSubdir] 用于把某个子目录排除在统计之外（传空串表示不排除）。存在这个参数
// 是因为 Download 是数据目录的子目录，而两者在卸载时是**分别**询问的 —— 不排除的话
// 「设置、观看记录与追番」那一项的体积会把用户下载的视频全算进去，显示成几个 GB，
// 用户会以为设置本身很大。
procedure MeasureDir(const Dir, SkipSubdir: string; var Files: Integer; var Bytes: Int64);
var
  FindRec: TFindRec;
  Sub: string;
  SkipFull: string;
begin
  if not DirExists(Dir) then Exit;
  SkipFull := '';
  if SkipSubdir <> '' then SkipFull := AddBackslash(Dir) + SkipSubdir;
  if FindFirst(AddBackslash(Dir) + '*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          Sub := AddBackslash(Dir) + FindRec.Name;
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
          begin
            // 跳过被排除的子目录；也跳过目录联接（reparse point），
            // 否则一个指向自身/祖先的联接会让这里无限递归 —— 而在卸载事件
            // 函数里抛异常是致命的（整个卸载失败）。
            if (SkipFull <> '') and (CompareText(Sub, SkipFull) = 0) then
              Continue;
            if (FindRec.Attributes and FILE_ATTRIBUTE_REPARSE_POINT) = 0 then
              MeasureDir(Sub, '', Files, Bytes);
          end
          else
          begin
            Inc(Files);
            // 必须显式转 Int64 再乘。4294967296 这个字面量在 Pascal Script 里
            // 按 32 位处理、被截断成 0，于是 SizeHigh 整段丢失：一个 5 GiB 的
            // 文件会被报成 1 GiB（实测原式 High=1,Low=0 得 0，而非 4294967296）。
            Bytes := Bytes + Int64(FindRec.SizeHigh) * 4294967296 + Int64(FindRec.SizeLow);
          end;
        end;
      until not FindNext(FindRec);
    finally
      FindClose(FindRec);
    end;
  end;
end;

// 把字节数写成人看的单位。
//
// 这里刻意全部用整数运算、只让 %d 参与格式化。两点原因（均经实测）：
//
//  1. Format('%.1f MB', [Bytes / 1048576]) 会抛
//       Runtime error: Format '%.1f MB' invalid or incompatible with argument
//     （%f 要求浮点参数，传整数直接报错），而卸载事件函数里抛异常是致命的 ——
//     首次实现踩过：整个卸载失败、退出码 1，日志里只有 "raised an exception (fatal)"。
//  2. Pascal Script 的 Format **不实现零填充标志**：Format('%d.%02d GB', [1, 0])
//     实测输出 "1. 0 GB"（一个空格），不是 "1.00 GB"。所以小数位要自己补零，
//     见下面 GB 分支的 if。
function HumanSize(Bytes: Int64): string;
var
  Whole, Frac: Int64;
begin
  if Bytes >= 1073741824 then
  begin
    Whole := Bytes div 1073741824;
    Frac := (Bytes mod 1073741824) * 100 div 1073741824;
    // 手动补零：%02d 不被支持（会变成空格）
    if Frac < 10 then
      Result := Format('%d.0%d GB', [Whole, Frac])
    else
      Result := Format('%d.%d GB', [Whole, Frac]);
  end
  else if Bytes >= 1048576 then
  begin
    Whole := Bytes div 1048576;
    Frac := (Bytes mod 1048576) * 10 div 1048576;
    Result := Format('%d.%d MB', [Whole, Frac]);
  end
  else if Bytes >= 1024 then
  begin
    Whole := Bytes div 1024;
    Frac := (Bytes mod 1024) * 10 div 1024;
    Result := Format('%d.%d KB', [Whole, Frac]);
  end
  else
    Result := Format('%d B', [Bytes]);
end;

// 删除一个目录树；失败返回 False，由调用方汇总成一句提示，不在这里弹窗。
function RemoveTreeQuiet(const Dir: string): Boolean;
begin
  Result := True;
  if not DirExists(Dir) then Exit;
  if not DelTree(Dir, True, True, True) then Result := False;
end;

// 删除应用数据目录，但**保住**里面的 Download 子目录。
//
// 为什么需要这个专门的函数：Download 物理上是 AppDataDir() 的子目录，而 DelTree
// 会连子目录一起删。而这两处在卸载时是**分别**询问的 —— 用户完全可能回答「清掉
// 设置」+「保留视频」。直接 DelTree(AppDataDir()) 会把他明确选择保留的视频一起删光。
//
// 实测确认过这个后果（探针脚本，Inno 6.x）：
//   删前: 父存在=1 Download存在=1
//   DelTree(父) 后: 父存在=0 Download存在=0   <- 用户选的是「保留下载」
//
// 做法：先把 Download 改名到数据目录之外（同一卷内 rename 是元数据操作，几十 GB
// 也瞬间完成、不搬运数据），删完父目录再建回同名目录并改回来。名字里带 `.` 前缀
// 是为了不容易和别的东西撞名。
//
// [KeepDownload]=False 时退化为普通整树删除（用户选了连视频一起删）。
function RemoveAppDataKeepingDownload(KeepDownload: Boolean): Boolean;
var
  DataDir, DownloadDir, StashDir: string;
  Stashed: Boolean;
begin
  Result := True;
  DataDir := AppDataDir();
  if not DirExists(DataDir) then Exit;

  DownloadDir := DefaultDownloadDir();
  StashDir := DataDir + '.download-keep';
  Stashed := False;

  if KeepDownload and DirExists(DownloadDir) then
  begin
    // 上次异常中断可能留下 stash，先清掉避免撞名
    if DirExists(StashDir) then RemoveTreeQuiet(StashDir);
    Stashed := RenameFile(DownloadDir, StashDir);
    if Stashed then
      Log('kept downloads aside: ' + StashDir)
    else
      // 改名失败（被占用 / 跨卷）时**不要**继续删父目录 —— 那会连视频一起删掉。
      // 宁可这次不清理设置，也不能丢用户的文件。
      Log('could not set downloads aside, skipping app data removal');
  end;

  if (not KeepDownload) or (not DirExists(DownloadDir)) or Stashed then
  begin
    if not RemoveTreeQuiet(DataDir) then Result := False;
  end
  else
    Result := False;   // 改名没成功 → 放弃本次删除，交给调用方提示

  // 把保留下来的下载放回原位。父目录已被删掉，这里顺带把数据目录重建出来，
  // 让应用下次启动时看到的目录结构是完整的。
  if Stashed and DirExists(StashDir) then
  begin
    if not DirExists(DataDir) then CreateDir(DataDir);
    if not RenameFile(StashDir, DownloadDir) then
      Log('WARNING: downloads left at ' + StashDir);
  end;
end;

// 卸载前问用户要不要清理数据。
//
// 这里**故意**用 MsgBox 而不是自建窗体 + 复选框。原因是实测踩到的坑：
// 用 CreateCustomForm 建窗体、放三个 TNewCheckBox，初值设对了（日志：创建后
// c1=1 c2=0 c3=0），但 ShowModal 返回之后再读，三个框全变成 1 —— 也就是说
// 无论用户是否勾选、甚至根本没人点（窗体显示约 4 秒后自动以 mrOk 返回），
// 读回来永远是「全选」。那会导致两个后果：用户没机会真正做选择；而且一旦
// 误触就按「连下载的视频一起删」执行。第一次实现就是这么写的，实测确实把
// WebView2 缓存和用户的下载目录都删掉了。
//
// MsgBox 是 Inno 脚本里最稳的交互手段，返回值可靠。代价是只能表达
// 「二选一」而不能三个独立勾选，所以按「风险」分两级提问：
//   第一问：清掉应用数据（设置/记录/登录状态，含 WebView2 缓存）—— 默认推荐是
//   第二问：连下载的视频一起删 —— 默认推荐否
// 这样最常见的「干净卸载」一次确认就够，而涉及用户文件的那一步必须显式再确认。
procedure AskCleanupOptions;
var
  SettingsFiles, WebviewFiles, DownloadFiles: Integer;
  SettingsBytes, WebviewBytes, DownloadBytes: Int64;
  Message: string;
begin
  SettingsFiles := 0; SettingsBytes := 0;
  WebviewFiles := 0; WebviewBytes := 0;
  DownloadFiles := 0; DownloadBytes := 0;
  // 统计「设置」时必须排掉 Download：它是数据目录的子目录，不排的话用户下载的
  // 几十 GB 视频会被算进「设置、观看记录与追番」这一项，显示成几个 GB ——
  // 实测过：3 个文件的数据目录被报成 3.0 GB，其中 3 GB 全来自 Download 里的视频。
  MeasureDir(AppDataDir(), 'Download', SettingsFiles, SettingsBytes);
  MeasureDir(LegacyAppDataDir(), '', SettingsFiles, SettingsBytes);
  MeasureDir(WebViewDir(), '', WebviewFiles, WebviewBytes);

  Message :=
    '是否一并清理本应用留下的数据？' + #13#10 + #13#10 +
    '· 设置、观看记录与追番：' + HumanSize(SettingsBytes) +
    Format('（%d 个文件）', [SettingsFiles]) + #13#10 +
    '· 网页缓存与登录状态：' + HumanSize(WebviewBytes) +
    '（清理后会退出登录）' + #13#10 + #13#10 +
    '选「否」则全部保留，重装后仍然可用。';

  // MB_YESNO + 默认按钮为「是」：干净卸载是最常见诉求。
  if MsgBox(Message, mbConfirmation, MB_YESNO) = IDYES then
  begin
    CleanSettings := True;
    CleanWebview := True;   // 登录状态属于「应用数据」，跟设置一起清
  end
  else
  begin
    CleanSettings := False;
    CleanWebview := False;
  end;

  // 下载的视频单独再问一次：它是用户的文件，不是应用数据，绝不能在用户
  // 只是「想清掉设置」的时候被顺手删掉。默认按钮设为「否」。
  if DirExists(DefaultDownloadDir()) then
  begin
    DownloadFiles := 0; DownloadBytes := 0;
    MeasureDir(DefaultDownloadDir(), '', DownloadFiles, DownloadBytes);
    if MsgBox('还要删除下载的视频吗？' + #13#10 + #13#10 +
              DefaultDownloadDir() + #13#10 +
              Format('%d 个文件，共 %s', [DownloadFiles, HumanSize(DownloadBytes)]) + #13#10 + #13#10 +
              '这是你自己的文件，删掉后无法从本应用恢复。' + #13#10 +
              '（如果你在设置里改过下载目录，那里的文件不会被碰。）',
              mbConfirmation, MB_YESNO or MB_DEFBUTTON2) = IDYES then
      CleanDownloads := True
    else
      CleanDownloads := False;
  end
  else
    CleanDownloads := False;
end;

// 结束掉还在运行的 Han1meWinPlus 进程。
//
// 为什么必须显式做：Inno 的 CloseApplications 靠 Restart Manager 找「占用待删
// 文件的进程」，而 RM 认不出本应用的两类进程 —— 独立播放窗口进程没有主窗口，
// 且安装器提权而应用不提权。实测后果（用户真实遇到过）：卸载后安装目录里留下
// 19 个文件，正好是所有被进程加载过的 exe/dll（flutter_windows.dll、libmpv-2.dll、
// 11 个插件 dll……），而 data/ 下的资源因为没被锁定反倒删干净了。残留的 exe
// 还能被误点开，是个比「占几十 MB」更麻烦的状态。
//
// 时机很关键：必须赶在 Inno 的 AppMutex 检查之前跑完。那个检查在卸载流程启动
// 时就会做，检测到应用在运行会弹「请先关闭」的询问；在静默卸载（/SUPPRESSMSGBOXES）
// 下这个询问被按「放弃」处理，整个卸载直接中止 —— 实测就是这样：ExitCode=1、
// 71 个文件一个没删。所以这里放在 InitializeUninstall（最早的钩子）里，
// 先把进程清掉，后面 AppMutex 自然检测不到冲突。
//
// taskkill 按进程名结束，不碰任何数据。失败不报错：没在跑时它返回非零。
function InitializeUninstall(): Boolean;
var
  ResultCode: Integer;
begin
  Result := True;
  if Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM han1me_win_plus.exe /T',
          '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then
    Log(Format('taskkill exit code: %d', [ResultCode]))
  else
    Log('taskkill could not be started');
  // 给系统一点时间释放文件句柄，否则紧接着的删除仍然会失败。
  Sleep(1500);
end;

// 卸载时按用户的选择清理。
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
var
  Failed: string;
begin
  if CurUninstallStep <> usUninstall then Exit;

  // 静默卸载（/SILENT、/VERYSILENT）下不弹窗：那种场景是脚本或包管理器在驱动，
  // 一个模态框会把它们挂住。此时取**比交互模式更保守**的默认值：
  //   清应用设置 = 是（与交互模式一致，这是最常见的诉求）
  //   清网页缓存与登录态 = **否**（交互模式问「是否清理」时默认是「是」，
  //                              但静默场景没人能确认，保留登录态代价更小）
  //   清下载视频 = 否（与交互模式一致，那是用户文件）
  if UninstallSilent then
  begin
    Log('silent path');
    CleanSettings := True;
    CleanWebview := False;
    CleanDownloads := False;
  end
  else
  begin
    Log('interactive path');
    AskCleanupOptions;
    Log(Format('cleanup choice: settings=%d webview=%d downloads=%d', [Ord(CleanSettings), Ord(CleanWebview), Ord(CleanDownloads)]));
  end;

  Failed := '';

  if CleanSettings then
  begin
    // 关键：删数据目录时把 Download 摘出来。用户可能回答「清设置」+「保留视频」，
    // 而 Download 物理上在数据目录里面 —— 直接整树删会把他明确保留的视频删掉。
    // 详见 RemoveAppDataKeepingDownload 的说明。
    Log('removing app data (keep downloads=' + IntToStr(Ord(not CleanDownloads)) + ')');
    if not RemoveAppDataKeepingDownload(not CleanDownloads) then
      Failed := Failed + #13#10 + AppDataDir();
    // 历史目录一起清掉，避免重装后又读到旧数据。失败也要报出来（原先这一处
    // 的返回值被丢掉了，和其他三处不一致）。
    if not RemoveTreeQuiet(LegacyAppDataDir()) then
      Failed := Failed + #13#10 + LegacyAppDataDir()
    else
      // 它删掉后父目录 %APPDATA%\Han1meWinPlus 就成了空壳，顺手清掉
      RemoveTreeQuiet(ExpandConstant('{userappdata}\Han1meWinPlus'));
  end;

  // 用户选择「连下载一起删」时，Download 还留在原处（RemoveAppDataKeepingDownload
  // 在 KeepDownload=False 时已随父目录一起删掉，但那是父目录还在的情况；
  // 这里兜一下独立存在的情形）。
  if CleanDownloads and DirExists(DefaultDownloadDir()) then
  begin
    Log('removing ' + DefaultDownloadDir());
    if not RemoveTreeQuiet(DefaultDownloadDir()) then
      Failed := Failed + #13#10 + DefaultDownloadDir();
  end;

  if CleanWebview then
  begin
    Log('removing ' + WebViewDir());
    if not RemoveTreeQuiet(WebViewDir()) then Failed := Failed + #13#10 + WebViewDir();
  end;

  // 有删不掉的（通常是应用 / WebView2 还在跑）就明确说一声，不静默吞掉。
  if Failed <> '' then
  begin
    Log('cleanup incomplete:' + Failed);
    if not UninstallSilent then
      MsgBox('以下目录未能完全删除，可能仍被占用。关闭本应用后手动删除即可：' +
             Failed, mbInformation, MB_OK);
  end;
end;
