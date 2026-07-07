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
- `chart.dart` — `ChartSpec`/`ChartSeries` for bar/line/pie/radar/scatter chart slides with inline or CSV data.
- `cockpit.dart` — `CockpitSpec`/`CockpitMeterSpec` for instrumentation gauges (speedometer, voltmeter, etc.).
- `deck.dart` — `Deck` with metadata, TLP classification, slides list, annotations, and user notes.
- `markdown_validation.dart` — `MarkdownValidationResult`/`MarkdownValidationIssue` for linting markdown content.
- `question.dart` — `QuestionSpec`/`QuestionView` for interactive quiz slides (multiple-choice/true-false/multiple-correct/ordering).
- `rehearsal.dart` — `RehearsalRun`/`SlideTiming` for tracking presentation-practice durations per slide.
- `settings.dart` — `AppSettings`, `ThemeProfile`, `AppAppearanceProfile`, `CockpitColorScheme` config.
- `slide.dart` — `Slide` model with typed fields; `SlideType` enum for the slide layout variants.
- `slide_quality.dart` — `SlideQualityResult`/`SlideQualityIssue` for accessibility/contrast/density audits.
- `timeline.dart` — `TimelineEvent` and `TimelineLayout`/`TimelineReveal` enums for animated timeline slides.
- `video_source.dart` — `VideoSource` parser for local files, YouTube, Vimeo, and remote video URLs.
- `webdav_settings.dart` — `WebdavServer`/`WebdavOrigin` for Nextcloud/WebDAV integration configuration.

## `lib/services/` — business logic & IO

- `annotation_codec.dart` — Serializes slide annotation layers with content fingerprints.
- `caption_service.dart` — Stores image captions in JSON sidecars per image directory.
- `classification_enforcement_policy.dart` — Enforces deck TLP classification rules on export (the authoritative gate).
- `classification_policy.dart` — Thin backward-compatible wrapper around the TLP export ceiling only.
- `description_service.dart` — Stores searchable image descriptions as JSON sidecars.
- `export_metadata.dart` — `ExportDocumentMetadata` stamped into PDF/PPTX/HTML (title, author, org, keywords, TLP).
- `export_service.dart` — The single chokepoint that renders decks to PDF, PPTX, and HTML.
- `file_service.dart` — Scans presentation files, opens decks (with the safety gate), and import/URL/package IO.
- `image_dedup_service.dart` — Finds byte-identical image files by md5 to clean up libraries.
- `image_sidecar_store.dart` — Shared read/mutate/atomic-write layer for the per-directory JSON sidecars of captions and descriptions.
- `image_reference_service.dart` — Finds and rewrites image references in Marp markdown files.
- `image_service.dart` — Validates and manages imported image and media asset files.
- `markdown_body_blocks.dart` — Splits markdown into code blocks and paragraphs.
- `markdown_safety.dart` — Scans raw `.md` for executable content and blocks unsafe imports.
- `markdown_service.dart` — Serializes decks to Marp markdown and parses it back (the file-format contract).
- `markdown_validator.dart` — Line-anchored structural pre-flight against the parser's expectations.
- `marp_html_service.dart` — Builds the self-contained, sanitised HTML export with embedded assets.
- `mermaid_render_service.dart` — Renders Mermaid diagrams to cached inline SVG via a shared WebView.
- `open_file_channel.dart` — Receives file-open paths from macOS for `.md` files.
- `quality_export_policy.dart` — Gates export by slide-quality issues with warnings.
- `recovery_service.dart` — Auto-saves deck snapshots for crash/unsaved recovery.
- `rehearsal_controller.dart` — Unit-testable controller tracking elapsed/remaining/per-slide rehearsal timing.
- `rich_text_layout.dart` — Computes pagination and scaling for rich-text markdown bodies.
- `secret_store.dart` — Manages secrets (WebDAV credentials) in the OS keychain.
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
- `deck_provider_markdown.dart` — `DeckNotifierMarkdown` extension: generate/apply markdown for the whole deck or a single slide (per-slide markdown view).
- `deck_quality_provider.dart` — Computes accessibility/quality analysis for the loaded deck.
- `editor_provider.dart` — `EditorState`/`EditorNotifier`: selected slide, editor mode, markdown buffer.
- `image_contrast_provider.dart` — Computes title-slide image-contrast issues asynchronously per deck.
- `settings_provider.dart` — `SettingsNotifier`: app settings, theme/appearance profiles, cockpit schemes.
- `slide_clipboard_provider.dart` — Global slide clipboard for copy/paste across tabs.
- `tabs_provider.dart` — `TabInfo` and the tabs notifier: open editor tabs, recovery, WebDAV origin.
- `webdav_provider.dart` — Providers for `WebdavService`, server config, and directory listings.

## `lib/utils/` — small shared helpers

- `atomic_file.dart` — Atomic writes (temp file + rename) to prevent data loss on crash.
- `bundled_asset.dart` — `asset:`-schema voor méégebundelde logo's van ingebouwde stijlprofielen.
- `color_contrast.dart` — WCAG 2.1 contrast-ratio calculation and hex colour parsing.
- `deck_markdown_dashes.dart` — Escapes standalone dash lines so the deck parser can't misread them.
- `file_download.dart` — Browserdownload (blob + anker) voor web-opslaan; conditional import met stub.
- `image_limits.dart` — Caps decoded image dimensions (and `cappedNetworkImage`) to prevent OOM.
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
- `privacy_statement_content.dart` — Privacy/license content shared by the consent and settings dialogs.

