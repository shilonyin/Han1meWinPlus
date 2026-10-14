#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <dwmapi.h>
#include <gdiplus.h>
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

#include <cmath>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <memory>
#include <string>

// Reference the Windows plugin registrant with a path relative to this file
// (windows/runner -> windows/flutter). The bare "flutter/..." form is resolved
// against the include directories as well, where the Linux registrant
// (linux/flutter/generated_plugin_registrant.h) can be found first. That header
// includes flutter_linux/flutter_linux.h and cannot be compiled on Windows.
#include "../flutter/generated_plugin_registrant.h"
#include "resource.h"

// Ask the graphics driver to put us on the discrete GPU. On hybrid systems the
// app can otherwise be scheduled onto the integrated one, which is slower to
// start up and to render. Flutter's GpuPreference below covers the engine side;
// these two exports are what the NVIDIA/AMD drivers look for at process start.
extern "C" __declspec(dllexport) DWORD NvOptimusEnablement = 0x00000001;
extern "C" __declspec(dllexport) int AmdPowerXpressRequestHighPerformance = 1;

namespace {

constexpr const wchar_t kWindowClassName[] = L"Han1meWinPlusWindow";
constexpr const wchar_t kWindowTitle[] = L"Han1meWinPlus";
// A second launch should focus the window that is already running instead of
// starting another copy of the engine and the video player.
constexpr const wchar_t kInstanceMutexName[] = L"Han1meWinPlus.instance.mutex";
// Player windows keep exactly one live instance of their own (separate from the
// main window mutex): a click on another video hands the id to the window that
// is already open instead of spawning a second player.
constexpr const wchar_t kPlayWindowMutexName[] = L"Han1meWinPlus.play-window.mutex";


void ApplyPerMonitorDpiAwareness() {
  if (!SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2)) {
    SetProcessDPIAware();
  }
}

// Reuse the console of the shell that launched us, if there is one. Without this
// the executable is a plain WIN32 subsystem app and everything Dart writes with
// print/debugPrint (startup timings, for instance) goes nowhere.
void AttachParentConsole() {
  if (!::AttachConsole(ATTACH_PARENT_PROCESS)) return;
  FILE* stream = nullptr;
  if (freopen_s(&stream, "CONOUT$", "w", stdout) == 0) _dup2(_fileno(stdout), 1);
  if (freopen_s(&stream, "CONOUT$", "w", stderr) == 0) _dup2(_fileno(stdout), 2);
  std::ios::sync_with_stdio();
}

UINT SystemDpi() {
  const auto dpi = GetDpiForSystem();
  if (dpi != 0) return dpi;
  const auto screen = GetDC(nullptr);
  if (screen == nullptr) return 96;
  const auto result = static_cast<UINT>(GetDeviceCaps(screen, LOGPIXELSX));
  ReleaseDC(nullptr, screen);
  return result == 0 ? 96 : result;
}

int DpiScale(int value, UINT dpi) {
  return static_cast<int>(static_cast<double>(value) * dpi / 96.0 + 0.5);
}

// Splash icon side length (logical px). app_icon.ico ships 16-256 px images,
// so the DPI-scaled request resolves to a crisp source.
constexpr int kSplashIconSide = 64;
// Height of the design lockup (icon + wordmark) drawn on the splash, in logical
// px; the image keeps its aspect ratio and is centred.
constexpr int kSplashLogoHeight = 56;
// Minimum time the splash stays visible. The engine is ready in a couple of
// hundred milliseconds on an idle machine, so without a floor the lockup only
// flashes by.
constexpr int kSplashMinDurationMs = 1300;
constexpr UINT_PTR kSplashTimerId = 1;

bool SystemPrefersDarkApps() {
  DWORD use_light = 1;
  DWORD size = sizeof(use_light);
  const auto status = RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &use_light, &size);
  return status == ERROR_SUCCESS && use_light == 0;
}

// Older SDK headers may not define these DWM attributes; the values match the
// Windows 11 SDK.
#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif
#ifndef DWMWA_BORDER_COLOR
#define DWMWA_BORDER_COLOR 34
#endif
#ifndef DWMWA_CAPTION_COLOR
#define DWMWA_CAPTION_COLOR 35
#endif
#ifndef DWMWA_TEXT_COLOR
#define DWMWA_TEXT_COLOR 36
#endif

// Follow the system light/dark preference and use an M3 surface color so the
// window does not visibly jump when the first Flutter frame lands.
HBRUSH WindowBackgroundBrush() {
  static HBRUSH brush = nullptr;
  if (brush == nullptr) brush = CreateSolidBrush(SystemPrefersDarkApps() ? RGB(28, 27, 32) : RGB(253, 248, 255));
  return brush;
}

