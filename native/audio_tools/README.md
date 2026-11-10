# Native desktop audio helpers

OciDeck builds and installs `ocideck-audio[.exe]` beside the app. These are
project sources under EUPL-1.2, not redistributed FFmpeg executables.

- Windows: `--decode INPUT OUTPUT` uses Media Foundation to produce 16 kHz,
  mono PCM16 WAV. Windows N/KN requires Microsoft's Media Feature Pack.
- Linux: the same decode command uses a fixed GStreamer pipeline. User paths
  are properties, never pipeline syntax. `--list-sources` enumerates libpulse
  sources; `--capture [SOURCE]` emits 48 kHz stereo PCM16 on stdout. This
  works with PulseAudio and PipeWire's PulseAudio-compatible server without
  `parecord` or `pactl`. No application is installed or downloaded at runtime.
- Exit 3 means a container has no audio track; other failures are nonzero.
  Failed decoding removes the partial output. OciDeck supplies a private
  staging destination, an environment allowlist and a ten-minute deadline.

The Linux packages declare GStreamer/base/good/libav and libpulse. Standalone
Linux bundles use the same declared system libraries as the video backends.
The direct Flatpak also inventories codec plugins missing from its GNOME
runtime, with their dependent libraries, notices, hashes and matching sources.

`integration_test/desktop_audio_test.dart` runs the installed decoder against
synthetic MP3/M4A/MP4 fixtures and a video with no audio. The native
`ocideck_track_capture_test` target compiles the production per-track WebRTC
sink against the same headers/library as OciDeck. It verifies separate sources,
PCM ownership, post-mute gating, cancellation and bounded backpressure. Build
that explicit CMake target after the app and run it from `native_audio_tests/`.
GitHub desktop CI runs these checks for Linux and Windows alongside the real
Mermaid/MathJax document-PDF integration test.

`test/offscreen_renderer_test.cc` can also be built with the vendored GTK
webview and WebKitGTK pkg-config flags. Its argument is the HTML emitted by
MermaidRenderService; under Xvfb it requires three SVG responses (flowchart,
Gantt and formula). This isolates the real native renderer from Flutter.
A VM's native-component checks do not establish physical device or real-call
behaviour; the existing Jitsi two-client integration test remains required
for that evidence on each OS.
