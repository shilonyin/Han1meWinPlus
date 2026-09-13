# Han1meWinPlus

<p align="center">
  <img src="assets/logo.png" alt="Han1meWinPlus Logo" width="160">
</p>

基于 Material Design 3 设计语言，使用 Dart & Flutter 构建的 Hanime1 第三方客户端 —— **Windows 专修分支**

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%2B-0078D6?style=for-the-badge&logo=windows11&logoColor=white" alt="Windows">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-4CAF50?style=for-the-badge" alt="License">
  <img src="https://img.shields.io/badge/Dart-3.0%2B-0175C2?style=for-the-badge&logo=dart&logoColor=white" alt="Dart">
  <img src="https://img.shields.io/badge/Flutter-3.0%2B-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter">
  <img src="https://img.shields.io/badge/Material_Design-3-6750A4?style=for-the-badge&logo=materialdesign&logoColor=white" alt="Material Design 3">
</p>


## 简介

Han1meWinPlus 是 [Han1mePlus](https://github.com/1wc10086/Han1mePlus) 的 **Windows 专修分支（fork）**，基于 Flutter 开发，采用 Material Design 3 设计规范。

本分支只维护 Windows 平台，专注于 Windows 端的窗口、播放器、安装包与更新流程。`android` / `ios` / `macos` / `linux` 目录仅保留上游代码以便同步上游改动，不在本分支的维护范围内，也不保证可用。

> 本项目为与 Hanime1 官方无任何关联。

## 与上游的关系

- 上游仓库：[1wc10086/Han1mePlus](https://github.com/1wc10086/Han1mePlus)（AGPL-3.0）
- 本仓库为其派生作品，同样遵循 AGPL v3.0
- 同步上游：`git fetch upstream && git merge upstream/main`
- 上游通用问题请反馈到上游仓库；仅 Windows 相关的问题请提到本仓库的 Issue

## 平台支持

- `Windows` ✅ 本分支维护中
- ~~`Android`~~ / ~~`iOS`~~ / ~~`macOS`~~ / ~~`Linux`~~ 不维护

## 下载

前往 [Releases](../../releases/latest) 页面下载最新版（Windows 安装包为 `Han1meWinPlus-Setup.exe`）。

## 从源码构建

```bash
flutter pub get
flutter build windows --release
```

打包 Windows 安装程序（需先安装 [Inno Setup](https://jrsoftware.org/isinfo.php)）：

```bash
iscc windows/installer.iss
```

> 本分支的依赖要求 **Flutter ≥ 3.47.0**（`m3e_core: ^1.1.1` 的约束），`.fvmrc` 已锁定为 `3.47.4`，建议使用相同版本构建。Flutter 版本偏低时 `flutter pub get` 会直接解析失败，与业务代码无关。

## 发布新版本

发布由 GitHub Actions 自动完成（[`.github/workflows/build-windows.yml`](.github/workflows/build-windows.yml)），不需要本地打包。

1. 更新 `pubspec.yaml` 里的 `version:`（例如 `1.1.9+20`），提交并推送到 `win` 分支
2. 打 tag 并推送，tag 必须和 `pubspec.yaml` 的版本号一致：

   ```bash
   git tag v1.1.9
   git push origin v1.1.9
   ```

3. Actions 会用 `.fvmrc` 锁定的 Flutter 版本编译，再用 Inno Setup 打包，最后把 `Han1meWinPlus-Setup.exe` 和免安装 zip 发到 Releases

> [!IMPORTANT]
> tag 必须是 `v` + 数字版本开头（`v1.1.9`、`v1.1.9-win.1` 都可以）。应用内「检查更新」只解析 tag 的前三段数字，写成 `win-v1.1.9` 会被当成 `0.0.0`，永远检测不到更新。tag 与 `pubspec.yaml` 版本不一致时 CI 会直接失败，避免发出对不上号的包。

> [!NOTE]
> 安装包未做代码签名，Windows 首次运行可能提示「未知发布者」，属正常现象。

## 如何贡献

> [!Important]
> **本项目仅由我个人维护，且打算继续保持这种状态。** 

> [!TIP]
> **​在 Issue 中提交建议**： 随时欢迎分享你的想法！

> [!NOTE]
> **分享想法与建议**： 如果你觉得缺少某个功能，或者有什么有意思的想法，欢迎随时新建一个 Issue。

> [!WARNING]
> **​反馈 Bug**： 遇到了应用崩溃或运行异常？请创建一个 Issue 并尽可能提供详细信息，以便我排查和解决问题。

## 开源协议

本项目遵循 [AGPL v3.0](LICENSE) 协议，使用者必须严格遵守该协议的相关条款。

本仓库是 [Han1mePlus](https://github.com/1wc10086/Han1mePlus) 的修改版本：依据 AGPL-3.0 保留原作者署名、公开全部修改后的源代码，且不提供任何额外授权。分发本仓库（含编译后的二进制）时必须一并提供对应源码。

本应用为非官方客户端。使用者须自负合规审查责任，确保自身行为符合所访问平台的服务条款及适用法律。

本应用仅供年满 18 周岁的成年人使用。

本项目按“现状（As-Is）”提供，开发者不保证程序运行的连续性、稳定性或安全性。开发者不对因使用本项目而导致的任何形式的损失、损害、账号异常或法律纠纷承担任何法律责任。下载、安装或运行本项目即视为您已阅读、理解并完全同意本免责声明的所有条款。

## 鸣谢

[Han1mePlus](https://github.com/1wc10086/Han1mePlus)

本分支的上游项目，Windows 专修分支的全部基础代码均来源于此。

[Han1meViewer](https://github.com/misaka10032w/Han1meViewer)

一个优秀的开源项目，为本项目提供了参考与灵感。

如果这个项目对你有帮助，欢迎点亮 Star ⭐