// During the splash the window still shows the native caption bar (the in-app
// one is only installed once Flutter is up). Tint the caption, its text and the
// window border with the same colour as the client area, otherwise a system
// coloured bar sits on top of an identically framed dark screen. Windows 10 does
// not support these attributes (the calls simply fail) and keeps its default.
void ApplySplashCaptionColors(HWND window) {
  const auto dark = SystemPrefersDarkApps();
  const auto background = dark ? RGB(28, 27, 32) : RGB(253, 248, 255);
  const auto text = dark ? RGB(233, 236, 241) : RGB(28, 27, 32);
  const BOOL use_dark = dark ? TRUE : FALSE;
  DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE, &use_dark, sizeof(use_dark));
  DwmSetWindowAttribute(window, DWMWA_CAPTION_COLOR, &background, sizeof(background));
  DwmSetWindowAttribute(window, DWMWA_TEXT_COLOR, &text, sizeof(text));
  DwmSetWindowAttribute(window, DWMWA_BORDER_COLOR, &background, sizeof(background));
}

// ---------------------------------------------------------------------------
// Window title bar (system caption vs the app's own bar)
// ---------------------------------------------------------------------------
//
// The window is created and shown before the Flutter engine is up, so that the
// splash has something to sit on. The title bar style, though, is a *user
// preference* and only Dart used to read it: the runner showed a window with the
// system caption, and Dart removed that caption about a second later, once the
// engine was live.
//
// Removing it is not a style tweak. window_manager's `TitleBarStyle.hidden`
// rewrites the client rectangle during WM_NCCALCSIZE, folding the whole caption
// strip (39 px here) and part of the borders into the client area while the
// window is already on screen. The window frame does not move, so the content
// jumps outward and the edges "flash" - on every cold start, and again every
// time a standalone player window opens (same runner, same sequence).
//
// The fix is to have the preference reach the runner too, before the window is
// first shown, so the first painted frame already carries the final client
// rectangle. There is then nothing left to change when Dart applies its own
// setting.

// Only this one key is parsed out of setting.json. A hand written JSON reader
// would be the wrong size of dependency for a single boolean, and a value that
// cannot be read falls back to the system title bar - which is also the default
// Dart uses for a missing key (`json['useSystemTitleBar'] as bool? ?? true`).
bool ReadUseSystemTitleBar() {
  const auto length = GetEnvironmentVariableW(L"APPDATA", nullptr, 0);
  if (length == 0) return true;
  std::wstring app_data(length, L'\0');
  GetEnvironmentVariableW(L"APPDATA", app_data.data(), length);
  app_data.resize(length - 1);
  const auto path = std::filesystem::path(app_data) / L"han1me_win_plus" / L"setting.json";
  std::ifstream stream(path, std::ios::binary);
  if (!stream) return true;
  const std::string contents((std::istreambuf_iterator<char>(stream)), std::istreambuf_iterator<char>());
  constexpr char key[] = "\"useSystemTitleBar\"";
  const auto at = contents.find(key);
  if (at == std::string::npos) return true;
  const auto colon = contents.find(':', at + sizeof(key) - 1);
  if (colon == std::string::npos) return true;
  const auto value = contents.find_first_not_of(" \t\r\n", colon + 1);
  if (value == std::string::npos) return true;
  if (contents.compare(value, 5, "false") == 0) return false;
  return true;
}

// window_manager keeps one pixel at the top of the client area on Windows 11
// and later, through a helper named `IsWindows11OrGreater` whose expression
// tests the opposite (`build < 22000`). The resulting arithmetic is deliberate:
// the plugin adds 0 on Windows 10 and 1 on Windows 11+ ("on windows 10, if set
// to 0, there's a white line at the top"). Reproducing the *effect* rather than
// the misleading name, and re-reading the same version query, keeps the runner
// and the plugin in step - any mismatch is itself a flicker.
int CaptionTopInset() {
  DWORD version = 0;
  DWORD build = 0;
#pragma warning(push)
#pragma warning(disable : 4996)
  version = GetVersion();
  if (version < 0x80000000) build = static_cast<DWORD>(HIWORD(version));
#pragma warning(pop)
  return build < 22000 ? 0 : 1;
}

// Mirrors window_manager's TitleBarStyle.hidden client rectangle. The runner
// only owns this while the window is being prepared and while Dart's preference
// says to hide the caption; the plugin's own title_bar_style_ stays "normal",
// so its hidden branch never runs and there is exactly one implementation of
// this arithmetic in play at any moment.
void ExpandClientAreaOverCaption(HWND window, NCCALCSIZE_PARAMS* params) {
  if (IsZoomed(window)) {
    // Maximised: grow the client area over the frame so the edges are not cut
    // off. Copied from the plugin's adjustNCCALCSIZE.
    LONG left = 8;
    LONG top = 8;
    const auto monitor = MonitorFromRect(&params->rgrc[0], MONITOR_DEFAULTTONEAREST);
    MONITORINFO info{};
    info.cbSize = sizeof(MONITORINFO);
    if (monitor != nullptr && GetMonitorInfo(monitor, &info)) {
      left = params->rgrc[0].left - info.rcWork.left;
      top = params->rgrc[0].top - info.rcWork.top;
    }
    params->rgrc[0].left -= left;
    params->rgrc[0].top -= top;
    params->rgrc[0].right += left;
    params->rgrc[0].bottom += top;
    return;
  }
  params->rgrc[0].top += CaptionTopInset();
  params->rgrc[0].right -= 8;
  params->rgrc[0].bottom -= 8;
  params->rgrc[0].left += 8;
}

