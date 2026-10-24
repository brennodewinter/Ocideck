#ifndef RUNNER_SYSTEM_CAPTURE_H_
#define RUNNER_SYSTEM_CAPTURE_H_

#include <flutter/binary_messenger.h>

#include <windows.h>

// Apart van de microfoonpost, zodat een mic-`open` nooit de uitvoermix pakt.
constexpr UINT kSystemCaptureMessage = WM_APP + 0x4E;

void RegisterSystemCapture(flutter::BinaryMessenger* messenger, HWND window);
void ShutdownSystemCapture();
void HandleSystemCaptureMessage(WPARAM wparam, LPARAM lparam);

#endif  // RUNNER_SYSTEM_CAPTURE_H_
