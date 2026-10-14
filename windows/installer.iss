#ifndef MyAppVersion
#define MyAppVersion "1.1.25"
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

; 关掉 Setup Loader —— 这是让「双击安装」在受影响的机器上能工作的关键。
;
; 背景：Inno 默认（UseSetupLdr=yes）把全部数据打进单个 Setup.exe，而这个 exe 其实是
; 一个叫 SetupLdr 的引导程序。它的启动顺序是：
;   1) 以调用者权限（未提权）启动
;   2) **把自己解包到 %TEMP%\is-XXXX.tmp 并从那里启动内嵌的主安装程序**
;   3) 主程序带提权清单，Windows 这时才弹 UAC
; 问题出在第 2 步：它发生在提权**之前**。在一部分机器上（机制见文末），未提权的
; 进程建不了那个 %TEMP% 子目录，于是安装还没开始就死了：
;   Setup was unable to create the directory "...\Temp\is-XXXX.tmp"
;   Error 5: 拒绝访问
; 此时连日志都还没初始化，界面上只有这一个框，看起来像安装包本身坏了。
;
; 设为 no 之后第 2 步整个消失：没有引导程序，主安装程序直接启动 → Windows 先按
; 清单提权 → 提权之后再建临时目录，于是成功。实测（同一脚本、同一台机器）：
;   UseSetupLdr=yes（默认）+ admin → ExitCode=1，报上面的 Error 5
;   UseSetupLdr=no        + admin → ExitCode=0，71 个文件全部装好
;
; 代价：产物从 1 个 exe 变成 3 个文件（Setup.exe + Setup-0.bin + Setup-1.bin），
; 发布时必须一起提供、放在同一目录（见 build-windows.yml 与发布说明里的打包处理）。
; 官方文档对这个指令的说法是 "the only reason you would probably want to use no is
; for debugging purposes"，但在这个场景下它是唯一能绕开该失败的手段。
UseSetupLdr=no

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
; 为什么默认是 admin 而不是免管理员
; ===========================================================================
;
; 起因：把 PrivilegesRequired 改成 lowest（免管理员）后，安装在同一台机器上
; 直接失败，报的是和 SetupLdr 那个错一样的文本：
;   Setup was unable to create the directory "...\Temp\is-XXXX.tmp"
;   Error 5: 拒绝访问
; 排查后确认这是**另一个独立的原因**，与 UseSetupLdr 无关，机制如下。
;
; 1) Inno 创建那个临时目录时，走哪条分支取决于「账户是不是管理员」，而不是
;    「进程有没有提权」。官方源码 Projects/InstFunc.pas 的 CreateTempDir：
;
;      S := CreateTempDir('.tmp', IsAdminLoggedOn);
;
;    参数是 IsAdminLoggedOn —— 只要账户属于 Administrators 组就为真，哪怕当前
;    进程用的是未提权的 UAC 拆分令牌。
;
; 2) 为真时它走 "Protected" 分支：创建目录时附带一个显式 SDDL，
;    而不是靠父目录继承 ACL。SDDL 形如
;      D:PAI(A;OICI;FRFX;;;<当前用户>)(A;OICI;FA;;;BA)(A;OICI;FA;;;SY)
;    其中 FRFX 是**受限**权限集（读/执行，不含写）。
;
; 3) 本机正是这种情况：TAKI\24243 属于 Administrators 组，而普通双击启动的
;    进程用拆分令牌（whoami /groups 里该组标着 "Group used for deny only"）。
;    于是 Inno 选中了那条 SDDL 分支，而它在这个令牌下无法生效 → Error 5。
;    实测：手工用同一段 SDDL 建目录，目录确实建出来了，但建完连创建者自己都
;    没有写权限（随后要靠 icacls 夺取才能删掉）—— 与报错完全吻合。
;
; 4) 三条实测对照（同一脚本、同一台机器，唯一变量是安装模式与调用方式）：
;
;      UseSetupLdr=yes + admin（旧默认）         → ExitCode=1  Error 5
;      UseSetupLdr=no  + admin                   → ExitCode=0  71 个文件
;      UseSetupLdr=no  + lowest，默认/用户级     → ExitCode=1  Error 5
;      UseSetupLdr=no  + lowest，加 /ALLUSERS    → ExitCode=0  71 个文件
;
;    最后一行是关键：提权之后就能成功。也就是说，在**这台机器这一类环境**里，
;    要装上就必须提权 —— 免管理员不是脚本没写对，而是这条路在当前令牌模型下
;    走不通。提权后 Inno 建的目录 owner 是 BUILTIN\Administrators，当前用户只有
;    读权限，与上面第 2 条的 SDDL 描述一致。
;
; 因此：默认保持 admin；解析到「不提权就装不上」的机器走默认路径即可（会弹一次
; UAC）。而 /CURRENTUSER 这个开关仍然留着 —— 纯非管理员账户（不在
; Administrators 组里，令牌里没有那个组）走的是另一条不依赖 SDDL 的分支，
; 用户级安装对他们可用，那条路才是真正免管理员的。
;
; 另外：URL 协议注册已经改用 HKA（见 [Registry]），它在两种模式下会自动落到
; HKLM 或 HKCU，所以无论最终以哪种模式安装，协议都能正确注册 —— 这一项不再
; 是「必须提权」的理由。

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
procedure MeasureDir(const Dir: string; var Files: Integer; var Bytes: Int64);
var
  FindRec: TFindRec;
  Sub: string;
