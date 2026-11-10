# OciDeck per-track desktop audio capture

Based on LibreKAT/flutter_webrtc commit
`b82f0db567e10aecd152c4039336d09e48f295a8` (upstream
flutter_webrtc v1.6.2+hotfix.4). Original MIT licence and notices retained.
Only Git-tracked source is vendored, not downloaded WebRTC binaries.
The upstream example application is omitted; Dart sources are formatted using
the repository SDK and two current analyzer lints are resolved.

OciDeck adds the missing Windows/Linux handlers for startAudioTrackCapture and
stopAudioTrackCapture. Each attaches a libwebrtc AudioTrackSink to one live
track. PCM is copied on the audio thread and delivered on the platform runner;
queue capacity, capture count and formats are bounded. Backpressure reports an
error instead of silently claiming a complete recording. Stopping removes the
sink and invalidates queued delivery. Disabled tracks are excluded both natively
and in OciDeck's post-mute gate. The Dart wrapper handles native format/capacity
errors and cancellation during a failed start.

New native capture files are licensed under EUPL-1.2 by Stichting LibreKAT;
modifications to the existing MIT files remain under MIT. Apple and browser
capture implementations are inherited unchanged. The download/version manifest
for libwebrtc remains the original pinned manifest. Remove this vendor when
the equivalent native capture implementation is available in the pinned fork.

Native binary downloads/extraction live in the CMake build directory, not the
vendored source directory. This keeps source hashes and source kits stable
after a native build. The native test target reads the same resolved library
directory from the production plugin target.
