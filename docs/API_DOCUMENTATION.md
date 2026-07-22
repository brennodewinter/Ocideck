# OciDeck — API Documentation

> **Status:** current-state reference for internal APIs · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

This document describes the key internal APIs and interfaces in the OciDeck
codebase. OciDeck is not a library with a published public API; the surfaces
below are the seams a contributor works with when extending the app. Signatures
are kept in sync with the source under `lib/` — if one drifts, the source is the
source of truth.

## Overview

OciDeck follows a modular architecture: immutable models, a service layer for
serialization/export/privacy/git, and Riverpod `StateNotifier`s for app state.
The sections below cover the primary models, service interfaces, and state
providers.

## Core Data Models

### Deck Model
`lib/models/deck.dart` — `Deck` is an immutable presentation:
- Metadata: `title`, `author`, `organization`, `description`
- `List<Slide> slides`
- `ThemeProfile themeProfile`
- `TlpLevel tlp` (classification level)
- `Map<String, String> userNotes` and per-slide ink `annotations`
- `int presentationTargetSeconds` (presentation timing target)

The audience gates are top-level functions in the same file, not methods:

```dart
bool slideVisibleAtTlp(Slide slide, TlpLevel presentationTlp);
bool slideWithheldByTlp(Slide slide, TlpLevel presentationTlp); // its negation
int  withheldSlideCount(Deck deck);                            // for the editor
bool slideReachesAudience(Slide slide, {
  required TlpLevel presentationTlp,
  required bool includeDetail,
}); // skipped ∧ TLP ∧ detail — the one place the three gates meet
TlpLevel effectiveTlp({required TlpLevel deckTlp, required TlpLevel slideTlp});
TlpLevel deckReleaseTlp(Deck deck); // strictest level anywhere in the deck
```

`slideWithheldByTlp` exists beside `Slide.skipped` deliberately: both end in the
slide not reaching the audience, but a skip is an authoring choice and a
withholding is a policy consequence, so the UI has to be able to say which.

### Slide Model
`lib/models/slide.dart` — `Slide` is an immutable value object (all fields
`final`, `const` constructor). It is **not** a generic property bag: besides
`id` and `SlideType type`, it carries ~50 strongly-typed, type-specific fields
(`title`, `subtitle`, `bullets`, `tableRows`, `imagePath`, `quote`, `findingId`,
`tlp`, per-slide style overrides such as `titleTextColorOverride`, …). A field is
only meaningful for the slide types that use it.

`SlideType` (24 values): `title, section, bullets, twoBullets, bulletsImage,
twoImages, image, video, quote, table, freeMarkdown, code, chart, cockpit,
question, timeline, scorecard, assets, discoveries, finding, findingsSummary,
checklist, scopeMatrix, signOff`.
The last seven — from `assets` onward — are the informatieveiligheid
(pentest-reporting) layouts, hidden until the module is enabled. Note the
Marp `_class` token stored in Markdown can differ from the enum name (e.g. the
`split` class maps to `SlideType.bulletsImage`).

Per-type *pure data* lives in one place: the `slideTypeMeta` registry beside the
enum (`label`, `marpClass`, `splitWithImage`, `isHeading`, `category`,
`bulletColumns`, `backedByTable`), read through the `SlideTypeExtension`
getters. A guard test (`test/slide_type_meta_test.dart`) fails when a type is
missing an entry, and checks `backedByTable` against a real
serialize-then-parse round trip so the flag cannot drift from behaviour. UI
behaviour stays in the widget layer's registries (`slideEditorBuilders`,
`slideTypeIcons`) — the model layer imports no Flutter.

### ThemeProfile Model
`lib/models/settings.dart` — visual styling: colors, fonts (`fontFamily`,
`codeFontFamily`), logo (`logoPath`, `logoPosition`, `logoSize`) and footer
(`footerText`, `footerShowPageNumbers`, `footerPosition`). Per-slide visual
overrides live on `Slide`, not here.

## Key Service Interfaces

### MarkdownService
`lib/services/markdown_service.dart` — serialization of Marp Markdown with
OciDeck extensions:

```dart
// Generate Marp Markdown from a Deck.
String generateDeck(Deck deck, {
  bool inlineChartData = false,
  bool inlineStyleProfile = false,
  bool forExport = false,
});

// Parse Markdown back into a Deck. Returns null on unparseable input.
Deck? parseDeck(String markdown, {String? filePath});
```

Structural pre-flight validation is a separate class; `validate` is an instance
method, `MarkdownValidationResult validate(String markdown)`, in
`lib/services/markdown_validator.dart`, which returns a `MarkdownValidationResult`
(`lib/models/markdown_validation.dart`).

