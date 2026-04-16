#include "flutter_window.h"

#include <optional>
#include <string>

#include "flutter/generated_plugin_registrant.h"

namespace {

int ExtractUnreadCount(const flutter::EncodableValue* arguments) {
  if (arguments == nullptr) {
    return 0;
  }
  const auto* map = std::get_if<flutter::EncodableMap>(arguments);
  if (map == nullptr) {
    return 0;
  }
  const auto count_key = flutter::EncodableValue("count");
  const auto entry = map->find(count_key);
  if (entry == map->end()) {
    return 0;
  }
  if (const auto* value = std::get_if<int32_t>(&entry->second)) {
    return *value;
  }
  if (const auto* value = std::get_if<int64_t>(&entry->second)) {
    return static_cast<int>(*value);
  }
  return 0;
}

std::wstring BadgeLabelForCount(int count) {
  if (count <= 0) {
    return L"";
  }
  if (count > 99) {
    return L"99+";
  }
  return std::to_wstring(count);
}

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
  SetChildContent(flutter_controller_->view()->GetNativeWindow());
  RegisterShellChannel();
  if (taskbar_list_ == nullptr) {
    if (SUCCEEDED(CoCreateInstance(CLSID_TaskbarList, nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&taskbar_list_)))) {
      taskbar_list_->HrInit();
    }
  }
  base_title_ = L"The Vault";
  SetUnreadCount(unread_count_);

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
  shell_channel_.reset();
  ClearUnreadOverlay();
  if (taskbar_list_ != nullptr) {
    taskbar_list_->Release();
    taskbar_list_ = nullptr;
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
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

void FlutterWindow::RegisterShellChannel() {
  shell_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "the_vault/windows_shell",
          &flutter::StandardMethodCodec::GetInstance());

  shell_channel_->SetMethodCallHandler(
      [this](const auto& call, auto result) {
        if (call.method_name().compare("setUnreadCount") == 0) {
          SetUnreadCount(ExtractUnreadCount(call.arguments()));
          result->Success();
          return;
        }
        result->NotImplemented();
      });
}

void FlutterWindow::SetUnreadCount(int count) {
  if (taskbar_list_ == nullptr || GetHandle() == nullptr) {
    unread_count_ = count;
    return;
  }

  unread_count_ = count;
  ClearUnreadOverlay();
  UpdateWindowTitle();
  if (count <= 0) {
    taskbar_list_->SetOverlayIcon(GetHandle(), nullptr, L"No unread messages");
    return;
  }

  unread_overlay_icon_ = CreateUnreadOverlayIcon(count);
  if (unread_overlay_icon_ == nullptr) {
    return;
  }

  const auto label = BadgeLabelForCount(count);
  taskbar_list_->SetOverlayIcon(GetHandle(), unread_overlay_icon_,
                                label.c_str());
}

void FlutterWindow::ClearUnreadOverlay() {
  if (taskbar_list_ != nullptr && GetHandle() != nullptr) {
    taskbar_list_->SetOverlayIcon(GetHandle(), nullptr, L"");
  }
  if (unread_overlay_icon_ != nullptr) {
    DestroyIcon(unread_overlay_icon_);
    unread_overlay_icon_ = nullptr;
  }
}

void FlutterWindow::UpdateWindowTitle() {
  if (GetHandle() == nullptr) {
    return;
  }

  std::wstring title = base_title_;
  if (unread_count_ > 0) {
    title += L" (";
    title += BadgeLabelForCount(unread_count_);
    title += L")";
  }
  SetWindowTextW(GetHandle(), title.c_str());
}

