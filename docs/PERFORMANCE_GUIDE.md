# OciDeck — Performance Guide

> **Status:** current-state description of enforced limits and measured sizes · **Status last reviewed:** 2026-11-08 · **Published by:** Stichting LibreKAT

This document describes OciDeck's performance characteristics using the **actual
limits and sizes enforced in the codebase** (with `file:line` citations), plus a
few measured figures. Where a number is a hard cap in code, it is authoritative;
where it is a measured size or timing, it is labelled as such. OciDeck ships no
general latency benchmark suite, so there are deliberately no invented user-facing
timing promises here. One relative regression test does guard the local save path.

Browser copies have a **5 MiB aggregate encoded-data budget**, including base64
package data and metadata (`BrowserDeckStore.maxEncodedLength`). This differs
from the in-memory asset limit: a deck that works in memory may not fit browser
storage. Copy creation is explicit, not an autosave loop; a failed write leaves
the deck dirty. The separate consent journal retains at most 200 events.
*(Added 2026-11-08.)*

## Memory Management

### Image handling
Images are the dominant memory cost, so decoding is bounded up front:

| What | Limit | Source |
|---|---|---|
| Max image decode dimension (per axis) | **4096 px** | `lib/utils/image_limits.dart` (`kMaxImageDecodeDimension`) |
| Max in-memory image bytes | **64 MiB** *(bij het importeren, per bestand — niet een plafond voor alles wat tegelijk gedecodeerd in beeld staat)* | `lib/services/image_service.dart` (`maxImageBytes`) |
| Web `mem:` asset store (all tabs together) | **256 MiB encoded bytes** | `lib/services/web_asset_store.dart` (`maxTotalBytes`) |
| Max media (video/audio) bytes | **1 GiB** | `lib/services/image_service.dart` (`maxMediaBytes`) |
| Luminance sampling decode | **48 × 48 px** | `lib/utils/image_luminance.dart:54` |
| Carousel thumbnail / preview / full decode | `cacheWidth` **360 / 720 / 1000** | `image_carousel_picker_grid.dart`, `..._preview.dart` |
| Slide-strip thumbnail decode | **512 px** langste zijde | `slide_thumbnail.dart` (`decodeMaxEdge`) |
| Preview, presenter, beamer decode | **1024 / 2048 / 4096 px**, het vak × pixeldichtheid naar boven afgerond | `decodeEdgeForBox` |
| Export-raster decode | **2048 px** | `kExportImageDecodeEdge` (uitvoer is 1920 px) |

A decode allocates roughly `width × height × 4` bytes, so the 4096 px cap and the
64 MiB byte ceiling are two views of the same worst case (4096² × 4 ≈ 64 MiB).
Keeping source images near their on-screen size is the single most effective
optimisation.

### Asset storage
- Project assets live in dedicated subfolders (`images/`, `data/`, `logos/`,
  `themes/`); assets outside the project directory are refused on the
  render/present/export paths (containment, not just convention).
- On the web build, presentation media (images, video and audio) are held in an
  in-memory store (`mem:` scheme,
  `lib/services/web_asset_store.dart`) — so large decks consume browser tab
  memory rather than disk. The store has one **256 MiB** budget for the whole
  app/page, including every open deck and its undo/redo history plus the slide
  clipboard. Identical encoded content is SHA-256-deduplicated and charged only
  once. Unreferenced content returns its budget during the liveness sweep; a
  new unique asset is refused atomically before this total would be exceeded.
  This app-wide budget is enforced only in the browser; desktop imports can use
  the same temporary `mem:` paths but are not subject to the browser cap.

## Local save

- A repeat local save does **not** read or hash the existing `images/` directory.
  The SHA-256 content index is built only while a deck still carries a `mem:`
  image that must be materialised and deduplicated. After that first save, its
  project-relative path makes the index unnecessary (`ImageService.copyImagesToProject`).
- Image captions are collected for the whole deck and written with at most one
  read/parse/atomic-write cycle per image directory. The cost therefore grows
  with the caption data once, rather than repeatedly rewriting a growing JSON
  sidecar for every slide (`CaptionService.saveCaptions`,
  `ImageSidecarStore.writeAll`).
- Generated theme CSS, `.marprc.yml`, deck sidecars and image-metadata sidecars
  are byte-compared and left untouched when unchanged. This avoids redundant
  durable flushes while keeping atomic replacement for real changes
  (`writeStringAtomicIfChanged`).
