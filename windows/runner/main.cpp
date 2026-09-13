#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <fcntl.h>
#include <io.h>
#include <stdio.h>

#include <filesystem>
#include <iostream>
#include <memory>
#include <string>

#include "flutter/generated_plugin_registrant.h"
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

// Splash icon side length. app_icon.ico only ships a single 64x64 image.
constexpr int kSplashIconSide = 64;

bool SystemPrefersDarkApps() {
  DWORD use_light = 1;
  DWORD size = sizeof(use_light);
  const auto status = RegGetValueW(HKEY_CURRENT_USER, L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize", L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &use_light, &size);
  return status == ERROR_SUCCESS && use_light == 0;
}

// Follow the system light/dark preference and use an M3 surface color so the
// window does not visibly jump when the first Flutter frame lands.
HBRUSH WindowBackgroundBrush() {
  static HBRUSH brush = nullptr;
  if (brush == nullptr) brush = CreateSolidBrush(SystemPrefersDarkApps() ? RGB(28, 27, 32) : RGB(253, 248, 255));
  return brush;
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

// Bring the instance that is already running to the front.
void ActivateExistingWindow() {
  const auto window = FindWindowW(kWindowClassName, nullptr);
  if (window == nullptr) return;
  if (!IsWindowVisible(window)) ShowWindow(window, SW_SHOW);
  if (IsIconic(window)) ShowWindow(window, SW_RESTORE);
  SetForegroundWindow(window);
}

}

struct AppWindow {
  std::unique_ptr<flutter::FlutterViewController> controller;
  HINSTANCE instance = nullptr;
  UINT splash_dpi = 96;
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
  if (message == WM_GETMINMAXINFO) {
    // window_manager (registered as a plugin window proc delegate) claims this
    // message and returns 0 for it, so the switch below never sees it. Apply the
    // minimum size first, before the message is forwarded to the plugins.
    auto* info = reinterpret_cast<MINMAXINFO*>(lparam);
    const auto dpi = GetDpiForWindow(window);
    info->ptMinTrackSize.x = DpiScale(720, dpi);
    info->ptMinTrackSize.y = DpiScale(540, dpi);
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
      if (app != nullptr && app->controller == nullptr && app->instance != nullptr) {
        DrawStartupIcon(dc, client, app->instance, app->splash_dpi);
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
    case WM_DESTROY:
      PostQuitMessage(0);
      return 0;
  }
  return DefWindowProc(window, message, wparam, lparam);
}

int APIENTRY wWinMain(HINSTANCE instance, HINSTANCE, wchar_t*, int show_command) {
  const auto instance_mutex = CreateMutexW(nullptr, TRUE, kInstanceMutexName);
  if (instance_mutex != nullptr && GetLastError() == ERROR_ALREADY_EXISTS) {
    ActivateExistingWindow();
    CloseHandle(instance_mutex);
    return EXIT_SUCCESS;
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
  const auto width = DpiScale(1280, dpi);
  const auto height = DpiScale(720, dpi);
  const auto window = CreateWindow(kWindowClassName, kWindowTitle, WS_OVERLAPPEDWINDOW | WS_CLIPCHILDREN, CW_USEDEFAULT, CW_USEDEFAULT, width, height, nullptr, nullptr, instance, &app);
  if (window == nullptr) return EXIT_FAILURE;

  // Engine startup loads flutter_windows.dll plus the AOT snapshot and brings up
  // the Dart VM, which takes over a second. The window already exists at this
  // point, so show the splash now instead of leaving the screen blank.
  ShowWindow(window, show_command);
  UpdateWindow(window);

  RECT bounds{};
  GetClientRect(window, &bounds);
  flutter::DartProject project(L"data");
  // Prefer the discrete GPU when the machine has more than one.
  project.set_gpu_preference(flutter::GpuPreference::HighPerformancePreference);
  // The UI isolate already runs on its own thread by default; pinning the policy
  // keeps that explicit so a future engine change cannot move it onto the
  // platform thread and stall the Win32 message loop during startup.
  project.set_ui_thread_policy(flutter::UIThreadPolicy::RunOnSeparateThread);
  app.controller = std::make_unique<flutter::FlutterViewController>(bounds.right, bounds.bottom, project);
  if (!app.controller->engine() || !app.controller->view()) return EXIT_FAILURE;
  RegisterPlugins(app.controller->engine());
  const auto flutter_view = app.controller->view()->GetNativeWindow();
  SetParent(flutter_view, window);
  // Showing the window above happened before the Flutter view existed, so that
  // WM_SIZE was swallowed and nothing has sized the view yet. SetParent also
  // keeps the old screen coordinates, so stretch it over the client area here.
  GetClientRect(window, &bounds);
  MoveWindow(flutter_view, 0, 0, bounds.right, bounds.bottom, TRUE);
  // The Flutter view now covers the startup splash. Repaint the parent once so
  // the icon cannot linger in any area the view does not paint yet (the engine
  // still has to render its first frame).
  InvalidateRect(window, nullptr, FALSE);
  UpdateWindow(window);
  SetFocus(flutter_view);
  app.controller->engine()->SetNextFrameCallback([window]() { ShowWindow(window, SW_SHOWNORMAL); });
  app.controller->ForceRedraw();

  MSG message;
  while (GetMessage(&message, nullptr, 0, 0)) {
    TranslateMessage(&message);
    DispatchMessage(&message);
  }
  CoUninitialize();
  if (instance_mutex != nullptr) CloseHandle(instance_mutex);
  return EXIT_SUCCESS;
}
