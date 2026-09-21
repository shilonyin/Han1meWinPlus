# Han1meWinPlus

<p align="center">
  <b>English</b> · <a href="README.md">简体中文</a>
</p>

<p align="center">
  <img src="assets/logo.png" alt="Han1meWinPlus Logo" width="160">
</p>

<p align="center">
  A third-party Hanime1 client built with Dart &amp; Flutter, following Material Design 3 — <b>a Windows-focused fork</b>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Windows-10%20%2F%2011-0078D6?style=for-the-badge&logo=windows11&logoColor=white" alt="Windows 10 / 11">
  <img src="https://img.shields.io/badge/Flutter-3.47%2B-02569B?style=for-the-badge&logo=flutter&logoColor=white" alt="Flutter 3.47+">
  <img src="https://img.shields.io/badge/License-AGPL--3.0-4CAF50?style=for-the-badge" alt="License">
</p>

<p align="center">
  <a href="https://github.com/shilonyin/Han1meWinPlus/actions/workflows/build-windows.yml"><img src="https://img.shields.io/github/actions/workflow/status/shilonyin/Han1meWinPlus/build-windows.yml?style=for-the-badge&label=Build" alt="Build Windows"></a>
  <a href="https://github.com/shilonyin/Han1meWinPlus/releases/latest"><img src="https://img.shields.io/github/v/release/shilonyin/Han1meWinPlus?style=for-the-badge&label=latest%20release" alt="Latest Release"></a>
  <a href="https://github.com/shilonyin/Han1meWinPlus/releases"><img src="https://img.shields.io/github/downloads/shilonyin/Han1meWinPlus/total?style=for-the-badge&label=downloads" alt="Downloads"></a>
  <a href="https://github.com/shilonyin/Han1meWinPlus/stargazers"><img src="https://img.shields.io/github/stars/shilonyin/Han1meWinPlus?style=for-the-badge&color=FFB300" alt="Stars"></a>
</p>

<p align="center">
  <b>Ready to download and install on Windows 10 / 11</b><br>
  <a href="../../releases/latest">Download latest</a> · <a href="../../issues/new/choose">Report an issue</a> · <a href="../../releases">Changelog</a> · <a href="../../discussions">Discussions</a>
</p>


## About