- `test/large_deck_performance_test.dart` exercises the full `FileService.saveDeck`
  route with 150 image slides, 150 captions and 64 MiB of already stored image
  data. The image-heavy save must remain within `3 ×` the empty-project save plus
  100 ms; this relative guard is deliberately not a product latency promise.

## Rendering

- Slides render as native Flutter widgets for preview and presentation.
- Per-slide layout, rich-text plans and the text privacy scan are memoised on
  the slide object (`Expando`), not in a global LRU. A fixed global cap thrashed
  once a deck was larger than that cap, because each keystroke reads every slide
  in order. The layout and rich-text memos keep at most six geometries per slide.
- Split-run boundaries and their shared text-fit scale are computed once per
  slide-list/theme/font revision and weakly cached (`lib/services/split_run.dart`).
  The slide strip, preview, presenter, audience window and raster export then do
  constant-time index lookups instead of remeasuring every run member per slide.
- Charts use the `fl_chart` library; the categorical palette is **10 colours**
  and cycles (`index % 10`) beyond that (`lib/models/chart.dart:10`), and legend
  tiles lay out in **≤ 6 columns × 1–3 rows** (`marp_html_service_charts.dart`, `maxColumns`).
- Timeline rendering is linear in the number of events and capped at **64**
  events (`lib/models/timeline.dart`, `timelineMaxEvents`). Interactive surfaces
  keep **4–6** events in their viewport and scroll across the bounded rail;
  static exports lay out the same bounded sequence in full. Card geometry and
  text fit are measured once per content/size/style revision and reused while
  reveal animation frames only update paint and opacity.
