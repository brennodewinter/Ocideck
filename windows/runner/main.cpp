#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>
#include <cctype>
#include <cstdio>
#include <cwchar>
#include <string>
#include <vector>

#include "flutter_window.h"
#include "utils.h"

namespace {

// De vensterklasse die Win32Window::GetWindowClass registreert — hier nodig om
// het primaire venster te herkennen zonder de klasse opnieuw aan te melden.
constexpr wchar_t kFlutterWindowClass[] = L"FLUTTER_RUNNER_WIN32_WINDOW";

// Benoemde mutex die het primaire exemplaar vasthoudt (#2627). `Local\`
// scope: een tweede gebruiker op dezelfde machine krijgt een eigen OciDeck —
// dat is de bedoeling, want herstelbestanden en instellingen zijn per
// gebruiker.
constexpr wchar_t kSingleInstanceMutexName[] = L"Local\\OciDeckSingleInstance";

// Zoekt het venster van het primaire exemplaar: de Flutter-klasse én de
// eigenschap die alleen het primaire proces zet (het beamervenster deelt de
// klasse maar niet de prop, en moet hier ook niet doorheen).
HWND FindPrimaryInstanceWindow() {
  struct Context {
    HWND found = nullptr;
  } context;
  ::EnumWindows(
      [](HWND hwnd, LPARAM param) -> BOOL {
        wchar_t class_name[64]{};
        if (::GetClassNameW(hwnd, class_name, 64) == 0) return TRUE;
        if (::wcscmp(class_name, kFlutterWindowClass) != 0) return TRUE;
        if (::GetPropW(hwnd, kPrimaryInstanceProp) != nullptr) {
          reinterpret_cast<Context*>(param)->found = hwnd;
          return FALSE;
        }
        return TRUE;
      },
      reinterpret_cast<LPARAM>(&context));
  return context.found;
}

// De extensies die de bestandsassociatie mag aanleveren — dezelfde allowlist
// als `looksLikeDeckLaunchArg` in lib/platform/launch_files.dart. Alles wat
// er niet als deck uitziet (switches, flags) hoort niet geopend te worden.
bool LooksLikeDeckFile(const std::string& arg) {
  const size_t dot = arg.rfind('.');
  if (dot == std::string::npos) return false;
  std::string ext = arg.substr(dot);
  std::transform(ext.begin(), ext.end(), ext.begin(),
                 [](unsigned char c) {
                   return static_cast<char>(std::tolower(c));
                 });
  return ext == ".md" || ext == ".ocideck" || ext == ".zip";
}

// Stuurt de te openen bestanden naar het primaire venster en haalt het naar
// voren. `true` alleen als het venster binnen twee seconden antwoordt.
// SendMessage zonder time-out hing de tweede starter onzichtbaar vast als de
// UI-thread van de primaire bezet was (#2679).
bool HandoffToPrimary(HWND primary, const std::vector<std::string>& args) {
  std::string payload;
  for (const auto& arg : args) {
    if (!LooksLikeDeckFile(arg)) continue;
    if (!payload.empty()) payload.push_back('\n');
    payload += arg;
  }
  COPYDATASTRUCT data{};
  LPARAM lparam = 0;
  UINT message = WM_NULL;
  if (!payload.empty()) {
    data.dwData = kOpenFilesCopyDataId;
    data.cbData = static_cast<DWORD>(payload.size());
    data.lpData = const_cast<char*>(payload.data());
    lparam = reinterpret_cast<LPARAM>(&data);
    message = WM_COPYDATA;
  }
  DWORD_PTR result = 0;
  // De buffer van WM_COPYDATA moet blijven bestaan tot deze aanroep terug is.
  // De time-out dekt dat: bij een hangende ontvanger keren we terug zonder
  // dat de tweede starter zelf blijft hangen.
  const LRESULT sent = ::SendMessageTimeoutW(
      primary, message, 0, lparam, SMTO_ABORTIFHUNG | SMTO_BLOCK, 2000,
      &result);
  if (sent == 0) return false;
  DWORD pid = 0;
  ::GetWindowThreadProcessId(primary, &pid);
  if (pid != 0) ::AllowSetForegroundWindow(pid);
  ::ShowWindow(primary, SW_RESTORE);
  ::SetForegroundWindow(primary);
  return true;
}

// Het primaire venster bestaat pas ná Create. Tijdens opstarten of
// afsluiten is de mutex er al wel, en een tweede starter zou anders stil
// stoppen (#2679).
HWND PollPrimaryWindow() {
  for (int attempt = 0; attempt < 10; ++attempt) {
    if (HWND found = FindPrimaryInstanceWindow()) return found;
    ::Sleep(300);
  }
  return nullptr;
}

// Opnieuw proberen wacht nog een ronde. Annuleren stopt deze starter;
// stil EXIT_SUCCESS zonder venster of melding is precies de klacht.
bool UserWantsRetry(const wchar_t* why) {
  std::fwprintf(stderr, L"ocideck: tweede start: %s\n", why);
  std::fflush(stderr);
  const int answer = ::MessageBoxW(
      nullptr, L"OciDeck is nog bezig met opstarten of afsluiten.", L"OciDeck",
      MB_RETRYCANCEL | MB_ICONINFORMATION | MB_SETFOREGROUND);
  return answer == IDRETRY;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  // Eén exemplaar (#2627): elke dubbelklik op een `.md`/`.ocideck` en elke
  // klik op de snelkoppeling zou anders een tweede proces starten dat de
  // herstelmap en het instellingenbestand van het draaiende deelt. Het
  // beamervenster (`multi_window`) is bewust een tweede proces en gaat hier
  // altijd doorheen.
  const bool is_beamer_child = !command_line_arguments.empty() &&
                               command_line_arguments[0] == "multi_window";
  HANDLE single_instance_mutex = nullptr;
  if (!is_beamer_child) {
    single_instance_mutex =
        ::CreateMutexW(nullptr, TRUE, kSingleInstanceMutexName);
    if (single_instance_mutex != nullptr &&
        ::GetLastError() == ERROR_ALREADY_EXISTS) {
      for (;;) {
        HWND primary = PollPrimaryWindow();
        if (primary != nullptr &&
            HandoffToPrimary(primary, command_line_arguments)) {
          break;
        }
        const wchar_t* why = primary == nullptr
                                 ? L"geen primair venster na het wachten"
                                 : L"het primaire venster antwoordde niet";
        if (!UserWantsRetry(why)) break;
      }
      ::CloseHandle(single_instance_mutex);
      return EXIT_SUCCESS;
    }
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");
  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"ocideck", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  // Pas ná een geslaagde vensteraanmaak als primair merken: een starter die
  // nog voor OnCreate strandde mag geen doelwit voor een derde worden.
  if (single_instance_mutex != nullptr) {
    ::SetPropW(window.GetHandle(), kPrimaryInstanceProp,
               reinterpret_cast<HANDLE>(1));
  }

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  if (single_instance_mutex != nullptr) {
    ::CloseHandle(single_instance_mutex);
  }
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
