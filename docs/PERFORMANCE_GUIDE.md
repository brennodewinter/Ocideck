# OciDeck — Performance Guide

> **Status:** current-state description of enforced limits and measured sizes · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

This document describes OciDeck's performance characteristics using the **actual
limits and sizes enforced in the codebase** (with `file:line` citations), plus a
few measured figures. Where a number is a hard cap in code, it is authoritative;
where it is a measured size or timing, it is labelled as such. OciDeck ships no
formal timing/benchmark suite, so there are deliberately no invented latency
budgets here.

## Memory Management

### Image handling
Images are the dominant memory cost, so decoding is bounded up front:

| What | Limit | Source |
|---|---|---|
| Max image decode dimension (per axis) | **4096 px** | `lib/utils/image_limits.dart:16` (`kMaxImageDecodeDimension`) |
| Max in-memory image bytes | **64 MiB** *(bij het importeren, per bestand — niet een plafond voor alles wat tegelijk gedecodeerd in beeld staat)* | `lib/services/image_service.dart:40` |
| Max media (video/audio) bytes | **1 GiB** | `lib/services/image_service.dart:41` |
| Luminance sampling decode | **48 × 48 px** | `lib/utils/image_luminance.dart:54` |
| Carousel thumbnail / preview / full decode | `cacheWidth` **360 / 720 / 1000** | `image_carousel_picker_grid.dart`, `..._preview.dart` |
| Slide-strip thumbnail decode | **512 px** langste zijde | `slide_thumbnail.dart` (`decodeMaxEdge`) |

A decode allocates roughly `width × height × 4` bytes, so the 4096 px cap and the
64 MiB byte ceiling are two views of the same worst case (4096² × 4 ≈ 64 MiB).
Keeping source images near their on-screen size is the single most effective
optimisation.

### Asset storage
- Project assets live in dedicated subfolders (`images/`, `data/`, `logos/`,
  `themes/`); assets outside the project directory are refused on the
  render/present/export paths (containment, not just convention).
- On the web build, images are held in an in-memory store (`mem:` scheme,
  `lib/services/web_asset_store.dart`) — so large decks consume browser tab
  memory rather than disk.

## Rendering

- Slides render as native Flutter widgets for preview and presentation.
- Charts use the `fl_chart` library; the categorical palette is **10 colours**
  and cycles (`index % 10`) beyond that (`lib/models/chart.dart:10`), and legend
  tiles lay out in **≤ 6 columns × 1–3 rows** (`marp_html_service_charts.dart`, `maxColumns`).
- Mermaid diagrams render to sanitised inline SVG via a shared WebView.
- Video plays through a shared media host so only one heavy player is live.

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
| Default fetch timeout | **30 s** | `lib/services/file/file_service_net.dart:63` |
| Proxy/fallback timeout | **120 s** | `lib/services/file/file_service_net.dart:49` |

## Large presentations & directory scans

There is no hard slide-count limit, but responsiveness degrades with many
high-resolution media assets or complex charts. Directory scanning (used by the
deck browser and image-dedup tooling) is bounded so a pathological tree can't
hang the app:

| Scan | Ceiling | Source |
|---|---|---|
| Image-reference scan | **20 000** files, depth **32** | `lib/services/image_reference_service.dart:24,28` |
| Deck listing | **5 000** files, depth **32** | `file_service.dart`, `listDecks` defaults |
| Content search | **20 000** files, depth **8** | `file_service.dart`, `searchDecks` defaults |

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
| `lib/` Dart files / lines | ~545 files, ~201 000 lines |
| Test files | ~356 |
| `test(` / `testWidgets(` cases | ~2 510 / ~750 |

Counted on 2026-07-19. These grow with every feature; treat them as an order of
magnitude, not a current figure.

### Measured timing

**First visit to the web build: ~25 MB raw, ~9 MB compressed before the first
frame** (`make build-web`, measured 2026-07-22). That is `main.dart.js`
(13.8 MB / 3.8 MB), `canvaskit.wasm` (6.9 / 2.8), the eighteen fonts in
`FontManifest.json` (2.7 / 1.4) and `assets/privacy/health_lexicon.json`
(2.0 / 0.5), which `lib/main.dart` deliberately awaits before `runApp`. Serve
it compressed — see [HOSTING.md](HOSTING.md) §2 — and expect a blank page while
it arrives, because there is no loading indicator yet.

A single small test (`flutter test test/tlp_test.dart`, 15 cases) completes in
**~4.7 s** wall-clock — dominated by the Flutter test harness warm-up, not the
tests themselves.

**Still missing, and worth saying so:** there is no measured wall-clock for a
PDF export of a large deck, which is the figure a user actually feels.
`test/large_deck_performance_test.dart` covers serialise and parse only (150
slides, confirming the behaviour is not quadratic) — not the scan, not the
export, not the UI. There are **no** automated wall-clock or throughput
benchmarks in CI; profile a specific slowdown with Flutter DevTools rather than
relying on fixed budgets.

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