begin
  if not DirExists(Dir) then Exit;
  if FindFirst(AddBackslash(Dir) + '*', FindRec) then
  begin
    try
      repeat
        if (FindRec.Name <> '.') and (FindRec.Name <> '..') then
        begin
          Sub := AddBackslash(Dir) + FindRec.Name;
          if (FindRec.Attributes and FILE_ATTRIBUTE_DIRECTORY) <> 0 then
            MeasureDir(Sub, Files, Bytes)
          else
          begin
            Inc(Files);
            Bytes := Bytes + FindRec.SizeHigh * 4294967296 + FindRec.SizeLow;
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
// 这里刻意全部用整数运算，只有 %d 参与格式化。原因是 Pascal Script 的 Format
// 对浮点参数很挑剔：Format('%.1f MB', [Bytes / 1048576]) 会抛
//   Runtime error: Format '%.1f MB' invalid or incompatible with argument
// 而卸载事件函数里抛异常是致命的 —— 首次实现踩过：整个卸载直接失败、
// 退出码 1，日志里只有一行 "raised an exception (fatal)"。
function HumanSize(Bytes: Int64): string;
var
  Whole, Frac: Int64;
begin
  if Bytes >= 1073741824 then
  begin
    Whole := Bytes div 1073741824;
    Frac := (Bytes mod 1073741824) * 100 div 1073741824;
    Result := Format('%d.%02d GB', [Whole, Frac]);
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
  MeasureDir(AppDataDir(), SettingsFiles, SettingsBytes);
  MeasureDir(LegacyAppDataDir(), SettingsFiles, SettingsBytes);
  MeasureDir(WebViewDir(), WebviewFiles, WebviewBytes);

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
    MeasureDir(DefaultDownloadDir(), DownloadFiles, DownloadBytes);
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
  // 一个模态框会把它们挂住。此时按「只清应用自己的设置」处理，与交互模式下
  // 勾选框的默认值一致。
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
    Log('removing ' + AppDataDir());
    if not RemoveTreeQuiet(AppDataDir()) then Failed := Failed + #13#10 + AppDataDir();
    // 历史目录一起清掉，避免重装后又读到旧数据。
    RemoveTreeQuiet(LegacyAppDataDir());
  end;

  if CleanWebview then
  begin
    Log('removing ' + WebViewDir());
    if not RemoveTreeQuiet(WebViewDir()) then Failed := Failed + #13#10 + WebViewDir();
  end;

  if CleanDownloads then
  begin
    Log('removing ' + DefaultDownloadDir());
    if not RemoveTreeQuiet(DefaultDownloadDir()) then Failed := Failed + #13#10 + DefaultDownloadDir();
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
