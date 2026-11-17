# Standalone macOS media decoder

The macOS app includes FFmpeg 9.0.2 as a separate executable under
`Contents/Helpers/ffmpeg`. OciDeck invokes it through an argument vector;
OciDeck does not link against libav*. This particular build is LGPL-2.1-or-later:
GPL, nonfree and version3 components, autodetection of external libraries and
all network protocols are disabled. Only the manifest's demuxers/audio codecs,
PCM16 WAV encoding and resampling are enabled. Apple system libraries are not
redistributed. Windows keeps Media Foundation and Linux keeps GStreamer.

The full, unmodified, SHA-256-pinned source archive travels with the same app
under `Contents/Resources/ffmpeg`, together with the manifest, configure flags,
build script, upstream licence output and build-stage executable hash. The
archive includes all upstream copyright and licence files. `assets/licenses/`
also carries the complete LGPL text for the application's licence page.
The hash in `binary.sha256` is from the build **before code signing**; Developer
ID signing changes the Mach-O signature and therefore the whole-file hash.

To rebuild, put the included `manifest.json` under `native/media_decoder/`,
the build script under `scripts/`, and the included source archive under
`native/media_decoder/build/` in an empty directory. Run
`scripts/build_media_decoder.sh` on the corresponding macOS architecture.
Only Apple command-line tools, Python 3, curl, tar and make are required.
The archive is checked before extraction; no third-party executable is used.

You may modify and replace this standalone LGPL component and debug or reverse
engineer it for that purpose. Copy your replacement to `Contents/Helpers/ffmpeg`.
Changing a signed app invalidates its code signature: sign the replacement and
reseal your local copy of the app (ad-hoc signing is sufficient for a local
build), as `bundle_media_decoder.sh` demonstrates. Do not submit your modified
copy as an official OciDeck release. The component remains separately licensed;
OciDeck's EUPL licence does not restrict these LGPL rights.

This is an audio decoder. It does not decode the video track or download URLs.
Its successful tone-fixture matrix proves decoding, not speech recognition.
