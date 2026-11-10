#ifndef RUNNER_TRASH_CHANNEL_H_
#define RUNNER_TRASH_CHANNEL_H_
#include <flutter/binary_messenger.h>
#include <windows.h>
void RegisterTrashChannel(flutter::BinaryMessenger* messenger, HWND owner);
#endif