// Dart's preference for the window's title bar. Read once before the window is
// created so the first frame is already final, then kept in step through the
// `han1me/window` channel (see `ApplyTitleBarStyle`).
bool g_use_system_title_bar = true;

// Recomputes the client area after the preference changes at runtime. Mirrors
// window_manager's SetTitleBarStyle, which is what the app used before: the
// frame extension is reset and a frame-changed resize re-runs WM_NCCALCSIZE.
void RefreshTitleBarStyle(HWND window) {
  MARGINS margins = {0, 0, 0, 0};
  DwmExtendFrameIntoClientArea(window, &margins);
  RECT rect{};
  GetWindowRect(window, &rect);
  SetWindowPos(window, nullptr, rect.left, rect.top, 0, 0,
               SWP_NOZORDER | SWP_NOOWNERZORDER | SWP_NOMOVE | SWP_NOSIZE | SWP_FRAMECHANGED);
}

// Applies [use_system_title_bar] to the window. A no-op when the value is
// already in effect, so Dart re-applying the persisted preference at startup
// (which is what it always did) cannot repaint the frame.
void ApplyTitleBarStyle(HWND window, bool use_system_title_bar) {
  if (window == nullptr || g_use_system_title_bar == use_system_title_bar) return;
  g_use_system_title_bar = use_system_title_bar;
  RefreshTitleBarStyle(window);
}

// Loaded once and cached: dragging a resize repaints the splash many times.
HICON StartupIcon(HINSTANCE instance, UINT dpi, int& side) {
  static HICON icon = nullptr;
  static int cached_side = 0;
  const auto requested = DpiScale(kSplashIconSide, dpi);
  if (icon == nullptr || cached_side != requested) {
    if (icon != nullptr) DestroyIcon(icon);
    icon = static_cast<HICON>(LoadImage(instance, MAKEINTRESOURCE(IDI_APP_ICON), IMAGE_ICON, requested, requested, LR_DEFAULTCOLOR));
    cached_side = requested;
  }
  side = cached_side;
  return icon;
}

// The window has no content while the engine boots, so draw the app icon to
// make the wait visible. The caller passes the live client rect so the icon is
// re-centred on every repaint while the window is resized.
void DrawStartupIcon(HDC dc, const RECT& client, HINSTANCE instance, UINT dpi) {
  int side = 0;
  const auto icon = StartupIcon(instance, dpi, side);
  if (icon == nullptr) return;
  DrawIconEx(dc, (client.right - side) / 2, (client.bottom - side) / 2, icon, side, side, 0, nullptr, DI_NORMAL);
}

// GDI+ is only used by the splash: the engine has not started yet, so Flutter's
// image decoding is not available and the lockup is a PNG asset.
struct GdiPlusSession {
  ULONG_PTR token = 0;
  bool ready = false;
  GdiPlusSession() {
    Gdiplus::GdiplusStartupInput input;
    ready = Gdiplus::GdiplusStartup(&token, &input, nullptr) == Gdiplus::Ok;
  }
  ~GdiPlusSession() {
    if (ready) Gdiplus::GdiplusShutdown(token);
  }
};

GdiPlusSession& SplashGdiPlus() {
  static GdiPlusSession session;
  return session;
}

std::filesystem::path ExecutableDirectory() {
  std::wstring buffer(MAX_PATH, L'\0');
  const auto length = GetModuleFileNameW(nullptr, buffer.data(), static_cast<DWORD>(buffer.size()));
  buffer.resize(length);
  return std::filesystem::path(buffer).parent_path();
}

// The design lockup ships with the Flutter assets, next to the executable under
// data/flutter_assets/assets. Both background variants are cached; the dark one
// has a light wordmark, otherwise it would be invisible on a dark splash.
Gdiplus::Image* StartupLockup(bool dark) {
  static Gdiplus::Image* light = nullptr;
  static Gdiplus::Image* dark_image = nullptr;
  static bool light_failed = false;
  static bool dark_failed = false;
  auto*& image = dark ? dark_image : light;
  bool& failed = dark ? dark_failed : light_failed;
  if (image != nullptr || failed) return image;
  const auto name = dark ? L"logo_lockup_dark.png" : L"logo_lockup.png";
  const auto path = (ExecutableDirectory() / L"data" / L"flutter_assets" / L"assets" / name).wstring();
  auto* loaded = new Gdiplus::Image(path.c_str());
  if (loaded->GetLastStatus() != Gdiplus::Ok) {
    delete loaded;
    failed = true;
    return nullptr;
  }
  image = loaded;
  return image;
}

