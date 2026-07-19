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
- `chart.dart` — `ChartSpec`/`ChartSeries` and the `ChartType` enum (bar, stacked/horizontal bar, horizontal stacked bar, combo, line, area, pie, donut, radar, scatter, waterfall, heatmap) for chart slides with inline or linked data. Also the data-file codec: `dataToJson`/`withJson` for new files, `parseCsv`/`withCsv` for files written before the switch, and `withData` picking on the extension. The data file carries values only — colours stay in the chart block, which is what lets the save path compare two data files to decide whether the *numbers* changed. `parseChartDataJson` returns null rather than empty on a corrupt file, so a chart keeps what it has instead of quietly becoming an empty plot.
- `checklist_spec.dart` — `ChecklistSpec` for the security checklist slide (MIAUW tri-state test list linked to findings).
- `checklist_template.dart` — `ChecklistTemplate`/`ChecklistTemplateItem`: a user-created reusable checklist stored in the settings (feedback #9), with tolerant `encodeList`/`decodeList`.
- `cockpit.dart` — `CockpitSpec`/`CockpitMeterSpec` for instrumentation gauges (speedometer, voltmeter, etc.).
- `cvss_builder.dart` — CVSS 4.0 Base-metric metadata + vector assembly, `CiaRating`→`CR`/`IR`/`AR` mapping, `baseCvss4Vector` and `contextCvss` (derive a CIA-weighted context score).
- `cwe_entry.dart` — `CweEntry` for the offline CWE catalog (id/name/description/remediation).
- `maswe_weakness.dart` — `MasweWeakness` voor de MASWE-lijst (id/titel/categorie/platforms/CWE-koppeling/`isPlaceholder`).
- `mastg_test.dart` — `MastgTest` voor de offline MASTG-catalogus (id/titel/platform/MASVS-categorie/MASWE-zwakheid).
- `wstg_test.dart` — `WstgTest` for the offline WSTG catalog (id/title/category).
- `deck.dart` — `Deck` with metadata, TLP classification, slides list, annotations, user notes, and MIAUW waivers.
- `deck_template_security.dart` — The module-only **MIAUW-pentestrapport** deck template (`_buildMiauwReport`): scaffolds the full MIAUW report structure across the security slide types.
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
- `privacy_disposition.dart` — `PrivacyDisposition` (warn/accept/shield/redact) and the slide-overrides-deck resolution.
- `privacy_finding.dart` — `PrivacyFinding`/`PrivacyScanResult`: what the privacy scanner found. Never stores the raw value — only a masked sample.
- `used_tool.dart` — `UsedTool` + `toolsAppendixRows`: de hulpmiddelen die bij het onderzoek zijn gebruikt (MIAUW EIS 4.8.2 — beschrijving, versie, publieke referentie), met een tolerante `naam@versie | url | beschrijving`-vorm omdat het veld met de hand wordt getypt. Levert de bijlagetabel in eisvolgorde; de kopteksten komen van de aanroeper zodat ze in de taal van het *rapport* staan.
- `reference_standard.dart` — `ReferenceStandard`/`StandardFreshness`/`UpstreamProbe`: één gebundelde referentiestandaard als data (versie, bron-URL, wat er precies gebundeld is, licentie, en hoe upstream te bevragen). `UpstreamProbe` kent vier strategieën en met opzet géén `manual`: CWE en CVSS stonden eerst als "niet te bevragen" tot bleek dat MITRE een REST-API heeft en FIRST per versie een schema op een vaste URL publiceert. "Onbekend" (bron onbereikbaar) mag nooit als "actueel" lezen.
- `settings.dart` — `AppSettings`, `ThemeProfile` (incl. severity tokens + built-in Security profile), `AppAppearanceProfile`, `CockpitColorScheme` config.
- `slide.dart` — `Slide` model with typed fields; `SlideType` enum for the slide layout variants. Inline bullet-item helpers: checklist (`checklistBullet`/`checklistItemChecked`/`checklistItemText`) and group headings (`kGroupHeadingMarker`/`isGroupHeading`/`groupHeadingBullet`/`groupHeadingText`).
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
- `secmodule/sec_reference_inventory.dart` — `SecReferenceInventory` + `ReferenceCatalog`: counts what reference data is *actually* available locally (CWE, WSTG, MIAUW, the CVSS table, finding templates) for the Uitbreidingen tab, so "data available locally" is a number rather than a claim.
- `checklist_templates.dart` — `ChecklistSource` + helpers that present WSTG and each user `ChecklistTemplate` uniformly to the checklist editor and the per-scope generator (feedback #9).
- `description_service.dart` — Stores searchable image descriptions as JSON sidecars.
- `document_integrity.dart` — Computes/verifies the SHA-512 deck seal and seals a finalised deck.
- `evidence_hash_service.dart` — Computes the MIAUW SHA1 + SHA-256 of evidence bytes and builds the appendix hash table.
- `export_bundle.dart` — `ExportBundle`: everything an export needs for one audience profile. A factory the export dialog holds, so it can pick the profile without ever touching the source deck.
- `export_metadata.dart` — `ExportDocumentMetadata` stamped into PDF/PPTX/HTML (title, author, org, keywords, TLP).
- `export_service.dart` — The single chokepoint that renders decks to PDF, PPTX, and HTML.
- `file_service.dart` — Scans presentation files, opens decks (with the safety gate), and import/URL/package IO. `openDeckDetailed` returns `(deck, failure, warnings)`; the warnings carry chart data files that could not be read, because such a chart draws empty and an empty chart is indistinguishable from one that simply has no numbers yet. Part `parts/file_service_scan.dart` holds the private helpers of the disk scan, `parts/file_service_import_dirs.dart` those that pick where an import lands. Part `parts/file_service_dossier.dart` builds the one-click audit dossier (package + `AUDIT_DOSSIER.md` + optional `report.pdf`, AES-256). Part `parts/file_service_style_profile.dart` reads/writes a standalone `.ocideckstyle` style profile (FILE_FORMAT §3.3), embedding a custom logo as base64 and materializing it back on import.
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
- `miauw_eis_catalog.dart` — The bundled offline MIAUW EIS catalog (`MiauwEisCatalog`): all 88 testable EIS, parsed from the authoritative MIAUW workbook.
- `open_file_channel.dart` — Receives file-open paths from macOS for `.md` files.
- `privacy/privacy_checksums.dart` — Eleven-proof (BSN), Luhn and IBAN mod-97 with the country-length table.
- `privacy/privacy_allowlist.dart` — Known non-personal values: reserved domains, example IBANs, test cards, the official test-BSN range.
- `privacy/privacy_secret_rules.dart` — The secrets rule table: vendor tokens (AWS/GitHub/Slack/Stripe/…), PEM private keys, decodable JWTs, connection strings, plain-text passwords — plus the placeholder gate that keeps a how-to slide quiet.
- `privacy/privacy_checksums_eu.dart` — The European checksums: BE mod-97, DE ISO 7064 + digit-repetition, FR NIR, ES DNI/NIE, PT NIF, PL PESEL, IT codice fiscale, HR OIB, BG EGN, RO CNP, SE Luhn, FI mod-31, EE/LT mod-11, UK NHS/NINO — with embedded-birthdate validation where the checksum alone is too weak.
- `privacy/privacy_eu_rules.dart` — The European country packs as a data table: pattern, checksum, context words, confidence.
- `privacy/privacy_special_rules.dart` — GDPR art. 9/10: multilingual keyword families, genetic notation (dbSNP/HGVS), the Dutch parketnummer, the co-occurrence escalator's definition of "identifies a person", and `statementSpan` — because a special-category datum is a statement, not a word, so redacting it takes the whole line.
- `privacy/privacy_phone_rules.dart` — Phone numbers: E.164 validated against the ITU calling-code list (the only form that earns `certain`), national trunk forms, the context-word gate for bare digit runs, and the reserved "drama" ranges that are the `example.com` of telephony.
- `privacy/privacy_contact_rules.dart` — Address, Dutch postcode and labelled person-name: a street-suffix word with a house number, the `1234 AB` pattern (hex colours excluded), and names only behind a salutation (`dhr.`) or a label (`naam:`) — no NER. Address and postcode are each `possible`; a street and a postcode within ~40 characters escalate both to `certain`, because postcode + house number pins one home address.
- `privacy/privacy_export_policy.dart` — The export gate: counts findings by disposition and decides whether to warn, block, or stay quiet.
- `privacy/privacy_own_identity.dart` — `OwnIdentity`: the author's own name/email/domain, which is the sender rather than a finding. Exact and domain matching only — no fuzzy match, which would silently suppress a real finding.
- `privacy/privacy_structural_rules.dart` — Structural leaks: user paths that reveal a name, tokens and personal data in URL queries, share links with built-in access, mailto links, unscannable data-URIs.
- `privacy/privacy_bulk_rules.dart` — Bulk personal data: a table header that names the column ("Naam", "BSN"), or one rule firing too often on a slide. One finding on top of the individual ones, not instead of them.
- `privacy/privacy_scanner.dart` — `PrivacyScanner`: reads a deck for privacy-sensitive data (email, phone, IBAN, BSN, EU numbers, address, postcode, name), with context gates where the checksum is too weak and proximity escalation where a postcode meets a house number.
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
- `slide_layout_metrics.dart` — Layout constants/helpers for text sizing, fonts, and fit scaling; `bulletFitCounts` measures how many bullets fit at natural size (the input to the "Split slide" page capacity).
- `bullet_pagination.dart` — Pure "Split slide" pagination (`chunkBullets`, `splitBulletsIntoPages`/`splitTwoColumnsIntoPages`): fills pages of a fixed size with the remainder last, never leaving a page under `kMinPageBullets`, and halves a list that already fits. Counts bullets and nothing else — measuring what physically fits used to collapse the page size and turn one slide into a stack.
- `slide_quality_analyzer.dart` — Checks deck slides for accessibility and readability issues.
- `slide_rasterizer.dart` — Renders on-screen slide previews to PNG for WYSIWYG PDF/PPTX export.
- `text_measurement.dart` — `measureTextHeight`/`measureTextWidth` for rendered text dimensions.
- `user_notes_codec.dart` — Serializes per-slide user notes with content fingerprints.
- `web_asset_store.dart` — In-memory afbeeldingsopslag (`mem:`-paden) voor de webversie; per-pagina levensduur.
- `webdav_service.dart` — Talks WebDAV (Nextcloud) over a pinned, redirect-free `HttpClient`.

### `lib/services/git/` — Git-repository storage (design: `docs/design/GIT_STORAGE.md`)

Reading, writing, concept branches, review PRs, merges and release tags, over
the forge REST plane (all platforms) and — on desktop, when `git` is present —
over a real partial clone. Three forges behind one interface. Open: cross-deck
search (Phase 6) and asset deletion (§6.2, deliberately manual).

- `git_forge.dart` — The provider-agnostic `GitForge` interface (`listTree`, `readBlob`, `headSha`; the release surface `listBranches`/`createBranch`/`listTags`/`createTag`/`openPullRequest`/`mergePullRequest` (with a `deleteBranch` flag to prune the merged branch)/`pullRequestForBranch`) plus its value types (`BranchRef`, `TagRef`, `PullRequestRef` carrying head/base, `PullRequestMergeMethod`), `GitForgeException` and the `listDecks` extension. Everything git itself has no notion of lives behind this.
- `gitea_forge.dart` — Forgejo/Gitea adapter (one adapter: same REST surface). The only place provider-specific knowledge may live. The release ops map onto the REST endpoints (`branches`, `tags`, `pulls`, `pulls/{n}/merge`) through the same `_apiUri`/`_headers`/`_checkStatus` skeleton.
- `github_forge.dart` — GitHub adapter (github.com and Enterprise). Differs from Gitea where it matters: a multi-file commit is four round-trips through the Git Data API (blob → tree → commit → non-forcing ref update), and that last step *is* the concurrency guard; the API host differs from the web host; auth is `Bearer`; an annotated tag is two calls; pruning a merged branch is a separate `DELETE`.
- `gitlab_forge.dart` — GitLab adapter (gitlab.com and self-hosted). One commit call again, but an `actions[]` list that must name `create`/`update`/`delete` per file, guarded by `start_sha`; a project is one URL-encoded `owner/repo` segment; auth is `PRIVATE-TOKEN`; a merge request is addressed by its per-project `iid`. Its tree listing carries no file size — recorded via the contract's `reportsBlobSize` flag rather than faked.
- `git_transport.dart` — The HTTP layer under the forge; carries no provider knowledge, not even the auth header (that differs per forge).
- `git_transport_factory.dart` — Conditional export: pinned `dart:io` on desktop, browser fetch on web.
- `git_transport_io.dart` — Desktop: `NetGuard.safeResolveTrusted` + socket pin + no redirects + byte cap.
- `git_transport_web.dart` — Web: browser fetch with the same-origin fetch-proxy as fallback, but never for a request carrying a token.
- `native_git_mirror_api.dart` / `native_git_mirror_io.dart` / `native_git_mirror_stub.dart` (+ `_factory`) — `NativeGitMirror`, the desktop working copy as a real partial clone (`--filter=blob:none`). Satisfies the `DeckMirror` storage contract (via a `FileDraftStore` over the clone tree) and adds `commitDeck`/`sync`/`prepareForOpen`/`history` (`git log -- <deckDir>`, each entry flagged pushed/unpushed): save is a real `git commit` + best-effort push (durable offline; a rejected push is kept local, not a lost update). `commitDeck` takes an optional `workBranch`/`forkFrom` (D3): it checks out that branch — `git branch` then `git checkout`, not `checkout -b`, since the hardened runner puts operands after `--end-of-options` — or creates it off `forkFrom`, then commits and pushes it; push and unpushed-tracking follow the checked-out branch. `mergeRemote` handles a rejected push (§8.6): fetch, `git merge-base` for the *real* common ancestor, let git merge the rest of the tree (pool blobs are content-addressed and just come along) and hand `deck.md`'s three versions to a caller-supplied resolver, then record a true two-parent merge commit so the next push fast-forwards — pushed only when the resolver came out clean. Token via `GIT_CONFIG_*`, never `.git/config`. The `_GitHistoryDialog` in `shell_actions_git_dialogs.dart` renders the timeline.
- `git_cli.dart` / `git_cli_io.dart` / `git_cli_web.dart` (+ `_factory`) — the hardened native-`git` runner (§10.2), the only place in the tree that may spawn a process. `NativeGitCli` (io) builds a shell-free argv (user data as operands after `--end-of-options`), a genuinely closed environment — `includeParentEnvironment: false` plus an allowlist carrying only what a process needs to start, so no `GIT_TRACE_*` from the user's shell can write the token's `Authorization:` header to a trace and no `GIT_ASKPASS`/`GIT_SSH_COMMAND`/`GIT_CONFIG_PARAMETERS` can steer git (OQ-10), supplies the token via `GIT_CONFIG_*` never argv, caps output and enforces a timeout; `probe()` finds usable git (≥2.19) with the macOS xcode-select guard. The web half is an honest unavailable stub.
- `asset_pool.dart` — The shared content-addressed pool (`repo:assets/<sha256>.<ext>`): SHA-256 naming, fetch-once cache, and re-hashing of every fetched blob — a hash-named path from an untrusted forge proves nothing until checked. `refFor`/`existing` are the save side: hash bytes to a ref, skip blobs already pooled.
- `deck_repo_serializer.dart` — `buildDeckRepoFiles`: turns a deck into its repo file set — `deck.md` bytes plus the missing image blobs, images rewritten `mem:`→`repo:`. The exact inverse of the open path's `repo:`→`mem:`; video/audio are reported, not written as broken refs. Chart data gets its own file next to `deck.md` at the path its `source` names (`chartDataFilesOf` writing, `withRepoChartData` reading) — deliberately not in the content-addressed pool, since a hash path turns every edited cell into a new file instead of a diff.
- `deck_mirror.dart` — `DeckMirror` interface + `DraftMirror`: the durable offline working copy a save falls back to. Text only, one draft per deck (`hasRealHistory == false`); native git history comes later.
- `draft_store.dart` / `draft_store_factory.dart` / `draft_store_io.dart` / `draft_store_web.dart` — the mirror's storage: files on desktop (`FileDraftStore`), the browser key/value store on web (`PrefsDraftStore`), picked by conditional import.
- `outbox.dart` — `Outbox`/`PendingCommit`: the per-deck queue of not-yet-pushed saves, in `shared_preferences` so it survives restart. Carries the intent (deckDir, branch, message, `baseSha`, and an optional `forkFrom` so a work branch queued offline can be created on flush), never the bytes — the mirror holds those.
- `sync_engine.dart` — `SyncEngine`: drains the outbox against the forge (`flush`/`flushDeck`), with `baseSha` conflict detection and content-based idempotency (a commit that already landed is skipped, not duplicated). When a queued commit carries a `forkFrom`, the flush creates its work branch (off `forkFrom`) if it is not there yet — so a review round that began offline still lands (D3). A `DeckFilePreparer` hook runs just before each commit — how `flushGit` pools an offline-added image into the reconnect commit; idempotency and deletes compare the deck-dir files only, not the pool blobs.
- `deck_merge.dart` — `mergeDeckVersions`: a three-way merge of one deck against its common ancestor (§8.6). Per *slide*, not per line — a text merge would leave conflict markers in `deck.md`, and an unparseable deck is what you cannot show the user while they choose. Resolves what it can (one-sided edits, identical edits, both-deleted, reorders) and returns the rest as `SlideConflict`, each pointing at where its provisional choice sits in the merged deck so the dialog can swap the other side in. Two fail-safes: a conflict keeps *our* side provisionally, never silently theirs, and the deck TLP becomes the stricter of the two.
- `version_diff.dart` — `diffDeckVersions`: what changed between two released versions (§9.5). A deck has no slide IDs, so matching is two-pass — first on content signature (identical slides find each other even after a reorder → *moved*), then on same-type similarity, so a reworded slide reads as one *edited* change instead of an addition plus a deletion. Leans on `SlideDedupService` for `signatureOf`, `similarity` and the per-field `diff`.
- `deck_search.dart` — `DeckSearch`: text search across every `deck.md` in the repo (§9.3), the text twin of `asset_index.dart`. Hits carry deck, slide index, slide title and a windowed snippet; slide attribution reuses the parser's fence-aware `splitSlideBlocks` (a naive `split('---')` would read a `---` inside a code block as a slide boundary and point at the wrong slide) without needing the deck to parse. Deliberately the opposite failure direction from the asset index: an unreadable deck shortens the answer and is reported alongside it, rather than refusing — every hit shown is true regardless. `truncated` means a real match went unreported, not that the list is exactly full.
- `asset_index.dart` — `AssetIndex`: the reverse index over the shared pool (§9.3). One pass over the repo — every `deck.md`, then `assets/` — inverted into asset → the decks that reference it, plus (with `includeReleases`) the release tags that still do. References are found by scanning the raw markdown rather than parsing it, because a slide type the parser skips would hide a reference and a missed reference marks an asset as unused. Two answers with deliberately different standards of proof: `decksUsing` may answer from an incomplete round (whoever is listed really is a user), `unusedAssets` may not — an unreadable deck or release could be the one user, and deleting is irreversible (P2), so it always scans releases too and throws when anything failed to read. Rendered by `_AssetUsageDialog`.

## `lib/state/` — Riverpod providers

- `consent_provider.dart` — `ConsentNotifier` managing consent acceptance/revocation with persistent storage.
- `deck_provider.dart` — `DeckNotifier`: loaded deck, dirty state, undo/redo history, file path.
- `deck_provider_ai.dart` — `DeckNotifierAiAlt` extension: count/clear AI-generated image alt-texts.
- `deck_provider_auto.dart` — `DeckNotifierAuto` extension: `autoRenumberFindings` (P2-AUTO).
- `deck_provider_checklist.dart` — `DeckNotifierChecklist` extension: `generateScopeChecklists` (one checklist per scope object, feedback #8) and `clearAllChecklists`.
- `deck_provider_markdown.dart` — `DeckNotifierMarkdown` extension: generate/apply markdown for the whole deck or a single slide (per-slide markdown view).
- `deck_provider_miauw.dart` — `DeckNotifierMiauw` extension: set/remove MIAUW compliance waivers.
- `deck_quality_provider.dart` — Computes accessibility/quality analysis for the loaded deck.
- `git_provider.dart` — `gitForgeProvider` (builds the adapter from the configured repo plus the token from the keychain) and `gitDeckListProvider` (the decks on a branch).
- `editor_provider.dart` — `EditorState`/`EditorNotifier`: selected slide, editor mode, markdown buffer.
- `tabs_provider_git_native.dart` — `TabsNotifierGitNative` extension: the native-git plane through the notifier — `openDeckFromGitNative` (read from the clone, tab `baseSha` = clone HEAD), `saveToGitNative` (resolve the round's work branch like the REST path → `commitDeck(workBranch, forkFrom)`; on a rejected push `_mergeNative` runs `mergeRemote` with a resolver that puts all three versions through the import gate and merges them with `mergeDeckVersions`), `syncGitNative`. Chosen over the REST path by `nativeGitMirrorProvider`.
- `tabs_provider_git.dart` — `TabsNotifierGit` extension: `openDeckFromGit` — fetch a deck from a repo, through the shared import gate, into a tab carrying a `GitOrigin`; `readVersionDeck` — read a deck at a release tag through the same gate without placing it (the read side under opening *and* under comparing two versions); `openVersionFromGit` — the same, placed **read-only** (a labelled snapshot, no `GitOrigin`, so the save path can never target it); `saveToGit` — the inverse, but landing on a dated **work branch** (`decks/<naam>/<datum>`, D3) rather than the default branch: the first save of a round creates it (lazily, off the default), later saves stay on it, and offline it queues with a `forkFrom` so the flush can create it. `openForReview` — evaluate the classification gate on `deckReleaseTlp` (max effective TLP, fail-closed, before any push) then `openPullRequest(work → default)`; `mergeConcept` — find the work branch's PR (`pullRequestForBranch`), merge it (optionally pruning), and re-base the tab onto the default branch; `tagRelease` — the same gate, then `createTag(releaseTag(deckName, version), target: default HEAD)`. `flushGit` drains the queue and re-bases any open tab whose deck landed. The "Concept mergen…"/"Versie vastleggen…" menu items live in `app_shell_menu.dart`; their dialogs, and the version-compare dialogs, in `shell_actions_git_dialogs.dart`.
- `git_provider.dart` — the forge-plane providers: `gitForgeProvider` (build the adapter from config + keychain token), `draftMirrorProvider` / `outboxProvider` / `syncEngineProvider` (the offline queue), `gitDeckListProvider` (the browser's deck list), and `gitDeckTagsProvider` (a deck's release tags, newest first — the "Versies…" picker). The "Versies…" menu lives in `app_shell_menu.dart`; `_GitVersionsDialog`, `_VersionComparePicker` and `_VersionDiffDialog` in `shell_actions_git_dialogs.dart`.
- `image_contrast_provider.dart` — Computes title-slide image-contrast issues asynchronously per deck.
- `sec_module_provider.dart` — The security-module enable/reveal state that gates the pentest features.
- `local_cve_provider.dart` — `LocalCveNotifier`/`LocalCveState`: the local CVE database's status, build progress and cancellation, plus `localCveAvailableProvider` — which the CVE picker uses to search offline (and then deliberately *not* fall back online).
- `provider_warmup.dart` — `warmTabDerivedProviders`: keeps the tab's derived chain subscribed for as long as the tab lives, so a deck change schedules its refresh *before* the frame. Without it an unread chain goes dirty unnoticed and the first widget to read it flushes mid-build, which Flutter answers with "setState() called during build". Guarded by `provider_warmup_test.dart`.
- `privacy_provider.dart` — Runs the privacy scan for the active deck (per-tab scoped) and surfaces it everywhere the deck's quality is shown. The raw scan (`privacyRawScanProvider`) feeds two views: the panel/thumbnail issues (`privacyScanProvider` → `privacyQualityIssuesProvider`, which suppress already-handled slides) and the export gate's count (`privacyExportSummaryProvider`, which must *not* suppress them — a gate has to know how much was handled).
- `parts/settings_provider_privacy.dart` — The privacy switches (master, per-rule, own identity, export gate).
- `settings_provider.dart` — `SettingsNotifier`: app settings, theme/appearance profiles, cockpit schemes.
- `slide_clipboard_provider.dart` — Global slide clipboard for copy/paste across tabs.
- `tabs_provider_package.dart` — `_TabsPackageAssets` extension: the unpack path of an `.ocideck` opened in memory (web, or an import without a project folder). Images go to the `WebAssetStore` and slide paths are rewritten to `mem:`; chart data is inlined into the spec (it is text belonging in the spec, and on web there is no project folder for a separate file to sit in); the sidecars are re-attached as layers. All three refuse a reference that points outside the package root with `../`.
- `tabs_provider.dart` — `TabInfo` and the tabs notifier: open editor tabs, recovery, WebDAV origin. Also hosts the one-shot open-time signals the shell listens on, including `securityModulePromptProvider` — set once per open when a deck carries Informatieveiligheid slide types, driving the "enable the module" discovery snackbar.
- `webdav_provider.dart` — Providers for `WebdavService`, server config, and directory listings.

## `lib/utils/` — small shared helpers

- `asn1_der.dart` — Minimal dependency-free ASN.1/DER encode + parse for RFC 3161 timestamping.
- `atomic_file.dart` — Atomic writes (temp file + rename) to prevent data loss on crash.
- `bundled_asset.dart` — `asset:`-schema voor méégebundelde logo's van ingebouwde stijlprofielen.
- `color_contrast.dart` — WCAG 2.1 contrast-ratio calculation and hex colour parsing.
- `number_convention.dart` — Works out whether a file writes `1.234,56` or `1,234.56`, from evidence across all its values rather than per cell (`scanDecimalConvention`), and reads a value under a settled convention (`parseNumberUnder`). Deduces or refuses: what no value settles comes back as `undecided` for the chart import to ask about, never guessed from locale.
- `csv.dart` — RFC 4180 quoting for the two readers of CSV *files*, in two framings: `parseCsvRows` reads a whole document (a quoted field may hold a line break — MITRE's CWE export needs that) and `parseCsvLine` reads one already-split line, so a stray quote stops there instead of swallowing the file. Used by `models/chart.dart` and `tool/build_cwe_catalog.dart`. Also the scan behind `table_clipboard.dart` (spreadsheet paste). A fourth hand-rolled quote scanner fails `check_conventions.dart` — three had accumulated unnoticed before this was one file.
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
- `privacy_badge.dart` — `PrivacyBadge`, the bare `PrivacyKatMark`, and the `privacyKatSvg` mark: the non-blocking marker (with an explanation on hover) for a spot where personal data is pointed at or something leaves the device. Used by the status bar's remote-origin badge, the export-readiness chip's privacy warnings, and the Security tab's online-CVE switch.
- `privacy_statement_content.dart` — Privacy/license content shared by the consent and settings dialogs.

### `lib/widgets/shell/` (each `part of app_shell.dart`)

- `ai_actions.dart` — `_MainLayoutAiActions`: the bulk "wipe AI alt-texts" safety action.
- `command_palette_actions.dart` — `_MainLayoutCommandPalette`: builds and shows the Ctrl/Cmd+K command list (incl. the security-module actions).
- `shell_actions.dart` — File-IO helpers for deck import/export and Nextcloud integration, plus shared `presentDeck`/`requestCloseTab` helpers.
- `shell_actions_git.dart` — The `…`-menu handlers for the git plane: open/save, sync, flush the outbox, history, versions, compare, resolve a merge conflict, open for review, merge the concept, tag a release, and the pool overview. Each one gates and reports; the dialogs themselves live next door.
- `shell_actions_git_dialogs.dart` — The git dialogs: browse, history, the version list and its compare picker, the version diff, the merge-conflict chooser, save, review, merge and tag.
- `shell_actions_git_search.dart` — `_GitSearchDialog`: the cross-deck search UI. A button rather than search-as-you-type, since each round reads N files over REST. Picking a hit returns its deck dir to `_searchDecks`, which opens it through the ordinary `_openFromGit` path.
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
  Picking/creating/deleting a style profile plus exporting and importing one as
  a `.ocideckstyle` file is `parts/settings_dialog_profile.dart`; it mutates via
  `_adoptProfile` on the state class, since `setState` is protected and out of
  reach from an extension.
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
- `chart_preview_extra.dart` — Hand-drawn builders for the horizontal-bar, horizontal-stacked-bar, combo, waterfall, and heatmap chart types.
- `checklist_previews.dart` — Checklist slides with a progress bar; `_ChecklistBulletRow` and the `_GroupHeadingRow` (group-heading/divider) row widget shared by the bullet previews.
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

### `lib/widgets/presentation/parts/` (each `part of fullscreen_presenter.dart`, an `extension _PresenterX` unless noted)

- `presenter_beamer_payload.dart` — `buildBeamerMarkdown`: the self-contained markdown handed to the audience window. A top-level function, not an extension. Everything the beamer cannot look up for itself travels inside this string — hence the inlined style profile *and* the inlined chart data (a chart's `source` is a projectmap-relative path the second screen cannot resolve).
- `presenter_displays.dart` — Multi-monitor screen management.
- `presenter_ink.dart` — Annotation layer stroking/erasing/laser.
- `presenter_keys.dart` — Keyboard input during presentation.
- `presenter_navigation.dart` — Slide/page navigation.
- `presenter_notes.dart` — Speaker- and user-note management.
- `presenter_overlays.dart` — UI overlays (badges/help/grid/clock).
- `presenter_playback.dart` — Auto-advance and media playback.
- `presenter_questions.dart` — Question-slide logic (answers, timer).
- `presenter_table.dart` — Live table editing during presentation.
