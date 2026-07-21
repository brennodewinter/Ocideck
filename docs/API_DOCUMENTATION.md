# OciDeck — API Documentation

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

### Question Model
`lib/models/question.dart` — the payload of a `question` slide, carried as JSON in
`Slide.customMarkdown` (see [FILE_FORMAT.md](FILE_FORMAT.md) for the block).

`QuestionKind` (6 values): `multipleChoice, trueFalse, multipleCorrect, ordering,
imagePair, openText`. `QuestionOnWrong` (2 values): `retry, lockAndContinue`.
`QuestionResult` (3 values): `none, correct, wrong`.

Two classes, deliberately separate:

- **`QuestionSpec`** — what the author wrote: `kind`, `prompt`,
  `List<QuestionAnswer> answers` (each `text`, `correct`, and for `imagePair` an
  `image` path), `optionCount`, `timeLimitSeconds`, `onWrong`, `statementIsTrue`
  and `similarityThreshold`. It round-trips through `toBlock()` / `parse()`;
  `isPresentable` says whether it can be shown at all, and the rule differs per
  kind (`trueFalse` always can, `ordering` needs two answers, `openText` needs
  only a correct one, the rest need a correct *and* a wrong one).
- **`QuestionView`** — the drawn round, **session-only**: the options actually
  shown, `optionImages`, the pick, `openText`/`typedAnswer`, `result`, `revealed`,
  `locked`, `matchScore` and the countdown. It crosses the window channel to the
  audience window and drives what both screens paint — which is why an `openText`
  round leaves `expectedAnswer` empty until the answer is revealed. That is a
  render rule, not a confidentiality one: the audience window is separately handed
  the whole deck markdown, `correct` flags included. `answerable` is the flag for
  "a right answer can actually be given"; the presenter uses it instead of testing
  `correctIndices.isEmpty`, which `openText` cannot express because it draws no
  options.

`RehearsalRun` (`lib/models/rehearsal.dart`) carries a `List<QuestionAttempt>`
alongside its per-slide timings: one entry per *answered* attempt, with the
slide id, index, duration and whether it was right.

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

### ExportService
`lib/services/export_service.dart` — export to PDF, PPTX, and HTML:

```dart
// ExportFormat is { pdf, pptx, html }. Images are pre-rendered by the caller.
Future<ExportResult> export(
  String deckPath,
  ExportFormat format,
  List<Uint8List> images, { /* … */ });
```

Export metadata is built from the deck via the factory
`ExportDocumentMetadata.fromDeck(Deck deck)` (`lib/services/export_metadata.dart`).

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

### Git Integration API
`lib/services/git/git_forge.dart` — `GitForge` is the abstract forge adapter.
There are three REST implementations: `GiteaForge` (Forgejo and Gitea),
`GitlabForge` (gitlab.com and self-hosted) and `GithubForge`:

```dart
Future<List<RepoEntry>> listTree(String ref, String path, {bool recursive});
Future<Uint8List> readBlob(String ref, String path);
Future<String> headSha(String branch);
```

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

## Extending OciDeck

### Adding a slide type
1. Add a value to the `SlideType` enum in `lib/models/slide.dart` (append, so the
   stored token stays stable) and any type-specific fields on `Slide`.
2. Add its editor widget and its preview rendering in `lib/widgets/slides/`.
3. Add serialization/parsing in the markdown services
   (`markdown_service_serialize.dart` / `markdown_service_parse.dart`).
4. Cover the round-trip in `test/markdown_round_trip_test.dart`.

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

OciDeck is pre-release (currently 0.2.0) and has no formal versioning scheme yet.
These interfaces are internal and change freely between builds; the `.md`/Marp
on-disk format is the stable contract and is documented in
[`docs/FILE_FORMAT.md`](FILE_FORMAT.md).
