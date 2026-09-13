#ifndef MyAppVersion
#define MyAppVersion "1.1.8"
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
CloseApplications=yes
RestartApplications=no

[Files]
Source: "..\build\windows\x64\runner\Release\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{autoprograms}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"
Name: "{autodesktop}\Han1meWinPlus"; Filename: "{app}\han1me_win_plus.exe"; Tasks: desktopicon

[Run]
Filename: "{app}\han1me_win_plus.exe"; Description: "Launch Han1meWinPlus"; Flags: nowait postinstall skipifsilent

[Tasks]
Name: "desktopicon"; Description: "Create a desktop shortcut"; GroupDescription: "Additional shortcuts:"
