#include "flutter_window.h"

#include <algorithm>
#include <optional>
#include <shellapi.h>

#include "resource.h"

#include "flutter/generated_plugin_registrant.h"

namespace {

constexpr char kDeviceChannelName[] = "com.biostathelper.app/device";
constexpr int kFloatingWidth = 480;
constexpr int kFloatingHeight = 270;
constexpr int kFloatingMargin = 20;
constexpr UINT kStudyNotificationMessage = WM_APP + 0x341;
constexpr UINT kStudyNotificationIcon = 28004;

}  // namespace

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  // The size here must match the window dimensions to avoid unnecessary surface
  // creation / destruction in the startup path.
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  // Ensure that basic setup of the controller was successful.
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  RegisterPlugins(flutter_controller_->engine());
  device_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), kDeviceChannelName,
          &flutter::StandardMethodCodec::GetInstance());
  device_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name() == "enterPictureInPicture") {
          result->Success(
              flutter::EncodableValue(EnterFloatingPlayback()));
          return;
        }
        if (call.method_name() == "exitPictureInPicture") {
          result->Success(flutter::EncodableValue(ExitFloatingPlayback()));
          return;
        }
        if (call.method_name() == "startFloatingWindowDrag") {
          result->Success(
              flutter::EncodableValue(StartFloatingPlaybackDrag()));
          return;
        }
        if (call.method_name() == "showStudyNotification") {
          const auto* args = std::get_if<flutter::EncodableMap>(call.arguments());
          std::string title;
          int count = 0;
          if (args != nullptr) {
            const auto text = args->find(flutter::EncodableValue("title"));
            const auto number = args->find(flutter::EncodableValue("count"));
            if (text != args->end()) {
              if (const auto* value = std::get_if<std::string>(&text->second)) title = *value;
            }
            if (number != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&number->second)) count = *value;
            }
          }
          result->Success(flutter::EncodableValue(ShowStudyNotification(title, count)));
          return;
        }
        result->NotImplemented();
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  // Flutter can complete the first frame before the "show window" callback is
  // registered. The following call ensures a frame is pending to ensure the
  // window is shown. It is a no-op if the first frame hasn't completed yet.
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (study_notification_icon_) {
    NOTIFYICONDATAW data{};
    data.cbSize = sizeof(data);
    data.hWnd = GetHandle();
    data.uID = kStudyNotificationIcon;
    Shell_NotifyIconW(NIM_DELETE, &data);
    study_notification_icon_ = false;
  }
  device_channel_.reset();
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

bool FlutterWindow::ShowStudyNotification(const std::string& title, int count) {
  if (count <= 0 || GetHandle() == nullptr) return false;
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = GetHandle();
  data.uID = kStudyNotificationIcon;
  if (!study_notification_icon_) {
    data.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
    data.uCallbackMessage = kStudyNotificationMessage;
    data.hIcon = LoadIconW(GetModuleHandleW(nullptr), MAKEINTRESOURCEW(IDI_APP_ICON));
    wcscpy_s(data.szTip, L"\u751f\u7edf\u52a9\u624b");
    if (!Shell_NotifyIconW(NIM_ADD, &data)) return false;
    study_notification_icon_ = true;
    data.uVersion = NOTIFYICON_VERSION_4;
    Shell_NotifyIconW(NIM_SETVERSION, &data);
  }
  const int size = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, title.data(),
                                      static_cast<int>(title.size()), nullptr, 0);
  if (size <= 0 || size > 32768) return false;
  std::wstring text(size, L'\0');
  MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, title.data(),
                      static_cast<int>(title.size()), text.data(), size);
  text += L" (" + std::to_wstring(count) + L")";
  data.uFlags = NIF_INFO;
  data.dwInfoFlags = NIIF_INFO | NIIF_RESPECT_QUIET_TIME;
  wcscpy_s(data.szInfoTitle, L"\u5b66\u4e60\u8ba2\u9605\u66f4\u65b0");
  wcsncpy_s(data.szInfo, text.c_str(), _TRUNCATE);
  return Shell_NotifyIconW(NIM_MODIFY, &data) != FALSE;
}

