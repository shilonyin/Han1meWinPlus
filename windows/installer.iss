#ifndef MyAppVersion
#define MyAppVersion "1.1.15"
#endif

[Setup]
; 独立于上游的 AppId，避免与 Han1mePlus 的安装互相覆盖
AppId={{B7C4E9A2-3D51-4F8C-9E2A-6C7D1F5B8A34}
AppName=Han1meWinPlus
AppVersion={#MyAppVersion}
AppPublisher=Han1meWinPlus
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

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[InstallDelete]
; 升级安装时 Inno 不会清理「旧版本装过、新版本已不再分发」的文件，得显式删除。
; desktop_multi_window 的多引擎方案已放弃（播放窗口改为独立进程），这个插件 DLL
; 早期版本被装进过 {app}，留着既是死代码，也正是当初让主窗口假死的那套实现。
Type: files; Name: "{app}\desktop_multi_window_plugin.dll"

[Icons]
Name: "{autoprograms}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"
Name: "{autodesktop}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\han1me_win_plus.exe"; Description: "Launch Han1meWinPlus"; Flags: nowait postinstall skipifsilent

[Registry]
; 自定义 URL scheme：浏览器里点 han1me://video/xxx 就能唤起本应用。
; URL Protocol 这个空字符串值是 Windows 判定「这是一个可唤起协议」的依据，不能省。
Root: HKCR; Subkey: "han1me"; ValueType: string; ValueName: ""; ValueData: "URL:Han1meWinPlus"; Flags: uninsdeletekey
Root: HKCR; Subkey: "han1me"; ValueType: string; ValueName: "URL Protocol"; ValueData: ""; Flags: uninsdeletekey
Root: HKCR; Subkey: "han1me\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\han1me_win_plus.exe,0"; Flags: uninsdeletekey
Root: HKCR; Subkey: "han1me\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\han1me_win_plus.exe"" ""%1"""; Flags: uninsdeletekey

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"
