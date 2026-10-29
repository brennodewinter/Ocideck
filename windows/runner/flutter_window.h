#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/encodable_value.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>

#include <memory>

#include "win32_window.h"

// Gedeeld met main.cpp (#2627): het dwData-signatuur van de WM_COPYDATA die
// een tweede starter naar het draaiende exemplaar stuurt, en de venster-
// eigenschap waarmee dat exemplaar zich als primaire herkenbaar maakt.
constexpr ULONG_PTR kOpenFilesCopyDataId = 0x0C1DE001;
constexpr wchar_t kPrimaryInstanceProp[] = L"OciDeckPrimaryInstance";

// A window that does nothing but host a Flutter view.
class FlutterWindow : public Win32Window {
 public:
  // Creates a new FlutterWindow hosting a Flutter view running |project|.
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  // Win32Window:
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  // Handelt een WM_COPYDATA van een tweede starter af: de meegegeven paden
  // gaan via het open_file-kanaal naar Dart. Geeft true als de melding voor
  // ons was (#2627).
  bool HandleOpenFilesCopyData(HWND hwnd, LPARAM lparam) noexcept;

  // The project to run.
  flutter::DartProject project_;

  // The Flutter instance hosted by this window.
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;

  // Kanaal waarlangs een tweede starter zijn bestanden doorgeeft — dezelfde
  // `ocideck/open_file` als de macOS-host gebruikt (#2627).
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      open_file_channel_;
};

#endif  // RUNNER_FLUTTER_WINDOW_H_