### FileService (deck read/write)
`lib/services/file_service.dart` — opening and saving a deck as a project folder.
Each direction comes in a plain form and a `…Detailed` form; the detailed one
also reports the chart data files it could not handle, and the plain one is a
wrapper for callers with nothing to report:

```dart
Future<Deck?> openDeck(String filePath, {String? content});
Future<({Deck? deck, OpenFailure? failure, List<String> warnings})>
    openDeckDetailed(String filePath, {String? content});

Future<Deck> saveDeck(Deck deck, String filePath);
Future<({Deck deck, List<String> chartWarnings})>
    saveDeckDetailed(Deck deck, String filePath);

Future<String?> saveDeckAs(Deck deck, {String? initialDirectory});
Future<({String? path, List<String> chartWarnings})>
    saveDeckAsDetailed(Deck deck, {String? initialDirectory});
```

The two warning lists are not the same problem. On open, an unreadable data file
means a chart draws empty. On save, writing the deck has just moved the numbers
out of the markdown, so a data file that could not be written means they exist
nowhere but the open window — which is why `whileSaving` rides along on
`ChartDataWarning` and the shell shows an error rather than a note. `path` is
null when the user dismissed the file picker.

### ExportService
`lib/services/export_service.dart` — export to PDF, PPTX, and HTML:

```dart
// ExportFormat is { pdf, pptx, html }. Images are pre-rendered by the caller.
Future<ExportResult> export(
  String deckPath,
  ExportFormat format,
  List<Uint8List> images, {
  ExportBundle? audience, /* … */ });
```

The HTML markdown and the PPTX speaker notes come from `audience`, never from
loose strings: an `ExportBundle` cannot be built without an `AudienceDeck`, and
that type can only be produced by `PrivacyProjection`. `export` is listed in the
`audienceBoundary` guard (`tool/check_conventions.dart`), so the build fails if
that parameter is ever replaced by a raw `Deck` or `List<Slide>`.

Export metadata is built from the projected deck via the factory
`ExportDocumentMetadata.fromDeck(AudienceDeck audience)`
(`lib/services/export_metadata.dart`) — the six fields it copies (title, author,
organization, description, keywords, TLP) land readable in PDF info and PPTX
docProps, so taking a raw `Deck` there would make "forgot to project" a silent
leak.

That same factory counts one value over the projected slides rather than copying
it, because it is a fact about the deck and not something an author fills in:

```dart
final int unreviewedAiSlideCount; // slidesWithUnreviewedAiMarkers(deck).length
bool    get hasUnreviewedAi;      // count > 0
String? get htmlAiMarking;        // kAiDraftKeyword, or null — mirrors htmlClassification
String  get fileSuffix;           // kAiDraftFileSuffix ('-ai-concept'), or ''
```

`subject()` and `exportKeywords()` fold the same state in (`kAiDraftSubjectNote`
after the title, `kAiDraftKeyword` among the keywords). All of them are inert
when the count is zero, which is the state a reviewed deck is in — the marker
exists to be cleared. The three constants are untranslated on purpose: they are
read by tools, not by people.

`metadata` is an optional parameter, so `export` does not trust it for this one
value: whenever `audience` is present it recounts with
`withAiMarkingFrom(AudienceDeck)`. A caller that passes a bundle but no metadata
therefore still declares, and a caller that hand-builds metadata can neither
suppress the declaration nor keep it on a deck that has been reviewed.

### Privacy Projection API
`lib/services/privacy/privacy_projection.dart` — applies redaction and audience
scoping. The entry points are **static**:

```dart
// Project a deck for a given audience (own-identity aware).
static AudienceDeck PrivacyProjection.forAudience(Deck deck, {
  Set<String> disabledRules,
  OwnIdentity ownIdentity,
  PrivacyExportProfile profile,
});

// Stricter projection for hand-off to external processing (e.g. AI).
static AudienceDeck PrivacyProjection.forExternalProcessing(/* … */);
```

Export-time gating (does this audience deck satisfy the export policy?) lives in
`PrivacyExportGate` (`lib/services/privacy/privacy_export_policy.dart`).
`PrivacyDisposition` (`{ warn, accept, shield, redact }`) is defined in
`lib/models/privacy_disposition.dart`.

`lib/services/privacy/privacy_preview.dart` is the author-facing detour: the same
projection over a single slide, so the editor preview can show what the recipient
gets without rescanning the deck on every keystroke.

```dart
Slide audiencePreviewSlide(Deck deck, Slide slide, {
  Set<String> disabledRules,
  OwnIdentity ownIdentity,
});
bool slideIsRedacted(Deck deck, Slide slide); // effective disposition == redact
```

