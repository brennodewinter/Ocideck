# Explicit YouTube source practice evidence

The JSON records contain hashes/counts/control assertions, not provider caption
text or audio. `provenance.json` identifies the production/probe revision and
exact source-file/component/evidence hashes. The native client and widget
reports retain their own tested revisions; later changes affect probe reporting,
not the already measured production paths. The final pre-merge gate is recorded
on the PR's exact final head, after this evidence commit.

| Actual route | Result |
|---|---|
| Native production source/ASR HTTP clients | Manual and automatic captions; 25-second source fragment; full 19-second video; edited Markdown saved and reopened byte-for-byte |
| Native production widgets in Flutter test harness | URL-open proposal, ordinary Markdown-link deck action, video-slide editor action; identical manual-caption document apart from processing date; original deck unchanged |
| Compiled production web clients | Chromium 156.0.8078.4 and WebKit 27.2, real TLS/CORS source and ASR endpoints, production CSP and local CanvasKit; manual/automatic captions and four ASR segments with original 10–35 second source clock |
| Real provider-job cancellation | HTTP peer closed after observing the actual downloader process; no live group members or new private staging after 461 ms; subsequent metadata request succeeded |
| Fresh isolated operator install | Both pinned wheels, official Node and complete notices verified; optional existing signed FFmpeg/source/notices registered read-only |

`M7lc1UVf-VE` has 158 advertised tracks. Its automatic rolling VTT has 1,132
input display cues and 61,976 characters before deduplication; the resulting
571 cues contain 20,635 characters. Only suffix/prefix carry-over in overlapping
or contiguous display cues is removed; gaps reset the chain. Manual captions
remain 466 cues/20,211 characters. These are structural controls, not a manual
accuracy assessment of every caption.

The 10–35 second PCM fragment is exactly 800,044 bytes / 400,000 mono PCM16
frames at 16 kHz, source offset 10 seconds. Native, Chromium and WebKit receive
the same audio digest and yield the same ASR text digest/four timed segments.
The whole short-video test uses `jNQXAC9IVRw`, yields three ASR segments and
retains zero source offset. Source audio is removed/released after use.

`aqz-KE-bpKQ` actually reports **zero captions** and offers audio. Its selected
0–25 second fragment was downloaded, decoded and sent to the real ASR backend.
That fragment produced **zero speech segments**: document creation was correctly
refused. This is evidence of the audio/no-speech path, not a successful speech
transcript or a quality claim. `BaW_jenozKc` actually returned the typed `access`
error. Synthetic contract tests separately cover other error/cancellation paths;
we did not deliberately trigger provider rate limiting or access private videos.

The operator server used verified macOS ARM64 Python 3.15.2, yt-dlp 2026.10.26,
yt-dlp-ejs 0.8.0 and Node 22.23.5. ASR is the separately configured, local
Whisper-base ASR v1 reference server from `testbed/asr-multilingual`, using its
pinned model/runtime. This does not imply accurate arbitrary speech, diarization,
unbounded media downloads, or a source-extraction binary bundled with the app.
The separate fresh-install report verifies the same component hashes; the live
servers used the preceding clean private install of those identical components.

The browser driver alone accepts its explicit loopback test certificate in
isolated contexts. There is no app certificate/CSP bypass, wildcard CORS or
public fallback. The compiled probe registers an empty asset-root collector to
model the app's tabs ownership; an unregistered global store deliberately does
not garbage-collect unknown roots. This is not evidence of a full browser
save/download dialog, model install or packaged release workflow.

Windows/Linux source helpers and full packaged release flows on all OS/browser
combinations remain **not tested**, visibly qualified in the proposal. Those
release/hardware requirements remain tracked in #2947; this evidence does not
close that issue. Native widget tests use isolated preferences/staging and the
actual production source client; they do not change the user's profile or app.
