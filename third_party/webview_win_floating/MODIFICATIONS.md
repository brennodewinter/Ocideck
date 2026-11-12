# OciDeck GTK container integration

Upstream: webview_win_floating 3.0.3, https://pub.dev/packages/webview_win_floating/versions/3.0.3
Licence: BSD-3-Clause; upstream LICENSE retained.

Linux initWidgetContainer reuses the GtkFixed overlay installed by OciDeck's
primary and audience runners before the Flutter view is realized. Reparenting
an active FlView in upstream's lazy initialization stalls current Flutter's GTK
renderer. The prepared path initializes the focus/motion controller, and focus-in only
disconnects a nonzero signal handler. Empty documents (including the playback
stop URL about:blank) skip the HTTP response lookup when WebKit has no main
resource. The fallback widget hierarchy for hosts
without this overlay is unchanged. Windows C++ originally retained the upstream playback backend; examples are omitted. Windows CMake restores
SDK targets during configuration and selects the static WebView2 loader so a
clean build and the installed bundle include everything they need. Dart wrappers
receive mechanical updates for super parameters, unused imports, diagnostic
logging and Color.toARGB32(), without changing the playback API. Controller
disposal awaits native resource release so callers can stop playback and clean
up deterministically.

The overlay passes pointer input through its empty space to Flutter (#2899).
Native WebKit child windows retain their own input, so visible media controls
remain interactive. This applies to both the editor and audience windows.

The overlay is stored on GtkWindow under `ocideck-webview-container`. It creates
no browser and initiates no network traffic. Only an authorized media preview or a requested offline diagram/formula render
creates a WebKit view. Remove the fork when upstream supports an existing
container or an offscreen texture that avoids reparenting the active FlView.

Upstream pub archive SHA-256:
`40b4f6c66554d3eb9c486952b5c072e2478f9471f64e6d63e92ddc4e527b7aa8`.

## Offscreen renderer (#2860)

Controller creation now accepts `offscreen`, default false for existing video
previews. Windows sets a fixed viewport and IsVisible=false before creation
completes; later visibility calls cannot expose an offscreen controller. GTK
uses GtkOffscreenWindow, independently of the editor overlay. Controller disposal
releases that native host. OciDeck mounts no Flutter WebView widget for this mode.

The WebView2 script-channel registration now completes only after the document-
start script is installed. Dart awaits channel/delegate operations; registration
errors propagate. This prevents the renderer bootstrap racing its response
channel. A failed ExecuteScript submission reports through the retained result
rather than dereferencing a moved unique_ptr. The offline renderer serves only
its generated document over loopback because WebView2 inline HTML is limited to
2 MiB and the pinned Mermaid/MathJax bundles exceed that combined.