Han1meWinPlus is a **Windows-focused fork** of [Han1mePlus](https://github.com/1wc10086/Han1mePlus), built with Flutter and Material Design 3.

Only Windows is maintained in this branch, and the work concentrates on the Windows side: window behaviour, the player, the installer and the update flow. The `android` / `ios` / `macos` / `linux` directories are kept only so that upstream changes can be merged — they are neither maintained here nor guaranteed to build or work.

> This project has no affiliation with Hanime1 whatsoever. It is a community-maintained, third-party open-source client.

## Features

- **Windows desktop experience**: native window, custom title bar, windowed / full-screen switching, multi-monitor and high-DPI support
- **Player**: built on libmpv, with hardware decoding (d3d11va / dxva2 / nvdec), several super-resolution modes (Anime4K, EWA Lanczos), keyframe jumping, a buffered-range indicator on the progress bar, and automatic playback-position memory
- **Networking**: built-in direct-connect addresses, site diagnostics (DNS / connection / TLS certificate / page structure / sign-in state), latency probing with automatic address ranking, system proxy / direct / custom proxy, custom mirrors
- **Browsing & search**: home sections, category and tag filters, multi-criteria sorting, search suggestions and search history
- **Local library**: watch later, liked videos, playlists, watch history, offline downloads, subscriptions
- **Interface**: Material Design 3, dynamic color, light / dark / AMOLED themes, bundled HarmonyOS Sans font, UI available in Simplified Chinese / Traditional Chinese / English
- **Install & update**: installer and portable builds, in-app update checks with mirror fallback

## Screenshots

| Home (sections) | Search results |
| --- | --- |
| ![Home](docs/screenshots/home.jpg) | ![Search results](docs/screenshots/search.jpg) |

| My library (watch later / liked / playlists / subscriptions) | New releases |
| --- | --- |
| ![My library](docs/screenshots/library.jpg) | ![New releases](docs/screenshots/previews.jpg) |

| Appearance settings | Player settings |
| --- | --- |
| ![Appearance settings](docs/screenshots/appearance.png) | ![Player settings](docs/screenshots/player-settings.png) |

| Network settings | Site diagnostics |
| --- | --- |
| ![Network settings](docs/screenshots/network.png) | ![Site diagnostics](docs/screenshots/diagnostics.png) |

> Video covers and account information in the screenshots have been blurred. The screenshots show the Simplified Chinese interface; Traditional Chinese and English are also available in-app.

## Relationship to upstream

- Upstream repository: [1wc10086/Han1mePlus](https://github.com/1wc10086/Han1mePlus) (AGPL-3.0)
- This repository is a derivative work and is likewise licensed under AGPL v3.0
- Syncing upstream: `git fetch upstream && git merge upstream/main`
- Generic issues belong upstream; please file Windows-only issues in this repository

| | [Han1mePlus](https://github.com/1wc10086/Han1mePlus) | Han1meWinPlus (this repo) |
| --- | --- | --- |
| Purpose | Upstream, multi-platform | Windows-focused fork |
| Maintained platforms | Android and other mobile platforms | Windows 10 / 11 only |
| Windows window & title bar | Generic implementation | Purpose-built (custom title bar, full-screen window, DPI scaling) |
| Windows player | Generic implementation | Purpose-built (hardware-decoder options, super-resolution, proxy passed through to the player) |
| Windows installer | Depends on upstream | Installer and portable archive shipped with every release |
| Windows update flow | Generic | Purpose-built (in-app update check with mirror fallback) |

**Windows users should use this repository** (upstream's Windows support is outside the scope of this branch); for Android and other platforms, use the upstream project.

## Download

Grab the latest build from the [Releases](../../releases/latest) page:

| File | Description |
| --- | --- |
| `Han1meWinPlus-Setup.exe` | Installer: Start-menu shortcut and uninstall support (recommended) |
| `Han1meWinPlus-windows-x64.zip` | Portable: unzip and run `han1me_win_plus.exe` |
| `SHA256SUMS.txt` | Checksums: SHA256 of the installer and the portable archive, for verifying your download (also included in the release notes) |

- **System requirements**: Windows 10 (1809 or later) / Windows 11, 64-bit
- **About the "Unknown publisher" prompt**: the installer is not code-signed, so Windows may show an "Unknown publisher" warning or SmartScreen may block it. Click "More info" → "Run anyway"; alternatively just use the portable archive
- **Data directory**: `%APPDATA%\han1me_win_plus\`. It survives reinstalling and upgrading, and is *not* removed on uninstall (delete the folder manually if you want a clean slate)
- **Upgrading**: when you are on an older version the app shows an update prompt automatically, and you can also check manually under Settings → About

## Project status

- **Windows**: maintained, features are still being refined
- **Android / iOS / macOS / Linux**: not maintained; those directories exist only to merge upstream changes

Known limitations (stated up front so expectations are clear):

- The installer is not code-signed, so the first launch triggers a SmartScreen / "Unknown publisher" prompt
- Only Windows is maintained; other platforms are not guaranteed to compile or work
- Image CDNs of some sources are slow; the first paint of covers may take a moment before the local cache kicks in
- There is no automated test coverage for all features — the only unit tests in the repository cover update checking

## FAQ

<details>
<summary>Windows says "Unknown publisher" or an antivirus blocks the app on first launch</summary>

The installer is not code-signed (a personal project does not buy a signing certificate), so this is the normal prompt for unsigned software. Click "More info" → "Run anyway", or download the portable archive and run it directly.

</details>

<details>
<summary>The in-app update check fails or is very slow</summary>

Update checks go through GitHub Releases and may time out on restricted networks. "Automatically use an update mirror" under Settings → About tries mirrors in turn when the direct connection fails; you can also download the installer manually from the Releases page of this repository.

</details>

<details>
<summary>Why not just use the upstream project?</summary>

This repository is the Windows-focused fork of upstream: upstream changes are merged in, but the window, player, installer and update flow are maintained separately for Windows, and every release ships ready-to-install artifacts. See "Relationship to upstream" above.

</details>

<details>
<summary>Will uninstalling delete my data?</summary>

No. Data lives in `%APPDATA%\han1me_win_plus\` and is not removed on uninstall; delete that folder manually if you want to wipe everything.

</details>

## Build from source

```bash
flutter pub get
flutter build windows --release
```

Building the Windows installer (requires [Inno Setup](https://jrsoftware.org/isinfo.php)):

```bash
iscc /DMyAppVersion=1.1.21 windows/installer.iss
```

> `/DMyAppVersion=` writes the version number into the installer. When omitted, the fallback value inside `installer.iss` is used; it is better to always pass it explicitly (this is what CI does).

> This branch requires **Flutter ≥ 3.47.0** (a constraint from `m3e_core: ^1.1.1`), and `.fvmrc` pins `3.47.4`. Building with the same version is recommended. With an older Flutter, `flutter pub get` fails to resolve dependencies — this is unrelated to the application code.

## Releasing

Releases are produced automatically by GitHub Actions ([`.github/workflows/build-windows.yml`](.github/workflows/build-windows.yml)); no local packaging is needed.

1. Bump `version:` in `pubspec.yaml` (for example `1.1.9+20`), commit and push to the `win` branch
2. Create and push a tag that matches the `pubspec.yaml` version:

   ```bash
   git tag v1.1.9
   git push origin v1.1.9
   ```

3. Actions compiles with the Flutter version pinned in `.fvmrc`, packages with Inno Setup, then publishes `Han1meWinPlus-Setup.exe`, `Han1meWinPlus-windows-x64.zip` and `SHA256SUMS.txt` to Releases, generating a categorised changelog from `feat` / `fix` prefixed commits

> [!IMPORTANT]
> Tags must start with `v` followed by a numeric version (`v1.1.9`, `v1.1.9-win.1` are both fine). The in-app update check only parses the first three numeric segments of the tag, so something like `win-v1.1.9` is read as `0.0.0` and updates would never be detected. When the tag does not match the `pubspec.yaml` version, CI fails outright, which keeps mismatched builds from being published.

> [!NOTE]
> The installer is not code-signed, so Windows may show an "Unknown publisher" prompt on first launch. That is expected.

## Contributing

> [!Important]
> **This project is maintained by me alone, and I intend to keep it that way.**

> [!TIP]
> **Suggestions in Issues**: sharing your ideas is always welcome!

> [!NOTE]
> **Sharing ideas**: if you miss a feature or have an interesting thought, feel free to open an Issue.

> [!WARNING]
> **Reporting bugs**: if the app crashes or misbehaves, please open an Issue with as much detail as you can, so it can be investigated and fixed.

Want to send code? Please read [CONTRIBUTING.md](CONTRIBUTING.md) first (currently in Chinese).

## License

This project is licensed under [AGPL v3.0](LICENSE); users must comply strictly with its terms.

This repository is a modified version of [Han1mePlus](https://github.com/1wc10086/Han1mePlus): in accordance with AGPL-3.0 it retains the original author's attribution, publishes all modified source code, and grants no additional permissions. Distributing this repository (including compiled binaries) requires providing the corresponding source code alongside it.

This application is an unofficial client. Users are responsible for their own compliance review and must ensure their behaviour complies with the terms of service of the platforms they access and with applicable law.

This application is intended for adults aged 18 or over only.

The project is provided "as is"; the developer does not guarantee that it will run continuously, stably or securely, and accepts no liability of any kind for loss, damage, account issues or legal disputes arising from its use. Downloading, installing or running the project means you have read, understood and fully accepted this disclaimer.

## Credits

[Han1mePlus](https://github.com/1wc10086/Han1mePlus)

The upstream project of this branch; all of the base code in the Windows-focused fork comes from it.

[Han1meViewer](https://github.com/misaka10032w/Han1meViewer)

An excellent open-source project that provided reference and inspiration.

If this project is useful to you, a ⭐ would be appreciated.

Questions, suggestions or feedback are welcome in [Issues](../../issues/new/choose) and [Discussions](../../discussions) — clear bug reports with reproducible steps help the most.
