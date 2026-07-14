# OciDeck — Source Map

A one-line index of every Dart file under `lib/`, grouped by directory. It
complements [`ARCHITECTURE.md`](ARCHITECTURE.md) (the *why* and the cross-cutting
flows) with a *what-is-this-file* lookup. For the on-disk file format see
[`FILE_FORMAT.md`](FILE_FORMAT.md).

> Keep this in sync when you add, remove, or repurpose a file. The directory
> structure mirrors the layers in `ARCHITECTURE.md` § Module layout.

## Entry point

- `main.dart` — App entry: initialises the binding, routes a second-window launch
  to the audience window, otherwise runs `OciDeckApp` in a `ProviderScope`.
- `app.dart` — `OciDeckApp` root `MaterialApp` (theme, localization delegates) and
  the `_ConsentGate` that blocks the UI until consent is given.

## `lib/models/` — data model

- `annotation.dart` — `InkStroke` and `InkTool` enum for freehand drawing annotations on presentation slides.
- `chart.dart` — `ChartSpec`/`ChartSeries` and the `ChartType` enum (bar, stacked/horizontal bar, combo, line, area, pie, donut, radar, scatter, waterfall, heatmap) for chart slides with inline or CSV data.
- `checklist_spec.dart` — `ChecklistSpec` for the security checklist slide (MIAUW tri-state test list linked to findings).
- `checklist_template.dart` — `ChecklistTemplate`/`ChecklistTemplateItem`: a user-created reusable checklist stored in the settings (feedback #9), with tolerant `encodeList`/`decodeList`.
- `cockpit.dart` — `CockpitSpec`/`CockpitMeterSpec` for instrumentation gauges (speedometer, voltmeter, etc.).
- `cvss_builder.dart` — CVSS 4.0 Base-metric metadata + vector assembly, `CiaRating`→`CR`/`IR`/`AR` mapping, `baseCvss4Vector` and `contextCvss` (derive a CIA-weighted context score).
- `cwe_entry.dart` — `CweEntry` for the offline CWE catalog (id/name/description/remediation).
- `wstg_test.dart` — `WstgTest` for the offline WSTG catalog (id/title/category).
- `deck.dart` — `Deck` with metadata, TLP classification, slides list, annotations, user notes, and MIAUW waivers.
- `deck_template_security.dart` — The module-only **MIAUW-pentestrapport** deck template (`_buildMiauwReport`): scaffolds the full MIAUW report structure across the security slide types.
- `document_signature.dart` — `DocumentSignature`, the reusable visual signature for sign-off and the document seal.
- `eis_entry.dart` — `EisEntry`/`EisPart`/`EisDerivation`/`EisCheck` for the MIAUW compliance schema.
- `finding_spec.dart` — `FindingSpec`: the structured content of a `finding` header slide (scope, CVSS, CWE, CVE, retest status, sections); `RetestStatus` (hertest outcome).
- `finding_template.dart` — `FindingTemplate`, a reusable finding starter parsed from Markdown with YAML front matter.
- `findings_summary_spec.dart` — per-severity findings-summary counts + retest-resolved total + `deckFindingSeverities` / `deckRetestResolvedCount` derivations.
- `markdown_validation.dart` — `MarkdownValidationResult`/`MarkdownValidationIssue` for linting markdown content.
- `miauw_compliance.dart` — `MiauwComplianceResult`/`EisResult`/`EisStatus` for the compliance overview.
- `question.dart` — `QuestionSpec`/`QuestionView` for interactive quiz slides (multiple-choice/true-false/multiple-correct/ordering).
- `rehearsal.dart` — `RehearsalRun`/`SlideTiming` for tracking presentation-practice durations per slide.
- `scope_matrix_spec.dart` — `ScopeMatrixSpec`/`ScopeRow`/`ScopeObjectType`/`ScopeStatus` for the scope-matrix slide; each row carries a `CiaRating` (serialised as the `C`/`I`/`A` columns).
- `privacy_disposition.dart` — `PrivacyDisposition` (warn/accept/shield/redact) and the slide-overrides-deck resolution.
- `privacy_finding.dart` — `PrivacyFinding`/`PrivacyScanResult`: what the privacy scanner found. Never stores the raw value — only a masked sample.
- `settings.dart` — `AppSettings`, `ThemeProfile` (incl. severity tokens + built-in Security profile), `AppAppearanceProfile`, `CockpitColorScheme` config.
- `slide.dart` — `Slide` model with typed fields; `SlideType` enum for the slide layout variants.
- `slide_quality.dart` — `SlideQualityResult`/`SlideQualityIssue` for accessibility/contrast/density/privacy audits.
- `timeline.dart` — `TimelineEvent` and `TimelineLayout`/`TimelineReveal` enums for animated timeline slides.
- `video_source.dart` — `VideoSource` parser for local files, YouTube, Vimeo, and remote video URLs.
- `webdav_settings.dart` — `WebdavServer`/`WebdavOrigin` for Nextcloud/WebDAV integration configuration.

## `lib/services/` — business logic & IO

- `ai_alt_text_cleanup.dart` — Counts and clears still-unreviewed AI-generated image alt-texts (the bulk-wipe safety net).
- `ai_client_service.dart` — The gated, provider-agnostic `/v1` client for the optional local AI backend.
- `ai_request.dart` — `AiChatRequest`/`AiMessage`/`AiImagePart` request model + the shared system guardrail prompt.
- `ai_security_gate.dart` — Enforces the AI opt-in/consent/endpoint gate before any outbound AI call.
- `annotation_codec.dart` — Serializes slide annotation layers with content fingerprints.
- `audit_dossier.dart` — `buildAuditDossier`: the MIAUW §10.11 audit-dossier index (report identity, seal facts, summary, compliance tally, evidence hash table) as deterministic Markdown.
- `caption_service.dart` — Stores image captions in JSON sidecars per image directory.
- `classification_enforcement_policy.dart` — Enforces deck TLP classification rules on export (the authoritative gate).
- `classification_policy.dart` — Thin backward-compatible wrapper around the TLP export ceiling only.
- `cvss/cvss4.dart` — Native-Dart port of the FIRST CVSS v4.0 calculator (metrics, parse, score, severity); `cvss4_lookup.dart` + `cvss4_scoring.dart` are its lookup-table/scoring parts.
- `cwe_catalog.dart` — The offline CWE catalog (`CweCatalog`): a curated floor merged with the full MITRE list from `assets/cwe/cwe_full.json` (via `ensureLoaded`); search/byId.
- `cve_search_service.dart` — `CveSearchService` + `CveSource` cascade (`LibrekatCveSource` mirror → `EnisaCveSource` EUVD keyword search → `MitreCveSource` exact-id lookup); `CveHit` in `models/cve_hit.dart`.
- `cve_transport.dart` / `cve_transport_io.dart` / `cve_transport_web.dart` / `cve_transport_factory.dart` — injectable, SSRF-pinned HTTP transport for the CVE search (io) with a web stub, selected by conditional export.
- `wstg_catalog.dart` — The bundled offline OWASP WSTG v4.2 test catalog (`WstgCatalog`, 97 tests + pinned version) used to one-click-fill a `checklist` slide.
- `checklist_templates.dart` — `ChecklistSource` + helpers that present WSTG and each user `ChecklistTemplate` uniformly to the checklist editor and the per-scope generator (feedback #9).
- `description_service.dart` — Stores searchable image descriptions as JSON sidecars.
- `document_integrity.dart` — Computes/verifies the SHA-512 deck seal and seals a finalised deck.
- `evidence_hash_service.dart` — Computes the MIAUW SHA1 + SHA-256 of evidence bytes and builds the appendix hash table.
- `export_bundle.dart` — `ExportBundle`: everything an export needs for one audience profile. A factory the export dialog holds, so it can pick the profile without ever touching the source deck.
- `export_metadata.dart` — `ExportDocumentMetadata` stamped into PDF/PPTX/HTML (title, author, org, keywords, TLP).
- `export_service.dart` — The single chokepoint that renders decks to PDF, PPTX, and HTML.
- `file_service.dart` — Scans presentation files, opens decks (with the safety gate), and import/URL/package IO. Part `parts/file_service_dossier.dart` builds the one-click audit dossier (package + `AUDIT_DOSSIER.md` + optional `report.pdf`, AES-256).
- `finding_ai_service.dart` — Drafts a free-text finding field via the AI backend, grounded on the tester's facts; strips fabricated CWE/CVE/CVSS ids.
- `finding_group_builder.dart` — `buildFindingGroup`: assembles a finding header + optional detail/evidence slides sharing one id.
- `finding_numbering.dart` — `renumberFindings` (F-01… from deck order) + `deckFindingList` derivation.
- `finding_template_library.dart` — The bundled reusable finding-template library with search.
- `image_alt_ai_service.dart` — Vision consumer: suggests WCAG alt-text and searchable tags for an image via the local backend.
- `image_dedup_service.dart` — Finds byte-identical image files by md5 to clean up libraries.
- `image_sidecar_store.dart` — Shared read/mutate/atomic-write layer for the per-directory JSON sidecars of captions and descriptions.
- `image_reference_service.dart` — Finds and rewrites image references in Marp markdown files.
- `image_service.dart` — Validates and manages imported image and media asset files.
- `markdown_body_blocks.dart` — Splits markdown into code blocks and paragraphs.
- `markdown_safety.dart` — Scans raw `.md` for executable content and blocks unsafe imports.
- `management_summary.dart` — Derives the management summary from the deck (severity counts, scope coverage, standards used).
- `markdown_service.dart` — Serializes decks to Marp markdown and parses it back (the file-format contract).
- `markdown_service_finding.dart` — Parses/serializes the `finding` slide group's id/role markers and header spec.
- `markdown_validator.dart` — Line-anchored structural pre-flight against the parser's expectations.
- `marp_html_service.dart` — Builds the self-contained, sanitised HTML export with embedded assets.
- `mermaid_render_service.dart` — Renders Mermaid diagrams to cached inline SVG via a shared WebView.
- `miauw_compliance_analyzer.dart` — Scores each MIAUW EIS (Voldaan/Openstaand/Uitgesloten) from deck content + waivers.
- `miauw_eis_catalog.dart` — The bundled offline MIAUW EIS catalog (`MiauwEisCatalog`, curated subset).
- `open_file_channel.dart` — Receives file-open paths from macOS for `.md` files.
- `privacy/privacy_checksums.dart` — Eleven-proof (BSN), Luhn and IBAN mod-97 with the country-length table.
- `privacy/privacy_allowlist.dart` — Known non-personal values: reserved domains, example IBANs, test cards, the official test-BSN range.
- `privacy/privacy_secret_rules.dart` — The secrets rule table: vendor tokens (AWS/GitHub/Slack/Stripe/…), PEM private keys, decodable JWTs, connection strings, plain-text passwords — plus the placeholder gate that keeps a how-to slide quiet.
- `privacy/privacy_checksums_eu.dart` — The European checksums: BE mod-97, DE ISO 7064 + digit-repetition, FR NIR, ES DNI/NIE, PT NIF, PL PESEL, IT codice fiscale, HR OIB, BG EGN, RO CNP, SE Luhn, FI mod-31, EE/LT mod-11, UK NHS/NINO — with embedded-birthdate validation where the checksum alone is too weak.
- `privacy/privacy_eu_rules.dart` — The European country packs as a data table: pattern, checksum, context words, confidence.
- `privacy/privacy_special_rules.dart` — GDPR art. 9/10: multilingual keyword families, genetic notation (dbSNP/HGVS), the Dutch parketnummer, the co-occurrence escalator's definition of "identifies a person", and `statementSpan` — because a special-category datum is a statement, not a word, so redacting it takes the whole line.
- `privacy/privacy_phone_rules.dart` — Phone numbers: E.164 validated against the ITU calling-code list (the only form that earns `certain`), national trunk forms, the context-word gate for bare digit runs, and the reserved "drama" ranges that are the `example.com` of telephony.
- `privacy/privacy_export_policy.dart` — The export gate: counts findings by disposition and decides whether to warn, block, or stay quiet.
- `privacy/privacy_own_identity.dart` — `OwnIdentity`: the author's own name/email/domain, which is the sender rather than a finding. Exact and domain matching only — no fuzzy match, which would silently suppress a real finding.
- `privacy/privacy_structural_rules.dart` — Structural leaks: user paths that reveal a name, tokens and personal data in URL queries, share links with built-in access, mailto links, unscannable data-URIs.
- `privacy/privacy_bulk_rules.dart` — Bulk personal data: a table header that names the column ("Naam", "BSN"), or one rule firing too often on a slide. One finding on top of the individual ones, not instead of them.
- `privacy/privacy_scanner.dart` — `PrivacyScanner`: reads a deck for privacy-sensitive data (email, IBAN, BSN), with context gates where the checksum is too weak.
- `privacy/privacy_quality_bridge.dart` — Maps `PrivacyFinding` onto `SlideQualityIssue` so findings surface in the quality panel.
- `privacy/privacy_projection.dart` — `AudienceDeck` + `PrivacyProjection`: the single boundary a source deck crosses to reach any receiving surface. Redacts `[[…]]` markers before rendering or export; the private constructor means no export path can hold the unredacted source.
- `quality_export_policy.dart` — Gates export by slide-quality issues with warnings.
- `recovery_service.dart` — Auto-saves deck snapshots for crash/unsaved recovery.
- `rehearsal_controller.dart` — Unit-testable controller tracking elapsed/remaining/per-slide rehearsal timing.
- `rfc3161_timestamp.dart` — Builds a `.tsq` from the seal hash and parses/verifies a `.tsr` timestamp token.
- `rich_text_layout.dart` — Computes pagination and scaling for rich-text markdown bodies.
- `scope_coverage.dart` — `deckScopeCoverageGaps`: flags in-scope objects with no test and no finding.
- `finding_context_score.dart` — builds the deck's scope-object→CIA index and derives each finding's context (environmental) score / effective severity from it.
- `secret_store.dart` — Manages secrets (WebDAV credentials, AI API key) in the OS keychain.
- `slide_layout_metrics.dart` — Layout constants/helpers for text sizing, fonts, and fit scaling.
- `slide_quality_analyzer.dart` — Checks deck slides for accessibility and readability issues.
- `slide_rasterizer.dart` — Renders on-screen slide previews to PNG for WYSIWYG PDF/PPTX export.
- `text_measurement.dart` — `measureTextHeight`/`measureTextWidth` for rendered text dimensions.
- `user_notes_codec.dart` — Serializes per-slide user notes with content fingerprints.
- `web_asset_store.dart` — In-memory afbeeldingsopslag (`mem:`-paden) voor de webversie; per-pagina levensduur.
- `webdav_service.dart` — Talks WebDAV (Nextcloud) over a pinned, redirect-free `HttpClient`.

## `lib/state/` — Riverpod providers

- `consent_provider.dart` — `ConsentNotifier` managing consent acceptance/revocation with persistent storage.
- `deck_provider.dart` — `DeckNotifier`: loaded deck, dirty state, undo/redo history, file path.
- `deck_provider_ai.dart` — `DeckNotifierAiAlt` extension: count/clear AI-generated image alt-texts.
- `deck_provider_auto.dart` — `DeckNotifierAuto` extension: `autoRenumberFindings` (P2-AUTO).
- `deck_provider_checklist.dart` — `DeckNotifierChecklist` extension: `generateScopeChecklists` (one checklist per scope object, feedback #8) and `clearAllChecklists`.
- `deck_provider_markdown.dart` — `DeckNotifierMarkdown` extension: generate/apply markdown for the whole deck or a single slide (per-slide markdown view).
- `deck_provider_miauw.dart` — `DeckNotifierMiauw` extension: set/remove MIAUW compliance waivers.
- `deck_quality_provider.dart` — Computes accessibility/quality analysis for the loaded deck.
- `editor_provider.dart` — `EditorState`/`EditorNotifier`: selected slide, editor mode, markdown buffer.
- `image_contrast_provider.dart` — Computes title-slide image-contrast issues asynchronously per deck.
- `sec_module_provider.dart` — The security-module enable/reveal state that gates the pentest features.
- `privacy_provider.dart` — Runs the privacy scan for the active deck (per-tab scoped) and bridges it into the quality panel.
- `parts/settings_provider_privacy.dart` — The privacy switches (master, per-rule, own identity, export gate).
- `settings_provider.dart` — `SettingsNotifier`: app settings, theme/appearance profiles, cockpit schemes.
- `slide_clipboard_provider.dart` — Global slide clipboard for copy/paste across tabs.
- `tabs_provider.dart` — `TabInfo` and the tabs notifier: open editor tabs, recovery, WebDAV origin.
- `webdav_provider.dart` — Providers for `WebdavService`, server config, and directory listings.

## `lib/utils/` — small shared helpers

- `asn1_der.dart` — Minimal dependency-free ASN.1/DER encode + parse for RFC 3161 timestamping.
- `atomic_file.dart` — Atomic writes (temp file + rename) to prevent data loss on crash.
- `bundled_asset.dart` — `asset:`-schema voor méégebundelde logo's van ingebouwde stijlprofielen.
- `color_contrast.dart` — WCAG 2.1 contrast-ratio calculation and hex colour parsing.
- `deck_markdown_dashes.dart` — Escapes standalone dash lines so the deck parser can't misread them.
- `file_download.dart` — Browserdownload (blob + anker) voor web-opslaan; conditional import met stub.
- `image_focal.dart` — Maps a normalized image crop focal point (0..1) to the `Alignment` used to reposition a cropped/cover image.
- `image_limits.dart` — Caps decoded image dimensions to prevent OOM; the `CappedImage` provider only downscales over-cap images so within-cap animated GIFs/WebP decode natively and keep animating.
- `image_luminance.dart` — Computes average image colour, cached by mtime/size.
- `log.dart` — Fail-soft logging to DevTools without exposing sensitive data (`logError`/`logWarning`).
- `lru_cache.dart` — Fixed-capacity LRU cache backed by `LinkedHashMap`.
- `markdown_paste_cleanup.dart` — Cleans pasted website markdown and normalizes rich-text quirks.
- `markdown_quill_codec.dart` — Round-trip conversion between markdown and Quill documents.
- `net_guard.dart` — SSRF guards (host/address checks, `safeResolve`, media resolve gate) against DNS rebind.
- `page_scoped_notes.dart` — Per-page speaker/user-notes parsing and storage.
- `password_generator.dart` — Cryptographically strong random passwords (`Random.secure`) for encrypted packages.
- `password_strength.dart` — Entropy-based password-strength estimate (warn-only) for the encrypt dialog.
- `project_path.dart` — Path resolution with project containment and symlink checking.
- `sanitize_svg.dart` — Strips dangerous elements/attributes from Mermaid SVG output.
- `table_clipboard.dart` — Parses tabular clipboard content (TSV, CSV, markdown tables).
- `text_search.dart` — Case-insensitive text search/replace with match tracking.
- `title_contrast.dart` — Evaluates title contrast and recommends WCAG fixes.
- `url_launcher_util.dart` — Opens external links with scheme and SSRF validation.
- `zip_encryption.dart` — Detects whether a `.ocideck` zip is password-encrypted (header inspection, no password needed).

## `lib/platform/` — platform abstraction (conditional imports)

- `launch_files.dart` — Launch-argumenten (Windows/Linux-bestandsassociaties) en de `?deck=`-deeplink-parser.
- `native_window.dart` — Export selector for platform-specific window configuration.
- `native_window_io.dart` — Initialises native desktop window options (size, title, focus).
- `native_window_stub.dart` — No-op window stub for web (part of `native_window`).
- `platform_features.dart` — Feature detection: desktop, dual-screen, local projects.
- `platform_features_io.dart` — Desktop feature availability (part of `platform_features`).
- `platform_features_web.dart` — Web platform: no desktop features (part of `platform_features`).
- `presenter_fullscreen.dart` — Export selector: volledig scherm voor de presentatiemodus (desktop-venster of browser-API).
- `presenter_fullscreen_io.dart` — Desktop: window_manager fullscreen (part of `presenter_fullscreen`).
- `presenter_fullscreen_web.dart` — Web: browser-Fullscreen-API (part of `presenter_fullscreen`).
- `runtime_flags.dart` — Export selector for platform-specific runtime detection.
- `runtime_flags_io.dart` — Detects the flutter-test environment (part of `runtime_flags`).
- `runtime_flags_web.dart` — No test detection on web (part of `runtime_flags`).

## `lib/theme/`

- `app_theme.dart` — Material 3 theme builder with brand colours and appearance profiles.

## `lib/l10n/` — localization

- `app_localizations.dart` — `AppLocalizations` class + delegate; assembles the lookup maps from per-language files.
- `slide_quality_localization.dart` — Localized formatting for slide-quality issues and export summaries.
- `slide_quality_navigation.dart` — Routes a quality issue to the relevant editor field.

### `lib/l10n/translations/` (each `part of app_localizations.dart`)

- `nl.dart` — Dutch (the source language).
- `en.dart` — English. · `de.dart` — German. · `fr.dart` — French. · `es.dart` — Spanish.
- `it.dart` — Italian. · `fy.dart` — Frisian. · `pap.dart` — Papiamento.

## `lib/widgets/` — UI

- `app_shell.dart` — Main application shell: layout, file IO, and dialog coordination.
- `markdown_notes_editor.dart` — Barrel re-export of the markdown notes editor.
- `privacy_badge.dart` — `PrivacyBadge` + the `privacyKatSvg` mark: the non-blocking marker (with an explanation on hover) for a spot where something leaves the device. Used by the status bar's remote-origin badge and the Security tab's online-CVE switch.
- `privacy_statement_content.dart` — Privacy/license content shared by the consent and settings dialogs.

### `lib/widgets/shell/` (each `part of app_shell.dart`)

- `ai_actions.dart` — `_MainLayoutAiActions`: the bulk "wipe AI alt-texts" safety action.
- `command_palette_actions.dart` — `_MainLayoutCommandPalette`: builds and shows the Ctrl/Cmd+K command list (incl. the security-module actions).
- `shell_actions.dart` — File-IO helpers for deck import/export and Nextcloud integration, plus shared `presentDeck`/`requestCloseTab` helpers.
- `shell_overlays.dart` — `_DropOverlay` and `_ResizableDivider` chrome.
- `status_bar.dart` — `_DeckStatusBar`: save state, file info, TLP classification, and the remote-origin privacy badge (`_RemoteOriginBadge` + `remoteOriginTooltip`, rendered with the shared `PrivacyBadge`) shown when a deck was fetched from a URL.
- `tab_bar.dart` — `_AppTabBar`/`_TabChip` multi-deck tab management; `_TabContent` picks welcome / play-only / editor per deck.
- `welcome_screen.dart` — `_WelcomeScreen`: recent files and new/open/import actions.
- `play_only_screen.dart` — `_PlayOnlyScreen`: locked view for `Deck.playOnly` decks (first slide + Play + Close).

### `lib/widgets/panels/`

- `editor_panel.dart` — Routes slide edits to type-specific editors with toolbar/notes/timing controls.
- `editor_panel_slide_settings.dart` — The per-slide settings block (logo, footer, timing, table editing, audio, TLP, privacy disposition). One row shape throughout, grouped into cards by the question you are actually asking; the cards sit side by side when the column is wide enough, so a label and its control stay within one glance instead of a thousand pixels apart. Collapsed, the header badges what deviates from the default — including the redaction disposition, which decides what the recipient gets.
- `preview_panel.dart` — Zoomable slide preview with rich-text page navigation.
- `slide_list_panel_clipboard.dart` — Copy-slide-as-image: an egress path, so it runs the same classification gate and privacy projection as a real export.
- `slide_list_panel.dart` — Searchable, reorderable thumbnail list with import/paste/add controls.
- `slide_quality_panel.dart` — Slide accessibility/quality checks with issue filtering.

### `lib/widgets/dialogs/`

- `add_slide_dialog.dart` — Selects a slide type when adding a slide.
- `command_palette.dart` — Searchable command overlay (Ctrl/Cmd+K); filters actions, keyboard-navigable.
- `consent_dialog.dart` — Initial consent/welcome dialog (privacy and license).
- `cvss_builder_dialog.dart` — Reusable per-metric CVSS 4.0 builder (`CvssBuilder`) + modal wrapper (`CvssBuilderDialog`) with a base/context score read-out; shared by the finding wizard and editor.
- `cwe_picker.dart` — Searchable picker over the offline CWE catalog (finding editor / wizard).
- `cve_picker.dart` — Gated online CVE lookup dialog (by id pattern) returning the chosen id to the finding editor / wizard.
- `export_dialog.dart` — WYSIWYG export dialog for PDF/PPTX/HTML.
- `find_replace_dialog.dart` — Full-text find-and-replace across all slides.
- `finding_template_picker.dart` — Searchable picker over the reusable finding-template library.
- `finding_wizard.dart` — The guided finding wizard (title → scope → CVSS builder → CWE → CVE → sections → emits a group); stores the base vector, context score derived from the scope object's CIA.
- `image_carousel_picker.dart` — Image-library carousel (grid and coverflow modes).
- `import_security_alarm_dialog.dart` — Hard-stop alarm screen for a rejected unsafe presentation.
- `import_slides_dialog.dart` — Scans directories for presentations to import slides from.
- `management_summary_dialog.dart` — Shows the derived management summary (severity counts, coverage, standards).
- `miauw_compliance_panel.dart` — The MIAUW compliance overview panel with per-EIS status and waivers.
- `new_deck_dialog.dart` — Creates a new presentation with a title; the searchable template picker + `templatePickerIcons`, hiding `requiresSecurityModule` templates (MIAUW) until the module is revealed.
- `open_presentation_dialog.dart` — Full-text searchable presentation picker with directory scanning.
- `package_encrypt_dialog.dart` — Optional password protection when exporting a package: strength meter, generator, copy.
- `package_password_dialog.dart` — Prompts for the password when opening an encrypted package (with wrong-password retry).
- `presentation_info_dialog.dart` — Edits title/author/organization/description metadata.
- `scan_library_dialog.dart` — Scans well-known locations for presentations.
- `scope_coverage_dialog.dart` — Shows the scope-coverage gaps (in-scope objects with no test/finding).
- `seal_timestamp_dialog.dart` — RFC 3161 timestamp workflow: export the `.tsq`, import/verify the `.tsr`.
- `settings_dialog.dart` — Sidebar settings (theme colours, fonts, cockpit,
  Licentie en Privacy, Beveiliging, Nextcloud, Checklists, and an "Over OciDeck"
  screen); tab bodies live in `parts/settings_dialog_*.dart` (the Checklists tab
  managing user checklist templates is `parts/settings_dialog_checklists.dart`).
  Search over the settings lives in `parts/settings_dialog_search.dart`
  (`SettingsSearchEntry`, the search field, and the jump-and-flash), with the
  index of what is searchable in `parts/settings_dialog_search_index.dart`.
  Anchors are free: every section heading goes through `_sectionTitle`, which
  registers a `GlobalKey` under its own text, so a hit can scroll its section
  into view without any of the tab bodies knowing about search.
- `slide_finder_dialog.dart` — Stay-open searcher for gathering slides from many presentations.
- `slide_quality_details_dialog.dart` — Issues grouped by severity with counts and navigation.
- `webdav_browser_dialog.dart` — Browses WebDAV/Nextcloud folders to pick a deck or images.

### `lib/widgets/editors/` — per-slide-type editors

- `_editor_field.dart` — Shared layout helpers for slide editors.
- `ai_suggest_field.dart` — Per-field "suggest text (AI)" control + AI-concept badge/Nagekeken for finding free-text fields.
- `alt_text_field.dart` — Per-image alt-text field with the optional "suggest alt-text (AI)" button and AI-draft badge.
- `audio_attachment_editor.dart` — Edits a slide's audio file attachment.
- `bullet_marker_selector.dart` — Per-slide bullet-marker override (dot or paw).
- `bullets_editor.dart` — Edits a bullet-list slide (title, subtitle, nested levels, markers).
- `bullets_image_editor.dart` — Edits a bullets-with-image slide.
- `chart_editor.dart` — Edits a chart slide (type, data grid, CSV import/linking).
- `checklist_editor.dart` — Edits a checklist slide (standard label, tri-state test rows, finding links).
- `cockpit_editor.dart` — Edits a cockpit slide (title + meter specs).
- `code_editor.dart` — Edits a code slide (syntax-highlighted monospace field).
- `finding_editor.dart` — Edits a finding header (scope, CVSS vector, CWE picker, CVE, sections; template + CWE pickers).
- `findings_summary_editor.dart` — Edits the findings-summary counts (with "refresh from deck").
- `free_markdown_editor.dart` — Edits a free-form custom-markdown slide.
- `image_slide_editor.dart` — Edits a full-slide image (title, caption).
- `list_style_selector.dart` — Selects list style (bullets/numbered/checklist/rich text).
- `markdown_deck_editor.dart` — Markdown editor with validation and find/replace, plus a sliding scope toggle for whole-deck vs. single-slide markdown.
- `markdown_find_bar.dart` — In-editor find/replace bar for markdown mode.
- `question_editor.dart` — Edits a question slide (answers, options).
- `quote_editor.dart` — Edits a quote slide (text, author, background image).
- `scope_matrix_editor.dart` — Edits a scope-matrix slide (objects × type/standard × coverage status).
- `section_editor.dart` — Edits a section-divider slide (title, subtitle).
- `signoff_editor.dart` — Edits the sign-off slide (truthfulness statement, signature, certification, seal).
- `slide_type_help.dart` — Collapsible "what can I do here?" hint per slide type (and the TLP hint); exhaustive switch guarantees every type has one.
- `table_editor.dart` — Edits a table slide (grid of cells, header row).
- `timeline_editor.dart` — Edits a timeline slide (reorderable events, layout).
- `title_editor.dart` — Edits a title slide (title, subtitle, image, zoom).
- `two_bullets_editor.dart` — Edits a two-column bullet slide (per-column titles).
- `two_images_editor.dart` — Edits a two-image slide.
- `video_slide_editor.dart` — Edits a video slide (source, trim points, audio).

### `lib/widgets/markdown_editor/` — notes editor

- `markdown_editor.dart` — Notes editor with side-by-side WYSIWYG and raw-markdown modes.
- `markdown_editor_actions.dart` — Selection-wrapping and line-prefix helpers.
- `markdown_editor_theme.dart` — Readable editor chrome independent of slide/panel colours.
- `markdown_editor_toolbar.dart` — Formatting toolbar for the markdown editor.
- `notes_editor_mode.dart` — Enum: rendered vs raw editing surface.
- `notes_mode_toggle.dart` — Toggle between visual and markdown editing.
- `wysiwyg_notes_field.dart` — WYSIWYG rich-text field (Flutter Quill).
- `wysiwyg_notes_toolbar.dart` — Quill formatting toolbar.

### `lib/widgets/slides/` — slide rendering

- `image_crop_dialog.dart` — Interactive crop/reposition dialog: drag to set the focal point (and zoom for full-slide/title images), WYSIWYG in the slot's aspect ratio.
- `image_zoom_dialog.dart` — Full-screen pan/zoom image viewer.
- `inline_markdown.dart` — Lightweight inline-markdown parser (bold/italic/code/links).
- `mermaid_diagram.dart` — Renders Mermaid definitions to inline SVG in previews.
- `slide_preview.dart` — Central preview library coordinating all slide-type renderers + shared helpers.
- `slide_thumbnail.dart` — Thumbnail with slide preview, metadata, and action buttons.
- `video_playhead_bus.dart` — Cross-widget channel syncing the video playhead across previews.

### `lib/widgets/slides/previews/` (each `part of slide_preview.dart`)

- `bullets_previews.dart` — Bullet-point slide layout.
- `chart_preview.dart` — Chart slide rendering + dispatch, legend, hover, and screen-reader text for every chart type.
- `chart_preview_extra.dart` — Hand-drawn builders for the horizontal-bar, combo, waterfall, and heatmap chart types.
- `checklist_previews.dart` — Checklist slides with a progress bar.
- `cockpit_preview.dart` — Animated cockpit/gauge dashboard slides.
- `code_preview.dart` — Syntax-highlighted code slides with fit.
- `media_previews.dart` — Shared audio/video playback lifecycle (`_MediaPlaybackHost`) + remote-media SSRF gate.
- `overlays.dart` — Logo overlay and TLP-marking badge renderers.
- `question_preview.dart` — Question slides with answer reveal.
- `table_preview.dart` — Table slides with a cell-edit scope.
- `text_previews.dart` — Title and text-based slides.
- `timeline_preview.dart` — Animated timeline renderer with event cards.

### `lib/widgets/presentation/` — presenter & dual-screen

- `annotation_overlay.dart` — `AnnotationLayer` for interactive drawing/laser pointer on slides.
- `audience_window.dart` — `AudienceWindowApp`: fullscreen slide on the secondary (beamer) window.
- `fullscreen_presenter.dart` — `FullscreenPresenter`: dual-screen presenter mode (notes/clock/grid).
- `rehearsal_summary.dart` — Post-rehearsal timing summary dialog with per-slide breakdown.

### `lib/widgets/presentation/parts/` (each `part of fullscreen_presenter.dart`, an `extension _PresenterX`)

- `presenter_displays.dart` — Multi-monitor screen management.
- `presenter_ink.dart` — Annotation layer stroking/erasing/laser.
- `presenter_keys.dart` — Keyboard input during presentation.
- `presenter_navigation.dart` — Slide/page navigation.
- `presenter_notes.dart` — Speaker- and user-note management.
- `presenter_overlays.dart` — UI overlays (badges/help/grid/clock).
- `presenter_playback.dart` — Auto-advance and media playback.
- `presenter_questions.dart` — Question-slide logic (answers, timer).
- `presenter_table.dart` — Live table editing during presentation.