HICON FlutterWindow::CreateUnreadOverlayIcon(int count) const {
  constexpr int kIconSize = 32;
  void* dib_bits = nullptr;

  HDC screen_dc = GetDC(nullptr);
  if (screen_dc == nullptr) {
    return nullptr;
  }
  HDC memory_dc = CreateCompatibleDC(screen_dc);
  if (memory_dc == nullptr) {
    ReleaseDC(nullptr, screen_dc);
    return nullptr;
  }

  BITMAPV5HEADER bitmap_header = {};
  bitmap_header.bV5Size = sizeof(BITMAPV5HEADER);
  bitmap_header.bV5Width = kIconSize;
  bitmap_header.bV5Height = -kIconSize;
  bitmap_header.bV5Planes = 1;
  bitmap_header.bV5BitCount = 32;
  bitmap_header.bV5Compression = BI_BITFIELDS;
  bitmap_header.bV5RedMask = 0x00FF0000;
  bitmap_header.bV5GreenMask = 0x0000FF00;
  bitmap_header.bV5BlueMask = 0x000000FF;
  bitmap_header.bV5AlphaMask = 0xFF000000;

  HBITMAP color_bitmap = CreateDIBSection(
      memory_dc, reinterpret_cast<BITMAPINFO*>(&bitmap_header), DIB_RGB_COLORS,
      &dib_bits, nullptr, 0);
  if (color_bitmap == nullptr || dib_bits == nullptr) {
    if (color_bitmap != nullptr) {
      DeleteObject(color_bitmap);
    }
    DeleteDC(memory_dc);
    ReleaseDC(nullptr, screen_dc);
    return nullptr;
  }

  auto* pixels = static_cast<uint32_t*>(dib_bits);
  for (int index = 0; index < kIconSize * kIconSize; ++index) {
    pixels[index] = 0x00000000;
  }

  HBITMAP old_bitmap =
      reinterpret_cast<HBITMAP>(SelectObject(memory_dc, color_bitmap));
  HBRUSH badge_brush = CreateSolidBrush(RGB(220, 58, 74));
  auto old_brush = reinterpret_cast<HBRUSH>(SelectObject(memory_dc, badge_brush));
  auto old_pen = SelectObject(memory_dc, GetStockObject(NULL_PEN));
  Ellipse(memory_dc, 2, 2, kIconSize - 2, kIconSize - 2);

  const auto label = BadgeLabelForCount(count);
  HFONT badge_font = CreateFontW(
      count > 99 ? -10 : -14, 0, 0, 0, FW_BOLD, FALSE, FALSE, FALSE,
      DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS,
      CLEARTYPE_QUALITY, DEFAULT_PITCH | FF_DONTCARE, L"Segoe UI");
  auto old_font = SelectObject(memory_dc, badge_font);
  SetBkMode(memory_dc, TRANSPARENT);
  SetTextColor(memory_dc, RGB(255, 255, 255));
  RECT text_bounds = {0, 0, kIconSize, kIconSize};
  DrawTextW(memory_dc, label.c_str(), static_cast<int>(label.size()),
            &text_bounds, DT_CENTER | DT_VCENTER | DT_SINGLELINE);

  for (int index = 0; index < kIconSize * kIconSize; ++index) {
    const uint32_t rgb = pixels[index] & 0x00FFFFFF;
    if (rgb != 0) {
      pixels[index] = rgb | 0xFF000000;
    }
  }

  HBITMAP mask_bitmap = CreateBitmap(kIconSize, kIconSize, 1, 1, nullptr);
  ICONINFO icon_info = {};
  icon_info.fIcon = TRUE;
  icon_info.hbmMask = mask_bitmap;
  icon_info.hbmColor = color_bitmap;
  HICON icon = CreateIconIndirect(&icon_info);

  SelectObject(memory_dc, old_font);
  SelectObject(memory_dc, old_pen);
  SelectObject(memory_dc, old_brush);
  SelectObject(memory_dc, old_bitmap);
  DeleteObject(badge_font);
  DeleteObject(badge_brush);
  DeleteObject(mask_bitmap);
  DeleteObject(color_bitmap);
  DeleteDC(memory_dc);
  ReleaseDC(nullptr, screen_dc);

  return icon;
}
