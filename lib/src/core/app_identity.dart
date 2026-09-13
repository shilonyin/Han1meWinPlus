/// 本分支（Windows 专修分支）的应用标识与仓库信息。
///
/// 这里是改名 / 换源的**唯一入口**：
/// 把 [repoOwner] 改成你自己的 GitHub 用户名后，关于页、检查更新、
/// 下载更新都会指向你自己的 fork。
library;

/// 应用显示名称。
const String appName = 'Han1meWinPlus';

/// 应用内部标识，需与 `pubspec.yaml` 的 `name` 及 CMake 工程名保持一致。
const String appPackageName = 'han1me_win_plus';

/// 上游原始项目（AGPL v3.0 要求保留署名与来源）。
const String upstreamRepoOwner = '1wc10086';
const String upstreamRepoName = 'Han1mePlus';
const String upstreamRepoUrl = 'https://github.com/$upstreamRepoOwner/$upstreamRepoName';

/// 本 fork 的 GitHub 仓库。
///
/// 改名 / 换源只需要改这里，关于页、检查更新、下载更新都会跟着走。
const String repoOwner = 'shilonyin';
const String repoName = 'Han1meWinPlus';
const String repoUrl = 'https://github.com/$repoOwner/$repoName';
const String repoDisplayUrl = 'github.com/$repoOwner/$repoName';

/// 更新包（Windows 安装器）文件名前缀，需与 `windows/installer.iss` 保持一致。
const String installerBaseName = 'Han1meWinPlus-Setup';
