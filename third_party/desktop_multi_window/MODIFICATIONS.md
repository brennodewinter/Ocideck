# Modifications to `desktop_multi_window`

This directory is a **modified copy** of the `desktop_multi_window` package by
Mixin, licensed under the **Apache License, Version 2.0** (see [`LICENSE`](LICENSE),
© 2021 Mixin). Apache-2.0 §4(b) requires modified files to carry a prominent
notice; this file records what was changed, and each changed file carries a
notice of its own at the top.

**Upstream:** <https://github.com/MixinNetwork/flutter-plugins>
**Branched from commit:** `58a5868d1cb9031defa5db5868d6aaea0486d24a`
(2026-02-24, `packages/desktop_multi_window`), package version 0.3.0.
**Modified by:** the OciDeck project (Brenno de Winter), from 2026-06-06.

Every file in this directory is byte-identical to that upstream commit except
the six listed below. That was verified by hashing the upstream package subtree
at the commit and comparing it with this copy.

## Why the fork exists

The published 0.3.0 dropped the native window-geometry calls the dual-screen
presenter needs: placing the audience window on a chosen screen, filling that
screen borderlessly, and closing it again. Without them the beamer window cannot
be positioned, and the presenter's keyboard focus cannot be kept on the laptop.

## What was changed

| File | Change |
| --- | --- |
| `lib/src/window_controller.dart` | Added `close()`, `setFrame(Rect)` and `coverScreen({external, presenterScreen})` to the Dart API. `presenterScreen` targets the screen the presenter is *not* on, overriding the `external` heuristic (#1913). |
| `macos/Classes/FlutterWindow.swift` | Implemented `window_close`, `window_setFrame` and `window_coverScreen`. The cover window is borderless, sits at `.statusBar` level so it hides the menu bar/notch on the beamer, joins all Spaces, and is ordered front *without* becoming key so keyboard focus stays with the presenter. `window_coverScreen` honours an optional `presenterScreen` index to cover the screen the presenter is not on (#1913). |
| `macos/Classes/FlutterMultiWindowPlugin.swift` | Set `mouseTrackingMode = .inActiveApp` on the sub-window's `FlutterViewController`, so hover events reach a window that is never key (chart hover on the beamer). Also skip the window being registered or created when broadcasting `onWindowsChanged` (in both `AttachWindow` and `CreateWindow`): its Flutter engine's platform-message handler is not installed yet, so sending to it made `FlutterEngineSendPlatformMessage` fail with `kInvalidArguments` — as the first log line on startup (main window) and again when the audience window opens. |
| `windows/flutter_window_wrapper.h` | Implemented `window_close`, `window_setFrame` and `window_coverScreen` on Win32, including monitor enumeration to pick the external display. `window_coverScreen` honours an optional `presenterScreen` index (#1913). |
| `linux/flutter_window.cc` | Implemented `window_close` (destroying the GTK window on idle), `window_setFrame` and `window_coverScreen` with GDK monitor selection. `window_coverScreen` honours an optional `presenterScreen` index (#1913). |
| `linux/multi_window_manager.cc` | Stopped removing the `FlView` from its container on window destroy; letting GTK tear the view down with the window avoids `FlutterEngineRemoveView` errors. |

## Keeping it honest

`tool/sbom_build.dart` records the upstream URL, this commit and a SHA-256 tree
hash of this directory in the SBOM; `make sbom-verify` recomputes the hash, so
an edit here that is not committed alongside a regenerated SBOM fails the gate.

If you bump upstream, re-apply these six changes, re-test the dual-screen
presenter on all three desktop platforms, and update the commit above.
