# 贡献指南

感谢你愿意花时间帮助 Han1meWinPlus。这个项目由个人维护，所以下面的约定主要是为了让每一条反馈都能**被快速定位**。

## 反馈问题

优先到 [Issues](https://github.com/shilonyin/Han1meWinPlus/issues/new/choose) 提交，仓库已准备好三种模板：

- **Bug 反馈**：崩溃、报错、界面异常、播放异常等
- **功能建议**：希望增加或调整的功能
- **安装 / 运行问题**：装不上、打不开、被杀毒软件拦截等

写法与用法交流、配置分享请到 [Discussions](https://github.com/shilonyin/Han1meWinPlus/discussions)。

> 与 Windows 无关的通用问题（Android 端、上游基础功能等）请提交到[上游仓库](https://github.com/1wc10086/Han1mePlus/issues)。

## 一条好的 Bug 报告

至少包含这些信息，能省掉大量来回确认：

1. **应用版本**：设置 → 关于 里的版本号
2. **Windows 版本**：例如 Windows 11 23H2（22631.x）
3. **安装方式**：安装版 / 免安装版 / 自己编译
4. **复现步骤**：从打开应用到出问题的每一步，越具体越好
5. **期望结果与实际结果**
6. **截图或日志**：可以直接把图片拖进输入框

涉及播放问题时的额外建议：在 设置 → 播放设置 → 播放器设置 的自定义参数里加上 `log-file=<日志路径>`，复现后把日志文件一起贴上来（libmpv 的日志能直接看出是网络、解码还是渲染的问题）。

## 提交代码

### 分支

- 默认分支是 **`win`**，也是开发分支；所有 Pull Request 请提到 `win`
- `main` 保持为上游的纯净镜像，用来同步上游改动（`git fetch upstream && git merge upstream/main`）

### 构建

```bash
flutter pub get
flutter build windows --release
```

- 必须使用 `.fvmrc` 里锁定的 Flutter 版本（当前 `3.47.4`），版本偏低时 `flutter pub get` 会直接解析失败
- 构建前请先关掉正在运行的应用，否则 `WebView2Loader.dll` 被占用会导致链接失败

### 代码风格

- **不要对既有文件跑 `dart format`**：本仓库刻意保持「长单行」的写法，格式化会制造上千行无意义 diff，破坏与上游的合并
- 本地化文案请直接手改 `.arb` 与 `lib/l10n/app_localizations*.dart` 中的对应字符串，**不要运行 `flutter gen-l10n`**（生成器版本不同会产生大量格式噪音）
- 改动请沿用周围代码的写法与注释密度

### 提交信息

提交信息会被 GitHub Actions 直接用来生成每个版本的更新日志，所以请按 Conventional Commits 写：

```
feat(播放器): 支持 xxx
fix(网络): 修复 xxx
perf(首页): 优化 xxx
```

CI 会把提交分成「新功能 / 改进 / 修复」三组写进 Release 说明。措辞请面向用户、避免出现其他应用或产品的名称。

### CI 行为

- 推送到 `win` 或提交 PR：只做构建验证
- 推送 `v*` tag：编译 + 打包安装包 + 发布 Release（版本号必须与 `pubspec.yaml` 一致）

发版由维护者执行，正常提交不需要关心 tag。
