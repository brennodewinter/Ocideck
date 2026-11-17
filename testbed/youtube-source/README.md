# Explicit YouTube source adapter

This operator-installed reference server supplies video metadata, manual or
automatic captions, and bounded PCM audio to OciDeck. It is independent of the
ASR engine. The app does not install it, download its runtime, choose an endpoint
or fall back to a public extraction website.

The concrete operator runtime is **macOS ARM64**, Python **3.15.2**, yt-dlp
**2026.10.26**, yt-dlp-ejs **0.8.0**, and official Node **22.23.5**. Other operator
hosts are refused before availability. The client uses native pinned HTTP or
browser CORS; a shared protocol is not evidence that every release UI/platform
has been tested. The complete release matrix remains #2947.

## Install explicitly

Use your existing native Python 3.15.2 interpreter. The destination must not
exist. The installer verifies the two wheels and official Node archive against
`runtime_manifest.json`, creates a private venv, installs with `--no-index`,
`--no-deps`, and `--require-hashes`, and retains complete notices. It does not
change the system Python/Node or other environments.

For captions only:

```sh
python3.15 testbed/youtube-source/install_runtime.py /absolute/path/source-runtime
```

For audio, explicitly register the existing standalone FFmpeg 9.0.2 component
of a matching OciDeck macOS app. Keep its complete source/notices/recipe in the
application bundle. The installer reads that component; it does not modify,
copy or resign the app. A different version/build is refused. See
[`native/media_decoder/README.md`](../../native/media_decoder/README.md) to
rebuild/replace the separately licensed component.

```sh
python3.15 testbed/youtube-source/install_runtime.py /absolute/path/source-runtime \
  --decoder /Applications/OciDeck.app/Contents/Helpers/ffmpeg \
  --decoder-notices /Applications/OciDeck.app/Contents/Resources/ffmpeg
```

`register_decoder.py` can also create a new registration independently using
`--binary`, `--notices`, and `--output`. It checks the full source archive,
complete LGPL notice, build flags, ARM64 architecture and Apple-only dynamic
links, then records the actual executable and notice hashes. Code signing
changes the binary hash: the pre-signing `binary.sha256` in the component is
not the final app executable's hash. An app update invalidates the registration;
inspect/register the changed component explicitly.

Start the server from this checkout (omit `--decoder-registration` for captions
only):

```sh
/absolute/path/source-runtime/venv/bin/python testbed/youtube-source/source_server.py \
  --node /absolute/path/source-runtime/node-runtime/node \
  --decoder-registration /absolute/path/source-runtime/decoder-registration.json \
  --port 8866
```

It binds only `127.0.0.1`. In OciDeck's proposal, enter
`http://127.0.0.1:8866` as the source server, then explicitly fetch information.
An optional `OCIDECK_YOUTUBE_TOKEN` is matched as a bearer header; enter that
key in the proposal, not in the URL. Do not put tokens in shell arguments or
repository files. Requests, video links, source audio and caption text are not
logged.

For a browser, set `--origin` to the exact app origin and use trusted HTTPS
through `--cert`/`--key` or your own explicitly configured TLS termination. The
app CSP requires HTTPS for this separate endpoint. There is no wildcard CORS,
cookie authentication, implicit proxy or app certificate bypass. Self-signed
certificate exceptions used by isolated tests are not app settings.

## Data and bounds

Only the canonical video ID crosses the source-server boundary. Tracking,
playlist and URL credentials are not forwarded. Metadata/caption extraction
starts after the proposal's explicit fetch/action. Opening a presentation only
recognises references locally. ASR starts separately, with the existing engine,
language, diarisation and per-file destination consent.

- One provider job per server. HTTP bodies are at most 4 KiB; provider JSON
  stdout at most 4 MiB and stderr 64 KiB. A job has a 120-second deadline.
- Every downloader HTTPS connection uses a per-job authenticated loopback
  CONNECT proxy, resolves all IPv4 answers, rejects non-public/mixed answers,
  and connects to a verified numeric address. Only the documented YouTube
  extraction/media hosts and port 443 are allowed. Transfer budget: 32 MiB.
  This is transport confinement of the pinned downloader, not an OS sandbox.
- No cookies, user configuration, playlist expansion, remote JS component
  installation, arbitrary download URL, external downloader or shell.
- Downloaded compressed audio is at most 8 MiB. The registered network-disabled
  decoder streams into a private WAV capped at 64 MiB. Python's WAV reader cuts
  exact 16 kHz mono PCM16 frames; only the selected canonical WAV is returned.
  Output is at most 8 MiB (roughly 262 seconds). A requested interval beyond
  the decode/output budgets gives an explicit capacity error, with no silent
  truncation. Whole long-video captions remain available within their own cap.
- Provider captions are at most 2 MiB. HLS subtitle playlists are resolved by
  the downloader; a playlist is never treated as transcript text. Rolling
  automatic cues are deduplicated only across overlapping suffix/prefix text.
  Caption fragments retain complete overlapping cues and their real times;
  word boundaries are not invented.
- Private temporary directories are removed after success/failure/cancellation.
  HTTP disconnect and operator shutdown cancel jobs, terminate/kill process
  groups and reap the owned leader before shutdown finishes. The group ID
  remains reserved until group cleanup, including if a child exits first.
- The app accepts only validated PCM from this source-audio contract, avoiding
  full compressed-video WebAudio decoding for a short YouTube fragment. ASR
  segment times are shifted by the returned original offset. Source links,
  caption kind/language, chosen interval, engine and processing date remain in
  editable Markdown. The presentation is not overwritten.

Direct audio/video URLs use the app's own bounded transport, not this server:
8 MiB, cancellable; native redirects are revalidated/pinned and credentials and
HTTPS downgrades refused. Extensionless sources may be recognised by a bounded
HEAD request. The audio GET still requires the proposal. Browser CORS/CSP is
the boundary there. Signed query strings and URL credentials are excluded from
generated document provenance. Use ordinary local-file import for larger media.

## Licensing and evidence

The Python wheels are the specified **Unlicense** yt-dlp distribution and
**Unlicense AND MIT AND ISC** yt-dlp-ejs wheel (including meriyah/astring notices).
These are not a generic licence claim about yt-dlp standalone executables.
The full official Node licence includes its bundled third-party notices. The
optional FFmpeg component retains the separate LGPL-2.1-or-later review, full
source and replacement rights already documented for that exact app component.
None of these operator components is added to the app's bundled-helper SBOM or
automatic licence allow-list by this source adapter.

`test/python/test_youtube_*.py` covers protocol, egress and real process-control
boundaries; component fakes are identified as such. Live provider/UI results
must record the source revision, runtime/component hashes, video IDs, methods,
original time ranges and limitations. Keep public-provider audio/caption text
local unless redistribution rights have been established; hashes/counts and
protocol/control evidence suffice for repository reports. ASR text is model
output that users must review, not a guarantee supplied by YouTube metadata.