// Draws the design lockup; falls back to the square app icon if the PNG cannot
// be loaded.
void DrawStartupLogo(HDC dc, const RECT& client, HINSTANCE instance, UINT dpi) {
  auto* image = SplashGdiPlus().ready ? StartupLockup(SystemPrefersDarkApps()) : nullptr;
  if (image == nullptr) {
    DrawStartupIcon(dc, client, instance, dpi);
    return;
  }
  const auto height = DpiScale(kSplashLogoHeight, dpi);
  const auto width = static_cast<int>(std::lround(static_cast<double>(height) * image->GetWidth() / image->GetHeight()));
  Gdiplus::Graphics graphics(dc);
  graphics.SetInterpolationMode(Gdiplus::InterpolationModeHighQualityBicubic);
  graphics.DrawImage(image, Gdiplus::Rect((client.right - width) / 2, (client.bottom - height) / 2, width, height));
}

// Bring the instance that is already running to the front.
void ActivateExistingWindow() {
  const auto window = FindWindowW(kWindowClassName, nullptr);
  if (window == nullptr) return;
  if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOW);
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
}

// Standalone player window (the multi-process take on multi window playback):
// a launch like `han1me.exe --play-window --video=<id>` renders only the video
// page. Unlike the abandoned desktop_multi_window approach (multiple engines
// inside one process, see the NOTE below), every player window is its own
// process with its own engine and message loop, so it cannot freeze the main
// window. Player windows skip the *main* instance mutex (they live alongside
// the main window) but hold their own: the second player launch forwards its
// `--video=<id>` to the player that is already open and exits, so at most one
// player window exists at a time.
bool IsPlayWindowLaunch() {
  for (int i = 1; i < __argc; ++i) {
    if (wcscmp(__wargv[i], L"--play-window") == 0) return true;
  }
  return false;
}

// The `--video=<id>` argument of this launch, UTF-8 encoded; empty when absent.
// The forwarding path below needs it before any window exists, so it reads the
// command line directly instead of waiting for the Dart entrypoint arguments.
std::string PlayWindowVideoId() {
  constexpr const wchar_t prefix[] = L"--video=";
  constexpr size_t prefix_length = sizeof(prefix) / sizeof(wchar_t) - 1;
  for (int i = 1; i < __argc; ++i) {
    const std::wstring argument = __wargv[i];
    if (argument.compare(0, prefix_length, prefix) != 0) continue;
    const std::wstring value = argument.substr(prefix_length);
    const int size = WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
    std::string utf8(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, value.c_str(), static_cast<int>(value.size()), utf8.data(), size, nullptr, nullptr);
    return utf8;
  }
  return {};
}

// Player windows share the window class with the main window, so they are
// recognised by a property instead of by class name or title (the title changes
// with every video). The property list dies with the window, so a crashed or
// closed player can never leave a stale marker behind.
constexpr const wchar_t kPlayWindowPropName[] = L"Han1meWinPlus.play-window";

struct PlayWindowSearch {
  HWND window = nullptr;
};

BOOL CALLBACK FindPlayWindowCallback(HWND window, LPARAM lparam) {
  if (GetPropW(window, kPlayWindowPropName) != nullptr) {
    reinterpret_cast<PlayWindowSearch*>(lparam)->window = window;
    return FALSE;
  }
  return TRUE;
}

HWND FindPlayWindow() {
  PlayWindowSearch search;
  EnumWindows(FindPlayWindowCallback, reinterpret_cast<LPARAM>(&search));
  return search.window;
}

// Identifier for the WM_COPYDATA payloads this runner exchanges (dwData).
// WM_COPYDATA is delivered to any window of any process, so the receiver checks
// this tag before trusting lpData.
constexpr ULONG_PTR kCopyDataPlayVideo = 0x48314D50;  // 'H1MP'

std::string g_pending_play_video;      // a video that arrived before the engine was ready

// Hands `video_id` to the player window that is already open: WM_COPYDATA it
// the id, bring the window to the front, and report whether that worked.
bool ForwardVideoToPlayWindow(HWND window, const std::string& video_id) {
  COPYDATASTRUCT data{};
  data.dwData = kCopyDataPlayVideo;
  data.cbData = static_cast<DWORD>(video_id.size());
  // COPYDATASTRUCT::lpData is PVOID, but the receiver must not modify it (the
  // string belongs to this frame and only has to survive the synchronous
  // SendMessage below).
  data.lpData = const_cast<char*>(video_id.data());
  // SendMessage is synchronous: TRUE means the receiving WindowProc has taken
  // the id (it may still be parked in g_pending_play_video until the engine is
  // up - that is fine, delivery is guaranteed once the park happened).
  if (SendMessageW(window, WM_COPYDATA, 0, reinterpret_cast<LPARAM>(&data)) != TRUE) return false;
  if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOW);
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
  return true;
}

