# Han1meWinPlus

<p align="center">
  <b>English</b> · <a href="README.md">简体中文</a>
</p>

<p align="center">
  <img src="docs/logo-lockup.png" alt="Han1meWinPlus" width="400">
</p>

<p align="center">
  <b>A Hanime1 client built for Windows 10 / 11</b><br>
  Hardware decoding · Super-resolution · Installer + portable build · Built-in updater<br>
  <sub>Built with Flutter and Material Design 3 · a Windows-focused fork of Han1mePlus</sub>
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

- **Windows-specific**: native window and custom title bar, windowed / full-screen switching, multi-monitor and high-DPI support, installer + portable build, in-app updater (with mirror fallback)
- **Player**: libmpv + hardware decoding (d3d11va / dxva2 / nvdec) + several super-resolution modes (Anime4K, EWA Lanczos) + keyframe jumping, buffered-range indicator, playback-position memory
- **Networking**: built-in direct-connect addresses, site diagnostics (DNS / connection / certificate / page structure / sign-in), latency probing with automatic ranking, system proxy / direct / custom proxy, custom mirrors
- **Browsing & search**: home sections, category and tag filters, multi-criteria sorting, search suggestions and search history
- **Local library**: watch later, liked videos, playlists, watch history, offline downloads, subscriptions
- **Interface**: Material Design 3, dynamic color, light / dark / AMOLED, bundled HarmonyOS Sans, UI in Simplified Chinese / Traditional Chinese / English

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

**Windows users should use this repository** — upstream does not maintain Windows-specific work; the Windows window, player, installer and update flow all live here.

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

For Android and other platforms, use the upstream project.

## Download

### Recommended: the installer

**[Han1meWinPlus-Setup.exe](../../releases/latest)** — Start-menu shortcut, clean uninstall ([direct download](../../releases/latest/download/Han1meWinPlus-Setup.exe))

Portable build: `Han1meWinPlus-windows-x64.zip` — unzip and run `han1me_win_plus.exe` ([direct download](../../releases/latest/download/Han1meWinPlus-windows-x64.zip))

> An "Unknown publisher" prompt on first launch is expected (the installer is not code-signed). Click "More info → Run anyway"; the portable build skips the installer entirely.

- **System requirements**: Windows 10 (1809 or later) / Windows 11, 64-bit
- **Verifying your download**: each release ships `SHA256SUMS.txt` (also included in the release notes); check it in PowerShell with `certutil -hashfile <file> SHA256`
- **Data directory**: `%APPDATA%\han1me_win_plus\`. It survives reinstalling and upgrading, and is *not* removed on uninstall (delete the folder manually if you want a clean slate)
- **Upgrading**: when you are on an older version the app shows an update prompt automatically, and you can also check manually under Settings → About

All previous versions and their changelogs are on the [Releases](../../releases) page.

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
<summary>Will uninstalling delete my data? Will updating keep it?</summary>

No. Everything lives in `%APPDATA%\han1me_win_plus\` (account, subscriptions, watch history, liked videos, playlists). Reinstalling and upgrading leave it untouched, and uninstalling does not remove it; delete that folder manually if you want to wipe everything.

</details>

<details>
<summary>Hardware decoding does not work, or playback shows artifacts / a black screen</summary>

Settings → Playback settings has a hardware-decoding switch plus a decoder picker, defaulting to `auto-safe`. If you see artifacts, a green screen or a black screen:

1. Switch the decoder to `d3d11va-copy` or `dxva2-copy` (copy modes are more compatible, at the cost of one extra memory copy)
2. If it is still broken, turn hardware decoding off and use software decoding (heavier on the CPU, but the most compatible)

If a particular decoder works noticeably better on your GPU, a report with your GPU model and driver version is welcome.

</details>

<details>
<summary>How do I configure a proxy or a mirror?</summary>

Both live under Settings → Network settings:

- **Proxy**: follow the system / direct / custom address (`host:port`). Once saved, UI requests and the player (libmpv) use the same proxy
- **Site**: switch the video source; the "Site groups" entry at the bottom of the picker lets you rename and reorder groups
- **Custom mirror**: enter a mirror address and use "Test connection" to verify that it resolves

</details>

<details>
<summary>The sidebar disappears when the window gets narrow</summary>

That is intended: when the shortest side of the window drops below 600 logical pixels the layout switches to a compact one and the sidebar collapses into a drawer. Widen the window to get it back.
If the window is misplaced or does not restore after leaving full screen, update to the latest version first (these cases were fixed recently); if it persists, open an issue with a screenshot.

</details>

## Build from source

> **Flutter ≥ 3.47.0 is required** (a constraint from `m3e_core: ^1.1.1`), and `.fvmrc` pins `3.47.4`. Building with the same version is recommended. With an older Flutter, `flutter pub get` fails to resolve dependencies — this is unrelated to the application code.

```bash
flutter pub get
flutter build windows --release
```

Building the Windows installer (requires [Inno Setup](https://jrsoftware.org/isinfo.php)):

```bash
iscc /DMyAppVersion=1.1.21 windows/installer.iss
```

> `/DMyAppVersion=` writes the version number into the installer. When omitted, the fallback value inside `installer.iss` is used; it is better to always pass it explicitly (this is what CI does).

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

This project is currently maintained by one person. Issues and feature suggestions are very welcome; for code contributions please read [CONTRIBUTING.md](CONTRIBUTING.md) first (currently in Chinese).

> [!TIP]
> **Suggestions in Issues**: sharing your ideas is always welcome!

> [!NOTE]
> **Sharing ideas**: if you miss a feature or have an interesting thought, feel free to open an Issue.

> [!WARNING]
> **Reporting bugs**: if the app crashes or misbehaves, please open an Issue with as much detail as you can, so it can be investigated and fixed.

- **Feature requests / usage questions**: open an [issue](../../issues/new/choose) or start a [discussion](../../discussions)
- **Bug reports**: include your Windows version, the app version (Settings → About), reproduction steps and screenshots — it speeds up triage a lot
- Generic (non-Windows) issues belong in the [upstream repository](https://github.com/1wc10086/Han1mePlus/issues)

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
