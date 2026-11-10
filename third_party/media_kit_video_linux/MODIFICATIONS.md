# Linux-only native registration for media_kit_video

Upstream: media_kit_video 2.0.1, https://pub.dev/packages/media_kit_video/versions/2.0.1
Licence: MIT; the upstream LICENSE is retained.

Only the Linux plugin is registered in pubspec.yaml. Linux sources are unchanged. VideoController requests a frame after registering
its post-frame initialization callback, so an otherwise idle slide does not
wait indefinitely for a frame. The default decoder is software (`hwdec=no`): the video_player adapter treats
hardware codec probe errors as fatal even when mpv falls back successfully.
Explicit controller configuration can still select hardware decoding. The
texture renderer retains upstream hardware acceleration and software fallback. Other native platform sources and the
example are omitted.

OciDeck enables media_kit only on Linux. Windows uses video_player_win; Apple
platforms retain AVFoundation. Upstream media_kit_video registers an unused Apple
plugin without SwiftPM support, which would reintroduce CocoaPods into OciDeck's
SwiftPM-only macOS build. Restricting the registration avoids that regression.

Remove this override when upstream supports platform-selective registration or
when the application can adopt its Apple plugin without changing build tooling.

Upstream pub archive SHA-256:
`afaa509e7b7e0bf247557a3a740cde903a52c34ace9810f94500e127bd7b043d`.