### `lib/widgets/shell/` (each `part of app_shell.dart`)

- `shell_actions.dart` — File-IO helpers for deck import/export and Nextcloud integration, plus shared `presentDeck`/`requestCloseTab` helpers.
- `shell_overlays.dart` — `_DropOverlay` and `_ResizableDivider` chrome.
- `status_bar.dart` — `_DeckStatusBar`: save state, file info, TLP classification.
- `tab_bar.dart` — `_AppTabBar`/`_TabChip` multi-deck tab management; `_TabContent` picks welcome / play-only / editor per deck.
- `welcome_screen.dart` — `_WelcomeScreen`: recent files and new/open/import actions.
- `play_only_screen.dart` — `_PlayOnlyScreen`: locked view for `Deck.playOnly` decks (first slide + Play + Close).

### `lib/widgets/panels/`

- `editor_panel.dart` — Routes slide edits to type-specific editors with toolbar/notes/timing controls.
- `preview_panel.dart` — Zoomable slide preview with rich-text page navigation.
- `slide_list_panel.dart` — Searchable, reorderable thumbnail list with import/paste/add controls.
- `slide_quality_panel.dart` — Slide accessibility/quality checks with issue filtering.

### `lib/widgets/dialogs/`

- `add_slide_dialog.dart` — Selects a slide type when adding a slide.
- `command_palette.dart` — Searchable command overlay (Ctrl/Cmd+K); filters actions, keyboard-navigable.
- `consent_dialog.dart` — Initial consent/welcome dialog (privacy and license).
- `export_dialog.dart` — WYSIWYG export dialog for PDF/PPTX/HTML.
- `find_replace_dialog.dart` — Full-text find-and-replace across all slides.
- `image_carousel_picker.dart` — Image-library carousel (grid and coverflow modes).
- `import_security_alarm_dialog.dart` — Hard-stop alarm screen for a rejected unsafe presentation.
- `import_slides_dialog.dart` — Scans directories for presentations to import slides from.
- `new_deck_dialog.dart` — Creates a new presentation with a title.
- `open_presentation_dialog.dart` — Full-text searchable presentation picker with directory scanning.
- `package_encrypt_dialog.dart` — Optional password protection when exporting a package: strength meter, generator, copy.
- `package_password_dialog.dart` — Prompts for the password when opening an encrypted package (with wrong-password retry).
- `presentation_info_dialog.dart` — Edits title/author/organization/description metadata.
- `scan_library_dialog.dart` — Scans well-known locations for presentations.
- `settings_dialog.dart` — Sidebar settings (theme colours, fonts, cockpit,
  Licentie en Privacy, Beveiliging, Nextcloud, and an "Over OciDeck" screen);
  tab bodies live in `parts/settings_dialog_*.dart`.
- `slide_finder_dialog.dart` — Stay-open searcher for gathering slides from many presentations.
- `slide_quality_details_dialog.dart` — Issues grouped by severity with counts and navigation.
- `webdav_browser_dialog.dart` — Browses WebDAV/Nextcloud folders to pick a deck or images.

### `lib/widgets/editors/` — per-slide-type editors

- `_editor_field.dart` — Shared layout helpers for slide editors.
- `audio_attachment_editor.dart` — Edits a slide's audio file attachment.
- `bullet_marker_selector.dart` — Per-slide bullet-marker override (dot or paw).
- `bullets_editor.dart` — Edits a bullet-list slide (title, subtitle, nested levels, markers).
- `bullets_image_editor.dart` — Edits a bullets-with-image slide.
- `chart_editor.dart` — Edits a chart slide (type, data grid, CSV import/linking).
- `cockpit_editor.dart` — Edits a cockpit slide (title + meter specs).
- `code_editor.dart` — Edits a code slide (syntax-highlighted monospace field).
- `free_markdown_editor.dart` — Edits a free-form custom-markdown slide.
- `image_slide_editor.dart` — Edits a full-slide image (title, caption).
- `list_style_selector.dart` — Selects list style (bullets/numbered/checklist/rich text).
- `markdown_deck_editor.dart` — Markdown editor with validation and find/replace, plus a sliding scope toggle for whole-deck vs. single-slide markdown.
- `markdown_find_bar.dart` — In-editor find/replace bar for markdown mode.
- `question_editor.dart` — Edits a question slide (answers, options).
- `quote_editor.dart` — Edits a quote slide (text, author, background image).
- `section_editor.dart` — Edits a section-divider slide (title, subtitle).
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

- `image_zoom_dialog.dart` — Full-screen pan/zoom image viewer.
- `inline_markdown.dart` — Lightweight inline-markdown parser (bold/italic/code/links).
- `mermaid_diagram.dart` — Renders Mermaid definitions to inline SVG in previews.
- `slide_preview.dart` — Central preview library coordinating all slide-type renderers + shared helpers.
- `slide_thumbnail.dart` — Thumbnail with slide preview, metadata, and action buttons.
- `video_playhead_bus.dart` — Cross-widget channel syncing the video playhead across previews.

### `lib/widgets/slides/previews/` (each `part of slide_preview.dart`)

- `bullets_previews.dart` — Bullet-point slide layout.
- `chart_preview.dart` — Bar/line/pie chart slides with hover.
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
