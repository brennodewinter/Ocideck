#ifndef RUNNER_MIC_CAPTURE_H_
#define RUNNER_MIC_CAPTURE_H_

#include <flutter/binary_messenger.h>

#include <windows.h>

// Posted from the capture thread; handled on the UI thread so the event
// sink is never touched off-platform.
constexpr UINT kMicCaptureMessage = WM_APP + 0x4D;

void RegisterMicCapture(flutter::BinaryMessenger* messenger, HWND window);
void ShutdownMicCapture();
void HandleMicCaptureMessage(WPARAM wparam, LPARAM lparam);

#endif  // RUNNER_MIC_CAPTURE_H_