bool FlutterWindow::EnterFloatingPlayback() {
  if (is_floating_playback_) {
    return true;
  }

  const HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }

  restored_window_style_ = GetWindowLongPtr(window, GWL_STYLE);
  restored_window_ex_style_ = GetWindowLongPtr(window, GWL_EXSTYLE);
  restored_window_placement_.length = sizeof(WINDOWPLACEMENT);
  if (!GetWindowPlacement(window, &restored_window_placement_)) {
    return false;
  }

  HMONITOR monitor = MonitorFromWindow(window, MONITOR_DEFAULTTONEAREST);
  MONITORINFO monitor_info{};
  monitor_info.cbSize = sizeof(MONITORINFO);
  if (!GetMonitorInfo(monitor, &monitor_info)) {
    return false;
  }

  const UINT dpi = GetDpiForWindow(window);
  const int dpi_value = static_cast<int>(dpi);
  const int width = MulDiv(kFloatingWidth, dpi_value, 96);
  const int height = MulDiv(kFloatingHeight, dpi_value, 96);
  const int margin = MulDiv(kFloatingMargin, dpi_value, 96);
  const RECT work_area = monitor_info.rcWork;
  const int x = std::max(static_cast<int>(work_area.left),
                         static_cast<int>(work_area.right) - width - margin);
  const int y = std::max(static_cast<int>(work_area.top),
                         static_cast<int>(work_area.bottom) - height - margin);

  const LONG_PTR floating_style =
      (restored_window_style_ &
       ~(WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX | WS_MAXIMIZEBOX)) |
      WS_POPUP | WS_THICKFRAME;
  const LONG_PTR floating_ex_style =
      (restored_window_ex_style_ & ~WS_EX_APPWINDOW) | WS_EX_TOOLWINDOW |
      WS_EX_TOPMOST;

  ShowWindow(window, SW_RESTORE);
  SetWindowLongPtr(window, GWL_STYLE, floating_style);
  SetWindowLongPtr(window, GWL_EXSTYLE, floating_ex_style);
  if (!SetWindowPos(window, HWND_TOPMOST, x, y, width, height,
                    SWP_FRAMECHANGED | SWP_SHOWWINDOW)) {
    SetWindowLongPtr(window, GWL_STYLE, restored_window_style_);
    SetWindowLongPtr(window, GWL_EXSTYLE, restored_window_ex_style_);
    SetWindowPlacement(window, &restored_window_placement_);
    return false;
  }

  is_floating_playback_ = true;
  return true;
}

bool FlutterWindow::ExitFloatingPlayback() {
  if (!is_floating_playback_) {
    return true;
  }

  const HWND window = GetHandle();
  if (window == nullptr) {
    return false;
  }

  SetWindowLongPtr(window, GWL_STYLE, restored_window_style_);
  SetWindowLongPtr(window, GWL_EXSTYLE, restored_window_ex_style_);
  const bool placement_restored =
      SetWindowPlacement(window, &restored_window_placement_) != FALSE;
  const bool frame_restored =
      SetWindowPos(window, HWND_NOTOPMOST, 0, 0, 0, 0,
                   SWP_FRAMECHANGED | SWP_NOMOVE | SWP_NOSIZE |
                       SWP_NOACTIVATE | SWP_SHOWWINDOW) != FALSE;
  if (!placement_restored || !frame_restored) {
    return false;
  }

  is_floating_playback_ = false;
  SetForegroundWindow(window);
  return true;
}

bool FlutterWindow::StartFloatingPlaybackDrag() {
  const HWND window = GetHandle();
  if (!is_floating_playback_ || window == nullptr) {
    return false;
  }

  POINT cursor_position{};
  if (!GetCursorPos(&cursor_position)) {
    return false;
  }

  ReleaseCapture();
  SendMessage(window, WM_NCLBUTTONDOWN, HTCAPTION,
              MAKELPARAM(cursor_position.x, cursor_position.y));
  return true;
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == kStudyNotificationMessage) {
    const auto event = LOWORD(lparam);
    if (event == NIN_BALLOONUSERCLICK || event == WM_LBUTTONUP || event == NIN_SELECT) {
      ShowWindow(hwnd, SW_RESTORE);
      SetForegroundWindow(hwnd);
    }
    return 0;
  }
  // Give Flutter, including plugins, an opportunity to handle window messages.
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}
