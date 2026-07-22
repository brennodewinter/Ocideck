# OciDeck — Source Map

> **Status:** current-state index of `lib/` · **Status last reviewed:** 2026-07-22 · **Published by:** Stichting LibreKAT

A one-line index of the Dart files under `lib/`, grouped by directory. It aims at
the files worth naming; large uniform families (the 31 per-language translation
files, the 32 per-language finding-template tables, the `settings_dialog_*` parts)
are described as a group rather than file by file. It
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
- `chart.dart` — `ChartSpec`/`ChartSeries` and the `ChartType` enum (bar, stacked/horizontal bar, horizontal stacked bar, combo, line, area, pie, donut, radar, scatter, waterfall, heatmap) for chart slides with inline or linked data. Also the data-file codec: `dataToJson`/`withJson` for new files, `parseCsv`/`withCsv` for files written before the switch, and `withData` picking on the extension. The data file carries values only — colours stay in the chart block, which is what lets the save path compare two data files to decide whether the *numbers* changed. `parseChartDataJson` returns null rather than empty on a corrupt file, so a chart keeps what it has instead of quietly becoming an empty plot.
- `checklist_spec.dart` — `ChecklistSpec` for the security checklist slide (MIAUW tri-state test list linked to findings).
- `checklist_template.dart` — `ChecklistTemplate`/`ChecklistTemplateItem`: a user-created reusable checklist stored in the settings (feedback #9), with tolerant `encodeList`/`decodeList`.
- `cockpit.dart` — `CockpitSpec`/`CockpitMeterSpec` for instrumentation gauges (speedometer, voltmeter, etc.).
- `cvss_builder.dart` — CVSS 4.0 Base-metric metadata + vector assembly, `CiaRating`→`CR`/`IR`/`AR` mapping, `baseCvss4Vector` and `contextCvss` (derive a CIA-weighted context score).
- `cwe_entry.dart` — `CweEntry` for the offline CWE catalog (id/name/description/remediation).
- `maswe_weakness.dart` — `MasweWeakness` voor de MASWE-lijst (id/titel/categorie/platforms/CWE-koppeling/`isPlaceholder`).
- `mastg_test.dart` — `MastgTest` voor de offline MASTG-catalogus (id/titel/platform/MASVS-categorie/MASWE-zwakheid).
- `wstg_test.dart` — `WstgTest` for the offline WSTG catalog (id/title/category).
- `deck.dart` — `Deck` with metadata, TLP classification, slides list, annotations, user notes, and MIAUW waivers. Also the top-level audience gates: `slideVisibleAtTlp` (does this slide clear the presentation's level?), its counterpart `slideWithheldByTlp` and `withheldSlideCount` for the editor, and the three-gate `slideReachesAudience`. Withholding has its own name beside `Slide.skipped` on purpose: the outcome is the same (the slide is not there) but the cause is not — skipping is a per-slide choice, withholding follows from a classification policy the author may never have set, since both levels default to `TlpLevel.none`. One word for both would send the user to the wrong button.
- `deck_template_info_safety.dart` — The module-only **MIAUW-pentestrapport** deck template (`_buildMiauwReport`): scaffolds the full MIAUW report structure across the security slide types.
- `document_signature.dart` — `DocumentSignature`, the reusable visual signature for sign-off and the document seal.
- `eis_entry.dart` — `EisEntry`/`EisPart`/`EisDerivation`/`EisCheck` for the MIAUW compliance schema.
- `finding_spec.dart` — `FindingSpec`: the structured content of a `finding` header slide (scope, CVSS, CWE, **MASWE**, CVE, retest status, sections). Van MASWE wordt alleen het *id* opgeslagen; titel en categorie (die in de URL zit) komen uit `MasweCatalog` bij het schrijven, zodat een bijgestelde titel niet in een oud rapport bevriest. Een onbekend id blijft staan zonder link — liever geen link dan een 404; `RetestStatus` (hertest outcome).
- `finding_template.dart` — `FindingTemplate`, a reusable finding starter parsed from Markdown with YAML front matter.
- `findings_summary_spec.dart` — per-severity findings-summary counts + retest-resolved total + `deckFindingSeverities` / `deckRetestResolvedCount` derivations.
- `markdown_validation.dart` — `MarkdownValidationResult`/`MarkdownValidationIssue` for linting markdown content.
- `miauw_compliance.dart` — `MiauwComplianceResult`/`EisResult`/`EisStatus` for the compliance overview.
- `question.dart` — `QuestionSpec`/`QuestionView` for interactive quiz slides (multiple-choice/true-false/multiple-correct/ordering).
- `rehearsal.dart` — `RehearsalRun`/`SlideTiming` for tracking presentation-practice durations per slide.
- `scope_matrix_spec.dart` — `ScopeMatrixSpec`/`ScopeRow`/`ScopeObjectType`/`ScopeStatus` for the scope-matrix slide; each row carries a `CiaRating` (serialised as the `C`/`I`/`A` columns).
- `discoveries_spec.dart` — `DiscoveriesSpec`/`Discovery` for the shadow-IT slide: a named find with its kind, how many days it sat unnoticed and who owns it now. The longest exposure and the unowned tally are derived; an unknown exposure stays null rather than becoming a zero. `scaleDaysUnnoticed` restates a long exposure in months and leaves the word to the widget.
- `asset_overview_spec.dart` — `AssetOverviewSpec`/`AssetGroup` for the attack-surface slide: a *kind* of exposed object with how many there are, at risk, new and unowned. Totals are derived; "asset" here is an exposed object, not a media file.
- `scorecard_spec.dart` — `ScorecardSpec`/`ScorecardEntry` for the scorecard slide: a figure plus the figure it replaces, with the delta, direction and sentiment all derived. Polarity is stored because the deck cannot know whether a rise is good news.
- `privacy_disposition.dart` — `PrivacyDisposition` (warn/accept/shield/redact) and the slide-overrides-deck resolution.
- `quality_disposition.dart` — `QualityDisposition` (warn/accept): the same idea for quality findings, per slide only. Two values and not four — a contrast problem has no recipient to warn and nothing to black out.
- `privacy/image_face_scan.dart` — de beeldcontrole: staat er een herkenbaar gezicht op een dia-afbeelding? Alléén tellen, nooit identificeren — de kop van dat bestand legt uit waarom dat het verschil is tussen een privacycontrole en een biometrische verwerking (EDPB 3/2019 §74-76). `image_face_scan_io.dart` is de native helft (YuNet via OpenCV, multischaal), `image_face_scan_stub.dart` de webhelft die eerlijk meldt dat ze niets kan.
- `redaction_manifest.dart` — `RedactionEntry`/`RedactionManifest`: what an export removed, provably, without the values. Holds the two file suffixes (`-redactions.json`, `-redaction-keys.json`) and the two `notice` lines that go inside them. Both are English while the rest of the export naming is Dutch, and both say the same thing twice on purpose: the separation between the two files *is* the security, so it has to be readable without knowing Dutch, and a filename does not survive being renamed or zipped whereas the first line of the JSON does. `withoutSalts` produces the copy that may travel.
- `privacy_finding.dart` — `PrivacyFinding`/`PrivacyScanResult`: what the privacy scanner found. Never stores the raw value — only a masked sample. `PrivacyTermRole` splits an *indicator* ("diagnose") from the *value* itself (`F32.1`): redacting the first hides nothing and misleads the reader, so only the second is blacked out unless the escalator widened the span to the whole statement.
- `used_tool.dart` — `UsedTool` + `toolsAppendixRows`: de hulpmiddelen die bij het onderzoek zijn gebruikt (MIAUW EIS 4.8.2 — beschrijving, versie, publieke referentie), met een tolerante `naam@versie | url | beschrijving`-vorm omdat het veld met de hand wordt getypt. Levert de bijlagetabel in eisvolgorde; de kopteksten komen van de aanroeper zodat ze in de taal van het *rapport* staan.
- `reference_standard.dart` — `ReferenceStandard`/`StandardFreshness`/`UpstreamProbe`: één gebundelde referentiestandaard als data (versie, bron-URL, wat er precies gebundeld is, licentie, en hoe upstream te bevragen). `UpstreamProbe` kent vier strategieën en met opzet géén `manual`: CWE en CVSS stonden eerst als "niet te bevragen" tot bleek dat MITRE een REST-API heeft en FIRST per versie een schema op een vaste URL publiceert. "Onbekend" (bron onbereikbaar) mag nooit als "actueel" lezen.
- `settings.dart` — `AppSettings`, `ThemeProfile` (incl. severity tokens + built-in Security profile), `AppAppearanceProfile`, `CockpitColorScheme` config.
- `slide.dart` — `Slide` model with typed fields; `SlideType` enum for the slide layout variants. Inline bullet-item helpers: checklist (`checklistBullet`/`checklistItemChecked`/`checklistItemText`) and group headings (`kGroupHeadingMarker`/`isGroupHeading`/`groupHeadingBullet`/`groupHeadingText`).
- `asset_origin.dart` — `AssetOrigin` + `classifyAssetPath`: answers the only question that matters about a slide's media — does it travel along when the presentation goes to someone else? Purely lexical (no disk access), because the UI asks it per frame; whether the file still exists is a separate question for the quality analyser. `deckCarriesMemoryAssets` lifts the same lexical test to the whole deck (any `mem:` image/media/logo), which the web save path uses to warn before a plain `.md` download drops in-memory media.
- `slide_quality.dart` — `SlideQualityResult`/`SlideQualityIssue` for accessibility/contrast/density/privacy audits.
- `timeline.dart` — `TimelineEvent` and `TimelineLayout`/`TimelineReveal` enums for animated timeline slides.
- `video_source.dart` — `VideoSource` parser for local files, YouTube, Vimeo, and remote video URLs.
- `parts/app_appearance_profile.dart` — `AppAppearanceProfile`: how the application itself looks, as opposed to `ThemeProfile`, which styles a slide and travels inside the deck. A `part` of `settings.dart` so callers need no second import.
- `storage_origin.dart` — `StorageOrigin`: het smalle contract dat elke herkomst deelt (`connectionId`, `remoteLocation`), geïmplementeerd door `WebdavOrigin`, `S3Origin` en `GitOrigin`. Bestaat zodat een tabblad één herkomstveld heeft in plaats van drie: met drie losse velden kon een deck er twee tegelijk dragen en was "waar kwam dit vandaan" niet te beantwoorden.
- `storage_connection.dart` — `StorageConnection` (sealed: `LocalConnection`/`WebdavConnection`/`S3Connection`/`GitConnection`) — the single notion of "a place decks live". One list, user-ordered, replacing the old split between a libraries list and one-of-each network source. Each carries a stable `id` so renaming a connection or fixing a typo in its URL never detaches an open deck from its origin; secrets stay in the keychain, keyed on server + user, so two connections to one account share one password.
- `s3_settings.dart` — `S3Bucket` for S3 source configuration: endpoint, region, bucket, access key id, prefix and addressing style. The endpoint is a free field rather than a list of AWS regions because the self-hosted (MinIO) and European providers are the interesting case; `S3AddressingStyle` decides whether the bucket goes in the host name (AWS) or the path (most self-hosted endpoints). `uriForKey` encodes the path with the strict AWS rules instead of leaving it to `Uri` — S3 compares our signature against a canonical form derived from the path it received, so what goes over the wire must match what was signed byte for byte.
- `webdav_settings.dart` — `WebdavServer`/`WebdavOrigin` (the origin carries the `etag` a save is checked against, plus the `connectionId` that sends a save back to the connection it came from) for WebDAV source configuration (Nextcloud, ownCloud, or any other server).

## `lib/services/` — business logic & IO

This is the largest directory in the tree, and most of it is loose files: one
subject per file, which is why it is long rather than tangled. What is *not*
loose is grouped into the subdirectories below. Each of those carries a header
comment in the file named here, stating what belongs in that directory and what
does not, so the question "where does this change go" is answered next to the
code rather than only here. This map stays the file-by-file index.

| Directory | Role | Cluster header |
|---|---|---|
| `privacy/` | Detecting privacy-sensitive data, weighing it, redacting it and gating the export. | `privacy/privacy_scanner.dart` |
| `git/` | Decks stored in a Git repository: forge, transport, offline working copy, merge. | `git/git_forge.dart` |
| `finding_templates/` | Template *content*, one file per language — no logic. | `finding_templates/all.dart` |
| `cve/` | The offline CVE corpus: bulk download, on-disk index, desktop-only facade. | `cve/local_cve_database.dart` |
| `presentation_search/` | The network-backed sources 'Slide zoeken' scans (git, WebDAV, S3). | `presentation_search/presentation_source.dart` |
| `cvss/` | The CVSS v4.0 scoring engine — a faithful port, nothing else. | `cvss/cvss4.dart` |
| `s3/` | S3 and S3-compatible storage: SigV4 signing, and the pinned client. | `s3/s3_service.dart` |
| `info_safety/` | Counting what reference data the security module has locally. | `info_safety/info_safety_reference_inventory.dart` |
| `parts/` | Not a cluster: `part of` spillover, so a large service stays navigable and under the 1000-line file ratchet (`tool/check_conventions.dart`). Each file names its library in its first line. | — |

*(Added 2026-07-22: the subdirectories were only findable by reading the flat
list below, which made "where does this belong" slower than it needed to be.)*

- `ai_alt_text_cleanup.dart` — Counts and clears still-unreviewed AI-generated image alt-texts (the bulk-wipe safety net).
- `ai_client_service.dart` — The gated, provider-agnostic `/v1` client for the optional local AI backend.
- `ai_request.dart` — `AiChatRequest`/`AiMessage`/`AiImagePart` request model + the shared system guardrail prompt.
- `ai_security_gate.dart` — Enforces the AI opt-in/consent/endpoint gate before any outbound AI call.
- `annotation_codec.dart` — Serializes slide annotation layers with content fingerprints. Refuses a sidecar from a newer build (`sidecar_format.dart`) rather than loading the part it recognises.
- `audit_dossier.dart` — `buildAuditDossier`: the MIAUW §10.11 audit-dossier index (report identity, seal facts, summary, compliance tally, evidence hash table) as deterministic Markdown.
- `caption_service.dart` — Stores image captions in JSON sidecars per image directory.
- `classification_enforcement_policy.dart` — Enforces deck TLP classification rules on export (the authoritative gate).
- `classification_policy.dart` — Thin backward-compatible wrapper around the TLP export ceiling only.
- `cvss/cvss4.dart` — Native-Dart port of the FIRST CVSS v4.0 calculator (metrics, parse, score, severity); `cvss4_lookup.dart` + `cvss4_scoring.dart` are its lookup-table/scoring parts.
- `cwe_catalog.dart` — The offline CWE catalog (`CweCatalog`): a curated floor merged with the full MITRE list from `assets/cwe/cwe_full.json` (via `ensureLoaded`); search/byId.
- `cve_search_service.dart` — `CveSearchService` + `CveSource` cascade (`LibrekatCveSource` mirror → `EnisaCveSource` EUVD keyword search → `MitreCveSource` exact-id lookup); `CveHit` in `models/cve_hit.dart`.
- `cve_transport.dart` / `cve_transport_io.dart` / `cve_transport_web.dart` / `cve_transport_factory.dart` — injectable, SSRF-pinned HTTP transport for the CVE search (io) with a web stub, selected by conditional export.
- `cve/cve_record_parser.dart` — `CveRecordParser`: one CVE List V5 record → the handful of fields the picker shows. Reads CVSS from **both** `containers.cna.metrics` and `containers.adp[].metrics` (for much of the corpus the score was added later by an ADP, not the CNA).
- `cve/local_cve_index.dart` — `LocalCveIndex`: the on-disk JSONL index + meta. Search is a raw-line substring scan that only JSON-decodes the lines that hit, so a 300k-record query neither loads the corpus into memory nor needs a database engine.
- `cve/cve_bulk_ingest.dart` — `CveBulkIngest` + `CveBulkTransport`: discover the latest CVE List V5 release (the asset is named after the day, so there is no fixed URL), stream it to disk, unpack the **zip inside the zip**, and index record by record. Injectable transport so the whole chain is testable with a few-KB archive.
- `cve/local_cve_database.dart` (+ `_api` / `_io` / `_web`) — the desktop-only facade: real index + `GithubBulkTransport` on io, an unsupported stub on web.
- `reference_standards.dart` — het register (plus `currentStandardEntries`/`parseUsedStandard`/`outdatedStandards`: de `naam@versie`-regels die een deck bevriest, en de vergelijking daarvan met wat deze build meedraagt — dát is de verouderingsmelding bij verzegelen, zonder netwerk) van alles wat OciDeck aan referentiedata meedraagt (WSTG, CWE, MIAUW, CVSS). De enige plek waar die versies als *data* staan in plaats van als proza; `tool/check_reference_data.dart`, het instellingenoverzicht en `docs/LICENSE_COMPLIANCE.md` lezen hier vandaan, en `reference_standards_test.dart` houdt ze gelijk.
- `maswe_catalog.dart` (+ `_written`/`_draft` parts) — `MasweCatalog`: de OWASP MASWE-zwakhedenlijst (117), de mobiele tegenhanger van CWE en de laag waar MASTG-tests naar verwijzen. `forCwe` is de brug naar de CWE-taal die al gebundeld is. Vastgelegd op **datum**, want MASWE voert geen releases of tags. Anders dan bij MASTG blijven onuitgeschreven zwakheden er wél in (gemarkeerd): een geïdentificeerde zwakheid is citeerbaar, een niet-uitgevoerde test niet. Gegenereerd door `tool/build_maswe_catalog.dart`.
- `mastg_catalog.dart` (+ `_android`/`_ios` parts) — `MastgCatalog`: de offline OWASP MASTG-testindex (v2.0.0, 186 actieve tests) voor mobiele scope-objecten, tegenhanger van `wstg_catalog.dart`. Gesplitst per platform: dat houdt beide delen onder de regelratchet én is hoe een tester ze gebruikt. Gegenereerd door `tool/build_mastg_catalog.dart`, dat de ingetrokken v1-tests en de placeholders overslaat.
- `wstg_catalog_data.dart` — de gegenereerde WSTG-index (97 tests), `part` van `wstg_catalog.dart`. Komt uit `tool/build_wstg_catalog.dart`.
- `wstg_catalog.dart` — The bundled offline OWASP WSTG v4.2 test catalog (`WstgCatalog`, 97 tests + pinned version) used to one-click-fill a `checklist` slide.
- `finding_template_library.dart` — `FindingTemplateLibrary`: the bundled finding templates, resolved **per report language** (`Deck.language`, not the interface language — PENTEST_MIAUW §12.3), with a per-template fallback to English.
- `finding_templates/<code>.dart` (+ `all.dart`) — the template sources, one file per language like `lib/l10n/translations/`: a template is content, not a `d(...)` string. Only the prose is translated; the `## …` anchors, `cwe:`, `severity:` and the CVSS tokens are fixed. Guard: `test/finding_template_languages_test.dart`.
- `info_safety/info_safety_reference_inventory.dart` — `InfoSafetyReferenceInventory` + `ReferenceCatalog`: counts what reference data is *actually* available locally (CWE, WSTG, MIAUW, the CVSS table, finding templates) for the Uitbreidingen tab, so "data available locally" is a number rather than a claim.
- `checklist_templates.dart` — `ChecklistSource` + helpers that present WSTG and each user `ChecklistTemplate` uniformly to the checklist editor and the per-scope generator (feedback #9).
- `description_service.dart` — Stores searchable image descriptions as JSON sidecars.
- `document_integrity.dart` — Computes/verifies the SHA-512 deck seal and seals a finalised deck.
- `evidence_hash_service.dart` — Computes the MIAUW SHA1 + SHA-256 of evidence bytes and builds the appendix hash table.
- `export_bundle.dart` — `ExportBundle`: everything an export needs for one audience profile. A factory the export dialog holds, so it can pick the profile without ever touching the source deck.
- `export_metadata.dart` — `ExportDocumentMetadata` stamped into PDF/PPTX/HTML (title, author, org, keywords, TLP).
- `export_service.dart` — The single chokepoint that renders decks to PDF, PPTX, and HTML.
- `file_service.dart` — Scans presentation files, opens decks (with the safety gate), and import/URL/package IO. `openDeckDetailed` returns `(deck, failure, warnings)`; the warnings carry chart data files that could not be read, because such a chart draws empty and an empty chart is indistinguishable from one that simply has no numbers yet. `saveDeckDetailed`/`saveDeckAsDetailed` are the mirror image on the write side — the save has just lifted the numbers out of the markdown (`parts/file_service_open.dart`, `_externalizeCharts`), so a data file that could not be written leaves them nowhere but the open window; `saveDeck`/`saveDeckAs` remain as thin wrappers for callers with nothing to report. `_writeChartData` refuses to overwrite a data file that changed outside the app since it was read: an app-wins rewrite was a lost update, and the baseline is deliberately left standing so the next save sees the same clash instead of quietly resolving it. Part `parts/file_service_scan.dart` holds the private helpers of the disk scan, `parts/file_service_import_dirs.dart` those that pick where an import lands. Part `parts/file_service_dossier.dart` builds the one-click audit dossier (package + `AUDIT_DOSSIER.md` + optional `report.pdf`, AES-256). Part `parts/file_service_style_profile.dart` reads/writes a standalone `.ocideckstyle` style profile (FILE_FORMAT §3.3), embedding a custom logo as base64 and materializing it back on import.
- `finding_ai_service.dart` — Drafts a free-text finding field via the AI backend, grounded on the tester's facts; strips fabricated CWE/CVE/CVSS ids.
- `finding_group_builder.dart` — `buildFindingGroup`: assembles a finding header + optional detail/evidence slides sharing one id.
- `finding_numbering.dart` — `renumberFindings` (F-01… from deck order) + `deckFindingList` derivation.
- `finding_template_library.dart` — The bundled reusable finding-template library with search.
- `image_alt_ai_service.dart` — Vision consumer: suggests WCAG alt-text and searchable tags for an image via the local backend.
- `image_dedup_service.dart` — Finds byte-identical image files by md5 to clean up libraries.
- `image_sidecar_store.dart` — Shared read/mutate/atomic-write layer for the per-directory JSON sidecars of captions and descriptions.
- `image_reference_service.dart` — Finds and rewrites image references in Marp markdown files.
- `asset_staging.dart` — `AssetStaging`: the waiting room for media of a deck that has no folder on disk yet. Per session a temp folder laid out like a real project (`images/`, `media/`), so bytes are safe on insert and the ordinary save-time copy lifts them into place. `isStagedPath` tests against the *root*, not the session folder, so a deck recovered after a restart still recognises its earlier copies instead of calling them external. `pruneStale` (startup, fire-and-forget) drops session folders whose *files* have not been touched for `RecoveryService.defaultMaxAge` — files, because a directory timestamp means something different per platform; the shared constant keeps staging from being cleared before the recovery drafts that point into it.
- `image_service.dart` — Validates and manages imported image and media asset files. `importIntoDeck` is the single entry for material the user already pointed at (dropped, or picked from the library); it returns the source path rather than null when copying fails, so a slide never silently goes blank.
- `markdown_body_blocks.dart` — Splits markdown into code blocks and paragraphs.
- `markdown_safety.dart` — Scans raw `.md` for executable content and blocks unsafe imports.
- `management_summary.dart` — Derives the management summary from the deck (severity counts, scope coverage, standards used).
- `front_matter_merge.dart` — The front-matter half of the file-format contract: which keys OciDeck owns, the `ocideck_format` version rules, and the surgical update that leaves every other line untouched. Also the definition of "a key sits at column 0, an indented line belongs to the block above" that the reader, the writer and the checker all share — without it, CSS inside a `style: |` block set deck fields. `kRetiredFrontMatterKeys` holds the keys OciDeck no longer writes but still owns: taking them off the list entirely would mean "unknown, so leave it alone", and the base64 would stay in the file forever.
- `markdown_service.dart` — Serializes decks to Marp markdown and parses it back (the file-format contract). Writes **no base64**: what is opaque, or is about the document instead of in it, lives in a sidecar. Part `parts/markdown_service_parse_front_matter.dart` holds the `--- … ---` header; `parts/markdown_service_parse_columns.dart` reads the visible `<h3>`/`<ul><li>` of a two-column slide, which is the content itself rather than a rendering of a comment above it. The reader takes a slide's type from the same registry the writer uses (`slideTypeByMarpClass` in `models/slide.dart`) instead of its own list of string literals.
- `miauw_codec.dart` — The MIAUW disposition (client exclusions and confirmations) as the `<name>.miauw.json` sidecar, plus the read-only decoder for the base64 front-matter keys it replaced, so an older file still opens.
- `markdown_service_finding.dart` — Parses/serializes the `finding` slide group's id/role markers and header spec.
- `markdown_validator.dart` — Line-anchored structural pre-flight against the parser's expectations.
- `marp_html_service.dart` — Builds the self-contained, sanitised HTML export with embedded assets.
- `mermaid_render_service.dart` — Renders Mermaid diagrams to cached inline SVG via a shared WebView. Headless: the WebView host itself is a widget and lives in `lib/widgets/mermaid_render_host.dart`.
- `miauw_compliance_analyzer.dart` — Scores each MIAUW EIS (Voldaan/Openstaand/Uitgesloten) from deck content + waivers.
- `miauw_eis_catalog.dart` — The bundled offline MIAUW EIS catalog (`MiauwEisCatalog`): all 88 testable EIS, parsed from the authoritative MIAUW workbook.
- `open_file_channel.dart` — Receives file-open paths from macOS for `.md` files.
- `privacy/privacy_checksums.dart` — Eleven-proof (BSN), Luhn and IBAN mod-97 with the country-length table.
- `privacy/privacy_allowlist.dart` — Known non-personal values: reserved domains, example IBANs, test cards, the official test-BSN range.
- `privacy/privacy_secret_rules.dart` — The secrets rule table: vendor tokens (AWS/GitHub/Slack/Stripe/…), PEM private keys, decodable JWTs, connection strings, Azure keys and SAS tokens, password hashes, TOTP seeds, plain-text passwords — plus the placeholder gate that keeps a how-to slide quiet, the Shannon-entropy fallback (`secret.entropy`, the only rule here with a context gate) and its exclusions for hashes, UUIDs and checksums.
- `privacy/privacy_checksums_eu.dart` — The European checksums: BE mod-97, DE ISO 7064 + digit-repetition, FR NIR, ES DNI/NIE, PT NIF, PL PESEL, IT codice fiscale, HR OIB, BG EGN, RO CNP, SE Luhn, FI mod-31, EE/LT mod-11, IS kennitala mod-11, LV personas kods mod-11 (a *different* scheme from EE/LT), LU matricule (Luhn **and** Verhoeff, both over the same eleven digits), CY tax code mod-26 check letter, UK NHS/NINO, NL legacy VAT (elevenproof over the nine embedded digits, which are the owner's BSN) — with embedded-birthdate validation where the checksum alone is too weak. Two entries deliberately have no checksum because none is published: the Maltese identity card number (the trailing letter encodes birth region and century, it checks nothing) and the Liechtenstein PEID (four to twelve bare digits). Both are context-gated in the rule table.
- `privacy/privacy_national_rule.dart` — `NationalIdentifierRule`: the shape of one national identification number (country, pattern, validator, context words, confidence). Lives apart from any country list because nothing about it is regional — it was called `EuIdentifierRule` until the US and Canada arrived and the name started to lie.
- `privacy/privacy_eu_rules.dart` — The European country packs as a data table of `NationalIdentifierRule`s: pattern, checksum, context words, confidence. Includes the six Dutch numbers beside the BSN (`nl.btw_id_legacy`, `nl.vnummer`, `nl.anummer`, `nl.big`, `nl.agb`, `nl.pv_nummer`); only the first may fire without a context word.
- `privacy/privacy_checksums_world.dart` — The non-European validators: US SSN/ITIN/EIN range rules, ABA routing mod-10, NPI/MBI/DEA, CA SIN/BN Luhn + RAMQ date + OHIP, AU TFN mod-11/Medicare/ABN mod-89, **Verhoeff** for Aadhaar, ZA Luhn + birthdate, BR CPF/CNPJ double mod-11. Note what is *absent*: the American numbers have no check digit at all, so "validation" there is a range check that removes a few percent where a mod-11 removes ten in eleven — which is why every one of those rules also carries a context gate.
- `privacy/privacy_world_rules.dart` — The non-European country packs, same table shape as the European one. Carries the GDPR-as-yardstick reasoning: rules exist here because a number identifies a person under an open norm, not because a local statute enumerates it — hence `us.ssn_last4` and `us.itin`, and hence a company's Indian PAN is filtered out rather than reported.
- `privacy/privacy_regions.dart` — Which country packs run. A rule is country-bound when its id starts with a known two-letter code, derived from the id itself rather than a second list that would drift. All packs ship **on**: every rule carries a checksum or a context gate, and protection should not depend on the author having found a checkbox. A pack exists only where a rule exists — six European ones were removed in July 2026 because a checkbox that is on and finds nothing lets "nobody looked" read as "nothing found", and returned days later once CY, IS, LI, LU, LV and MT each had a rule. The European packs now cover all 27 EU member states plus Iceland, Liechtenstein, Norway, Switzerland and the UK. `sharedRegionRules` lets one rule answer to two country codes (the rodné číslo under `cz` and `sk`, the Baltic personal code under `ee` and `lt`) rather than shipping a second id that would report the same number twice. `privacyRuleRegion` deliberately tests against a *complete* list of country codes instead of the enabled packs: a future `cy.` rule must fall inside the region gate, not outside every pack. Guard: `test/privacy_region_coverage_test.dart`, which fails in both directions.
- `privacy/privacy_special_rules.dart` — GDPR art. 9/10: multilingual keyword families, genetic notation (dbSNP/HGVS), the Dutch parketnummer, the co-occurrence escalator's definition of "identifies a person", and `statementSpan` — because a special-category datum is a statement, not a word, so redacting it takes the whole line.
- `privacy/privacy_lexicon_data.dart` — The bundled art. 9/10 lexicon: every term states how it wants to be matched, in which language, and how specific it is. The language coverage is deliberately uneven *and visible* — Dutch rich, English reasonable, DE/FR/ES thin, the other 25 interface languages none — because a green bar saying "nothing found" for a language where nothing *can* be found is worse than no check at all.
- `privacy/privacy_bulk_lexicon.dart` — The bulk lexicons (Orphanet conditions, EuroVoc convictions) as an asset laid over the compiled floor, same shape as `CweCatalog`: if the asset is missing or broken the floor keeps running. Carries a start-token index, because a linear `indexOf` walk over 62k terms never meets the 5 ms-per-slide budget — the work is made proportional to the slide instead of to the lexicon.
- `privacy/privacy_context_role.dart` — Whose role a criminal-law finding is reading: suspect, reporter/victim, or witness. Three-way with `unknown` as the default and deliberately no two-way fallback: if you must guess, the expensive mistake is not "I don't know" but calling a complainant a suspect. Triggers are scoped to the statement and cut at "maar"/"but"/"hoewel"; two roles in one statement yields no role. Changes only the wording of the notice — never the severity, the redaction or the export gate.
- `privacy/privacy_card_rules.dart` — Payment cards: the issuer-range table per scheme with each scheme's exact lengths, plus the CVV keyword pattern. Luhn alone is far too weak (one in ten random digit runs passes), so a number must also belong to a real scheme *at that scheme's length*; a Luhn-valid number belonging to no scheme is coincidence, not a card. The CVV never fires without a valid card number in the same fragment.
- `privacy/privacy_document_rules.dart` — The machine-readable zone of a passport or ID card (TD1/TD2/TD3), validated on every ICAO check digit including the composite one that runs over the others. No context gate — four interlocking check digits do not let ordinary text through. One wrong digit means no match: a deliberate preference for a missed scan over a scanner that shouts "passport!" at every table of capitals.
- `privacy/privacy_digital_rules.dart` — Digital identifiers: IPv4/IPv6, MAC, IMEI, ICCID, IMSI, advertising UUIDs and social handles. Skips the ranges reserved for documentation (RFC 5737/3849) and the version numbers that look just like addresses; a private range drops to `possible` — internal infrastructure is not a person, but an internal address plan on a public slide is still a leak. Two collisions are settled here: Amex prefixes are left to the card rule (both are 15 digits with a valid Luhn), and the checksum-less IMSI deliberately takes the 15-digit runs that *fail* Luhn, so the two never claim the same string. GitHub is absent from the handle list on purpose — in a technical deck that link is a repository, not a person.
- `privacy/privacy_plate_rules.dart` — Dutch licence-plate sidecodes and the international postcode patterns. The plate's context word is mandatory rather than recommended: `XX-99-99` is equally an article code or a version marker, so the pattern on its own excludes almost nothing. Letter groups the RDW never issues are dropped.
- `privacy/privacy_location_rules.dart` — Birthdates and coordinates: the two that point at a person without naming one. The birthdate's context word is not negotiable — a date is the most common number form in a business deck, and a rule that reports them all reports the calendar. The coordinate needs none: four decimals on both sides is about eleven metres, a shape ordinary prose does not produce.
- `privacy/privacy_phone_rules.dart` — Phone numbers: E.164 validated against the ITU calling-code list (the only form that earns `certain`), national trunk forms, the context-word gate for bare digit runs, and the reserved "drama" ranges that are the `example.com` of telephony.
- `privacy/privacy_contact_rules.dart` — Address, Dutch postcode and labelled person-name: a street-suffix word with a house number, the `1234 AB` pattern (hex colours excluded), and names only behind a salutation (`dhr.`) or a label (`naam:`) — no NER. Address and postcode are each `possible`; a street and a postcode within ~40 characters escalate both to `certain`, because postcode + house number pins one home address.
- `privacy/privacy_export_policy.dart` — The export gate: counts findings by disposition and decides whether to warn, block, or stay quiet.
- `privacy/privacy_own_identity.dart` — `OwnIdentity`: the author's own name/email/domain, which is the sender rather than a finding. Exact and domain matching only — no fuzzy match, which would silently suppress a real finding.
- `privacy/privacy_structural_rules.dart` — Structural leaks: user paths that reveal a name, tokens and personal data in URL queries, share links with built-in access, mailto links, unscannable data-URIs.
- `privacy/privacy_bulk_rules.dart` — Bulk personal data: a table header that names the column ("Naam", "BSN"), or one rule firing too often on a slide. One finding on top of the individual ones, not instead of them.
- `privacy/privacy_scanner.dart` — `PrivacyScanner`: reads a deck for privacy-sensitive data (email, phone, IBAN, BSN, EU numbers, address, postcode, name), with context gates where the checksum is too weak and proximity escalation where a postcode meets a house number.
- `privacy/privacy_scanner_detectors.dart` — `part of privacy_scanner.dart`: the detectors for the families added after the first release — digital identifiers, the MRZ, the birthdate and coordinates — plus the address anchors and `fin.us_routing` that moved out of the scanner later. A `part` and not a library of its own, so `privacy_scanner.dart` stays under the thousand-line ratchet while these keep direct access to `_finding`, `_hasContextWord` and `ownIdentity`. Because they run through `_finding`, they inherit the own-identity and `[[…]]` suppression for free.
- `privacy/privacy_scanner_fragments.dart` — `part of privacy_scanner.dart`: which text the scanner walks — the deck fields that end up in document metadata (and so travel in PDF properties and PPTX docProps), and the per-slide fields. The list answers the question that decides the whole feature's reach: what is not scanned is not redacted either, because the projection only rewrites fields that carry a finding.
- `privacy/privacy_scan_memo.dart` — Per-slide memoisation of the scan. The provider used to re-scan the whole deck on every keystroke (~1.07 ms per slide, so 208 ms at 200 slides); one keystroke changes one slide. The cache key carries the scanner *object* — a settings change rebuilds it, so a different configuration is a different object and therefore a miss — rather than the settings fields, which would drift.
- `privacy/redaction_manifest_service.dart` — Builds and verifies the redaction manifest. Deliberately *outside* the projection: the projection runs on every render (preview, thumbnail, presenter) and so must stay pure and deterministic — a salt generated there would give a different answer each frame and the preview would rebuild forever. The manifest is therefore made once, at export. `redactedValues` is the single source of truth for both building and verifying, and it applies the same `isRedactable` gate as the projection plus a non-empty-span test: an entry for a redaction that is not in the document sends the recipient looking for a block that was never there.
- `privacy/privacy_quality_bridge.dart` — Maps `PrivacyFinding` onto `SlideQualityIssue` so findings surface in the quality panel.
- `privacy/privacy_projection.dart` — `AudienceDeck` + `PrivacyProjection`: the single boundary a source deck crosses to reach any receiving surface. Redacts `[[…]]` markers before rendering or export; the private constructor means no export path can hold the unredacted source. Media redaction erases the paths *and* sets the projection-only `Slide.mediaRedacted`, because an empty path alone cannot tell the renderer whether a photo was removed or never chosen. Its field list is written out by hand and must match the scanner's and the manifest's, or the export gate reports a finding that *Redact* cannot clear; `test/privacy_scan_redact_parity_test.dart` holds the three lists against each other.
- `quality_export_policy.dart` — Gates export by slide-quality issues with warnings.
- `recovery_service.dart` — Auto-saves deck snapshots for crash/unsaved recovery. A `RecoverySnapshot` carries the markdown plus the two layers that are *not* in it: the user notes and the ink (`annotations`, the payload of `AnnotationCodec.encode`). Drawing marks a deck dirty, so a deck that was only drawn on gets a snapshot — and without that field the restore handed it back silently without the drawings. `available` is the honest platform answer (false on web: no application-support directory, so every call is a no-op); ask it rather than re-testing `kIsWeb` at the call site, so the UI's claim and the service cannot drift apart.
- `rehearsal_controller.dart` — Unit-testable controller tracking elapsed/remaining/per-slide rehearsal timing.
- `rfc3161_timestamp.dart` — Builds a `.tsq` from the seal hash and parses/verifies a `.tsr` timestamp token.
- `rich_text_layout.dart` — Computes pagination and scaling for rich-text markdown bodies.
- `scope_coverage.dart` — `deckScopeCoverageGaps`: flags in-scope objects with no test and no finding.
- `finding_context_score.dart` — builds the deck's scope-object→CIA index and derives each finding's context (environmental) score / effective severity from it.
- `sidecar_format.dart` — The version contract shared by every sidecar next to a `.md`: a file declaring a higher version is not loaded **and** not overwritten. Refusing to read while still saving over it is worse than reading half, not better — the deck holds nothing in memory, so the save reads as "there is nothing here".
- `secret_store.dart` — Manages secrets (WebDAV credentials, S3 secret access key, git token, AI API key) in the OS keychain.
- `slide_layout_metrics.dart` — Layout constants/helpers for text sizing, fonts, and fit scaling; `bulletFitCounts` measures how many bullets fit at natural size (the input to the "Split slide" page capacity).
- `bullet_pagination.dart` — Pure "Split slide" pagination (`chunkBullets`, `splitBulletsIntoPages`/`splitTwoColumnsIntoPages`): fills pages of a fixed size with the remainder last, never leaving a page under `kMinPageBullets`, and halves a list that already fits. Counts bullets and nothing else — measuring what physically fits used to collapse the page size and turn one slide into a stack.
- `split_run.dart` — Pure split-run logic shared by the preview and the quality check: `splitRunRange` finds the maximal group of same-type bullet slides joined by `continuesSplit`, `splitRunDrag` reports which pages of such a run render needlessly small because one page is far fuller (threshold `kSplitRunDragRatio`), and `canContinueSplitFrom` answers whether offering the editor's continuation switch makes sense. No theme, no layout — so both callers agree on what a run is.
- `slide_quality_analyzer.dart` — Checks deck slides for accessibility and readability issues. Note that the split-run check (`_checkSplitRuns`, in the density part) runs *outside* the per-slide memo: whether a slide renders small depends on its neighbours, and that cache is keyed on slide identity.
- `slide_rasterizer.dart` — Renders on-screen slide previews to PNG for WYSIWYG PDF/PPTX export.
- `text_measurement.dart` — `measureTextHeight`/`measureTextWidth` for rendered text dimensions.
- `user_notes_codec.dart` — Serializes per-slide user notes with content fingerprints. Same version rule as `annotation_codec.dart` — it used to read an unknown version `3` as a `2`, which loaded half a file and then wrote that half back.
- `web_asset_store.dart` — In-memory afbeeldingsopslag (`mem:`-paden) voor de webversie; per-pagina levensduur. `retain` ruimt de assets op die nergens meer gebruikt worden; `TabsNotifier.sweepWebAssets` stelt de complete levende verzameling samen (alle tabbladen + ongedaan/opnieuw + klembord) en roept dat aan na dia-verwijdering en opslag.
- `s3/s3_sigv4.dart` — AWS Signature Version 4, written by hand rather than pulled from an SDK: an SDK brings its own HTTP stack and would connect around `NetGuard`, losing the socket pinning every other network source applies. Signing only, no network, so it is testable against fixed vectors (`test/s3_sigv4_test.dart`, cross-checked against botocore).
- `s3/s3_service.dart` — Talks S3 (and S3-compatible endpoints) over a pinned, redirect-free `HttpClient` with SigV4. Lists with a delimiter so prefixes behave as folders. Conditional writes use `If-Match`, but not every S3-compatible endpoint supports them — AWS only since 2024 — so an endpoint that refuses the condition yields `S3Error.conditionalUnsupported` rather than silently overwriting.
- `webdav_service.dart` — Talks WebDAV over a pinned, redirect-free `HttpClient`. Writes are guarded with `If-Match` so a file changed on the server surfaces as `WebdavConflictException` instead of a silent overwrite.
- `presentation_search/presentation_source.dart` — `PresentationSource`: one searchable source of decks for *Slide zoeken*. Local libraries are scanned straight off disk; this abstraction covers the ones that need the network, so the finder can walk them uniformly and in parallel. A source may be slow and may throw — the finder reports per source, so one unreachable connection does not block the rest or the local search.
- `presentation_search/git_presentation_source.dart` — Searches every deck on a git repository's default branch. Reads each `deck.md` through the forge and puts it through the same safety gate as a normal open (scan → marp-sniff → parse), then resolves `repo:` images to in-memory `mem:` paths so previews work. An unreadable or refused deck is skipped, not fatal.
- `presentation_search/remote_presentation_source.dart` — The same for WebDAV and S3: walks the directory tree and reads both loose `.md` files and `.ocideck` packages, again through `FileService.openDeckFromContent`.
- `presentation_search/remote_file_client.dart` — `RemoteFileClient`/`RemoteFileEntry`: a listing detached from the WebDAV- and S3-specific types, so the tree-walking exists once instead of once per protocol.
- `presentation_search/storage_file_clients.dart` — The two adapters that put that interface on top of `WebdavService` and `S3Service`.

### `lib/services/git/` — Git-repository storage (design: `docs/design/GIT_STORAGE.md`)

Reading, writing, concept branches, review PRs, merges and release tags, over
the forge REST plane (all platforms) and — on desktop, when `git` is present —
over a real partial clone. Three forges behind one interface. Cross-deck search
ships (`deck_search.dart` + its shell UI). Open: asset deletion (§6.2,
deliberately manual).

- `git_forge.dart` — The provider-agnostic `GitForge` interface (`probe` for the connection test, `listTree`, `readBlob`, `headSha`, `close`; the release surface `listBranches`/`createBranch`/`listTags`/`createTag`/`openPullRequest`/`mergePullRequest` (with a `deleteBranch` flag to prune the merged branch)/`pullRequestForBranch`) plus its value types (`BranchRef`, `TagRef`, `PullRequestRef` carrying head/base, `PullRequestMergeMethod`), `RepoProbe` (default branch, emptiness, push rights — what the settings dialog's *Test connection* reports), `GitForgeException` and the `listDecks` extension. Everything git itself has no notion of lives behind this. Also the optional `CodeSearchCapable` capability (a separate interface, not a `GitForge` method, because most forges cannot do this and the base contract must only promise what every adapter can keep): `searchDeckCodeDirs` returns the deck dirs a server-side search matched, or `null` when the forge/instance can't — index-based, so best-effort. Only `GitLabForge` implements it; Gitea/Forgejo has no endpoint at all, and GitHub's is word/token-based and would silently miss partial-word matches.
- `forge_http.dart` — `ForgeHttp`, the HTTP plumbing the three adapters share: `getJson`/`post`/`sendJson` over the transport, the status-to-`GitForgeException` translation, the JSON decode and the ref check, plus the `kForgeMax*` caps. Not a new layer — `GitForge` remains the contract upwards; this only stops the same code living in three files. What genuinely differs is supplied by the adapter: the URL shape (`apiUri`), the auth header (`headers`), the name the forge carries in an error message (`forgeName`) and whether a 409 means "the repository is empty" (`treats409AsEmptyRepo`, true for GitHub and Gitea, false for GitLab, which uses 409 for a collision).
- `gitea_forge.dart` — Forgejo/Gitea adapter (one adapter: same REST surface). The only place provider-specific knowledge may live. The release ops map onto the REST endpoints (`branches`, `tags`, `pulls`, `pulls/{n}/merge`) through the shared `ForgeHttp` skeleton over its own `apiUri`/`headers`. Gitea/Forgejo deliberately does **not** implement `CodeSearchCapable`: there is no REST code-search endpoint (go-gitea/gitea#31375).
- `github_forge.dart` — GitHub adapter (github.com and Enterprise). Differs from Gitea where it matters: a multi-file commit is four round-trips through the Git Data API (blob → tree → commit → non-forcing ref update), and that last step *is* the concurrency guard; the API host differs from the web host; auth is `Bearer`; an annotated tag is two calls; pruning a merged branch is a separate `DELETE`. Deliberately does **not** implement `CodeSearchCapable`: `/search/code` exists, but its index is word/token-based, so a partial word (`dekk` in `dekking`) does not match while the local scan searches substrings — as a pre-filter it would systematically skip decks the user meant. GitHub search goes through `git grep` or the full scan instead.
- `gitlab_forge.dart` — GitLab adapter (gitlab.com and self-hosted). One commit call again, but an `actions[]` list that must name `create`/`update`/`delete` per file, guarded by `start_sha`; a project is one URL-encoded `owner/repo` segment; auth is `PRIVATE-TOKEN`; a merge request is addressed by its per-project `iid`. Its tree listing carries no file size — recorded via the contract's `reportsBlobSize` flag rather than faked. Implements `CodeSearchCapable` via the project-scope `search?scope=blobs&ref=…` (any branch); needs Advanced/Exact Search on the instance, so an empty answer declines with `null`.
- `git_transport.dart` — The HTTP layer under the forge; carries no provider knowledge, not even the auth header (that differs per forge).
- `git_transport_factory.dart` — Conditional export: pinned `dart:io` on desktop, browser fetch on web.
- `git_transport_io.dart` — Desktop: `NetGuard.safeResolveTrusted` + socket pin + no redirects + byte cap.
- `git_transport_web.dart` — Web: browser fetch with the same-origin fetch-proxy as fallback, but never for a request carrying a token.
- `native_git_mirror_api.dart` / `native_git_mirror_io.dart` / `native_git_mirror_stub.dart` (+ `_factory`) — `NativeGitMirror`, the desktop working copy as a real partial clone (`--filter=blob:none`). Satisfies the `DeckMirror` storage contract (via a `FileDraftStore` over the clone tree) and adds `commitDeck`/`sync`/`prepareForOpen`/`history` (`git log -- <deckDir>`, each entry flagged pushed/unpushed): save is a real `git commit` + best-effort push (durable offline; a rejected push is kept local, not a lost update). `commitDeck` takes an optional `workBranch`/`forkFrom` (D3): it checks out that branch — `git branch` then `git checkout`, not `checkout -b`, since the hardened runner puts operands after `--end-of-options` — or creates it off `forkFrom`, then commits and pushes it; push and unpushed-tracking follow the checked-out branch. `mergeRemote` handles a rejected push (§8.6): fetch, `git merge-base` for the *real* common ancestor, let git merge the rest of the tree (pool blobs are content-addressed and just come along) and hand `deck.md`'s three versions to a caller-supplied resolver, then record a true two-parent merge commit so the next push fast-forwards — pushed only when the resolver came out clean. Token via `GIT_CONFIG_*`, never `.git/config`. The `_GitHistoryDialog` in `shell_actions_git_dialogs.dart` renders the timeline. Also `grepDeckDirs` — a fixed-string, binary-skipping `git grep -l` over the working tree (the needle rides as an operand behind `--end-of-options`; exit 1 "no matches" is an empty answer, not an error; a leading-dash term or a foreign branch declines with `null`) — which powers `NativeGrepShortlister`, the search accelerator (§9.3).
- `git_cli.dart` / `git_cli_io.dart` / `git_cli_web.dart` (+ `_factory`) — the hardened native-`git` runner (§10.2), the only place in the tree that may spawn a process. `NativeGitCli` (io) builds a shell-free argv (user data as operands after `--end-of-options`), a genuinely closed environment — `includeParentEnvironment: false` plus an allowlist carrying only what a process needs to start (plus `LC_ALL=C` and an empty `LANGUAGE`, so git always answers in English — `isPushRejection` reads that output, and a translated "non-fast-forward" would be classified as "offline" and silently queue the user's work instead of reporting the conflict), so no `GIT_TRACE_*` from the user's shell can write the token's `Authorization:` header to a trace and no `GIT_ASKPASS`/`GIT_SSH_COMMAND`/`GIT_CONFIG_PARAMETERS` can steer git (OQ-10), supplies the token via `GIT_CONFIG_*` never argv, caps output and enforces a timeout; `probe()` finds usable git (≥2.19) with the macOS xcode-select guard. The web half is an honest unavailable stub.
- `asset_pool.dart` — The shared content-addressed pool (`repo:assets/<sha256>.<ext>`): SHA-256 naming, fetch-once cache, and re-hashing of every fetched blob — a hash-named path from an untrusted forge proves nothing until checked. `refFor`/`existing` are the save side: hash bytes to a ref, skip blobs already pooled.
- `repo_asset_resolver.dart` — `resolveRepoAssetsToMem`: the other direction — every `repo:` image reference in a deck becomes an in-memory `mem:` path with the bytes from the pool. Shared by opening a git deck in a tab and by searching one (`presentation_search/git_presentation_source.dart`), so both see the same pictures. An asset that cannot be fetched or turns out not to be an image is skipped rather than fatal: the deck opens with a placeholder where the picture belongs, exactly like a package with a broken reference.
- `deck_repo_serializer.dart` — `buildDeckRepoFiles`: turns a deck into its repo file set — `deck.md` bytes plus the missing image blobs, images rewritten `mem:`→`repo:`. The exact inverse of the open path's `repo:`→`mem:`; video/audio are reported, not written as broken refs. Chart data gets its own file next to `deck.md` at the path its `source` names (`chartDataFilesOf` writing, `withRepoChartData` reading) — deliberately not in the content-addressed pool, since a hash path turns every edited cell into a new file instead of a diff. `gitDeckOmissions` counts, per kind, what a commit leaves behind — video, audio, the ink sidecar and the user-notes sidecar, none of which anything in `services/git/` writes — so `_confirmGitOmissions` can ask *before* the commit. Only non-empty layers count: a warning that also fires when nothing is wrong teaches the user to click it away. Carrying those layers is a larger change and is not made here; the warning is.
- `deck_mirror.dart` — `DeckMirror` interface + `DraftMirror`: the durable offline working copy a save falls back to. Text only, one draft per deck (`hasRealHistory == false`). `NativeGitMirror` is the other implementation: it makes real local commits (`hasRealHistory == true`) and serves the history dialog.
- `draft_store.dart` / `draft_store_factory.dart` / `draft_store_io.dart` / `draft_store_web.dart` — the mirror's storage: files on desktop (`FileDraftStore`), the browser key/value store on web (`PrefsDraftStore`), picked by conditional import.
- `outbox.dart` — `Outbox`/`PendingCommit`: the per-deck queue of not-yet-pushed saves, in `shared_preferences` so it survives restart. Carries the intent (deckDir, branch, message, `baseSha`, and an optional `forkFrom` so a work branch queued offline can be created on flush), never the bytes — the mirror holds those. Keyed per repository (`GitRepoConfig.storageSlug`): a repo is a trust boundary, and an unscoped queue meant two repos with a same-named deck overwrote each other's pending commit while a flush pushed the lot to whichever forge happened to be configured. `adoptLegacyEntries()` carries commits from the unscoped era over to the repo that was configured then — that work has reached no server yet, so leaving it behind would silently strand it.
- `sync_engine.dart` — `SyncEngine`: drains the outbox against the forge (`flush`/`flushDeck`), with `baseSha` conflict detection and content-based idempotency (a commit that already landed is skipped, not duplicated). When a queued commit carries a `forkFrom`, the flush creates its work branch (off `forkFrom`) if it is not there yet — so a review round that began offline still lands (D3). A `DeckFilePreparer` hook runs just before each commit — how `flushGit` pools an offline-added image into the reconnect commit; idempotency and deletes compare the deck-dir files only, not the pool blobs.
- `deck_merge.dart` — `mergeDeckVersions`: a three-way merge of one deck against its common ancestor (§8.6). Per *slide*, not per line — a text merge would leave conflict markers in `deck.md`, and an unparseable deck is what you cannot show the user while they choose. Resolves what it can (one-sided edits, identical edits, both-deleted, reorders) and returns the rest as `SlideConflict`, each pointing at where its provisional choice sits in the merged deck so the dialog can swap the other side in. Two fail-safes: a conflict keeps *our* side provisionally, never silently theirs, and the deck TLP becomes the stricter of the two.
- `version_diff.dart` — `diffDeckVersions`: what changed between two released versions (§9.5). A deck has no slide IDs, so matching is two-pass — first on content signature (identical slides find each other even after a reorder → *moved*), then on same-type similarity, so a reworded slide reads as one *edited* change instead of an addition plus a deletion. Leans on `SlideDedupService` for `signatureOf`, `similarity` and the per-field `diff`.
- `deck_search.dart` — `DeckSearch`: text search across every `deck.md` in the repo (§9.3), the text twin of `asset_index.dart`. Hits carry deck, slide index, slide title and a windowed snippet; slide attribution reuses the parser's fence-aware `splitSlideBlocks` (a naive `split('---')` would read a `---` inside a code block as a slide boundary and point at the wrong slide) without needing the deck to parse. Deliberately the opposite failure direction from the asset index: an unreadable deck shortens the answer and is reported alongside it, rather than refusing — every hit shown is true regardless. `truncated` means a real match went unreported, not that the list is exactly full. A `DeckShortlister` seam lets an accelerator pre-filter *which* decks to read (K instead of N) while the hit-building stays identical; `NativeGrepShortlister` (in `native_git_mirror_api.dart`) is the forge-agnostic, exhaustive one — `git grep` over the local clone — so on desktop only the matching decks are read. Without a clone (web), `ServerCodeSearchShortlister` uses a `CodeSearchCapable` forge's server-side search — only GitLab implements it — marked `bestEffort`. Can neither help, the shortlister is absent and the full scan runs. `DeckSearchResult.coverage` records whether the answer is `exhaustive` (grep or full scan) or `bestEffort` (indexed server search, which the dialog flags as possibly lagging).
- `asset_index.dart` — `AssetIndex`: the reverse index over the shared pool (§9.3). One pass over the repo — every `deck.md`, then `assets/` — inverted into asset → the decks that reference it, plus (with `includeReleases`) the release tags that still do. References are found by scanning the raw markdown rather than parsing it, because a slide type the parser skips would hide a reference and a missed reference marks an asset as unused. Two answers with deliberately different standards of proof: `decksUsing` may answer from an incomplete round (whoever is listed really is a user), `unusedAssets` may not — an unreadable deck or release could be the one user, and deleting is irreversible (P2), so it always scans releases too and throws when anything failed to read. Rendered by `_AssetUsageDialog`.

## `lib/state/` — Riverpod providers

- `consent_provider.dart` — `ConsentNotifier` managing consent acceptance/revocation with persistent storage.
- `deck_provider.dart` — `DeckNotifier`: loaded deck, dirty state, undo/redo history, file path. Also `refreshEditorFields`, which bumps `DeckState.revision` without touching the deck: the editor's text fields cache their content in their own controllers and only re-read when that revision changes, so a change arriving from outside them (a table cell edited live while presenting) would otherwise sit behind stale text that the next keystroke writes back. `onChartDataWarnings` is the save-side counterpart of `onSweepWebAssets`: this notifier has no `Ref`, so it hands the chart-data complaints of a save up to `TabsNotifier`, which owns one.
- `deck_provider_ai.dart` — `DeckNotifierAiAlt` extension: count/clear AI-generated image alt-texts.
- `deck_provider_auto.dart` — `DeckNotifierAuto` extension: `autoRenumberFindings` (P2-AUTO).
- `deck_provider_checklist.dart` — `DeckNotifierChecklist` extension: `generateScopeChecklists` (one checklist per scope object, feedback #8) and `clearAllChecklists`.
- `deck_provider_markdown.dart` — `DeckNotifierMarkdown` extension: generate/apply markdown for the whole deck or a single slide (per-slide markdown view).
- `deck_provider_miauw.dart` — `DeckNotifierMiauw` extension: set/remove MIAUW compliance waivers.
- `image_privacy_provider.dart` — De beeldbevindingen als kwaliteitsmeldingen. Eigen asynchrone provider naast de synchrone tekstscan, want dit is de duurste controle: decoderen plus een neuraal netwerk per afbeelding. Scheidt "nul gezichten" van "niet kunnen lezen" — HEIC valt in die tweede categorie, en iPhone-foto's zijn standaard HEIC.
- `deck_quality_provider.dart` — Computes accessibility/quality analysis for the loaded deck. `deckQualityRawProvider` keeps every finding (the badges and the popover need the accepted ones); `deckQualityProvider` drops the ones on an accepted slide (the panel and the export gate want the open work). Both run through named top-level functions so the per-tab override in `AppShell` cannot drift from the original.
- `git_provider.dart` — `gitForgeProvider` (builds the adapter from one connection's repo plus the token from the keychain) and `gitDeckListProvider` (the decks on a branch). Both are families keyed on connection id.
- `editor_provider.dart` — `EditorState`/`EditorNotifier`: selected slide, editor mode, markdown buffer.
- `tabs_provider_git_native.dart` — `TabsNotifierGitNative` extension: the native-git plane through the notifier — `openDeckFromGitNative` (read from the clone, tab `baseSha` = clone HEAD), `saveToGitNative` (resolve the round's work branch like the REST path → `commitDeck(workBranch, forkFrom)`; on a rejected push `_mergeNative` runs `mergeRemote` with a resolver that puts all three versions through the import gate and merges them with `mergeDeckVersions`), `syncGitNative`. Chosen over the REST path by `nativeGitMirrorProvider`.
- `tabs_provider_git.dart` — `TabsNotifierGit` extension: `openDeckFromGit` — fetch a deck from a repo, through the shared import gate, into a tab carrying a `GitOrigin`; `readVersionDeck` — read a deck at a release tag through the same gate without placing it (the read side under opening *and* under comparing two versions); `openVersionFromGit` — the same, placed **read-only** (a labelled snapshot, no `GitOrigin`, so the save path can never target it); `saveToGit` — the inverse, but landing on a dated **work branch** (`decks/<naam>/<datum>`, D3) rather than the default branch: the first save of a round creates it (lazily, off the default), later saves stay on it, and offline it queues with a `forkFrom` so the flush can create it. `openForReview` — evaluate the classification gate on `deckReleaseTlp` (max effective TLP, fail-closed, before any push) then `openPullRequest(work → default)`; `mergeConcept` — find the work branch's PR (`pullRequestForBranch`), merge it (optionally pruning), and re-base the tab onto the default branch; `tagRelease` — the same gate, then `createTag(releaseTag(deckName, version), target: default HEAD)`. `flushGit` drains the queue and re-bases any open tab whose deck landed. The "Concept mergen…"/"Versie vastleggen…" menu items live in `app_shell_menu.dart`; their dialogs, and the version-compare dialogs, in `shell_actions_git_dialogs.dart`.
- `git_provider.dart` — the forge-plane providers, every one of them a family keyed on connection id: `gitForgeProvider` (build the adapter from config + keychain token), `nativeGitMirrorProvider`, `draftMirrorProvider` / `outboxProvider` / `syncEngineProvider` (the offline queue), `gitDeckListProvider` (the browser's deck list), and `gitDeckTagsProvider` (a deck's release tags, newest first — the "Versies…" picker). Keyed on the id rather than the config so a corrected typo in the server URL does not detach an open deck from its source; `gitConnectionsProvider` and `primaryGitConnectionProvider` answer "which repos are there" and "which is the default". The "Versies…" menu lives in `app_shell_menu.dart`; `_GitVersionsDialog`, `_VersionComparePicker` and `_VersionDiffDialog` in `shell_actions_git_dialogs.dart`.
- `image_contrast_provider.dart` — Computes title-slide image-contrast issues asynchronously per deck.
- `info_safety_provider.dart` — The security-module enable/reveal state that gates the pentest features.
- `local_cve_provider.dart` — `LocalCveNotifier`/`LocalCveState`: the local CVE database's status, build progress and cancellation, plus `localCveAvailableProvider` — which the CVE picker uses to search offline (and then deliberately *not* fall back online).
- `provider_warmup.dart` — `warmTabDerivedProviders`: keeps the tab's derived chain subscribed for as long as the tab lives, so a deck change schedules its refresh *before* the frame. Without it an unread chain goes dirty unnoticed and the first widget to read it flushes mid-build, which Flutter answers with "setState() called during build". Guarded by `provider_warmup_test.dart`.
- `privacy_provider.dart` — Runs the privacy scan for the active deck (per-tab scoped) and surfaces it everywhere the deck's quality is shown. The raw scan (`privacyRawScanProvider`) feeds two views: the panel/thumbnail issues (`privacyScanProvider` → `privacyQualityIssuesProvider`, which suppress already-handled slides) and the export gate's count (`privacyExportSummaryProvider`, which must *not* suppress them — a gate has to know how much was handled).
- `parts/settings_provider_connections.dart` — The file connections: add/update/remove/reorder, and the one-time migration out of the three older prefs keys (`libraries`, `webdavServer`, `gitRepo`). Those keys are left alone until the first change, so falling back to an older build costs nothing.
- `parts/settings_provider_privacy.dart` — The privacy switches (master, per-rule, own identity, export gate).
- `settings_provider.dart` — `SettingsNotifier`: app settings, theme/appearance profiles, cockpit schemes.
- `slide_clipboard_provider.dart` — Global slide clipboard for copy/paste across tabs.
- `tabs_provider_package.dart` — `_TabsPackageAssets` extension: the unpack path of an `.ocideck` opened in memory (web, or an import without a project folder). Images go to the `WebAssetStore` and slide paths are rewritten to `mem:`; chart data is inlined into the spec (it is text belonging in the spec, and on web there is no project folder for a separate file to sit in); the sidecars are re-attached as layers. All three refuse a reference that points outside the package root with `../`.
- `tabs_provider.dart` — `TabInfo` and the tabs notifier: open editor tabs, recovery, WebDAV origin. Also hosts the one-shot open-time signals the shell listens on, including `securityModulePromptProvider` — set once per open when a deck carries Informatieveiligheid slide types, driving the "enable the module" discovery banner. The signal carries only the tab id; which slide the banner points at is read from the live deck on every click, because slides can be deleted or moved while it is up. The shell takes the banner away as soon as its claim stops holding — another tab in view, the deck closed, or the last security slide deleted. The autosave tick writes the ink layer into the snapshot alongside the user notes, and `restoreRecovered` decodes it back; an unreadable ink payload is logged and skipped rather than allowed to block the recovery of the text. `chartDataWarningProvider` is the same one-shot shape, now carrying a `whileSaving` flag: reading and writing need different words, because a failed read leaves a chart empty while a failed write leaves the numbers nowhere but the open window.
- `webdav_provider.dart` — Providers for `WebdavService`, connection lookup and directory listings, all keyed on connection id. The listing key carries the connection too: two servers with the same folder name were otherwise served each other's contents from cache.

## `lib/utils/` — small shared helpers

- `asn1_der.dart` — Minimal dependency-free ASN.1/DER encode + parse for RFC 3161 timestamping.
- `asset_destination.dart` — `resolveAssetDestination`: picks where an imported asset lands. On a name clash it compares contents — identical means reuse, different means a numbered suffix — so two pictures both called `screenshot.png` stay two pictures instead of silently becoming one.
- `atomic_file.dart` — Atomic writes (temp file + rename) to prevent data loss on crash.
- `bullet_fixes.dart` — The deterministic one-click fixes behind the text-density quality reports: `splitSentenceBullets` cuts a multi-sentence bullet into one bullet per sentence (and copies the line as it was into the speaker notes, because the connection between those sentences lived in the full sentence), `trimBulletExplanations` moves the explanation behind a *label : explanation* bullet off the slide. Each has a `can…` twin so the panel offers an action only when it does something — and, for the sentence split, only while the result stays inside the readability threshold, since splitting adds bullets.
- `bundled_asset.dart` — `asset:`-schema voor méégebundelde logo's van ingebouwde stijlprofielen.
- `color_contrast.dart` — WCAG 2.1 contrast-ratio calculation and hex colour parsing.
- `number_convention.dart` — Works out whether a file writes `1.234,56` or `1,234.56`, from evidence across all its values rather than per cell (`scanDecimalConvention`), and reads a value under a settled convention (`parseNumberUnder`). Deduces or refuses: what no value settles comes back as `undecided` for the chart import to ask about, never guessed from locale.
- `csv.dart` — RFC 4180 quoting for the two readers of CSV *files*, in two framings: `parseCsvRows` reads a whole document (a quoted field may hold a line break — MITRE's CWE export needs that) and `parseCsvLine` reads one already-split line, so a stray quote stops there instead of swallowing the file. Used by `models/chart.dart` and `tool/build_cwe_catalog.dart`. Also the scan behind `table_clipboard.dart` (spreadsheet paste). A fourth hand-rolled quote scanner fails `check_conventions.dart` — three had accumulated unnoticed before this was one file.
- `deck_markdown_dashes.dart` — Escapes standalone dash lines so the deck parser can't misread them.
- `file_download.dart` — Browserdownload (blob + anker) voor web-opslaan; conditional import met stub.
- `image_focal.dart` — Maps a normalized image crop focal point (0..1) to the `Alignment` used to reposition a cropped/cover image.
- `image_limits.dart` — Caps decoded image dimensions to prevent OOM; the `CappedImage` provider only downscales over-cap images so within-cap animated GIFs/WebP decode natively and keep animating.
- `media_fetch.dart` (+ `_io` / `_web`) — `guardedNetworkImage`: the image provider for a deck-supplied remote URL. On desktop it fetches the bytes itself over a socket pinned by `NetGuard.connectPinned`, so `NetworkImage` never re-resolves the host and there is no DNS-rebind window between check and fetch. On web the browser (CORS, mixed content) and the page CSP are the gate — `dart:io` pinning cannot run there.
- `image_luminance.dart` — Computes average image colour, cached by mtime/size.
- `inline_markdown.dart` — The widget-free half of the inline markdown: `parseInlineRuns`/`stripInlineMarkdown`/`inlineRunStyle`/`buildInlineSpans`. Text and its styling, not a widget tree, so the headless services (`text_measurement`, `slide_quality_analyzer`) can measure and analyse exactly what the render will show without importing the UI layer.
- `log.dart` — Fail-soft logging to DevTools without exposing sensitive data (`logError`/`logWarning`). The rule is that a message carries an operation description and the caught error, never deck or file *contents*; `test/log_no_content_test.dart` scans `lib/` for the shapes that break it (a collection joined, taken from or sliced into a message), which is how a chart warning holding real cell values was found.
- `lru_cache.dart` — Fixed-capacity LRU cache backed by `LinkedHashMap`.
- `markdown_paste_cleanup.dart` — Cleans pasted website markdown and normalizes rich-text quirks.
- `markdown_quill_codec.dart` — Round-trip conversion between markdown and Quill documents.
- `net_guard.dart` — SSRF guards (host/address checks, `safeResolve`, `resolveConfigured` — which names *why* a host was refused, so a typo is not blamed on the trusted-internal setting — and the media resolve gate) against DNS rebind, plus `connectPinned` — the only supported way to build a pinned `connectionFactory`, because setting one makes the factory solely responsible for TLS (a plain socket meant no encryption at all).
- `user_facing_error.dart` — Caught exception → short, actionable, translated message. One table per storage kind (`webdavErrorMessage`, `gitForgeErrorMessage`, `s3ErrorMessage`), each an exhaustive switch so a new error kind cannot be forgotten; tests assert no two kinds share a message. The raw service message stays for the log.
- `page_scoped_notes.dart` — Per-page speaker/user-notes parsing and storage.
- `password_generator.dart` — Cryptographically strong random passwords (`Random.secure`) for encrypted packages.
- `password_strength.dart` — Entropy-based password-strength estimate (warn-only) for the encrypt dialog.
- `project_path.dart` — Path resolution with project containment and symlink checking.
- `sanitize_svg.dart` — Strips dangerous elements/attributes from Mermaid SVG output.
- `table_dates.dart` — `parseIsoDateCell`/`isPastDateCell`: recognises a table cell that is a bare ISO date and whether it has passed. Strict `yyyy-mm-dd` only, and it rejects dates that do not exist (`DateTime` silently rolls 31 February into March). Drives the `table-overdue` marking, which is derived against the day the deck is shown rather than stored.
- `table_clipboard.dart` — Recognises whether clipboard content is a table and which separator it uses (the part that is genuinely about a paste); the field scanning is `csv.dart`. Parses tabular clipboard content (TSV, CSV, markdown tables).
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
- `unsaved_work_guard.dart` — Export selector: `setUnsavedWorkGuard(bool)`, called by the shell whenever the dirty state of the open tabs changes.
- `unsaved_work_guard_io.dart` — Desktop/mobile: a no-op. `windowManager`'s `setPreventClose` + `onWindowClose` already hold the window and the shell asks its own question there; two confirmations in a row teach nobody anything.
- `unsaved_work_guard_web.dart` — Web: registers a `beforeunload` listener while unsaved work is open, and removes it again. Both `preventDefault()` and a non-empty `returnValue` are set because browsers differ in which they honour; the wording is the browser's own and cannot be chosen. Registered only when needed — an always-present listener keeps some browsers from putting the page in their back/forward cache. The one listener is kept in a variable, since `removeEventListener` matches on identity.

## `lib/theme/`

- `app_theme.dart` — Material 3 theme builder with brand colours and appearance profiles.

## `lib/l10n/` — localization

- `app_localizations.dart` — `AppLocalizations` class + delegate; assembles the lookup maps from per-language files.
- `slide_quality_localization.dart` — Localized formatting for slide-quality issues and export summaries.
- `slide_quality_navigation.dart` — Routes a quality issue to the relevant editor field.

### `lib/l10n/translations/` (each `part of app_localizations.dart`)

One file per language, 32 in total. `nl.dart` is the source language; the other 31
carry the translations and are kept in step by `make add-l10n` / `make l10n-check`:
`en` (English), `de`, `fr`, `es`, `it`, `pt`, `pl`, `uk`, `el`, `da`, `sv`, `fi`,
`cs`, `sk`, `sl`, `hr`, `hu`, `ro`, `bg`, `et`, `lv`, `lt`, `ga`, `mt`, `tr`, `id`,
`fy` (Frisian), `pap` (Papiamento), `gsw` (Swiss German), `la` (Latin) and
`tlh` (Klingon).

## `lib/widgets/` — UI

- `app_shell.dart` — Main application shell: layout, file IO, and dialog coordination. Also the listeners for the one-shot signals: `_listenChartDataWarning` (two texts, since a data file that could not be *read* leaves a chart empty while one that could not be *written* leaves the numbers only in this window — the second is shown as an error) and `_listenUnsavedWork`, which passes the dirty state to `setUnsavedWorkGuard` and, where `RecoveryService.available` is false, says once that a crash recovers nothing here. That notice waits for the first edit rather than firing at startup: a warning about losing work when there is no work yet reads as noise.
- `markdown_notes_editor.dart` — Barrel re-export of the markdown notes editor.
- `mermaid_render_host.dart` — `MermaidRenderHostLayer`/`MermaidRenderHost`: the offstage WebView that `MermaidRenderService` renders its diagrams in, mounted only after the first diagram is requested.
- `asset_origin_badge.dart` — `AssetOriginBadge`: makes visible what happens to a slide's media once the presentation is passed on. Says what the origin *means* rather than where the file sits, with the consequence and the way out in the tooltip. Deliberately confined to the editor — the rendered slide is also what the audience and the export see, and a work instruction does not belong there.
- `privacy_badge.dart` — `PrivacyBadge`, the bare `PrivacyKatMark`, and the `privacyKatSvg` mark: the non-blocking marker (with an explanation on hover) for a spot where personal data is pointed at or something leaves the device. Used by the status bar's remote-origin badge, the export-readiness chip's privacy warnings, and the Security tab's online-CVE switch.
- `privacy_statement_content.dart` — Privacy/license content shared by the consent and settings dialogs.

### `lib/widgets/shell/` (each `part of app_shell.dart`)

- `ai_actions.dart` — `_MainLayoutAiActions`: the bulk "wipe AI alt-texts" safety action.
- `command_palette_actions.dart` — `_MainLayoutCommandPalette`: builds and shows the Ctrl/Cmd+K command list (incl. the security-module actions).
- `shell_actions.dart` — File-IO helpers for deck import/export and the WebDAV source, plus shared `presentDeck`/`requestCloseTab` helpers. Draagt ook de twee gedeelde ingangen `_openFromConnection`/`_saveToConnection` (één "Openen uit…" en één "Opslaan naar…" voor alle opslagsoorten) en `_saveToOrigin`, waarmee de gewone opslaanknop teruggaat naar de plek waar het deck vandaan kwam in plaats van lokaal te landen. Also `emptyAudienceReason`, the one sentence shown when presenting or exporting is left with no slides at all: it names skipping and TLP withholding separately, and both together, because the old single line ("all slides are skipped") sent the user to a button that cannot undo a classification.
- `shell_actions_git.dart` — The `…`-menu handlers for the git plane: open/save, sync, flush the outbox, history, versions, compare, resolve a merge conflict, open for review, merge the concept, tag a release, and the pool overview. Each one gates and reports; the dialogs themselves live next door. `_confirmGitOmissions` runs first on the save path: it counts what a commit leaves behind (`gitDeckOmissions`) and blocks on a confirmation, in the same shape as `_confirmWebAssetLoss` — telling someone afterwards that their drawings did not travel is a condolence, not a warning.
- `shell_actions_git_dialogs.dart` — The git dialogs: browse, history, the version list and its compare picker, the version diff, the merge-conflict chooser, save, review, merge and tag.
- `shell_actions_git_assets.dart` — `_AssetUsageDialog`: the pool overview — per image who references it, in three states (a deck uses it / only a released version still does / found nowhere). The cleanup section shows what could not be read instead of a candidate list when the round was incomplete, and calls a complete list a proposal rather than a verdict: another branch may still use what looks orphaned here. Its own file because the dialogs file is at the line ratchet.
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
- `slide_list_panel_bars.dart` — The bars above the list (`part of slide_list_panel.dart`): `_SkipBanner` (how many slides are skipped, with *Alles tonen* to clear the marks), `_WithheldBanner` (how many are held back by their TLP) and `_BulkActionBar` for a multi-selection. Two separate banners on purpose: withholding is not a per-slide choice the author made and cannot be cleared by a button, so the withheld bar carries no action — raising the deck's level belongs with the TLP chip, not with a tidy-up in a sidebar.
- `slide_list_panel.dart` — Searchable, reorderable thumbnail list with import/paste/add controls.
- `slide_quality_panel.dart` — Slide accessibility/quality checks with issue filtering.

### `lib/widgets/dialogs/`

- `add_slide_dialog.dart` — Selects a slide type when adding a slide.
- `command_palette.dart` — Searchable command overlay (Ctrl/Cmd+K); filters actions, keyboard-navigable.
- `consent_dialog.dart` — Initial consent/welcome dialog (privacy and license).
- `cvss_builder_dialog.dart` — Reusable per-metric CVSS 4.0 builder (`CvssBuilder`) + modal wrapper (`CvssBuilderDialog`) with a base/context score read-out; shared by the finding wizard and editor.
- `maswe_picker.dart` — `MaswePicker`: doorzoekbare kiezer over de MASWE-lijst voor het MASWE-veld van een bevinding. Zet onuitgeschreven zwakheden onderaan en markeert ze; vult bewust géén beschrijving in, want die is bij de bron nog concept.
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
- `new_deck_dialog.dart` — Creates a new presentation with a title; the searchable template picker + `templatePickerIcons`, hiding `requiresInfoSafety` templates (MIAUW) until the module is revealed.
- `open_presentation_dialog.dart` — Full-text searchable presentation picker with directory scanning.
- `git_search_dialog.dart` — `GitSearchDialog`: the cross-deck search UI. A button rather than search-as-you-type, since each round reads N files over REST. Picking a hit returns its deck dir to `_searchDecks`, which opens it through the ordinary `_openFromGit` path. A dialog of its own rather than a `part` of the shell library, so it can be driven with a `DeckSearch` on its own.
- `package_encrypt_dialog.dart` — Optional password protection when exporting a package: strength meter, generator, copy.
- `package_password_dialog.dart` — Prompts for the password when opening an encrypted package (with wrong-password retry).
- `presentation_info_dialog.dart` — Edits title/author/organization/description metadata.
- `scan_library_dialog.dart` — Scans well-known locations for presentations.
- `scope_coverage_dialog.dart` — Shows the scope-coverage gaps (in-scope objects with no test/finding).
- `seal_timestamp_dialog.dart` — RFC 3161 timestamp workflow: export the `.tsq`, import/verify the `.tsr`.
- `settings_dialog.dart` — Sidebar settings (theme colours, fonts, cockpit,
  Opslag, Licentie en Privacy, Beveiliging, Checklists, and an "Over OciDeck"
  screen); tab bodies live in `parts/settings_dialog_*.dart` (the Checklists tab
  managing user checklist templates is `parts/settings_dialog_checklists.dart`).
  Which tabs exist, in what order, with which icon and label, is the
  `SettingsSection` enum in `parts/settings_dialog_sections.dart` — one list, on
  name. It replaced four index-aligned lists whose numbers silently drifted apart
  (the git tab was once inserted at index 8 without renumbering the search index,
  so "checklist" jumped to Git-repository). Nothing addresses a tab by number any
  more.
  The three network sources own their editing state instead of scattering it
  over the dialog: `parts/settings_dialog_webdav_form.dart`,
  `..._git_form.dart` and `..._ai_form.dart` each hold their controllers, their
  init and their save. Deliberately no shared base class — they differ for real
  (git has a forge/owner/repo, WebDAV a subfolder, AI a mode) and forcing one
  type yields a base class with holes. Only the part that was literally
  identical is shared: `parts/settings_dialog_secret.dart` (`KeychainSecret`),
  which answers "must this secret be written?" — the two silent failures being a
  save that lands before the async keychain read (blanks the secret) and an
  identity change that leaves it under the old key.
  The dialog's own shell — sidebar, nav items, branded footer, content header,
  footer bar — is `parts/settings_dialog_chrome.dart`. It is the one block that
  reads only the selected section and writes it back, touching none of the
  settings, so it can be read without holding the rest of the state in mind.
  Storage is one tab and one list: `parts/settings_dialog_storage.dart` renders
  the file connections as a single reorderable list — folders, WebDAV servers,
  S3 buckets and git repositories mixed — plus the export folder. Order is not decoration:
  the topmost usable connection of a kind is that kind's default
  (`AppSettings.primaryOf`), so dragging is how the user says which server is
  *the* server. Each row expands to that kind's own panel, which stayed where it
  was: `parts/settings_dialog_webdav.dart` and `parts/settings_dialog_git.dart`,
  now taking the form object of one connection (`_webdavPanel(form)` /
  `_gitPanel(form)`) instead of reading the single global one. The git panel's
  `_gitTokenScopeHelp` shows, under the token field and switching with the forge
  dropdown, which token permissions each forge needs (Gitea/GitHub/GitLab differ,
  and only GitLab's `read_api` unlocks its server-side search) — proactive, not
  only after a failed connection test. The form objects
  live per connection id in `_webdavForms`/`_gitForms`, because a
  `TextEditingController` cannot sit in an immutable model. A fourth kind is a
  value in `StorageConnectionKind` plus a branch in `_connectionPanel`.
  Search over the settings lives in `parts/settings_dialog_search.dart`
  (`SettingsSearchEntry`, the search field, and the jump-and-flash), with the
  index of what is searchable in `parts/settings_dialog_search_index.dart`.
  Picking/creating/deleting a style profile plus exporting and importing one as
  a `.ocideckstyle` file is `parts/settings_dialog_profile.dart`; it mutates via
  `_adoptProfile` on the state class, since `setState` is protected and out of
  reach from an extension.
  Anchors are free: every section heading goes through `_sectionTitle`, which
  registers a `GlobalKey` under its own text, so a hit can scroll its section
  into view without any of the tab bodies knowing about search.
- `slide_finder_dialog.dart` — Stay-open searcher for gathering slides from many presentations.
- `slide_quality_details_dialog.dart` — Issues grouped by severity with counts and navigation.
- `storage_connection_picker.dart` — Asks which file connection an action works with, for WebDAV, S3 and git alike. Shows nothing at all when there is exactly one usable connection of that kind, so the single-server case keeps the flow it always had; the question only appears once it is a real question. Deck-bound actions never reach it — they follow the origin (see `AppSettings.gitConnectionFor`).
- `s3_browser_dialog.dart` — Browses an S3 bucket to pick a deck or images, on the connection it is given rather than one it looks up itself. S3 has no folders; the common prefixes a delimited listing returns arrive as `S3Entry.isCollection`, so this screen needs to know nothing about prefixes.
- `webdav_browser_dialog.dart` — Browses WebDAV folders to pick a deck or images, on the connection it is given rather than one it looks up itself.

### `lib/widgets/editors/` — per-slide-type editors

- `_editor_field.dart` — Shared layout helpers for slide editors.
- `ai_suggest_field.dart` — Per-field "suggest text (AI)" control + AI-concept badge/Nagekeken for finding free-text fields.
- `alt_text_field.dart` — Per-image alt-text field with the optional "suggest alt-text (AI)" button and AI-draft badge.
- `audio_attachment_editor.dart` — Edits a slide's audio file attachment.
- `bullet_marker_selector.dart` — Per-slide bullet-marker override (dot or paw).
- `bullets_editor.dart` — Edits a bullet-list slide (title, subtitle, nested levels, markers, group headings/"tussenkoppen").
- `bullets_image_editor.dart` — Edits a bullets-with-image slide.
- `chart_editor.dart` — Edits a chart slide (type, data grid, CSV import/linking). The grid is editable whether or not the data is linked to a file — a linked chart writes that file back on save. It was read-only while linked until that write-back existed.
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
- `discoveries_editor.dart` — Edits a discoveries slide (up to six finds, four fields each), with a banner that restates the headline the slide will lead with as you type.
- `asset_overview_editor.dart` — Edits an asset-overview slide (up to eight kinds, four counts each), summing as you type and flagging a subtotal larger than its total.
- `actions_editor.dart` — Edits an actions slide (up to eight lines: action, owner, deadline, on-the-list-since, what is asked, status).
- `scorecard_editor.dart` — Edits a scorecard slide (up to five figures: label, now, previous report, unit, direction). One figure is one compact two-row card carrying a live change chip; ordering is a drag handle, like every other reorderable list in the app.
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
- `inline_markdown.dart` — `InlineMarkdownText`: renders inline markdown with tappable links (and disposes their recognizers). The parsing and styling live in `lib/utils/inline_markdown.dart`.
- `mermaid_diagram.dart` — Renders Mermaid definitions to inline SVG in previews.
- `slide_preview.dart` — Central preview library coordinating all slide-type renderers + shared helpers. `sharedSplitFitScale`/`splitRunMemberScale` compute the one font size a split run renders at; the quality analyzer calls the same functions, so a reported size is the size actually rendered.
- `slide_thumbnail.dart` — Thumbnail with slide preview, metadata, and action buttons. Carries the two finding badges (quality left, privacy right): click to read, double-click to accept or undo. Top-left it flags the two ways a slide can fail to reach the audience: *Overgeslagen* and *Achtergehouden* (`slideWithheldByTlp`), each dimming the preview, each in its own colour, stacked rather than side by side because a slide can be both — and the withheld one names its level in a tooltip, since knowing *that* it drops out does not tell you which control to change. Both states also go into the semantics label, so a screen-reader user hears them.
- `slide_badge_tone.dart` — `SlideBadgeTone` plus the two threshold functions. Grey (`accepted`) is a state of its own, not `none`: a slide where you accepted something must not look like a slide where nothing was found.
- `slide_badge_popover.dart` — The anchored list behind a badge, and `toggleSlideBadgeAcceptance`. Reads the raw results so a grey badge still opens a readable list; refuses to undo `redact`/`shield`, which would put redacted data back into an export.
- `video_playhead_bus.dart` — Cross-widget channel syncing the video playhead across previews.

### `lib/widgets/slides/previews/` (each `part of slide_preview.dart`)

- `preview_scaffold.dart` — `_PreviewScaffold`: the outer skeleton the report-style previews share — a filled area, a scale-down `FittedBox` over a fixed slide width, the logo-aware margin, and the column under it. Checklist, scope matrix, findings summary, sign-off, finding, free markdown, asset overview and discoveries use it. Chart, cockpit, table and scorecard deliberately do not: they compute their own aspect ratio, drop the `SizedBox.expand`, or give the box a fixed height, and bending the scaffold to cover them would turn it into a widget with ten switches.
- `bullets_previews.dart` — Bullet-point slide layout.
- `chart_preview.dart` — Chart slide rendering + dispatch, legend, hover, and screen-reader text for every chart type.
- `chart_preview_extra.dart` — Hand-drawn builders for the horizontal-bar, horizontal-stacked-bar, combo, waterfall, and heatmap chart types.
- `checklist_previews.dart` — Checklist slides with a progress bar; `_ChecklistBulletRow` and the `_GroupHeadingRow` (group-heading/divider) row widget shared by the bullet previews.
- `cockpit_preview.dart` — Animated cockpit/gauge dashboard slides.
- `code_preview.dart` — Syntax-highlighted code slides with fit.
- `media_previews.dart` — Shared audio/video playback lifecycle (`_MediaPlaybackHost`) + remote-media SSRF gate.
- `media_previews_image.dart` — Image rendering helpers, captions, and the placeholders. `ImagePlaceholderReason` keeps "no image chosen yet" visually distinct from "file missing", "outside the deck", "gone after reload", and `redacted` — the last one paints a fixed-black redaction block rather than the grey placeholder, and deliberately does not follow the slate palette (which inverts in dark mode).
- `media_previews_video.dart` — Video/audio slide rendering: local playback, embeds, and the shared media placeholder.
- `overlays.dart` — Logo overlay and TLP-marking badge renderers.
- `question_preview.dart` — Question slides with answer reveal.
- `table_preview.dart` — Table slides with a cell-edit scope.
- `text_previews.dart` — Title and text-based slides.
- `timeline_preview.dart` — Animated timeline renderer with event cards.
- `discoveries_preview.dart` — The longest exposure as a headline, then one row per find: name over kind, an exposure bar on the shared scale, the figure in words and the owner (red when there is none).
- `asset_overview_preview.dart` — Per-kind bars on one shared scale with the at-risk share filled, four aligned count columns and a derived totals row.
- `actions_preview.dart` — Action rows with a kind marker, owner and deadline; a passed deadline is flagged against the current date, like the footer's `{date}`.
- `scorecard_preview.dart` — Scorecard cards: label, figure, the signed change as a tinted pill and the figure it replaced. The number of figures decides the grid (one becomes a hero, four a 2×2, five three-above-two) and the card each figure gets decides its type size — `_CardMetrics` measures the label and hands the figure whatever is left. Card tint and rule follow the profile's accent; the green/red sentiment tokens stay fixed, because they carry meaning rather than styling.

### `lib/widgets/presentation/` — presenter & dual-screen

- `annotation_overlay.dart` — `AnnotationLayer` for interactive drawing/laser pointer on slides.
- `audience_window.dart` — `AudienceWindowApp`: fullscreen slide on the secondary (beamer) window. Its own engine, so it forwards every key it does not handle itself to the presenter over `presenterChannel` (modifiers included — the other side's `HardwareKeyboard` knows nothing of this window); without that bridge the whole shortcut set died the moment this window took the keyboard focus.
- `fullscreen_presenter.dart` — `FullscreenPresenter`: dual-screen presenter mode (notes/clock/grid).
- `rehearsal_summary.dart` — Post-rehearsal timing summary dialog with per-slide breakdown.

### `lib/widgets/presentation/parts/` (each `part of fullscreen_presenter.dart`, an `extension _PresenterX` unless noted)

- `presenter_beamer_payload.dart` — `buildBeamerMarkdown`: the self-contained markdown handed to the audience window. A top-level function, not an extension. Everything the beamer cannot look up for itself travels inside this string — hence the inlined style profile *and* the inlined chart data (a chart's `source` is a projectmap-relative path the second screen cannot resolve).
- `presenter_displays.dart` — Multi-monitor screen management.
- `presenter_ink.dart` — Annotation layer stroking/erasing/laser.
- `presenter_keys.dart` — Keyboard input during presentation. `_handleKey` is a thin `KeyEvent` adapter over `_handleLogicalKey`, which takes the key and its modifiers as plain values so the beamer window can feed its forwarded keys through the same ladder.
- `presenter_navigation.dart` — Slide/page navigation.
- `presenter_notes.dart` — Speaker- and user-note management.
- `presenter_overlays.dart` — UI overlays (badges/help/grid/clock).
- `presenter_playback.dart` — Auto-advance and media playback.
- `presenter_questions.dart` — Question-slide logic (answers, timer).
- `presenter_table.dart` — Live table editing during presentation.
