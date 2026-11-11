# 本机构建/打包环境备忘（Han1meWinPlus）

> 每次都别再找错。之前反复在 C:\Program Files 和 D 盘找 Inno Setup 找不到，是因为它装在用户级目录。

## Inno Setup（ISCC）
- ISCC.exe 路径：`C:\Users\24243\AppData\Local\Programs\Inno Setup 6\ISCC.exe`
- 开始菜单快捷方式：`C:\Users\24243\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Inno Setup 6\`
- 不要再去 Program Files / D盘 找。

## 已安装版 vs 开发构建
- **用户实际打开的安装版**：`D:\Program Files (x86)\Han1meWinPlus\han1me_win_plus.exe`
  - 开始菜单快捷方式指向它：`...\Start Menu\Programs\Han1meWinPlus.lnk`
- 开发构建产物：`F:\Han1meWinPlus\build\windows\x64\runner\Debug|Release\han1me_win_plus.exe`
- **改了源码 ≠ 用户能看到**：必须重新打包安装到 D:\Program Files (x86)\Han1meWinPlus 才会更新用户点开的版本。

## 更新安装版的标准流程
1. `flutter build windows --release`
2. `"C:\Users\24243\AppData\Local\Programs\Inno Setup 6\ISCC.exe" /DMyAppVersion=<版本号> windows\installer.iss`
   - 版本号取 pubspec.yaml 的 `version:`（当前 1.1.28+39 → 传 1.1.28）
   - 产物：`build\Han1meWinPlus-Setup.exe`
3. 运行 Setup 覆盖安装（默认 admin，会弹 UAC 需用户确认）