### Git Integration API
`lib/services/git/git_forge.dart` — `GitForge` is the abstract forge adapter.
There are three REST implementations: `GiteaForge` (Forgejo and Gitea),
`GitlabForge` (gitlab.com and self-hosted) and `GithubForge`:

```dart
Future<List<RepoEntry>> listTree(String ref, String path, {bool recursive});
Future<Uint8List> readBlob(String ref, String path);
Future<String> headSha(String branch);
```

The three REST adapters share their HTTP plumbing through the `ForgeHttp` mixin
(`lib/services/git/forge_http.dart`): request/JSON handling, the status-to-
`GitForgeException` translation and the ref check. It is deliberately not a new
layer — `GitForge` stays the contract — and each adapter still supplies its own
URL shape, auth header, error-message name and 409 meaning.

Alongside the REST path, a native-git path (`NativeGitMirror`,
`lib/services/git/native_git_mirror_api.dart`) makes real local commits and
carries version history; see [`docs/design/GIT_STORAGE.md`](design/GIT_STORAGE.md).

## Riverpod State Management

### DeckProvider
`lib/state/deck_provider.dart` — `DeckNotifier extends StateNotifier<DeckState>`
manages the open deck and its undo/redo history:

```dart
void loadDeck(Deck deck, {String? filePath, String? remoteOrigin});
Future<void> openDeck({String? initialDirectory});
void newDeck(/* … */);
Future<bool> save({String? initialDirectory}); // false if the user cancels
void undo();
void redo();

// Callbacks, because this notifier has no Ref and TabsNotifier does.
void Function()? onSweepWebAssets;
void Function(List<String> sources)? onChartDataWarnings;
```

### SettingsProvider
`lib/state/settings_provider.dart` — `SettingsNotifier extends
StateNotifier<AppSettings>` handles application configuration:

```dart
Future<void> saveThemeProfile(ThemeProfile profile, { /* … */ });

// Classification is set through granular setters, not one policy object:
Future<void> setRequireClassificationOnExport(bool enabled);
Future<void> setClassificationWatermarkEnabled(bool enabled);
```

The `ClassificationEnforcementPolicy` used at export time is **built** from the
current settings via `ClassificationEnforcementPolicy.fromAppSettings(...)`; it is
not stored wholesale on the settings state.

## Security & Utility APIs

### NetGuard
`lib/utils/net_guard.dart` — SSRF protection for outbound requests:
`isBlockedHost`, `isBlockedAddress`, and `safeResolve` reject loopback, RFC1918,
link-local, cloud-metadata, CGNAT, ULA and IPv4-in-IPv6 targets, and return the
resolved address so the caller can pin the socket against DNS rebinding.
Redirect prevention and byte caps are enforced at the transport layer that calls
NetGuard (`file_service_net.dart`, `git_transport_web.dart`), not inside NetGuard
itself.

### Asset Path Containment
`lib/utils/project_path.dart` — a set of top-level functions (not a class) keep
asset references inside the project folder: `resolveSlideAssetPath`,
`resolveContainedRealPath`, `isRenderPathContained`, `resolveProjectRelative` /
`resolveProjectAbsolute`, `resolveTrustedAssetPath`, `resolveEditorAssetPath`.
Containment is checked with `p.isWithin` from the `path` package; absolute paths
and `../` escapes are refused on the render/present/export paths.

### SecretStore
`lib/services/secret_store.dart` — OS keychain integration via
`flutter_secure_storage` (macOS Keychain, Windows Credential Manager, and the
platform-appropriate backend elsewhere). Typed accessors:
`write/read/deleteWebdavPassword`, `write/read/deleteS3SecretKey`,
`write/read/deleteAiApiKey`, `write/read/deleteGitToken`. Only secrets go here;
server URLs, usernames and the S3 access key ID stay in the prefs domain.

### ClassificationEnforcementPolicy
`lib/services/classification_enforcement_policy.dart` — export classification gate:

```dart
// Returns an allow / block-with-reason decision for a deck's TLP level.
ExportDecision evaluate(TlpLevel deckLevel);
bool get hasGate;
```

Construct it with `ClassificationEnforcementPolicy.fromAppSettings(...)` or
`.fromMaxReleaseKey(...)`. `ExportDecision` is in
`lib/services/classification_policy.dart`.

## Media & Web APIs

### ImageService
`lib/services/image_service.dart` — a concrete service (not an injectable
interface) for importing and resolving images. Images are validated by magic
bytes, not extension (`imageMimeFromBytes` accepts PNG, JPEG, GIF, BMP, WebP).
Key methods: `pickImage` / `pickImageDetailed` (→ `ImageImportOutcome`),
`pasteImage` / `pasteImageDetailed`, `readSlideImageBytes`, `copyImagesToProject`,
`copyMediaToProject`.