// A player launch that found the mutex taken: the running player takes over
// the video and this process exits without ever showing a window. Fails (and
// lets the caller fall back to becoming a player itself) only when the running
// player is on its way out - the mutex exists but its window is already gone.
bool RedirectPlayWindowLaunch() {
  const auto video_id = PlayWindowVideoId();
  if (video_id.empty()) return false;
  // The mutex holder creates its window a few milliseconds after the mutex, so
  // a click landing inside that gap has to retry briefly instead of failing.
  for (int attempt = 0; attempt < 40; ++attempt) {
    const auto window = FindPlayWindow();
    if (window != nullptr && ForwardVideoToPlayWindow(window, video_id)) return true;
    Sleep(25);
  }
  return false;
}

}

struct AppWindow {
  std::unique_ptr<flutter::FlutterViewController> controller;
  HINSTANCE instance = nullptr;
  UINT splash_dpi = 96;
  // Whether the splash is still on screen (until kSplashMinDurationMs elapses
  // the Flutter view is deliberately kept behind it).
  bool splash_visible = true;
};

void ConfigureWebViewUserDataFolder() {
  const auto length = GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (length == 0) return;
  std::wstring local_app_data(length, L'\0');
  GetEnvironmentVariableW(L"LOCALAPPDATA", local_app_data.data(), length);
  local_app_data.resize(length - 1);
  const auto user_data_folder = std::filesystem::path(local_app_data) / L"Han1meWinPlus" / L"webview2";
  std::error_code error;
  std::filesystem::create_directories(user_data_folder, error);
  if (!error) SetEnvironmentVariableW(L"WEBVIEW2_USER_DATA_FOLDER", user_data_folder.c_str());
}

constexpr char kWindowChannelName[] = "han1me/window";
constexpr char kPlayWindowChannelName[] = "han1me/play-window";

// Wires up the channel Dart uses to change the title bar at runtime, replacing
// the window_manager call it used to make. Kept process-lifetime: the plugin
// equivalent is owned by its registrar, and dropping this would leave Dart
// calling into nothing.
void RegisterWindowChannel(flutter::BinaryMessenger* messenger, HWND window) {
  static std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> channel;
  channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kWindowChannelName, &flutter::StandardMethodCodec::GetInstance());
  channel->SetMethodCallHandler(
      [window](const flutter::MethodCall<flutter::EncodableValue>& call,
               std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "setUseSystemTitleBar") {
          result->NotImplemented();
          return;
        }
        const auto* argument = std::get_if<bool>(call.arguments());
        if (argument == nullptr) {
          result->Error("bad-arguments", "setUseSystemTitleBar expects a bool");
          return;
        }
        ApplyTitleBarStyle(window, *argument);
        result->Success();
      });
}

// Delivers a forwarded video id ("click while this player was already open")
// to the Dart side. The second player process usually arrives while the engine
// is still booting - before RegisterPlayWindowChannel ran - so until then the
// id is parked and pushed once the channel exists.
std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> g_play_window_channel;

void DeliverPlayVideo(const std::string& video_id) {
  if (g_play_window_channel == nullptr) {
    g_pending_play_video = video_id;
    return;
  }
  g_play_window_channel->InvokeMethod("loadVideo", std::make_unique<flutter::EncodableValue>(video_id));
}

void RegisterPlayWindowChannel(flutter::BinaryMessenger* messenger) {
  g_play_window_channel = std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
      messenger, kPlayWindowChannelName, &flutter::StandardMethodCodec::GetInstance());
  if (!g_pending_play_video.empty()) {
    const auto pending = g_pending_play_video;
    g_pending_play_video.clear();
    DeliverPlayVideo(pending);
  }
}

LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam) {
  auto* app = reinterpret_cast<AppWindow*>(GetWindowLongPtr(window, GWLP_USERDATA));
  if (message == WM_NCCREATE) {
    app = static_cast<AppWindow*>(reinterpret_cast<CREATESTRUCT*>(lparam)->lpCreateParams);
    SetWindowLongPtr(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(app));
  }
  if (message == WM_SIZE && app != nullptr) {
    // A resize exposes new client area. Repaint the whole client so it is filled
    // with the window background instead of being left unpainted, and so the
    // splash icon is re-centred. This must run before the Flutter view handles
    // the message: it returns early for WM_SIZE, so the switch below never sees
    // resizes once the engine is up.
    InvalidateRect(window, nullptr, FALSE);
    if (app->controller == nullptr) UpdateWindow(window);
  }
  if (message == WM_COPYDATA) {
    // Another player process hands over a `--video=<id>` launch. Only player
    // windows speak this protocol; the main window ignores it, and the payload
    // tag keeps unrelated COPYDATA senders from being misread.
    if (IsPlayWindowLaunch()) {
      const auto* data = reinterpret_cast<COPYDATASTRUCT*>(lparam);
      if (data != nullptr && data->dwData == kCopyDataPlayVideo && data->cbData > 0 && data->lpData != nullptr) {
        DeliverPlayVideo(std::string(static_cast<const char*>(data->lpData), data->cbData));
        return TRUE;
      }
    }
  }
  if (message == WM_GETMINMAXINFO) {
    // window_manager (registered as a plugin window proc delegate) claims this
    // message and returns 0 for it, so the switch below never sees it. Apply the
    // minimum size first, before the message is forwarded to the plugins.
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    const auto dpi = GetDpiForWindow(window);
    // The player window has to shrink into the picture-in-picture corner window
    // (380x240 logical, see PlayWindowTitleBar._togglePictureInPicture). It has no
    // navigation shell, so 320x200 leaves enough room for its title bar and player.
    // The main window keeps 720x540: below that the navigation rail plus the content
    // area no longer lay out.
    //
    // These floors must differ. WM_GETMINMAXINFO clamps SetWindowPos back up to the
    // minimum, so a shared 720x540 floor made the PiP bounds impossible to apply
    // (measured: 380x240 came back as 720x540) - the feature looked present but was
    // dead.
    const bool play_window = IsPlayWindowLaunch();
    info->ptMinTrackSize.x = DpiScale(play_window ? 320 : 720, dpi);
    info->ptMinTrackSize.y = DpiScale(play_window ? 200 : 540, dpi);
  }
  if (app != nullptr && app->controller != nullptr) {
    const auto result = app->controller->HandleTopLevelWindowProc(window, message, wparam, lparam);
    if (result.has_value()) return result.value();
  }
  switch (message) {
    case WM_ERASEBKGND:
      // WM_PAINT owns the background; skipping the erase avoids flicker.
      return 1;
    case WM_PAINT: {
      PAINTSTRUCT state{};
      const auto dc = BeginPaint(window, &state);
      RECT client{};
      GetClientRect(window, &client);
      // Repaint the whole client area instead of just state.rcPaint: resizing
      // moves the splash icon, so filling only the newly exposed strip would
      // leave the previous one behind in the old position.
      FillRect(dc, &client, WindowBackgroundBrush());
      if (app != nullptr && app->splash_visible && app->instance != nullptr) {
        DrawStartupLogo(dc, client, app->instance, app->splash_dpi);
      }
      EndPaint(window, &state);
      return 0;
    }
    case WM_SIZE: {
      if (app == nullptr || app->controller == nullptr) return 0;
      const auto child = app->controller->view()->GetNativeWindow();
      MoveWindow(child, 0, 0, LOWORD(lparam), HIWORD(lparam), TRUE);
      return 0;
    }
    case WM_TIMER: {
      // The minimum splash time elapsed: reveal the Flutter view that was kept
      // hidden behind the splash.
      if (wparam != kSplashTimerId || app == nullptr || app->controller == nullptr) return 0;
      KillTimer(window, kSplashTimerId);
      app->splash_visible = false;
      const auto child = app->controller->view()->GetNativeWindow();
      ShowWindow(child, SW_SHOW);
      InvalidateRect(window, nullptr, FALSE);
      SetFocus(child);
      return 0;
    }
    case WM_DESTROY:
      // Tear the engine down *here*, while the message loop is still pumping.
      //
      // Destroying the FlutterViewController posts work to the platform thread
      // and waits for the engine's UI/raster threads to wind down. Doing that
      // after the loop has exited (i.e. from the stack unwinding at the end of
      // wWinMain) leaves nobody to run those tasks, and the engine aborts the
      // process with __fastfail - every window close produced
      // `flutter_windows.dll` / 0xc0000409 (measured: 4 of 4 closes, the crash
      // timestamp matching the close to the second). The stock Flutter win32
      // runner avoids this by dropping its controller in OnDestroy, i.e. at
      // exactly this point; this runner now does the same.
      if (app != nullptr) app->controller.reset();
      PostQuitMessage(0);
      return 0;
    case WM_NCACTIVATE:
      // With the caption folded into the client area there is no non-client
      // area left to repaint when the window gains or loses focus. Returning
      // TRUE says "handled" and stops the system from drawing activation
      // chrome over the app's own title bar. Same answer window_manager gives
      // for its hidden style.
      if (!g_use_system_title_bar) return TRUE;
      break;
    case WM_NCCALCSIZE:
      // The client rectangle is computed once, here, instead of being widened
      // later by window_manager: whichever preference setting.json carries has
      // already been applied before the window was first shown, so this only
      // ever has to run for the value it already reflects.
      //
      // Returning 0 for wParam == TRUE means "the client area is exactly
      // rgrc[0]" - that is what folds the caption strip into the client area.
      // The resize borders survive because DefWindowProc's WM_NCHITTEST works
      // off WS_THICKFRAME, not off this rectangle.
      if (wparam == TRUE && !g_use_system_title_bar) {
        ExpandClientAreaOverCaption(window, reinterpret_cast<NCCALCSIZE_PARAMS*>(lparam));
        return 0;
      }
      break;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

/// Converts command line arguments (skipping argv[0], the program path) to
/// UTF-8 for the Dart entrypoint.
///
/// Only launches like the han1me:// scheme carry arguments; a normal launch
/// (double click) yields an empty list.
static std::vector<std::string> Utf8CommandLineArguments() {
  std::vector<std::string> arguments;
  for (int i = 1; i < __argc; ++i) {
    const std::wstring wide = __wargv[i];
    const int size = WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), nullptr, 0, nullptr, nullptr);
    std::string utf8(static_cast<size_t>(size), '\0');
    WideCharToMultiByte(CP_UTF8, 0, wide.c_str(), static_cast<int>(wide.size()), utf8.data(), size, nullptr, nullptr);
    arguments.push_back(utf8);
  }
  return arguments;
}

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int show_command) {
  // Player windows never touch the *main* instance handshake (they must never
  // redirect to or activate the main window), but they hold their own mutex:
  // a second player launch hands its `--video=<id>` to the player that is
  // already open and exits, so at most one player window exists at a time.
  const bool play_window = IsPlayWindowLaunch();
  HANDLE instance_mutex = nullptr;
  HANDLE play_window_mutex = nullptr;
  if (!play_window) {
    instance_mutex = CreateMutexW(nullptr, TRUE, kInstanceMutexName);
    if (instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
      ActivateExistingWindow();
      CloseHandle(instance_mutex);
      return EXIT_SUCCESS;
    }
  } else {
    play_window_mutex = CreateMutexW(nullptr, TRUE, kPlayWindowMutexName);
    if (play_window_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
      const bool redirected = RedirectPlayWindowLaunch();
      CloseHandle(play_window_mutex);
      play_window_mutex = nullptr;
      if (redirected) return EXIT_SUCCESS;
      // Redirect failed only when the holder is on its way out (mutex alive,
      // window already gone). Fall through and become the player ourselves -
      // never leave a click without a video. Later launches find this window
      // through the property marker, not the mutex, so sharing the namespace
      // with the dying process for a few more milliseconds is harmless.
    }
  }
  ApplyPerMonitorDpiAwareness();
  CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  AttachParentConsole();
  ConfigureWebViewUserDataFolder();
  WNDCLASS window_class{};
  window_class.hInstance = instance;
  window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
  window_class.hIcon = LoadIcon(instance, MAKEINTRESOURCE(IDI_APP_ICON));
  window_class.lpszClassName = kWindowClassName;
  window_class.lpfnWndProc = WindowProc;
  RegisterClass(&window_class);

  AppWindow app;
  app.instance = instance;
  const auto dpi = SystemDpi();
  app.splash_dpi = dpi;
  // Read the title bar preference *before* the window exists. CreateWindow runs
  // WM_NCCALCSIZE on the way up, so this is the one moment at which the client
  // rectangle can be decided without the window ever having been on screen with
  // the other value - see the title bar section above.
  g_use_system_title_bar = ReadUseSystemTitleBar();
  // The player window is a touch narrower and taller than the main one: its
  // layout is "16:9 player + right sidebar", which wants the extra height.
  const auto width = DpiScale(play_window ? 1180 : 1280, dpi);
  const auto height = DpiScale(play_window ? 760 : 720, dpi);
  const auto window = CreateWindow(kWindowClassName, kWindowTitle, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr, instance, &app);
  if (window == nullptr) return EXIT_FAILURE;
  if (play_window) {
    // Mark this top-level window as *the* player window: later launches locate
    // it by this property (the class name is shared with the main window and
    // the title changes with every video). The property list dies with the
    // window, so nothing needs to be cleaned up manually.
    SetPropW(window, kPlayWindowPropName, reinterpret_cast<HANDLE>(1));
  }
  // CreateWindow sends its own WM_NCCALCSIZE, but only with wParam FALSE - the
  // "client area is being recalculated" form (wParam TRUE), which is the one
  // that carries the folding, arrives when the frame is refreshed. Do that here,
  // while the window is still hidden, so the client rectangle the user ever sees
  // is already the final one. This is the same frame-changed resize
  // window_manager performs; the difference is only *when*.
  if (!g_use_system_title_bar) RefreshTitleBarStyle(window);
  // Tint the native caption before it is first painted, so it matches the splash.
  // A hidden caption has no colour to tint; the call is harmless either way.
  ApplySplashCaptionColors(window);

  // Engine startup loads flutter_windows.dll plus the AOT snapshot and brings up
  // the Dart VM, which takes over a second. The window already exists at this
  // point, so show the splash now instead of leaving the screen blank.
  const auto splash_started = GetTickCount64();
  ShowWindow(window, show_command);
  UpdateWindow(window);

  RECT bounds{};
  GetClientRect(window, &bounds);
  flutter::DartProject project(L"data");
  // Custom URL schemes (han1me://...) arrive as command line arguments;
  // forward them to Dart so the app can navigate to the target page.
  project.set_dart_entrypoint_arguments(Utf8CommandLineArguments());
  // Prefer the discrete GPU when the machine has more than one.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
  // Do NOT call set_ui_thread_policy(RunOnSeparateThread) here.
  //
  // It used to be set as a defensive measure ("keep the UI isolate off the
  // platform thread so a future engine change cannot stall the message loop").
  // It turned out to be the cause of a crash on *every* window close: the
  // process died with 0xc0000005 inside coremessaging.dll (the component that
  // dispatches thread messages), always at the same offset, 120 occurrences
  // since July. Measured with the option toggled: 4 of 4 closes crashed with it
  // on, and every close exited cleanly with it off. The default (which the
  // stock Flutter win32 runner relies on) already runs the UI isolate on its own
  // thread - the call only pinned a policy that already held.
  app.controller = std::make_unique<flutter::FlutterViewController>(bounds.right, bounds.bottom, project);
  if (!app.controller->engine() || !app.controller->view()) return EXIT_FAILURE;
  RegisterPlugins(app.controller->engine());
  // Lets Dart change the title bar at runtime, without going back through
  // window_manager (whose hidden branch would be a second implementation of the
  // same arithmetic - see the title bar section above).
  RegisterWindowChannel(app.controller->engine()->messenger(), window);
  // The channel a redirected player launch talks to ("switch this window to
  // video X"). Registers once the engine is live, and flushes any video that
  // arrived while it was still booting.
  if (play_window) RegisterPlayWindowChannel(app.controller->engine()->messenger());
  // NOTE: do NOT register DesktopMultiWindowSetWindowCreatedCallback here.
  // The multi-engine child window is incompatible with this hand written runner:
  // as soon as a child window is created, the main window keeps pumping messages
  // (IsHungAppWindow stays false) but its Flutter engine stops processing input
  // and never repaints again. Keep this runner free of the multi window plugin
  // until the runner is replaced by the stock FlutterWindow template.
  //
  // The desktop_multi_window dependency has since been removed from pubspec.yaml
  // (playback windows are separate processes, see --play-window above), so the
  // plugin is no longer even compiled in. This note stays as the reason not to
  // bring it back.
  const auto flutter_view = app.controller->view()->GetNativeWindow();
  SetParent(flutter_view, window);
  // Showing the window above happened before the Flutter view existed, so that
  // WM_SIZE was swallowed and nothing has sized the view yet. SetParent also
  // keeps the old screen coordinates, so stretch it over the client area here.
  GetClientRect(window, &bounds);
  MoveWindow(flutter_view, 0, 0, bounds.right, bounds.bottom, TRUE);
  // The Flutter view would cover the splash right away. Keep it hidden until the
  // minimum splash time has passed so the design lockup is actually readable
  // (on an idle machine the engine is ready in a couple of hundred ms).
  // Player windows use a much shorter floor: the user just clicked a cover, so
  // the priority is getting the video on screen, not branding.
  const auto splash_min = play_window ? 250 : kSplashMinDurationMs;
  const auto splash_elapsed = static_cast<int>(GetTickCount64() - splash_started);
  if (splash_elapsed < splash_min) {
    ShowWindow(flutter_view, SW_HIDE);
    SetTimer(window, kSplashTimerId, static_cast<UINT>(splash_min - splash_elapsed), nullptr);
  } else {
    app.splash_visible = false;
    SetFocus(flutter_view);
  }
  // Repaint the parent once so the logo cannot linger in any area the view does
  // not paint yet (the engine still has to render its first frame).
  InvalidateRect(window, nullptr, FALSE);
  UpdateWindow(window);
  app.controller->engine()->SetNextFrameCallback([window]() { ShowWindow(window, SW_SHOWNORMAL); });
  app.controller->ForceRedraw();

  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  // Deliberately no CoUninitialize() here.
  //
  // The plugins keep WinRT/COM objects alive past the message loop - the toast
  // notifier and WebView2 both run on the Windows composition stack
  // (CoreMessaging.dll, Windows.UI.dll, CoreUIComponents.dll are all in the
  // crash module list). Releasing those objects after the apartment has been
  // torn down faults inside coremessaging.dll, which is exactly what every
  // window close used to do (0xc0000005 at a fixed offset, 120 occurrences since
  // July). Letting the OS reclaim the apartment at process death is the
  // standard way out; the thread's apartment is not reused afterwards.
  if (instance_mutex != nullptr) CloseHandle(instance_mutex);
  if (play_window_mutex != nullptr) CloseHandle(play_window_mutex);
  return EXIT_SUCCESS;
}
