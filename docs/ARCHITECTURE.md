# OciDeck — Architecture

> **Status:** current-state description of the system and its layering · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

A high-level map of how OciDeck is put together, for contributors. For how files
are stored on disk, see [`FILE_FORMAT.md`](FILE_FORMAT.md). For a one-line
description of the files under `lib/`, see [`SOURCE_MAP.md`](SOURCE_MAP.md).

## Stack

- **Flutter** desktop and web app (macOS, Windows, Linux, web), Dart 3.12+.
- **State**: [Riverpod](https://riverpod.dev/).
- **Storage**: standard Marp Markdown (`.md`) as the single source of truth, with
  sidecars for anything that isn't plain Marp.

## Runtime & network model

OciDeck is a **client-side app with no application backend**. On every platform —
desktop and web alike — the editor, live preview, the on-device privacy scan
(OciWacht), export to PDF/PPTX/HTML, and the CVSS/MIAUW engines run **in the
process the user is looking at**: the native app on desktop, and on web the
browser tab, into which the whole Dart-compiled bundle is downloaded and then
run. Deck content is never shipped to a server to be processed.

There is **no telemetry, analytics, or tracking** of any kind. The only HTTP
client dependency is `http` (see `pubspec.yaml`) — no Firebase/Sentry/GA/PostHog.
`video_player` and `webview_flutter` also reach the network, for remote media
behind the Online-media gate. And
`web/index.html` ships a strict CSP (`default-src 'self'`; `connect-src 'self'
https:`) with no third-party scripts. The app never phones home. (The only
`tracking` strings in `lib/` belong to the *privacy detector*, which flags
trackers found in the user's own slides — not tracking of the user.)

**What a web host can and cannot see.** A server that *serves* the web bundle sees
only what any static host sees — ordinary HTTP access logs (IP, timestamp, which
assets were fetched, user-agent). It has **no application-level insight**: not the
deck, its content, the edits, or what the user does inside the tab. Everything
above the transport stays in the browser.

**Outbound calls are user-initiated and go where the user points them**, never to
the hosting origin as telemetry:

- **fetch-proxy** (`server/fetch-proxy/`) — the *one* optional server-side
  component. When the web app opens a deck from a URL whose host sends no CORS
  headers, it falls back to the same-origin `/fetch-proxy?url=…` and the proxy
  fetches those bytes server-side, relaying **raw bytes only** (no content
  inspection). So in that one case the host does see the fetched URL. It is
  SSRF-guarded, mirroring `utils/net_guard.dart` (public-routable targets only,
  socket pinned to the validated address against DNS rebind, no redirects, hard
  byte cap). Without it deployed the web app still works for same-origin and
  CORS-friendly sources.
- **Optional AI assistance** (`services/ai_*`, off by default) — a local model or
  a *consented* outbound endpoint the user configures.
- **Nextcloud/WebDAV** (`services/webdav_service.dart`) — the user's own server.
- **S3** (`services/s3/s3_service.dart`) — the endpoint the user configured. There
  is no AWS SDK and no default endpoint: SigV4 is signed by hand precisely so the
  request goes out over the guarded `HttpClient` rather than an SDK's own stack.
- **Git** (`services/git/`) — the user's own forge, over two different transports
  (REST, and a native `git` subprocess); see below for how each is guarded.
- **CVE database** — an opt-in download.
- **URL import / remote media** — a link the user pastes.

Every outbound request from the app funnels through `utils/net_guard.dart`, which
rejects internal targets (loopback, RFC1918, link-local incl. cloud metadata,
CGNAT, ULA, IPv4-in-IPv6) and pins the socket to the validated address. The one
opt-in exception is a WebDAV, S3 or git host the user has ticked as a *trusted
internal server* (`NetGuard.safeResolveTrusted`, `WebdavServer.trustedInternal`),
which allows a private/LAN address over plain `http`.

**The native git path is guarded differently, because it is not our socket.**
Git storage has two transports. The REST forge path
(`services/git/git_transport_io.dart`) is guarded the usual way — resolve, pin
via `connectionFactory`, no redirects, plus a same-origin assertion. The native
path (`services/git/native_git_mirror_io.dart`) spawns a real `git` subprocess
for `clone`/`fetch`/`push`, so there is no `connectionFactory` to hook: git does
its own DNS and opens its own connection.

It is therefore guarded by *imposing the outcome* on git rather than by
intercepting it (`_networkConfig`):

- `http.curloptResolve` binds the hostname to the address `NetGuard` approved, so
  a DNS rebind cannot move the destination. TLS still validates against the
  hostname, so no certificate has to be issued to an IP.
- `http.followRedirects=false` turns any redirect into an error instead of a
  second, unvalidated host. That matters more here than elsewhere: the token
  travels as `http.extraHeader`, and a header follows a redirect.
- The same scheme rule as WebDAV and S3 — `https`, unless the server is
  deliberately marked *trusted internal*. `file://` is exempt (it never reaches
  the network); `ssh://` and `git://` are refused outright.

`test/git_network_guard_test.dart` checks both halves: that the app passes this
config, and that `git` actually honours it — offline, by pinning
`example.invalid` (a name that by RFC 2606 never resolves) at a local server, so
a connection that arrives at all can only have come from the pin.

## Module layout

```
lib/
  models/     # Deck, Slide, Settings/ThemeProfile, Chart, Annotation
  services/   # mostly loose files, one subject each: markdown,
              # markdown_validator, file, export, classification_policy,
              # classification_enforcement_policy, export_metadata, image,
              # caption, description, image_dedup (md5 duplicates),
              # image_reference (.md rewrites), recovery, rasterizer,
              # marp_html, annotation_codec, rehearsal_controller,
              # webdav (Nextcloud source), secret_store (keychain)
              #
              # …plus the subdirectories that are a subject of their own:
              #   privacy/             detect, weigh, redact, gate the export
              #   git/                 forge source (docs/design/GIT_STORAGE.md)
              #   s3/                  bucket source (SigV4 + pinned client)
              #   cve/                 the offline CVE corpus
              #   cvss/                the CVSS v4.0 scoring engine
              #   finding_templates/   template content, one file per language
              #   presentation_search/ the network sources 'Slide zoeken' scans
              #   info_safety/         what reference data is locally present
              #   parts/               `part of` spillover, not a cluster
              #
              # Each of those (except parts/) carries a header comment naming
              # what belongs in it and what does not; SOURCE_MAP.md lists which
              # file holds it.
  state/      # Riverpod providers (top-level + parts/): deck, editor,
              # settings, tabs, clipboard, webdav, s3, git, consent, privacy,
              # info_safety, local_cve, deck_quality, …
  platform/   # conditional-import platform abstraction (io/web halves)
  widgets/    # app shell, panels, dialogs, per-type editors, slides, presenter
  l10n/       # AppLocalizations + translations/<lang>.dart (32 languages)
  theme/      # app theming
  utils/      # small shared helpers (clipboard table parsing, URL launching)
```

The direction of traffic between those layers is enforced, not just intended: a
`check_conventions` guard (`layerRules`) fails the build when `models/` imports
`state/` or `widgets/`, when `services/` imports `state/`, or when `state/`
imports `widgets/`. All three are a hard zero. A separate ratchet
(`serviceUiImportBaseline`, now 4) counts UI imports inside `services/`; the
remaining four are in `slide_rasterizer`, which paints real widgets into an
image and therefore has the widget tree as its subject.

Together those keep the core headless: runnable and testable without pumping a
widget tree, and acyclic between layers. They held on discipline alone until
2026-07-22, which is exactly the kind of invariant a reviewer eventually misses.

## Data model

- **`Deck`** holds metadata, a list of **`Slide`**s, the active **`ThemeProfile`**,
  the deck-wide TLP level, and an **annotation layer** (`Map<slideId,
  List<InkStroke>>`) that is *never* serialized into the Markdown — it goes to
  its own sidecar on save, and into the autosave snapshot in between.
- **`Slide`** is a single immutable value with a `SlideType` and typed fields. A
  few types reuse `customMarkdown` for their payload: free-Markdown (raw),
  `code` (the source), `chart` (the JSON spec), `cockpit` (the JSON spec of
  its instrument meters), and `question` (the JSON quiz spec — kind, prompt,
  answers, option count, time limit, and the match threshold for a typed answer).
  answers, option count, time limit).
- A couple of `Slide` fields exist **only for rendering** and never reach a saved
  file: `mediaRedacted`, set by the privacy projection because an emptied image
  path alone cannot tell the renderer whether a photo was removed or never chosen,
  and `renderPage`, set by `expandRichTextForRender` to say which page of a
  paginated rich-text body this copy draws. `renderPage` is not serialized at all;
  `mediaRedacted` is written as `<!-- ocideck_media_redacted -->` under `forExport`
  only, so the HTML export can draw the black block the rasterized exports draw
  themselves. Neither is carried over by `Slide.duplicate`.
- **"Which images does this slide use" has one definition**,
  `services/slide_image_refs.dart` (added 2026-07-22), and it is not
  `imagePath` + `imagePath2`: a rich-text body may carry `![…](…)` of its own
  (FILE_FORMAT § *Rich text*), and those are slide images too. `slideImageRefs` /
  `slideImagePaths` read the set; `rewriteSlideImagePaths` /
  `rewriteInlineImagePaths` rewrite it — a caller that can enumerate must be able
  to rewrite, or it leaves an inline path pointing nowhere. A dozen or so files
  had spelled the field pair out by hand, and each one that missed the body
  failed in its own direction: the privacy projection let a redacted slide keep
  its picture, the git pool wrote a path into `deck.md` that only the author's
  machine could resolve, the web `mem:` sweep freed bytes still being drawn, the
  save and package paths shipped a deck with a hole in it, and the library's
  "0 slides use this" invited a deletion.
  `services/image_usage.dart` sits on top of it for the library's two questions
  (who uses this file, and repoint them), which existed twice with the same blind
  spot.
- **Question slides** are interactive. The authored `QuestionSpec` round-trips in
  `customMarkdown`; the live per-presentation state (`QuestionView` — the options
  drawn, the pick or the typed text, correct/wrong, timer) is **session-only** and
  never serialized. During presentation the presenter window is the single source
  of truth: the audience window forwards clicks (`answerSelected` /
  `answerSubmit`) and the presenter pushes the resulting `QuestionView` back over
  the window channel, the same pattern as the checklist/table sync.

  Two consequences of that split are load-bearing rather than incidental. First,
  the `QuestionView` is a **render state**, so whatever it holds is on screen: an
  `openText` round therefore carries no `expectedAnswer` until the reveal, and the
  presenter fills it in at the moment it resolves the answer. This is not a
  confidentiality boundary — `buildBeamerMarkdown` hands the audience window the
  whole deck markdown, `question` block and `correct` flags and all, so the answer
  key is already over there. It is a display rule: the view decides what is
  painted, and painting the answer before it is given would spoil the question.
  (*Corrected 2026-07-21: this paragraph claimed the answer key does not travel to
  the beamer window. It does.*) Second, typing must not be possible in two places
  at once, so the audience window passes no `onAnswerTextChanged` and its input
  field mirrors read-only; `presenter_keys.dart` hands the keyboard to the field
  while such a round is open, keeping only `Enter`, `PageUp`/`PageDown`, `Esc` and
  `Ctrl/Cmd+W` as shortcuts.
- **Timeline slides** keep their events in the normal `bullets` field as
  `marker :: title :: description` list items (no `customMarkdown`), so the `.md`
  stays a readable Markdown list. The layout (`TimelineLayout`) and animation
  (`TimelineReveal`) are typed `Slide` fields that round-trip as extra `_class`
  tokens (`timeline-horizontal/-vertical/-steps/-static`) rather than in the
  content. In *step* mode the revealed-event count is **session-only**, mirroring
  the `_richTextPage` pattern: the presenter intercepts next/prev and pushes a
  `timelineStep` over the window channel so the audience window reveals in sync.
- Slide ids are **regenerated on every parse**, so they are stable only within a
  session. Anything persisted that must survive a reload (annotations) re-anchors
  by slide order + a content fingerprint rather than by id.
- **`CockpitColorScheme`** is a named set of cockpit status colours (good /
  warning / critical / cold). Schemes live in `AppSettings` (a managed list plus
  a globally selected name, mirroring `ThemeProfile`/`AppAppearanceProfile`), not
  in the deck — the colours are styling. The active scheme is resolved from
  settings and threaded into `SlidePreviewWidget` and the export chain alongside
  `themeProfile`; the cockpit painter and the export SVG read the four colours
  from it instead of hardcoded constants. For the beamer window it travels in the
  transient audience payload, like the inlined style profile.
- **`ThemeProfile` travels three ways**, all through the same `toJson` /
  `fromJson` pair: in `AppSettings` as the managed list of profiles (persisted to
  preferences), inlined in a deck's front matter (base64url), and — since it must
  also be shareable on its own — as a standalone `.ocideckstyle` file
  (`parts/file_service_style_profile.dart`, FILE_FORMAT §3.3). `fromJson` is
  deliberately the single hardened gate for all three: two of them are untrusted
  input, so validating at the model rather than per call site means a new carrier
  cannot forget to. The standalone file is the only carrier that embeds the logo
  bytes, because it is the only one that travels without a project folder to
  resolve a path against.

## Markdown round-trip

`MarkdownService` is the contract:

- `generateDeck` / `generateSlide` write Marp Markdown. OciDeck extras live in
  front-matter keys and `<!-- … -->` comments that Marp ignores.
- `parseDeck` / `_parseBlock` read it back. `code` and `chart` slides are detected
  by their `_class` and parsed separately (their fenced block would otherwise
  confuse the generic line parser).

`MarkdownValidator` (`lib/services/markdown_validator.dart`) performs a
structural pre-flight before applying raw markdown in the editor: it reports line-
anchored errors/warnings for the same shapes the parser expects (front matter,
slide separators, `_class`, fences, OciDeck HTML fragments, chart JSON, etc.).
See `docs/FILE_FORMAT.md` §10 and `docs/USER_GUIDE.md` (Markdown mode).

This service is heavily covered by the round-trip tests — treat it as the
source-of-truth for the file format and keep `FILE_FORMAT.md` in sync.

## The two rendering worlds

Charts, diagrams, and slides are rendered in **two independent places**, which is
the key thing to understand before touching rendering:

1. **In-app** — `widgets/slides/slide_preview.dart` (`SlidePreviewWidget`) renders
   a slide as Flutter widgets. Free-Markdown ` ```mermaid ` blocks are rendered
   to inline SVG via `services/mermaid_render_service.dart` (shared WebView +
   bundled `mermaid.min.js`). The *same* widget is used for the editor preview,
   thumbnails, the fullscreen presenter, and — via `services/slide_rasterizer.dart`
   — the **PDF and PPTX** exports (rasterized to images). So anything that must
   appear in PDF/PPTX must render here. Charts use `fl_chart`.
   Video sources are classified once by `models/video_source.dart`
   (`VideoSource`: local file / remote file / YouTube / Vimeo) so the preview,
   markdown serializer and exporter agree. Local and remote files play through
   the shared `_MediaPlaybackHost` (`video_player`, file vs `networkUrl`), which
   also seeks to the segment start and stops at the segment end (the per-slide
   trim window that powers "cut a video across slides"). YouTube/Vimeo play in a
   second on-screen WebView (`_VideoEmbedPreview`, the same pattern as the
   Mermaid host); remote rendering is gated by the **Online media** setting. Both
   embeds are a bare iframe on the URL `VideoSource.embedUri` builds. End
   detection and playhead reporting come from the provider: Vimeo through its
   `player.js` API, YouTube through the player's own `postMessage` channel
   (`enablejsapi=1`) with **no** script fetched from YouTube — that script came
   from `www.youtube.com` and put the player itself on that origin, which is the
   one the `youtube-nocookie.com` variant exists to avoid (*corrected
   2026-07-22*). `_youTubePlayerNavigationAllowed` matches on host, not
   substring, and refuses `www.youtube.com` so the player's "Watch on YouTube"
   link cannot navigate the slide there.
2. **HTML export** — `services/marp_html_service.dart` produces a single `.html`
   that renders in a browser using inlined JavaScript (marked, highlight.js,
   mermaid, MathJax), inlined CSS and an inlined font. Charts are pre-rendered to
   inline **SVG in Dart** here (no JS chart library). Fidelity differs from the
   in-app renderer by design. The service never reads image files: an `![](…)`
   reaches the browser as a relative `<img src>`, so the export is
   self-contained in everything except slide images (corrected 2026-07-21).

Both worlds converge at one chokepoint: `services/export_service.dart`
(`ExportService.export()`) is the only place that writes an export.

### Render-time pagination

What an export enumerates is not the deck's slide list.
`_MainLayoutState._expandForExport` (`widgets/app_shell_main_layout.dart`) runs
`expandFindingsForRender` (`services/finding_pagination.dart`) and then
`expandRichTextForRender` (`services/rich_text_layout.dart`) over the chosen
slides, and that expanded list is the deck the privacy projection is taken of —
so it is what the rasterizer walks and what the export's markdown is generated
from. Both transforms are pure and leave the deck itself alone.

The reason is the same in both cases: a finding whose prose overflows, and a
rich-text body longer than one slide, are *edited* as one slide but must be
*rendered* as several at full size. The editor preview and the presenter page
through those pages themselves; a surface that enumerates slides cannot, and
until 2026-07-22 the export therefore rendered the first page of a paginated
rich-text slide and left the rest out of the file.

Two consequences worth knowing:

- The footer's page number is the slide's **position in the expanded list**
  (`SlideRasterizer` hands `SlidePreviewWidget` `i + 1` and `slides.length`), so
  continuation pages are counted like any other slide.
- Each rich-text page copy keeps the *whole* body and the original slide id, and
  carries only `renderPage`. The page split and the shared font scale are
  properties of the body as a whole — one page's markdown in isolation would be
  scaled on its own and the text would jump from page to page. Presenting expands
  findings only (`widgets/shell/shell_actions.dart`), because the presenter pages
  through a rich-text slide itself; `SlidePreviewWidget._effectivePage` lets a set
  `renderPage` win over the page a surface paged to, and the two never occur
  together.

### Classification enforcement

Export blocking is decided by `ClassificationEnforcementPolicy`
(`services/classification_enforcement_policy.dart`), evaluated inside
`ExportService.export()` **before** any file bytes are built — fail-closed, so no
format (PDF/PPTX/HTML/package) can bypass the gate. The export dialog and status
bar run the same policy up front for UX (explain early, disable misleading work).

The policy combines three optional rules from `AppSettings`:

| Setting key | Rule |
| --- | --- |
| `maxReleaseExportTlpKey` | Release **ceiling** — deck TLP must not exceed this level. |
| `minRequiredExportTlpKey` | **Floor** — deck TLP must be at least this level. |
| `requireClassificationOnExport` | Deck must have a TLP level (`TlpLevel.none` is rejected). |

`ClassificationPolicy` remains as a thin wrapper around the ceiling only
(backward compatible); new code should use `ClassificationEnforcementPolicy`.
The gate evaluates **deck-wide** `Deck.tlp`, not per-slide levels (those still
control visibility via `slideVisibleAtTlp`).

`ExportDocumentMetadata` (`services/export_metadata.dart`) is built from deck
metadata and passed into PDF (`pw.Document` title/author/subject/keywords/creator/producer),
PPTX core properties, and HTML `<meta>` tags. HTML also gets a fixed
`.tlp-export-banner` when classified.

The same object carries the **unreviewed-AI declaration**, counted from
`Slide.aiAssistedFields` (`unreviewedAiSlideCount`). It rides the existing
channels rather than adding a new one: the keyword `kAiDraftKeyword` joins
`exportKeywords()`, `kAiDraftSubjectNote` is appended to `subject()` behind the
TLP prefix, `htmlAiMarking` emits `<meta name="ai-generated">` beside
`ai-generated-slides`, `MarpHtmlService._aiBanner` renders an
`.ai-export-banner` (offset below the TLP banner when there is one, at the top
when there is not), and `fileSuffix` puts `-ai-concept` in the filename that
`ExportService.export` composes. Every one of them is empty when the count is
zero, so a reviewed deck exports exactly as before. The count is taken from the
**projected** deck the export dialog holds, so the redacted copy declares it too.

### Visual TLP marking

In-app slides (`SlidePreviewWidget`) compute `effectiveTlp(deckTlp, slideTlp)` —
the stricter of deck and slide — and render FIRST TLP 2.0 markings from
`widgets/slides/previews/overlays.dart`:

- `_TlpOverlay` — bottom-right (or bottom-left) badge
- `_ClassificationWatermark` — optional diagonal watermark (`TLP · organisation`),
  controlled by `AppSettings.classificationWatermarkEnabled`

The same widget tree is rasterized for PDF/PPTX (`slide_rasterizer.dart`), so
markings are WYSIWYG. The watermark setting is threaded through preview, presenter,
audience window, thumbnails, and export dialog.

## Presenter

`widgets/presentation/fullscreen_presenter.dart` drives presenting:

- Keyboard navigation, presenter view, blank screen, grid overview, auto-advance,
  and the **annotation tools** (pen/highlighter/eraser/laser).
- The single `_FullscreenPresenterState` is split for navigability into
  `widgets/presentation/parts/presenter_*.dart` (questions, table, ink, playback,
  displays, navigation, keys, notes, overlays). Each is a `part of` the main file
  and adds one `extension _PresenterX on _FullscreenPresenterState`, so the state
  and all imports stay in the main library. Two rules for this pattern: extensions
  can't call the protected `setState`, so they go through the main class's
  `_rebuild(fn)` wrapper; and `static` members used by a part must live at
  top-level (e.g. `_questionTickMs`, `_digits`), since extensions don't see class
  statics. The main file keeps the fields, lifecycle (`initState`/`dispose`/
  `build`), `_slideCanvas`, and the shared getters.
- Neighbour slide images are **precached** and `gaplessPlayback` is on, so slide
  changes never flash black (important for screen recording).
- **Rehearsal timing** lives in `services/rehearsal_controller.dart` — a plain,
  unit-testable controller (injectable clock) that the presenter feeds via a
  cheap, idempotent `observe(id, index)` on every build, so it captures every
  navigation path. It measures only: elapsed, remaining against a target,
  per-slide time, and — through the explicit `startQuestion`/`finishQuestion`
  pair, which the question logic calls — the duration and verdict of each
  *answered* question attempt. No pacing logic. State is **session-only** (no
  prefs, no `.md`); `_exit` shows a summary (`rehearsal_summary.dart`) and
  discards it. The default target lives in `Deck.presentationTargetSeconds`
  (front matter: `ocideck_target_seconds`).

  Whether that summary appears at all is decided in `FullscreenPresenter`, not at
  the call site: a `playOnly` deck is refused before the `showRehearsalSummary`
  switch is even consulted. Putting the gate in the widget means every route into
  the presenter is covered by it, which is the point — the switch travels in the
  recipient's copy of the file, so a caller-side check would only cover the
  callers we happened to think of.

### Dual-screen mode

When a second display is present (`shouldUseDualScreen` on macOS, Windows, or
Linux), the presenter runs in two OS windows:

- The **laptop** window shows the presenter view.
- A borderless **audience** window (`audience_window.dart`) fills the external
  screen with the slide.
- They sync over method channels (`ocideck/audience`, `ocideck/presenter`):
  current index, blank state, ink strokes, and the laser pointer. Media plays only
  on the beamer to avoid double audio.

This needs a real second window, which `window_manager` (single-window) can't do,
hence the vendored multi-window fork below.

## Sidecars (separate layers)

To keep the `.md` pure Marp, five kinds of data live beside it (see
`FILE_FORMAT.md` §6):

- **Captions** — `.ocideck_captions.json` (per image, in `images/`).
- **Descriptions/tags** — `.ocideck_descriptions.json` (searchable image
  metadata, used by the library's search and the untagged filter).
- **Annotations** — `<name>.ink.json` (`services/annotation_codec.dart`).
- **User notes** — `<name>.user-notes.json` (`services/user_notes_codec.dart`).
  In the visual editor, slides with user notes are marked on thumbnails in the
  slide list (`widgets/slides/slide_thumbnail.dart`).
- **Linked chart data** — `data/*.json` for anything new, `data/*.csv` for a deck
  that already links one (the living source for a chart).

The last two carry a consequence worth stating where the layers are listed: a
commit to a git repository takes `deck.md`, the pooled images and the chart data
— and **not** the ink or the user-notes sidecar, since nothing in `services/git/`
writes them. `gitDeckOmissions` counts what stays behind and the save path asks
before committing (`design/GIT_STORAGE.md` §9.1). The ink and the notes *are*
carried in an autosave snapshot, because both live outside the markdown and
drawing alone already makes a deck dirty.

## Git storage (`services/git/`)

A deck source that is "WebDAV with version history". Two planes sit behind one
interface:

- **Forge REST plane** (all platforms) — `GitForge` with three adapters
  (`gitea_forge.dart` for Gitea/Forgejo, `github_forge.dart`, `gitlab_forge.dart`).
  Transport is SSRF-pinned (`git_transport_io.dart` / `_web.dart`): https-only
  unless the server is marked trusted-internal, resolve-then-pin against DNS
  rebinding, no redirects, byte caps.
- **Native git plane** (desktop, when `git` is present) — `NativeGitMirror` over a
  real partial clone. It makes true local commits (`hasRealHistory == true`), so
  work survives offline and the history dialog and release/version chooser have
  something real to show.

`DeckMirror` is the seam between them: the editor always writes to the mirror, and
`SyncEngine` + `outbox.dart` reconcile with the forge later — losing the connection
must never lose work. Deck↔repo conversion lives in `deck_repo_serializer.dart`;
`deck_search.dart` adds cross-deck search. State: `state/git_provider.dart` and the
`tabs_provider_git*` files; UI: the `shell_actions_git*` family. Design rationale:
[`design/GIT_STORAGE.md`](design/GIT_STORAGE.md).

## The privacy projection boundary

`services/privacy/privacy_projection.dart` is a type-enforced chokepoint, not a
convention. `PrivacyProjection.forAudience(...)` is the only way to obtain an
`AudienceDeck` (its constructor is private), and every surface that can *emit*
content — the rasterizer, the export bundle and dialog, the fullscreen presenter,
the slide-list clipboard — accepts an `AudienceDeck` rather than a raw `Deck`. A
`check_conventions` guard (`audienceBoundary`) fails the build if a receiving
surface takes a raw `Deck`/`List<Slide>`, so redaction cannot be bypassed by
forgetting a call. `forExternalProcessing(...)` is the stricter variant for
hand-off outside the app.

The boundary is about what *leaves*, so the author's own editor sits on the
source side: the preview, the thumbnails and the slide list render the raw deck,
because a screen that blacks out your own sentence leaves you nothing to correct.
`services/privacy/privacy_preview.dart` is the one deliberate crossing back —
`audiencePreviewSlide` runs a *single* slide through `forAudience` and hands the
projected `Slide` to the preview, on request, so the author can look at the
recipient's version. It projects one slide rather than the deck because the
projection scans, and rescanning a deck on every keystroke in the editor beside
it would make the preview unusable; the scanner escalates within a slide, so the
result for that slide is the same either way.

The type says a deck went through the boundary; it does not say the boundary
looked at every field. That second half is a list written by hand in three
places — the scanner's fragments, the projection, and the redaction manifest —
and the compiler connects none of them. When one lags, the export gate reports a
finding that *Redact* cannot clear and the value travels anyway, which is how six
deck fields and a slide's checklist scope stayed unredacted until July 2026.
`test/privacy_scan_redact_parity_test.dart` is the ratchet that holds the three
lists together; it names the field that is missing rather than only failing.

Adjacent egress control: `services/ai_security_gate.dart` is a pure, I/O-free
decision run before every AI request (mode, consent, loopback/trusted-internal/
cloud rules, fail-closed on web); `utils/zip_encryption.dart` backs encrypted
`.ocideck` packages; `services/cve/` holds the desktop-only offline CVE index.

## Vendored forks

Two upstream plugins are forked into `third_party/` and wired via `pubspec.yaml`
(path dependency / `dependency_overrides`):

- **`desktop_multi_window`** (MixinNetwork, **Apache-2.0**) — vendored fork with
  `window_setFrame`, `window_coverScreen` (borderless fill of a chosen screen),
  and `window_close` on **macOS, Windows, and Linux**. macOS additionally tracks
  the mouse for non-key windows so chart hover works on the beamer.
- **`screen_retriever_macos`** (leanflutter, MIT) — a Swift Package Manager
  layout added for recent Xcode/CocoaPods; no upstream file edited.

Each fork carries a `MODIFICATIONS.md` naming the upstream commit it descends
from and every local change, and — for the Apache-2.0 one — each changed file
opens with the §4(b) notice that licence requires. The SBOM records the same
commit plus a SHA-256 tree hash of the directory.

If you bump either upstream, re-apply the local changes, update
`MODIFICATIONS.md` and `_forkOrigins` in `tool/sbom_build.dart`, run `make sbom`,
and re-test the dual-screen presenter.

## Information-security module (optional, off by default)

The MIAUW pentest-reporting module (design: `docs/design/PENTEST_MIAUW.md`) is
gated behind `state/info_safety_provider.dart`: `infoSafetyRevealProvider` stays
false until the user enables it in Settings, so its UI (a dedicated slide-picker
tab, command-palette actions, the report template) is hidden otherwise. It rides
the existing rails rather than adding a parallel stack:

- **Slide types** — `finding`, `findingsSummary`, `checklist`, `scopeMatrix` and
  `signOff` are ordinary entries in the `slideTypeMeta` registry
  (`models/slide.dart`); each carries a `_class` token and round-trips its
  structured data as `<!-- ocideck_* -->` comments like every other type. A
  **finding** is authored as a *group*: a header slide plus detail / evidence
  slides sharing one `ocideck_finding_id` and a `FindingRole`.
- **Domain services** (pure, network-free) — the native **CVSS 4.0** engine
  (`services/cvss/`), the offline **CWE** and **MIAUW EIS** catalogs, the finding
  numbering / evidence hashing / scope-coverage / management-summary /
  compliance-analyzer derivations, and the audit-dossier index builder
  (`services/audit_dossier.dart`).
- **Document integrity** — `services/document_integrity.dart` seals a finalised
  deck with a SHA-512 hash over the **bytes of the `.md`**, recorded beside the
  file in `<name>.seal.json` (`services/seal_codec.dart`) together with the
  visible signature. Because the seal sits outside the file it covers, a
  recipient recomputes it with `sha512sum` — no OciDeck, no specification to
  replay. Re-verified on open by comparing that value with the hash of the bytes
  just read. An optional **RFC 3161** token
  (`services/rfc3161_timestamp.dart`, with a hand-rolled ASN.1 DER codec in
  `utils/asn1_der.dart` — no new dependency) binds the hash to a claimed time;
  OciDeck compares the token's imprint and nothing else — no CMS signature, no
  certificate chain — and never contacts a TSA itself.
- **Audit dossier** — `parts/file_service_dossier.dart` reuses the AES-256
  package builder to bundle the sealed report, its evidence and the hash tables
  into one encrypted `.ocideck` archive plus an `AUDIT_DOSSIER.md` index.
- **Optional AI** — a shared, off-by-default backend (`services/ai_*`) drafts
  finding text and image alt-text behind the outbound-privacy consent; drafts are
  marked `ocideck_ai_assisted` and block sealing until a human reviews them. The
  marker also survives the file boundary: while it is present, every PDF, PPTX
  and HTML export declares it in its document properties and its filename (see
  § Classification enforcement). Export itself is not blocked — sealing is a statement,
  sending a draft to a reviewer is the normal way to get it cleared.

## Localization

Dutch is the source language: UI code calls `d('Nederlandse brontekst')` (literal
source) or `t('key')` (keyed). `l10n/app_localizations.dart` keeps only the
`AppLocalizations` class and delegate, and **assembles** the three lookup maps
(`_strings`, `_dutchSourceStrings`, `_dutchSourceStringAdditions`) from one file
per language. The translation data lives in `l10n/translations/<lang>.dart` (31
languages), each a `part of '../app_localizations.dart'` that declares
`_strings<Lang>`, `_dutchSource<Lang>`, and (for the languages that need later
additions) `_dutchSourceAdd<Lang>` (Dutch only needs `_stringsNl`, being the
source). For a Dutch source string `d()` reads the additions map before the
primary map, so a key must never live in both (guarded by
`test/l10n_duplicate_keys_test.dart`); every `d()`/`t()` string is required in all
languages by `test/app_localizations_test.dart`.

**Homographs — use `t()`, not `d()`.** Because `d('bron')` keys on the Dutch
text, a word that spells the same but means different things in different
contexts collapses to one translation. Reach for a keyed `t('...')` string in
that case, so each meaning gets its own value. Concrete example: the cockpit
artificial-horizon roll angle `d('Bank')` (translated as aviation *Roulis /
Rollen / Alabeo*) and the financial bank on the About page (`t('bankLabel')` →
*Banque / Banco / …*) — one Dutch word, two meanings, two keys. This is the one
class the shadowing guard cannot catch, because it is a semantic collision, not a
data duplicate.

- **Translate or add a string:** edit the relevant language file(s). A test
  (`test/app_localizations_test.dart`) fails unless every literal `d('…')` has a
  translation in *every* language.
- **Add a language:** create `translations/<lang>.dart`, add its `part` directive
  and its entry in each of the three assembly maps in `app_localizations.dart`,
  and register it in `supportedLocales` and `languageNames`.