### WebAssetStore
`lib/services/web_asset_store.dart` — in-memory image store for the web build,
keyed under a `mem:` path scheme. Static `put(bytes, {name})`, `bytesFor`,
`nameFor`, `clear`, `isMemPath`.

### Fetch proxy (web only)
There is no `FetchProxyService` class. On the web, URL fetches that CORS would
block are routed through a **server-side** `fetch-proxy?url=…` endpoint (see
[`server/fetch-proxy/README.md`](../server/fetch-proxy/README.md)). Clients call
it via `FileService.fetchUrlBytes(String url, {int maxBytes, …})`
(`lib/services/parts/file_service_net.dart`), which falls back to the proxy on
web; the git web transport uses the same endpoint.

## Export readiness
`lib/services/export_readiness.dart` — one pure function folds the four gates
into the single status the status-bar chip and the export dialog both render:

```dart
ExportReadiness evaluateExportReadiness({
  required bool needsSave,
  required ExportDecision classificationDecision,
  required QualityExportDecision qualityDecision,
  PrivacyExportDecision privacyDecision,
  bool privacyChecksEnabled,   // the setting, not the outcome
});
```

`ExportReadinessStatus` (8 values): `ready, readyPrivacyUnchecked,
qualityWarnings, privacyWarnings, needsSave, blockedByClassification,
blockedByPrivacy, blockedByQuality`. Only `needsSave` makes
`ExportReadiness.canOpenExport` false. `readyPrivacyUnchecked` exists because a
disabled privacy check yields an empty scan result, which is indistinguishable
from a clean one: callers must pass `privacyChecksEnabled` so "we found nothing"
is not rendered on top of "we did not look".

## Extending OciDeck

### Adding a slide type
1. Add a value to the `SlideType` enum in `lib/models/slide.dart` (append, so the
   stored token stays stable) and any type-specific fields on `Slide`.
2. Add its `slideTypeMeta` entry in the same file — including `bulletColumns`
   when it shows flowing bullet text and `backedByTable` when its content lives
   in `Slide.tableRows`. These two drive the split action, the bullet splitter
   and the table side of the Markdown round trip; getting them right here means
   there is nothing to register in `markdown_service_parse.dart`.
3. Add its editor widget (`slideEditorBuilders`) and its preview rendering in
   `lib/widgets/slides/`.
4. Add serialization in `markdown_service.dart`.
5. Cover the round-trip in `test/markdown_round_trip_test.dart`.

Adding a value makes the analyzer reject eleven non-exhaustive switches across
eight files; those remaining spots are genuinely per-type (renderer, wireframe,
help text, writer, fit-scale geometry, contrast pairs) and are deliberately not
tabulated.

### Adding an item to the macOS menu bar
`lib/widgets/shell/app_menu_bar.dart` — `buildAppMenus(l10n, actions, deck)` is a
pure function returning `List<PlatformMenuItem>`, so `test/app_menu_bar_test.dart`
can assert labels, shortcuts and enablement without opening a window.

An action that needs no open presentation goes on `AppMenuActions`, which
`AppShell` fills directly. An action that lives inside the per-tab editor layer
goes on `AppDeckMenuActions`, and the workspace publishes it through
`ShellDeckCommands` / `shellDeckCommandsProvider`
(`lib/widgets/shell/shell_deck_commands.dart`); a `null` provider value means "no
deck open", which greys the items rather than removing them. Only the visible tab
publishes, and only when an enablement flag changes — `sameEnablement` keeps the
menu from being rewritten to the platform on every frame.

## Testing APIs

### Golden tests
`test/golden/` — slide-renderer visual-regression goldens over
`SlidePreviewWidget`. They are excluded from the default suite (pixel- and
platform-specific); run with `make test-golden`, accept intended changes with
`make test-golden UPDATE=1`.

### Fakes for tests
The suite drives platform seams with fakes (a fake `VideoPlayerPlatform` for the
media lifecycle, a fake `UrlLauncherPlatform` for external-link tests) rather
than a formal mock framework — see the `dev_dependencies` in `pubspec.yaml`.

## Compatibility

OciDeck has never tagged a release and has no versioning scheme, so there is no
version these interfaces are stable *against* — see
[MIGRATION_GUIDE.md](MIGRATION_GUIDE.md). They are internal and change freely
between commits; the `.md`/Marp on-disk format is the stable contract and is
documented in [`docs/FILE_FORMAT.md`](FILE_FORMAT.md).

*(Corrected 2026-07-22: this read "pre-release (currently 0.2.0)", which reads as
a version claim. `0.2.0+1` is a string in `pubspec.yaml`; no tag carries it and
the app never shows it.)*
