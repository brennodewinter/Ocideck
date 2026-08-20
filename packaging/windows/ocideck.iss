; OciDeck — Windows installer (Inno Setup 6.3 or newer).
;
; What this is, and deliberately is not (#1208). This script wraps *exactly* the
; bundle `make build-windows` leaves in build\windows\x64\runner\Release and adds
; the three things a Windows user expects and a raw folder cannot give: a Start
; menu shortcut, the file associations, and a clean uninstall through
; Programs and Features.
;
; It is a DUMB, OFFLINE installer, and that is the hard boundary. There is no
; auto-update, no version check, no release feed, no "a new version is
; available", and nothing here reaches the network at install time or after.
; SECURITY.md promises that OciDeck does not phone home and that a fix reaches
; you by pulling the default branch and rebuilding; an installer that could
; update itself would break that promise for convenience. The convenience is
; worth having, the update channel is not — `test/windows_packaging_test.dart`
; holds that line so it cannot creep back in unnoticed.
;
; The registry block below is the same set of keys as
; windows\file-associations.reg, which stays the hand-import route for people who
; run from the raw bundle. The two must not drift; the same test compares them.
;
; Build it with scripts/build_windows_installer.sh (never by opening this file in
; the Inno IDE and pressing F9 — the script is what passes the version in and
; runs the optional signing step).

#define AppName "OciDeck"
#define AppPublisher "Stichting LibreKAT"
#define AppUrl "https://pawprint.vigilis.online/LibreKAT/Ocideck"
#define ExeName "ocideck.exe"
#define ProgId "OciDeck.Package"

; The version is passed in by scripts/build_windows_installer.sh
; (ISCC /DAppVersion=x.y.z), read there from pubspec.yaml — so a release still
; has exactly one place where a version number is bumped, and this file never
; becomes a second one to forget. The fallback only exists so a bare `iscc` run
; fails on something legible rather than on an undefined symbol.
#ifndef AppVersion
  #define AppVersion "0.0.0-unset"
#endif

; Where `make build-windows` puts the bundle, relative to this file. The
; packager may override it (/DBundleDir=…) so that the directory it guards and
; signs is provably the directory that gets packed — two defaults that agree
; today can drift apart silently the day someone overrides only one of them.
#ifndef BundleDir
  #define BundleDir "..\..\build\windows\x64\runner\Release"
#endif

[Setup]
; Never change AppId: Windows keys the installed-program identity and every
; upgrade-in-place on it. A new GUID would leave the old install orphaned in
; Programs and Features next to the new one.
AppId={{5AEB475C-9E67-475B-BB99-F52816B739C8}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppUrl}
AppSupportURL={#AppUrl}/issues
; A static link in the Programs and Features entry, not a check: nothing here
; ever fetches it. It points at the channel SECURITY.md names as *the* way you
; find out a fix exists — the repository itself — precisely because the app will
; never tell you.
AppUpdatesURL={#AppUrl}/releases
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
UninstallDisplayIcon={app}\{#ExeName}
; Without this, Setup registers the associations but never tells Explorer to
; refresh them — .ocideck files keep their blank icon and old handler until the
; user logs out. Uninstall gets the same refresh.
ChangesAssociations=yes
; Plain-text licence, generated from LICENSE.md by tool/generate_license_txt.dart
; (#1600). Inno Setup shows LicenseFile content verbatim on the first page a
; Windows user sees — feeding it the Markdown source rendered the HTML comment,
; #/##/**/> markers and --- rules literally. The .txt is committed and pinned
; fresh by test/windows_packaging_test.dart.
LicenseFile=LICENSE.txt
OutputDir=..\..\dist
OutputBaseFilename=ocideck-windows-x64-setup-{#AppVersion}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
; Flutter's Windows embedder is x64-only and needs Windows 10 or newer; refuse
; up front rather than installing something that cannot start. The
; `x64compatible` spelling (which also covers ARM64 running x64 code) needs
; Inno Setup 6.3 or newer — see docs/BUILD.md.
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0
; Default to a machine-wide install (Program Files, associations for everyone),
; but let someone without admin rights pick a per-user install instead. HKA in
; [Registry] and {autopf}/{autodesktop} above follow that choice automatically,
; which is why the same key list serves both.
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog

[Languages]
Name: "en"; MessagesFile: "compiler:Default.isl"
Name: "nl"; MessagesFile: "compiler:Languages\Dutch.isl"

[Tasks]
Name: "desktopicon"; Description: "{cm:CreateDesktopIcon}"; GroupDescription: "{cm:AdditionalIcons}"; Flags: unchecked

[Files]
Source: "{#BundleDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#ExeName}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#ExeName}"; Tasks: desktopicon

[Registry]
; Same ProgID and same key shapes as windows\file-associations.reg. .ocideck
; becomes ours outright; .md only joins the "Open with…" list and never takes
; the default away from whatever the user already uses for Markdown.
Root: HKA; Subkey: "Software\Classes\{#ProgId}"; ValueType: string; ValueName: ""; ValueData: "OciDeck presentation package"; Flags: uninsdeletekey
Root: HKA; Subkey: "Software\Classes\{#ProgId}\DefaultIcon"; ValueType: string; ValueName: ""; ValueData: "{app}\{#ExeName},0"
Root: HKA; Subkey: "Software\Classes\{#ProgId}\shell\open\command"; ValueType: string; ValueName: ""; ValueData: """{app}\{#ExeName}"" ""%1"""
Root: HKA; Subkey: "Software\Classes\.ocideck"; ValueType: string; ValueName: ""; ValueData: "{#ProgId}"; Flags: uninsdeletevalue
; ValueType none would create only the KEY and silently drop the value —
; Explorer reads value NAMES under OpenWithProgids, so the "Open with…" entry
; would simply never exist. An empty REG_SZ named after the ProgID is the
; documented shape (the .reg file writes the REG_NONE equivalent).
Root: HKA; Subkey: "Software\Classes\.md\OpenWithProgids"; ValueType: string; ValueName: "{#ProgId}"; ValueData: ""; Flags: uninsdeletevalue

[Run]
Filename: "{app}\{#ExeName}"; Description: "{cm:LaunchProgram,{#AppName}}"; Flags: nowait postinstall skipifsilent