- Mermaid diagrams render to sanitised inline SVG via a shared WebView.
  In-flight renders deduplicate by source text: N widgets asking the same
  diagram share one future instead of N WebView round trips (#2725).
- The paged document view mounts only the sheets in and around the viewport
  plus the one off-screen measurement tree; off-screen pages keep an exactly
  equal placeholder so scroll geometry does not shift (#2725).
- Slide rasterisation precaches per slide inside the capture loop, so only
  ~1 slide's images are live at once; the remaining imageCache cap during
  export is 1 GiB — far above one slide but below a whole photo deck (#2726).
- Video plays through a shared media host so only one heavy player is live.
- A Marp background may keep every authored image filter for lossless Markdown,
  but Flutter and HTML apply at most **32 filters**. This bounds Flutter's
  compositing-layer depth without rewriting the source
  (`lib/utils/marp_style_values.dart`, `kMaxRenderedMarpImageFilters`).

## Export

- PDF/PPTX exports rasterize each slide to a PNG at a default **1920 × 1080**
  (16:9) target (`lib/services/slide_rasterizer.dart`, `logicalSize` and `targetWidth`); rasterization cost
  scales with slide count and per-slide complexity.
- The slide count it scales with is the **expanded** one: an overflowing finding
  and a rich-text body longer than one slide each become several full-size slides
  before rasterization (ARCHITECTURE § *Render-time pagination*), so a deck with
  long prose costs more images than it has slides in the editor.
- HTML export pre-renders charts to inline SVG in Dart and inlines the vendored
  JS/CSS (see measured bundle sizes below). Slide images are the exception — they
  stay relative `<img src>` references and are not inlined. *Corrected 2026-07-22:
  this called the result "a self-contained file", the same overstatement corrected
  in ARCHITECTURE and USER_GUIDE on 2026-07-21.*
- Repeated `data:image` values in HTML export are charged to the cumulative
  embed budget once and referenced through one shared definition. Deck-wide
  Marp headers and footers are likewise stored once instead of copied into
  every slide section, so deck-level chrome cannot multiply the output size.

## Network limits

OciDeck makes no network calls except explicit, user-initiated ones, and each is
capped. `NetGuard` itself is SSRF/address classification only; the byte caps and
timeouts live at the call sites:

| Operation | Cap / timeout | Source |
|---|---|---|
| Deck markdown fetch/open | **32 MiB** | `file_service.dart`, `maxDeckMarkdownBytes` |
| Package (`.ocideck`/zip) | **512 MiB** | `file_service.dart`, `maxPackageBytes` |
| Style profile / logo | **16 MiB / 8 MiB** | `file_service.dart`, `maxStyleProfileBytes` / `maxStyleProfileLogoBytes` |
| CVE search fetch | **2 MiB** | `lib/services/cve_transport_io.dart:17` |
| OciServe course image | **64 MiB encoded / 4096 px per decoded axis** | `ociserve_gateway.dart`, `image_limits.dart` |
| OciServe account avatar | **5 MiB encoded / 4096 px per decoded axis** | `ociserve_gateway.dart`, `image_limits.dart` |
| Default fetch timeout | **30 s** | `lib/services/file/file_service_net.dart:63` |
| Proxy/fallback timeout | **120 s** | `lib/services/file/file_service_net.dart:49` |

The OciServe learning environment refuses feeds above **500 lessons** before it
builds course cards, charts or activity lists (`ociserve_courses_dialog.dart`,
`_maxLessons`).

## Large presentations & directory scans

`test/large_deck_performance_test.dart` also guards lossless document reparsing
at **2 000 explicit blocks/page breaks** against quadratic identity matching:
one 2 000-block reparse must cost less than `2.5 ×` four 500-block reparses.
This is a relative complexity guard, not an editing-latency promise
(`MarkdownSourceDocument.reparse`).

There is no hard slide-count limit, but responsiveness degrades with many
high-resolution media assets or complex charts. Directory scanning (used by the
deck browser and image-dedup tooling) is bounded so a pathological tree can't
hang the app:

| Scan | Ceiling | Source |
|---|---|---|
| Image-reference scan | **20 000** files, depth **32** | `lib/services/image_reference_service.dart:24,28` |
| Deck listing | **5 000** files, depth **32** | `file_service.dart`, `listDecks` defaults |
| Presentation scan (parse) | **5 000** files, depth **32**, **256 MiB** retained | `file_service.dart`, `scanPresentations` defaults |
| Content search | **20 000** files, depth **8** | `file_service.dart`, `searchDecks` defaults |

`scanPresentations` also stats each `.md` and skips any file over the 32 MiB
markdown cap *before* reading it, and stops once the retained sources would cross
the 256 MiB budget — so neither one giant file nor many valid ones can exhaust
memory.

**Optimisation tips:** compress high-resolution photos before import; keep chart
series modest (the palette cycles after 10); split very large decks; and keep
project folders reasonably shallow.

## Autosave & recovery

- Autosave ticks every **25 s** (`lib/state/tabs_provider.dart`, `_autosaveInterval`), writing an
  atomic snapshot so a crash never truncates the open file.
- A snapshot holds the deck markdown plus the two layers that are not in it: the
  user notes and the ink annotations. Three encodes per dirty tab per tick, and
  only for tabs whose deck actually changed since the last one.
- Recovery snapshots are retained for **7 days** by default
  (`RecoveryService.defaultMaxAge`, `lib/services/recovery_service.dart`), then
  pruned. *(The line number that stood here, `:134`, had drifted; a constant name
  survives an edit above it. Corrected 21-07-2026.)*
- **On web none of this runs.** The timer is only started where local project
  folders exist, and `RecoveryService.available` is false anyway — no
  application-support directory to write to, so every snapshot call would be a
  no-op. Ticking there would serialise a deck every 25 s for nothing. Because the
  absence is silent otherwise, the shell says so once at the first edit
  (`RecoveryService.available`, not a second `kIsWeb` test). The browser build
  instead registers a
  `beforeunload` guard while work is unsaved (`lib/platform/unsaved_work_guard_web.dart`),
  and only while it is unsaved, so a clean tab can still enter the back/forward
  cache.

## Development ratchets (keep the codebase fast to work in)

| Ratchet | Value | Source |
|---|---|---|
| Max file length | **1000 lines** | `tool/check_conventions.dart`, `maxFileLines` |
| Max method/function length | **150 lines** | `tool/check_method_length.dart:26` |
| Coverage floor | **80 %** line coverage | `Makefile`, the `coverage` target |
| `*Sync` dart:io calls in `lib/widgets/` + `lib/state/` | **0** (allowlist `syncIoBaseline`) | `tool/check_conventions.dart`, `syncIoCallsIn` — one blocking call on the UI isolate is a felt stutter; two deliberate entries are documented there (#1854, `writeBytesAtomicSyncRetrying`) |

### Performance gates in the test suite (#2636)

These exist so a quadratic regression is caught by a test, not by a user
report. They all compare **equal work** (N small runs vs one big run) or
**call counts**, never wall-clock thresholds — absolute timing breaks on a
loaded runner.

| Gate | Where |
|---|---|
| Parse scales linearly in slides (200 vs 4×50) and in document blocks | `test/large_deck_performance_test.dart` |
| `markdownFromDocument` on 300 pages vs 2×150 | same file, group `#2636` |
| Per-keystroke work (`reparse` + `inspectMarkdownWriting`) on 300 pages vs 4×75 | same file, group `#2636` |
| Split-run: one replaced slide in a 150-page run costs exactly one measurement | `test/shared_split_fit_scale_test.dart` (#2620) |
| `memoizedDeckScan` on a 1000-slide deck rescans nothing on the second call | `test/privacy_scan_memo_test.dart` |
| Cold quality/privacy scans distribute over idle frames, not the first frame | `test/slide_quality_analyzer_test.dart`, `test/privacy_scan_memo_test.dart` (#2634) |

**Still missing:** a Windows first-frame measurement (#2636). The dev
machines are macOS; there is no harness on the Windows runner to log time to
first frame, and no baseline figure exists to put a ceiling on. Until a
Windows run produces baseline data this stays a documented gap rather than a
pretended budget — add the milestone logging and measure on real hardware
first, then set the ratchet.

## Measured figures

These are measured on the current tree (not enforced limits), to set
expectations for build size and test speed.

### Bundled asset sizes
Measured 2026-07-22.

| Asset group | Size |
|---|---|
| `assets/` total | **13 MB** — of which the two privacy lexicons are 2.0 MB *(measured 2026-07-22; this said 10 MB, from before the lexicons were bundled)* |
| Vendored web-export JS/CSS (`assets/web_export/`) | **5.6 MB** |
| — `mermaid.min.js` | 3.2 MB |
| — `tex-svg.js` (MathJax) | 2.0 MB |
| — `highlight.min.js` / `marked.min.js` / `purify.min.js` | 127 KB / 43 KB / 28 KB |
| Bundled fonts (`assets/fonts/`) | **3.1 MB** |
| Privacy lexicons (`assets/privacy/`) | **2.0 MB** |
| Offline CWE catalog (`assets/cwe/cwe_full.json`) | ~237 KB |

*(Corrected 2026-07-22: the total read 10 MB, from before the two privacy
lexicons landed. It was 13 MB when this line was written, and the lexicons are
now broken out so the next drift is visible rather than hidden in a total.)*

Mermaid and MathJax dominate the web/HTML-export payload; they are only pulled in
where a deck actually uses diagrams or math.

### Codebase & test suite
| Item | Value |
|---|---|
| `lib/` Dart files / lines | ~1 143 files, ~430 000 lines |
| Test files | ~1 022 |
| `test(` / `testWidgets(` cases | ~8 030 / ~2 030 |

Counted on 2026-08-30. These grow with every feature; treat them as an order of
magnitude, not a current figure. *(The row above held the 2026-07-19 counts —
545 files, 356 test files — and six weeks had roughly doubled every one of them.
"Order of magnitude" is the right caveat, but it stops being a caveat when the
figure is off by a factor of two, so re-count it when you touch this table.)*

### Measured timing

**First visit to the web build: ~25 MB raw, ~9 MB compressed before the first
frame** (`make build-web`, measured 2026-07-22). That is `main.dart.js`
(13.8 MB / 3.8 MB), `canvaskit.wasm` (6.9 / 2.8), the eighteen fonts in
`FontManifest.json` (2.7 / 1.4) and `assets/privacy/health_lexicon.json`
(2.0 / 0.5), which `lib/main.dart` deliberately awaits before `runApp`. Serve
it compressed — see [HOSTING.md](HOSTING.md) §2 — and keep the static loading splash visible while it arrives. This historical
baseline predates the WASM measurements below.

A single small test (`flutter test test/tlp_test.dart`, 15 cases) completes in
**~4.7 s** wall-clock — dominated by the Flutter test harness warm-up, not the
tests themselves.

**Export timing, measured 2026-11-28.** The benchmark lane measures the
production PDF rasterizer and PDF writer, and each document writer with
production projection and filesystem output. The laptop was an ARM64
Mac15,7 with 18 GiB RAM, macOS 27.3 and Flutter 3.50.0. These are observations
from that run.

| Fixture | Wall-clock |
| --- | ---: |
| Presentation PDF, 150 text slides at 1920 px | 13.45 s |
| Document PDF, 80 sections with headings and tables | 200 ms |
| Document DOCX, same fixture | 74 ms |
| Document ODT, same fixture | 70 ms |
| Document ePub, same fixture | 79 ms |

The isolated gate uses the median ratio between one export and two half-size
exports, with alternating run order. It uses 640 px for the slide scale
comparison and the production resolution for the separate timing sample.
The presentation fixture uses text and bullets. A photo-heavy deck has
additional decode costs.

```sh
OCIDECK_EXPORT_TIMINGS=1 flutter test --concurrency=1 --tags benchmark test/slide_rasterizer_test.dart test/document_export_write_test.dart
```

What a release build does record since #2618 is **freezes in the field**: the
desktop log file gets one line whenever the UI isolate was unreachable for more
than 500 ms beyond its 250 ms tick, with the work labels (`noteWork`) set in
that window — face scan, document export, opening a deck, the Quill ↔ Markdown
conversion, the split-run index, the privacy scan and the quality check. The
start-up milestones (`opstart: …`, with milliseconds since `main`) say how long
each step before the first frame took. That is observation, not a budget: it
tells you where a user's machine stalled, and the fix still needs a measurement
here.

## Release size budgets

The [size limits](../tool/release_size_limits.json) bound the uncompressed
finished web tree, compressed Chromium startup resources and the four named
desktop installers. The web packer measures the assembled tree. The browser
probe counts response bodies for same-origin resource requests started by the
first frame, from a fresh browser context. The release-channel manifest
checks installer bytes before sealing a new candidate. Keep each limit at
or below its current value unless the change is reviewed with new measurements.

Measured on 2026-11-28. The web sample is pinned Chromium from
[Linux web run 6943](https://pawprint.vigilis.online/LibreKAT/Ocideck/actions/runs/6943)
on source `d2e778167`. That report includes resources seen immediately after the
first frame and provides the baseline for the more narrowly timed check.
The installer and full web tree baselines are from the 0.7.19 candidate.

| Surface | Baseline, bytes | Budget, bytes |
| --- | ---: | ---: |
| Web, assembled tree | 133321857 | 138000000 |
| Chromium WASM, first frame | 15305007 | 16700000 |
| Chromium JS fallback, first frame | 13830532 | 15800000 |
| Debian package | 205331838 | 210000000 |
| Linux AppImage | 224270840 | 229000000 |
| macOS ZIP | 137380774 | 142000000 |
| Windows setup | 47703554 | 52000000 |

Static PDF font faces are bundled and loaded when exporting a document. The
four retained style faces per family provide real bold and italic outlines
with the PDF library, and bundling keeps document export available offline.
The installed size check includes those bytes.

## WebAssembly release (Flutter 3.50, 2026-11-18)

The normal `make build-web` now produces both Dart WASM + skwasm and the
JavaScript + CanvasKit fallback. The loader enables modern Blink, WebKit and
Gecko after runtime feature detection. Cross-origin isolation moves skwasm
rendering to a worker; the application's Dart work still runs on the UI thread.
An import or privacy scan does not automatically become a worker task.

A separate native-cache repair prevents a web AOT link (zero native calls)
from leaving dartcv4's finalizer-only export list for a subsequent desktop
build. Cache hygiene checks the scanner's required symbols and invalidates
only the bad keep-list and hook results, preserving OpenCV downloads. The real
scanner unit suite recovers 96/107 covered lines; the coverage floor is retained.

Stability improvements include selecting the correct browser implementation
under both compilers (`dart.library.html` is false under WASM), rejecting
legacy JS interop at build time, retaining standard WASM O2 type/bounds checks,
and using content-addressed app/assets with revalidation of unhashed loaders
and engines. The deploy script retains N-1 hashes for open tabs. Mermaid's lazy
scripts resolve through Flutter's asset manager, so hashing does not break them.
The existing CSP remains strict and engine resources remain self-hosted.
The unmodified Noto Color Emoji interface slice is bundled, attributed and
hash-pinned too: Flutter otherwise fetched it from Google for the language
flags at startup, despite `--no-web-resources-cdn`. The UI explicitly selects
the local fallback. This prevents that startup request without changing the
appearance or loading every Unicode font. Arbitrary deck text outside the
bundled fonts can still trigger Flutter's existing dynamic font fallback; these
startup probes do not establish offline coverage of every Unicode script.

The shipped bootstrap records local User Timing marks and measures for engine
initialization, application initialization and the actual `flutter-first-frame`
event. The `runApp()` JavaScript promise only starts Dart main and is not itself
a first-frame measurement. No measurements are transmitted to a service.

Reproduce the actual release-bundle probes (Node 22+, pinned Playwright):

```sh
make check-web
npm ci --prefix tool/web-wasm-check
(cd tool/web-wasm-check && npx playwright install --with-deps chromium firefox webkit)
node tool/web-wasm-check/probe.cjs build/web chromium,firefox,webkit auto 3
node tool/web-wasm-check/probe.cjs build/web chromium,firefox,webkit fallback 3
node tool/web-wasm-check/probe.cjs build/web chromium,firefox,webkit single-thread 1
flutter test --platform chrome --wasm test/web_wasm_platform_test.dart
flutter test --platform chrome test/web_wasm_platform_test.dart
```

The probes load a subdirectory deployment under the shipped CSP and verify
actual compiler/renderer requests, worker creation, first paint, no HTTP errors,
no uncaught exceptions and no third-party startup requests. Fallback mode
changes only the loader's allow-list, exercising the JS build in the same bundle.
Single-thread mode removes the isolation headers. Apache was also tested with
the actual `.htaccess`: correct WASM/MJS MIME, gzip, immutable hashed resources
and revalidation of the loaders and unhashed engines.

Measurements are recorded in
[`results-2026-11-18.json`](../tool/web-wasm-check/results-2026-11-18.json).
Indicative medians for navigation to observed first app frame (three runs):

| Engine | WASM + skwasm | JavaScript + CanvasKit | Encoded startup resources, WASM / JS |
| --- | ---: | ---: | ---: |
| Chromium 159 | 1.185 s | 2.188 s | 15.02 / 13.72 MB |
| Firefox 159 | 1.364 s | 1.673 s | 15.81 / 14.61 MB |
| WebKit 27.2 | 1.415 s | 1.684 s | 15.78 / 14.59 MB |

WASM starts sooner in these samples while transferring about 1.2–1.3 MB more.
This is a real tradeoff on slow connections; first-visit download size is not
smaller. Content-addressed caching helps repeat visits and asset-only deploys.
All 21 release probes passed, including isolated rendering with a worker,
forced JavaScript fallback, and WASM without isolation or a worker.

They are local headless browser probes on an ARM64 Mac, not a network or frame
rate budget: three fresh HTTP cache contexts per engine, a shared browser
process, gzip, no network throttling, and possible concurrent build load. They
measure the first app frame (the consent screen), not a large deck interaction.
No claim about OciDeck's FPS, long-session memory or crash rate follows from
these startup probes. Flutter's published heavy-widget benchmark improvement
is an upstream result and has not been reproduced as an OciDeck FPS result.

Further options were considered deliberately:

- Keep WASM O2. O3 drops implicit type checks; O4 additionally drops bounds
  checks, making malformed imported data harder to diagnose safely.
- Content hashing is currently incompatible with deferred imports. There are
  no deferred imports in `lib/`; introducing lazy features would require
  restructuring and a new cache/deploy strategy, rather than just another flag.
- Browser-native WebParagraph text layout is a Chrome experimental preview.
  It is not enabled for a release targeting all three engines.
- The SIMD primitives in Dart 3.14 help explicitly vectorized code; they do not
  automatically vectorize every Dart loop. No unmeasured SIMD rewrite is made.
- WASM can support age crypto where dart2js cannot, but switching browser form
  sealing on needs its own end-to-end export and key-persistence verification.
  This change preserves the existing product availability policy.

Sources: [Flutter 3.50 announcement](https://flutter.dev/blog/whats-new-in-flutter-3-50),
[Flutter WASM support](https://docs.flutter.dev/platform-integration/web/wasm),
[deployment and content hashing](https://docs.flutter.dev/deployment/web),
[Dart WASM optimization levels](https://dart.dev/web/wasm).

## Best practices for users

- **Images:** use appropriate resolutions (don't drop a 6000 px photo onto a
  1920 px slide); the app will downscale to 4096 px max on decode regardless.
- **Charts:** keep series counts modest — the palette repeats after 10.
- **Media:** prefer shorter, lower-resolution clips; the 1 GiB media cap is a
  ceiling, not a target.
- **Structure:** group content into sections; split very large decks.

## Compatibility notes

Actual timings vary with hardware (CPU, RAM, storage), OS, and — on the web —
browser and available tab memory. The web build is more memory-constrained than
desktop and has no native filesystem access.
