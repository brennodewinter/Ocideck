// Guards project conventions in lib/ (see CONTRIBUTING / the logger in
// lib/utils/log.dart):
//
//   * No `print(` — diagnostics go through the logger, never stdout.
//   * No `debugPrint(` — it is stripped in release, reaches no operator and no
//     user, and reads like logging while being a silent swallow. RATCHET at 0.
//   * No bare `catch (_)` — swallowing errors silently hides failures; catch a
//     named error and route it through `logError`/`logWarning`. This is a
//     RATCHET: the count may not grow. It is currently 0 — keep it there.
//   * No plain `.writeAsString(`/`.writeAsBytes(` — those truncate the target
//     first, so a crash midway corrupts the file. Use `writeStringAtomic`/
//     `writeBytesAtomic` (lib/utils/atomic_file.dart), which alone is exempt.
//   * File-size RATCHET — a file may not exceed [maxFileLines], except the
//     baselined files below whose ceiling is their size at ratchet time. A
//     ceiling may shrink (split the file) but never grow, so big files trend
//     smaller instead of creeping bigger. Translation data is exempt.
//   * Class-size RATCHET — a class may not exceed [maxClassLines], counted over
//     ALL `part` files of its library (the class plus every `extension … on` it
//     carries). The file ratchet counts files, and a `part` split quiets it
//     without anything getting smaller; this counts the unit you actually have
//     to hold in your head. See [classSizeBaseline].
//   * No raw control bytes — write the escape (\u0000), never the
//     byte itself. See [controlByteBaseline]: this is a review hazard, not a
//     nitpick.
//   * Layer direction — a model may not import state/ or widgets/, a service may
//     not import state/, and state/ may not import widgets/. Hard zero; see
//     [layerRules]. Kept the layers acyclic on discipline alone until now.
//
// Exits non-zero (with the offending locations) when a rule is violated.

import 'dart:io';

/// Bare `catch (_)` sites allowed in lib/. Ratchet only downwards (now 0).
const int catchUnderscoreBaseline = 0;

/// Raw `Color(0x…)` literals allowed in lib/ outside the palette homes (see
/// [_isPaletteHome]). This is a RATCHET: prefer a semantic `AppTheme` token so a
/// palette change — and a future dark mode — touches one place. The count may
/// SHRINK (migrate a literal to a token, then lower this number — the run prints
/// a tip) but never grow. A self-contained non-theme palette (like a
/// deliberately-dark component) may move into its own file that [_isPaletteHome]
/// exempts.
const int rawColorBaseline = 0;

/// `debugPrint(` calls allowed in lib/. RATCHET: keep at 0.
///
/// `debugPrint` looks like the responsible sibling of `print`, and that is
/// exactly the problem. It is stripped in release builds, it never reaches
/// [logError]/[logWarning] and therefore never reaches the DevTools logging
/// stream an operator actually reads, and it reaches no user at all. Four call
/// sites sat in the consent and info-safety providers under a comment that
/// promised to "surface the failure instead of swallowing it" — while doing
/// precisely the swallowing, one rung quieter than a bare `catch (_)` because
/// the reviewer sees a logging call and moves on.
const int debugPrintBaseline = 0;

/// Raw control bytes (NUL, SOH, …) allowed in `lib/` sources. Keep at 0.
///
/// A control character written as the BYTE ITSELF inside a string literal — a
/// separator like `'\u0000'` typed raw — makes the whole file look BINARY to
/// every byte-oriented tool, even though Dart compiles it fine:
///
///   * `grep` silently skips the file. Not "no matches": *no output at all*.
///     A 900-line source file becomes invisible to any grep-based audit — a
///     file-sized blind spot in a tool whose job is security review.
///   * `git diff` renders it as `Bin 11326 -> 11331 bytes`, so a change to it
///     can never be read as a diff in review.
///
/// The fix is free: write the escape (`\u0000`), which produces a byte-identical
/// string. Only tab, LF and CR may appear raw.
const int controlByteBaseline = 0;

/// Files allowed to compare a character against a double quote.
///
/// Three separate CSV field splitters existed side by side — in the chart
/// model, the CWE build script and the clipboard parser — each written by
/// someone who did not know of the others, and each with its own quoting
/// behaviour. Nothing made that visible: the analyzer sees three healthy
/// private functions. This list is what makes a fourth one loud.
///
/// `markdown_service.dart` is not a splitter; it unescapes a backslashed quote
/// while parsing directives.
const Set<String> _quoteScannerHomes = {
  'lib/utils/csv.dart',
  'lib/services/markdown_service.dart',
  'lib/services/import/utils/xml_utils.dart',
  // Not a CSV splitter: scans JSON string-literal boundaries to count bracket
  // nesting depth without being fooled by brackets inside string values. The
  // shape (walk chars, track "…" with backslash-escapes) is unavoidable for a
  // string-aware scan, and the stdlib has no equivalent.
  'lib/utils/json_depth_guard.dart',
};

/// UI imports inside `lib/services/`. RATCHET: may shrink, never grow.
///
/// A service is the headless core: usable without a widget tree, testable
/// without pumping one. Four import lines are left, all in slide_rasterizer,
/// and all of them earned: that service paints actual widgets into an image, so
/// the widget tree IS its subject. text_measurement, slide_quality_analyzer and
/// mermaid_render_service used to sit here too; they were untangled by moving
/// the widget half out (`lib/widgets/mermaid_render_host.dart`) and the
/// text-only half in (`lib/utils/inline_markdown.dart`). A new entry means a
/// service grew a UI dependency it almost certainly does not need.
const int serviceUiImportBaseline = 4;

/// UI imports inside `lib/models/`. Hard zero — do not raise. A model that
/// imports Flutter cannot be reused, tested, or reasoned about on its own.
const int modelUiImportBaseline = 0;

/// A non-baselined `lib/` file may not exceed this many lines — split it first.
const int maxFileLines = 1000;

/// Files already above [maxFileLines] when the ratchet was introduced. Each
/// value is the file's ceiling: it may SHRINK (split the file, then lower the
/// number — the run prints a tip) but never grow. Add a new entry only with a
/// deliberate reason; the goal is fewer and smaller entries over time.
/// `lib/l10n/translations/*` is exempt — those files grow with every UI string.
const Map<String, int> fileSizeBaseline = {
  // +19: LaTeX-Beamer-export — de enum-uitbreiding (label/extension), de
  // latex-case in de switch, en _buildLatex (8 regels thin wrapper naar
  // buildBeamerBody + beamerPreamble). Het gedrag zit in lib/services/latex/;
  // dit is de chokepoint die elk formaat langskomt.
  'lib/services/export_service.dart': 1023,
  // +5: LaTeX-export — de `ocideck`-case in de extensie-switch (de early-return
  // hierboven voorkomt dat hij ooit bereikt wordt, maar de analyzer eist
  // exhaustiveness). Eén regel toegevoegd; onherleidbare plumbing.
  // +58 (#1500): documentmodus — de paginamaat-indicator in _visualLayout en
  // _insertToc (het invoeg-palet dat de `<!-- toc -->`-marker plaatst). De
  // ontleedde blokken en de weergave gingen wél naar aparte parts; dit is de
  // schermklasse zelf, die zijn eigen invoegacties draagt.
  'lib/widgets/document_editor_screen.dart': 1237,
  // +16 (#1235): de `onSessionEdit`-callback rijgt door vier lagen (present →
  // show/showDualScreen → constructor) — onherleidbare plumbing om session-data-
  // edits (checklist/tabel) apart van de live-fix terug te melden. Geen gedrag
  // dat uit te liften valt; de call-sites zitten in de part-bestanden.
  // +20: grafiek-hover spiegelen naar het publieksvenster — het `_chartHover`-
  // veld, de listener-registratie en de `chartHover`-tak in de presenterChannel-
  // handler die in initState (dus in dit bestand) leeft. Het zendhulpje
  // (`_sendChartHover`) en de ontvang-afhandeling (`_applyBeamerChartHover`)
  // staan al in het part-bestand presenter_beamer_payload.dart.
  'lib/widgets/presentation/fullscreen_presenter.dart': 1033,
  // Procesverbetering: matrix/canvas/tree/flow discovery + create() branches.
  // +20 (#1162): de twee onherleidbare navigatievelden `anchor` + `nextAnchor`
  // (stabiel dia-anker en per-dia sprong-uit) met hun doc, constructor- en
  // copyWith-doorvoer. Pure dataplumbing van een nieuw formaatveld; er valt geen
  // gedrag uit te tillen naar een part.
  // +9 (#1162): de `menu`-enumwaarde met haar doc + de slideTypeMeta-entry.
  // +18: de `TableAlign`-enum + het `tableColumnAlignments`-veld met doc,
  // constructor-, duplicate- en copyWith-doorvoer. Pure dataplumbing van een
  // nieuw formaatveld (GFM-scheidingsrij-uitlijning); er valt geen gedrag
  // uit te tillen naar een part.
  // +12: tableNumberColumns-veld + doc + constructor/duplicate/copyWith-doorvoer.
  // +4 (#1407): imageTitleAbove-veld + constructor/copyFrom/copyWith-doorvoer.
  // +8: imageZoom-veld + doc + constructor/duplicate/copyWith-doorvoer.
  'lib/models/slide.dart': 1071,
  // +17 (#1355, #1360): SealTamperWarning-klasse + sealTamperWarningProvider
  // voor de automatische zegelverificatie bij openen, en de diskFull-case in
  // _packageOpenResult. Beide zijn tightly coupled aan de bestaande providers
  // en _reportOpenOutcome in dit bestand — verplaatsen creëert indirectie.
  'lib/state/tabs_provider.dart': 1017,
  // Procesverbetering module card / reveal wiring in the shell.
  // +1 (#1037): the url_launcher_util import so the play-only landing can open
  // slide links in the browser, like every other presentation surface. The file
  // was already exactly at its ceiling; the behaviour itself is one shared call.
  // +2 (#977): the two imports the realtime-Matrix collaboration commands need —
  // `matrix_client_provider` (matrixAccountProvider) and `matrix_collab_dialogs`.
  // The commands themselves live in the collab part file, not here; only their
  // imports must sit in the library head.
  // +1 (#977): the collab_chat_panel import for the chat rail.
  // +1: the collaboration_provider import (matrixCollabActive) gating the
  // realtime-collab palette commands on the module.
  // +1 (#978): the collab_verify_banner import for the device-verification banner.
  // #1053 verplaatste de web-dropafhandeling naar shell_actions.dart; #1078
  // voegde daarna de cockpit-integratie op main toe.
  // +4 (#1098): imports voor de uitbreidingspoort en het rechtenoverzicht voor
  // afbeeldingen; het gedrag zelf blijft in losse providers en widgets.
  'lib/widgets/app_shell.dart':
      823, // +9 (#1270): deckProvider.overrideWith valt terug op een verse DeckNotifier als de tab al disposed is — voorkomt "Tried to use DeckNotifier after dispose" in de privacyketen bij sluiten.
  // +1 (#1235): session_export import — de afloop-flow wordt aangeroepen vanuit shell_actions_present.dart (een part-of zonder eigen imports), dus de import hoort in de library-head.
  // +7 (#1175): _onFilesDropped krijgt de presentatie-tak — een gesleepte
  // .pptx/.odp/.key gaat de import in (routing gedeeld in importDroppedPresentations).
  // +1 (#1004): a single build() ref.listen hook for owner-drop handover. The
  // behaviour is extracted (listenCollabAuthorityChange lives in the collab part
  // file, and _MainLayoutState stays under its class ceiling); only the tab-scoped
  // listen has to sit in build. The file was already exactly at its ceiling.
  // +1 (#977): the matching listenMatrixCollab hook for the realtime session
  // outcome — same one-line build-time listen, behaviour in the collab part file.
  // +4 (#977): the chat rail spread into the workspace row; its logic lives in
  // `collabChatRail` in collab_chat_panel.dart, only the spread + note remain.
  'lib/widgets/app_shell_main_layout.dart':
      985, // +6 (#978 Blok C): _signProvenance-delegator (zware logica in provenance_actions.dart); +1 (video-calls F1): callRail spread
  // +5 (#1209): het desktop- én web-openpad wachten nu op de geladen module-stand
  // (importModuleRevealedWhenReady) vóór ze de melding kiezen, met de bijhorende
  // mounted-guard. Onherleidbare plumbing: de wacht + guard horen in elk openpad
  // zelf, en beide paden delen al `_reportOpenFailure`. Het bestand stond exact op
  // zijn plafond.
  // +16: document-open via Bladeren (browseRequested + openFileByPath) en
  // image-search-pad-helper (deckImageSearchPaths) naast bestaande open-routes.
  'lib/widgets/shell/shell_actions.dart': 1021,
  // Procesverbetering category tab + engine types in the add-slide picker.
  // +18 (#1162): de menu-wireframe (2×2 raster van keuzeblokken) als eigen helper
  // `_paintMenuWireframe` (uit `paint` getild voor de methode-ratchet) plus de
  // `menu`-takken in de kiezer-switches.
  'lib/widgets/dialogs/add_slide_dialog.dart': 1115,
  // chart_preview_improvement part registration + improvement ChartType switch.
  // +Y-01-parameter; improvement cases in improvement_dispatch.dart (part).
  // +13 (#1164): het nieuwe publieke veld splitRunPosition met zijn dispatch en
  // export; de titelteller-helper zelf is naar de part bullets_previews.dart
  // getild, alleen de irreducibele plumbing bleef in de librarykop.
  // +2 (#1164): de optionele `trailing`-span op de gedeelde _md-helper, zodat de
  // teller inline in de titelparagraaf meeloopt i.p.v. ernaast te zweven.
  // +11 (#1162): de `menu`-tak in `_buildContent` (de _MenuPreview-aanroep) plus
  // de menu_blocks-import in de librarykop; de preview zelf staat in de part
  // menu_preview.dart.
  // +7 (#1162): het `onMenuBlockTap`-veld + constructor-param + doorgifte, zodat
  // een keuze-menublok tijdens presenteren aanklikbaar is.
  // +2 (#1281): twee nieuwe `part`-regels (chart_preview_heatmap /
  // chart_preview_touch) om chart_preview_extra.dart onder de 1000 te houden.
  // +1 (#1282): `fitScaleOverride` doorgeven aan `_FindingPreview`, zodat de
  // inhoud-bewuste header-fit te overschrijven is (o.a. voor de kostentoets).
  'lib/widgets/slides/slide_preview.dart': 1027,
  // +57 (#1240): LibrePlan-connector — setLibreplanPassword/deleteLibreplanPassword/
  // readLibreplanPassword methodes op SettingsNotifier (keychain-toegang).
  'lib/state/settings_provider.dart': 1073,
  // +31 (#1240): LibrePlan-connector — form-velden, init, dispose, save, import-
  // dialoog-import in de settings_dialog library-head.
  // +2 (#1500): twee part-declaraties erbij (tabelstijl-controls) plus de
  // import van de paginamaat-lokalisatie.
  'lib/widgets/dialogs/settings_dialog.dart': 1034,
};

/// Een klasse mag niet groter worden dan dit, opgeteld over álle
/// `part`-bestanden van haar library — de klasse zelf plus elke `extension … on`
/// die eraan hangt.
///
/// Waarom naast [maxFileLines], die immers al op 1000 staat: die telt
/// *bestanden*, en een `part`-splitsing haalt die teller onderuit zonder dat er
/// iets kleiner wordt. `TabsNotifier` staat op ~2.400 regels over zeven
/// `part`-bestanden, `_SettingsDialogState` op ~7.300 over tweeëntwintig — elk
/// bestand netjes onder de duizend, de klasse allang niet meer. De poort lag dus
/// stil op precies de plek waar hij bedoeld was: het ding dat één geheel vormt
/// en dat je in je hoofd moet houden om het te wijzigen.
///
/// Hetzelfde getal als [maxFileLines], met opzet: de belofte was "geen eenheid
/// boven de duizend regels", en dit herstelt die belofte voor de eenheid die
/// werkelijk telt. Dat er vandaag vijftien klassen boven zitten is de meting,
/// niet het doel — zie [classSizeBaseline].
const int maxClassLines = 1000;

/// Klassen die bij invoering van [maxClassLines] al te groot waren. De waarde is
/// het plafond van die klasse: het mag KRIMPEN (haal er iets uit, verlaag dan
/// dit getal — de run drukt een tip af) maar nooit groeien.
///
/// De sleutel is `<library>#<Naam>`, niet `<bestand>#<Naam>`: een `extension
/// TabsNotifierGit on TabsNotifier` in een `part` telt mee bij `TabsNotifier`,
/// want dat is waar de code terechtkomt. De library maakt de sleutel ook
/// eenduidig — twee private `_FooState`-klassen in verschillende schermen zijn
/// niet dezelfde klasse en mogen niet bij elkaar opgeteld worden.
///
/// Een nieuwe regel hier is een bewuste beslissing en hoort een reden te hebben;
/// het doel is minder en kleinere regels, niet meer.
const Map<String, int> classSizeBaseline = {
  // +1 (#1098): de uitbreidingskaart voor afbeeldingsrechten in de bestaande
  // modulelijst; de kaart zelf is een losse widget.
  'lib/widgets/dialogs/settings_dialog.dart#_SettingsDialogState':
      // +78 (#1500): de tabelstijl-controls (randstijl, zebra, celopvulling,
      // accentlijn) en de paginamaat-/margecontrols. Ze staan in eigen parts
      // (settings_dialog_table_style.dart, settings_dialog_general.dart), maar
      // blijven extensies op deze klasse — een part-splitsing verkleint het
      // bestand, niet de klasse. De laatste +10 komt van het opsplitsen van
      // `_checklistTableColorSettings`: met de zes stijlvelden erbij liep dat
      // ene blok over de methodelengte-grens, dus staan de tabelkleuren nu in
      // een eigen `_tableColorSettings` — twee onderwerpen, twee methodes.
      6201,
  // Verlaagd van het tijdelijke plafond 3465 (in aa25ce2e opgerekt om main te
  // deblokkeren nadat #865 en #872 deze klasse over 3412 duwden) naar 3310: het
  // trekken van een vraagronde — welke antwoorden meedoen en in welke volgorde —
  // is uit deze klasse gehaald naar `QuestionRoundBuilder`
  // (lib/services/question_round_builder.dart). Dat is pure rekenkunde over het
  // model (geen widget, geen setState, geen vensterkanaal) en dus nu op zichzelf
  // te toetsen; de presenter houdt alleen nog de timer, het oefenlogboek en de
  // vensters bij. De extractie brengt de klasse écht onder het plafond in plaats
  // van het plafond op te rekken.
  // +1: Y-01-doorvoer naar SlidePreview in views/overlays (resolve-at-draw).
  // +6 (#1164): splitRunPosition-doorvoer naar SlidePreview in views/overlays,
  // zodat de (2/3)-titelteller ook in de presentatie- en publieksweergave staat.
  // Pure plumbing van een nieuw veld; er valt geen gedrag uit te tillen.
  // +24 (#1162): de sprong-uit + navigatiestack in de presentator — `_advanceTo`,
  // de sprong-tak in `_next`, de retrace in `_prev` en het wissen van de stack bij
  // een teleport. De anker-resolutie zelf is al top-level (`_indexOfAnchor`) en
  // telt niet mee; wat rest gebruikt `_index`/`_rebuild` en hoort in de state.
  // +8 (#1162): `_jumpToAnchor` (klik op een menublok) + de onMenuBlockTap-wiring;
  // gebruikt `_advanceTo` en hoort dus in de state.
  // +49: grafiek-hover spiegelen naar het publieksvenster — het `_chartHover`-
  // veld, `_broadcastChartHover`/`_applyBeamerChartHover` (in het part-bestand
  // presenter_beamer_payload.dart, maar leden van deze State) en het wissen van
  // de hover bij diawissel in `_syncAudience`. Het pure zendhulpje
  // `_sendChartHover` is top-level en telt niet mee.
  'lib/widgets/presentation/fullscreen_presenter.dart#_FullscreenPresenterState':
      3398,
  // +34 (#1350, #1351, #1355): truncatie-check in openDeckFromContent,
  // versleutelde-zip-streaming via writeContent(capped), en automatische
  // zegelverificatie bij openen. Security-fixes die in het open-pad landen
  // — onherleidbaar aan dit chokepoint-bestand.
  'lib/services/file_service.dart#FileService': 2742,
  // Procesverbetering Phase 2/8/9: statistical chart painters (control,
  // histogram, Pareto, run, box, probability, DOE) live as an extension on
  // this State via chart_preview_improvement.dart. Raising rather than a
  // half-extract: the painters share grow/font/profile from the State and a
  // separate helper would re-plumb the same surface without shrinking the
  // mental model. Follow-up: lift painters to a ChartImprovementSurface.
  // +1: normalityLabel (l10n 'AD p=') on the probability-plot painter call.
  // +7: Y-01-resolutie in de preview-aanroep (deck-limieten via yRef).
  // +134 (#1281): hover-tooltips voor scatter/gestapelde/horizontale staaf/
  // combo/waterval/bullet. De herbruikbare stukken (tooltiptekst-bouwers, de
  // overlay-widget, de combo-overlay) staan al top-level in
  // chart_preview_touch.dart; wat resteert is de touch-configuratie die per
  // definitie ín de builder-methoden van deze State leeft (fl_chart
  // *TouchData, MouseRegion-omhulsels, het `_cellTooltip`-veld + setter).
  // +160: grafiek-hover spiegelen presentator↔beamer. Net als hierboven leeft de
  // capture per definitie ín de builders: de `touchCallback`s op bar/gestapelde/
  // lijn/scatter en de pie-`onHovered` melden welke reeks/punt/taartpunt onder de
  // aanwijzer zit. Daarnaast de hover-spiegel-leden (legenda-setters,
  // effectieve-hover-getters, `_withMirroredTooltip`, de controller-listener). De
  // herbruikbare kern staat al buiten de State: het `ChartHover`-model +
  // controller + scope in chart_hover.dart, `composedChartHoverText` en het
  // verhuisde `_HoverPieChart` in chart_preview_touch.dart.
  'lib/widgets/slides/slide_preview.dart#_ChartPreviewState': 3160,
  // Procesverbetering: improvement-slide discovery + save paths.
  // +4: Y-01/framework-args op newDeck + improvement-module-prompt.
  'lib/state/tabs_provider.dart#TabsNotifier': 2235,
  // Procesverbetering: matrix/canvas/tree/flow/phaseGate serialize/parse.
  // +33: Y-01 front-matter keys (name/unit/usl/lsl/target/baseline/goal).
  // +16 (#1162): het lezen van de twee navigatie-comments (`ocideck_slide_anchor`
  // + `ocideck_next`) in `_parseBlockDirectives` — typedef-veld, init en twee
  // parse-takken per veld. Onherleidbare parse-plumbing; de serialisatie zelf zit
  // al in de top-level `_writeSlideDirectives` en telt niet mee.
  // +15: `_decodeTableWithAlignment` (finding.dart) + `tableDecoded`/
  // `tableAlignments` (parse.dart) + `_writeTable` alignments-parameter
  // (markdown_service.dart). Onherleidbare codec-plumbing voor de nieuwe
  // `tableColumnAlignments`-veld; de logica zelf staat in
  // `markdown_table_codec.dart` en telt niet mee.
  // +14: ocideck_table_num_cols directive schrijven + _parseNumCols-lezen.
  // +4 (#1407): image-title-above class-token in de classes-lijst.
  // +12: ocideck_image_zoom directive schrijven + lezen.
  'lib/services/markdown_service.dart#MarkdownService': 2409,
  'lib/widgets/dialogs/image_carousel_picker.dart#_ImageCarouselPickerState':
      2437, // +228 (#1404): hernoem-actie + dialoog; testbare logica zit in
  // ImageRenameService, hier blijft alleen UI-orchestratie
  'lib/services/privacy/privacy_scanner.dart#PrivacyScanner': 1604,
  // +7 (#1098): menu- en dialoogaanroepen voor het rechtenoverzicht; de scan en
  // beoordeling leven buiten de State in providers en services.
  'lib/widgets/app_shell.dart#_MainLayoutState':
      1449, // +1 (video-calls F1): callRail spread
  // Bewust verhoogd van 1331 naar 1344: het app-globale Matrix-account
  // (setMatrixAccount + de keychain-getters voor het access-token) spiegelt
  // bewust de bestaande AI- en git-account-setters. Het gedrag staat in de
  // part `settings_provider_matrix.dart`, maar telt mee voor de klasse; het
  // laadwerk (aiSettings + matrixAccount) ging in dezelfde wijziging naar
  // top-level helpers, wat de netto groei drukte.
  'lib/state/settings_provider.dart#SettingsNotifier':
      // +13 (#1500): setDocumentEditorMaxWidth, setDocumentPageSize en
      // setDocumentPageMargins — drie zetters voor de documentmodus-instellingen.
      1398,
  // Nieuw plafond (#1500): de schermklasse van de documenteditor stond nog niet
  // in deze lijst en kwam er met de paginamaat-indicator en _insertToc overheen.
  'lib/widgets/document_editor_screen.dart#_DocumentEditorScreenState': 998,
  // Bewust verhoogd van 1256 naar 1261 (#651): `setDismissals` is een nieuwe
  // openbare mogelijkheid, geen drift. In dezelfde wijziging ging er 24 regels
  // uit — de vier identieke regels die annotaties, notities en terzijdeleggingen
  // deelden staan nu één keer in `_updateSidecarLayer`, en het opschonen en
  // zetten van een notitie is top-level geworden. Wat overblijft raakt allemaal
  // `state` en is dus niet uit de klasse te tillen zonder een eigen laag te
  // bouwen die groter is dan de functie die hem vraagt.
  'lib/state/deck_provider.dart#DeckNotifier':
      1374, // +14 (#978 Blok C): applyProvenance; +15 (#1162): de dunne
  // setSlideJump-delegator (de berekening zelf zit in slidesWithJump,
  // slide_anchors.dart) — muteert via `currentState`/`_mutate` en hoort in de
  // klasse. +16 (#1162): de even dunne setMenuBlockTarget-delegator (berekening
  // in slidesWithMenuTarget, menu_blocks.dart). +22 (#1235): revertSlidesById —
  // zet meerdere dia's in één _mutate terug (één undo-stap voor session-data-
  // edits na een presentatie). Onherleidbaar: de coalescing/undo-logica zit in
  // _mutate, dus de batch-revert hoort bij de notifier. +14: splitTableSlide —
  // dezelfde dunne delegator als splitSlide, maar dan voor tabellen. +17
  // (#1473): saveAs/_saveToPath vergelijken naast `identical` ook de
  // undo-stapel-lengte, zodat een state-vervanging die geen inhoudswijziging
  // is (bv. copyWith voor themeProfile) het deck niet onterecht vuil laat.
  // +8: idempotente dispose() (hardening #1478) — vangt een dubbele dispose
  // bij een teardown-race fail-safe af; een dispose-override kan niet uit de
  // klasse getild worden (roept super.dispose()).
  'lib/widgets/slides/slide_preview.dart#_QuestionPreview': 1213,
  // +10 (#1162): de `menu`-tak in de drie kwaliteitsswitches (contrast, alt-tekst,
  // ontbrekend bestand) + de dichtheidsswitch — menublokken zijn een raster, geen
  // doorlopende tekst; de blokafbeeldingen zitten in de bullet-tekst, niet in
  // [Slide.imagePath], dus de generieke controles slaan er (vooralsnog) niet op.
  'lib/services/slide_quality_analyzer.dart#SlideQualityAnalyzer': 1130,
  // Procesverbetering: Y-01-UI, type-toolbar, plaklogica en DOE-dialoog zijn
  // naar losse widgets/helpers getild (chart_histogram_limits,
  // chart_type_toolbar, table_clipboard, DoeDesignDialog). Plafond verlaagd
  // van 1198 naar 1081.
  'lib/widgets/editors/chart_editor.dart#_ChartEditorState': 1081,
  // +10 (#977): each thumbnail reads collab presence and wraps in the presence
  // overlay. The overlay's real work (filter + Stack + dots) lives in the
  // top-level `slideWithPresence` in slide_presence_dots.dart; only the per-item
  // read and the wrap call remain in the state class.
  // +1 (#1164): splitRunPosition-doorvoer naar de thumbnail voor de (2/3)-teller.
  'lib/widgets/panels/slide_list_panel.dart#_SlideListPanelState': 1025,
};

final _print = RegExp(r'(?<![\w.])print\(');
final _debugPrint = RegExp(r'(?<![\w.])debugPrint\(');
final _catchUnderscore = RegExp(r'catch\s*\(\s*_\s*\)');
final _plainWrite = RegExp(r'\.writeAs(String|Bytes)(Sync)?\(');
final _rawColor = RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)');

/// An import that drags the UI layer in: Flutter's widget/painting libraries,
/// or anything under `lib/widgets/`. `foundation.dart` and `services.dart` are
/// deliberately NOT here — they carry no widget tree (kIsWeb, rootBundle,
/// compute), so a headless service may use them.
final _uiImport = RegExp(
  r"^import 'package:flutter/(material|widgets|cupertino|rendering)\.dart'"
  r"|^import '[^']*widgets/",
);

/// De toegestane richting van het verkeer tussen de lagen.
///
/// Sleutel = de map, waarde = de mappen die daaruit niet geïmporteerd mogen
/// worden. Dit is een HARDE nul, geen ratchet: elke overtreding is er één te
/// veel, en er zijn er vandaag geen.
///
/// De richting is nu schoon — niets in `lib/models/` kent `state/` of
/// `widgets/`, niets in `lib/services/` kent `state/`, en niets in `lib/state/`
/// kent `widgets/`. Dat bleef zo op discipline en op reviewers die het zagen.
/// Eén import op een ongelukkige dag draait dat om, en dan is de kern niet meer
/// headless te draaien of te testen zonder een widgetboom eromheen — met een
/// cyclus tussen de lagen als volgende stap. Een reviewer die het mist is geen
/// verwijt; een check die het nooit mist is goedkoper.
///
/// De UI-imports (`package:flutter/material` en `lib/widgets/`) worden apart
/// geteld door [_uiImport] — dáár zit een ratchet omdat `slide_rasterizer`
/// terecht widgets schildert. Deze lijst gaat over de rest van de richting.
const Map<String, List<String>> layerRules = {
  'lib/models/': ['state/', 'widgets/'],
  'lib/services/': ['state/'],
  'lib/state/': ['widgets/'],
};

/// Een import uit een van de verboden mappen, relatief of via `package:ocideck`.
RegExp _forbiddenImport(String dir) =>
    RegExp("^import '(?:package:ocideck/|[./]+)[^']*$dir");

/// The token/palette homes, exempt from the raw-colour ratchet: the app theme
/// and the deliberately-dark image-picker palette (its own dark chrome, not
/// part of the light theme).
bool _isPaletteHome(String path) {
  final p = path.replaceAll(r'\', '/');
  return p == 'lib/theme/app_theme.dart' ||
      p == 'lib/theme/image_picker_palette.dart' ||
      p == 'lib/theme/presenter_palette.dart';
}

/// The atomic-write helpers themselves are the only place a plain write may
/// live: everything else goes through them.
/// De privacy-projectiegrens is verhuisd naar
/// tool/check_audience_boundary.dart: die vindt de uitvoeroppervlakken zelf
/// in plaats van vier namen te vertrouwen, en dwingt per oppervlak een
/// geclassificeerde keuze af.

// ── FilePicker: een pad uit de kiezer, zonder platformpoort ─────────────────
//
// Issue #150: knoppen in de web-demo deden niets. De oorzaak was
// `FilePicker.getDirectoryPath()`, dat in de browser geen implementatie heeft
// en stil null teruggeeft. Gerepareerd door de knoppen te verbergen — maar niets
// bewaakte die reparatie, en een dag later stond dezelfde fout er alweer bij
// (#506, de logokiezer).
//
// Een test kan dit niet vangen: onder `flutter test` is `kIsWeb` altijd false,
// de vlag komt via een conditionele import zonder injectiepunt, en er is geen
// `--platform chrome`-doel. Vandaar een statische regel.
//
// Twee gedaanten, allebei "ik krijg een pad in het bestandssysteem":
//   * `getDirectoryPath(` — bestaat niet op web, geeft stil null.
//   * `pickFiles(` waarvan `.path` gelezen wordt zonder `withData: true` —
//     `PlatformFile.path` GOOIT op web een kale String (file_picker 5.5.0,
//     platform_file.dart). Hier stond dat het een `blob:`-URL oplevert; dat is
//     onjuist, en het maakt uit: een blob-URL faalt stil en verkeerd, een worp
//     vliegt ongevangen omhoog. Nagekeken in de pakketbron op 2026-07-22.
// `saveFile(bytes:)` staat er bewust NIET bij: dat is op web een download en
// doet precies wat het belooft.
final _getDirectoryPath = RegExp(r'FilePicker\.getDirectoryPath\s*\(');
final _pickFiles = RegExp(r'FilePicker\.pickFiles\s*\(');

/// De vormen waarin de poort geschreven wordt. `kIsWeb` hoort er nadrukkelijk
/// bij: dat is de meest directe vorm, en `image_service.dart` gebruikt hem al
/// zo. De eerste versie van deze regel kende hem niet en zette twee correct
/// gepoorte bestanden daardoor ten onrechte in de basislijn.
final _platformFlag = RegExp(
  r'\b(supportsLocalProjectFolders|isWebPlatform|kIsWeb)\b',
);

/// Bestanden die vandaag een pad uit de kiezer halen zonder de vlag zelf te
/// noemen. **Deze lijst mag alleen krimpen.** Elk geval vraagt een eigen
/// afweging — verbergen op web, of de bytes-route nemen — en die staat per
/// regel genoteerd. Zolang een bestand hier staat, is het níet goedgekeurd: het
/// is opgeschreven.
const Map<String, String> filePickerPathBaseline = {
  // Leeg, en dat is de bedoeling (#528). Elke kiezer die een PAD uit
  // `FilePicker` haalt noemt nu zelf `supportsLocalProjectFolders`, in plaats
  // van te leunen op een poort bij zijn aanroeper. Een nieuwe regel hier is
  // geen boekhouding maar een besluit: schrijf erbij waarom dit bestand het
  // niet zelf kan.
};

/// Leest een `pickFiles(`-aanroep uit en zegt of hij een pad oplevert dat op
/// web onbruikbaar is. Kijkt naar het venster ná de aanroep in plaats van naar
/// de aanroep alleen, omdat `withData:` in de argumenten staat en `.path` een
/// paar regels verderop wordt gelezen.
bool _pickFilesYieldsPath(String source, int from) {
  // Twintig regels vangt de ruimste schrijfwijze die hier voorkomt (zes regels
  // tussen `pickFiles(` en het lezen van `.path`).
  const window = 20;
  var scope = source.substring(from).split('\n').take(window).join('\n');

  // ...maar knip bij de volgende methodekop. Zonder die knip pleitte een
  // `withData: true` uit de *volgende* methode de huidige vrij:
  // `file_service.pickMarkdownFile` leest `.path` en de bytes-variant staat er
  // elf regels onder, waardoor de aanroep ten onrechte schoon leek.
  final next = _methodStart.firstMatch(scope);
  if (next != null) scope = scope.substring(0, next.start);

  if (scope.contains('withData: true')) return false;
  return scope.contains('.path');
}

/// Een methodekop op klasseniveau, zoals deze codebase ze schrijft.
final _methodStart = RegExp(
  r'\n  (Future|void|String|bool|int|List|Set|Map)\b',
);

/// Of er vóór positie [at] een platformpoort staat die deze aanroep dekt.
///
/// Zonder parser is de omsluitende methode niet exact af te bakenen. Het venster
/// loopt daarom terug tot de vorige methodekop op hetzelfde inspringniveau — in
/// deze codebase `  Future<`, `  void ` of `  String ` op twee spaties — of
/// anders 1200 tekens. Dat is ruim genoeg voor een poort bovenin een methode en
/// te krap om er één uit de vorige methode voor aan te zien.
bool _gatedBefore(String source, int at) {
  var from = at - 1200;
  if (from < 0) from = 0;
  final window = source.substring(from, at);
  final lastMethod = _methodStart.allMatches(window).lastOrNull;
  final scope = lastMethod == null
      ? window
      : window.substring(lastMethod.start);
  return _platformFlag.hasMatch(scope);
}

/// Aanroepen in `lib/` die een pad uit FilePicker halen zonder dat er in
/// dezelfde methode een platformpoort staat.
List<String> _filePickerPathViolations() {
  final hits = <String>[];
  final seen = <String>{};

  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final source = file.readAsStringSync();
    if (!source.contains('FilePicker.')) continue;

    // Per AANROEP kijken, niet per bestand. Een poort in de ene methode zegt
    // niets over de volgende: `image_service.dart` poort `pickImageDetailed`
    // keurig met `kIsWeb` en laat `pickVideo`/`pickAudio` er pal naast
    // ongepoort staan. De eerste versie van deze regel keek naar het hele
    // bestand en zag dat verschil niet.
    final ongepoort = <String>[];
    void beoordeel(int at, String vorm) {
      if (_gatedBefore(source, at)) return;
      final line = '\n'.allMatches(source.substring(0, at)).length + 1;
      ongepoort.add('regel $line ($vorm)');
    }

    for (final match in _getDirectoryPath.allMatches(source)) {
      beoordeel(match.start, 'getDirectoryPath');
    }
    for (final match in _pickFiles.allMatches(source)) {
      if (_pickFilesYieldsPath(source, match.end)) {
        beoordeel(match.start, 'pickFiles → .path');
      }
    }
    if (ongepoort.isEmpty) continue;

    final path = file.path;
    seen.add(path);
    if (filePickerPathBaseline.containsKey(path)) continue;

    hits.add('$path: ${ongepoort.join('; ')} — zonder platformpoort');
  }

  // Een basislijn die niet meer klopt is erger dan geen basislijn: hij leest als
  // "hier is over nagedacht" terwijl het bestand allang weg is of gerepareerd.
  for (final path in filePickerPathBaseline.keys) {
    if (!seen.contains(path)) {
      hits.add(
        '$path: staat in filePickerPathBaseline maar haalt geen pad meer uit '
        'FilePicker — haal de regel weg, de lijst mag alleen krimpen',
      );
    }
  }
  return hits;
}

// ── Vaste vertragingen in tests ─────────────────────────────────────────────
//
// `runAsync(() => Future.delayed(const Duration(milliseconds: 80)))` wacht niet
// op een resultaat maar gokt hoe lang echt werk duurt op deze machine. Onder een
// volle `make check` — meerdere sessies op één machine — is die gok soms te krap,
// en dan faalt een test op iets wat een paar milliseconden later wél klaar was.
// Het getal verhogen verplaatst de gok alleen.
//
// Dat is geen theorie: vier tests werden op één dag om deze reden gerepareerd
// (shell_export_actions ×2, signature_draw, duplicate_cleanup_dialog). Ze slagen
// los en falen onder belasting — de duurste faalvorm die er is, want de test
// wordt opnieuw gedraaid, slaagt, en iedereen concludeert dat het toeval was.
//
// Het alternatief staat in `test/support/pump_until.dart`: wissel korte stapjes
// echte tijd af met een `pump` en kijk na elke stap of het resultaat er ís, met
// een bovengrens zodat een vastloper alsnog faalt.
final _runAsync = RegExp(r'runAsync\s*\(');
final _futureDelayed = RegExp(r'Future\.delayed\s*\(');

/// Haalt regelcommentaar weg vóór het zoeken.
///
/// Zonder dit valt de poort over zijn eigen tegenvoorbeeld: het doc-commentaar
/// van `pump_until.dart` schrijft het antipatroon voluit op om uit te leggen
/// waaróm het fout is. Een poort die zijn eigen uitleg verbiedt, wordt weggezet
/// — en terecht.
String _withoutLineComments(String source) => source
    .split('\n')
    .map((line) {
      final at = line.indexOf('//');
      if (at < 0) return line;
      // Een `//` binnen een string laten we staan; het gaat hier om
      // commentaarregels, niet om URL's in testdata.
      final before = line.substring(0, at);
      final quotes =
          "'".allMatches(before).length + '"'.allMatches(before).length;
      if (quotes.isOdd) return line;
      return before;
    })
    .join('\n');

/// Tests die binnen een `runAsync` op een vaste klok wachten.
List<String> _fixedDelayInRunAsync() {
  final hits = <String>[];
  for (final file in Directory('test').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final source = _withoutLineComments(file.readAsStringSync());
    if (!source.contains('runAsync')) continue;

    for (final start in _runAsync.allMatches(source)) {
      // Het venster loopt tot het einde van de aanroep; bij gebrek aan een
      // parser is 400 tekens ruim genoeg voor de vormen die hier voorkomen en
      // te krap om de volgende test binnen te trekken.
      final end = (start.end + 400).clamp(0, source.length);
      final scope = source.substring(start.end, end);
      final delay = _futureDelayed.firstMatch(scope);
      if (delay == null) continue;
      final line = '\n'.allMatches(source.substring(0, start.start)).length + 1;
      hits.add(
        '${file.path}:$line: Future.delayed binnen runAsync — wacht op het '
        'resultaat, niet op de klok (zie test/support/pump_until.dart)',
      );
    }
  }
  return hits;
}

/// Onderdrukte SAST-bevindingen in `lib/`. RATCHET: mag krimpen, niet groeien.
///
/// Eén `// nosemgrep:` is een afweging; tien is een gewoonte, en dan zegt een
/// groene `make sast` niets meer. De enige vandaag staat op de `chmod` in
/// `disk_traces.dart` (zie #521): de regel bewaakt netwerkverkeer buiten
/// NetGuard om, en `chmod` is niet netwerkvaardig.
///
/// Dit telt bewust in `check_conventions` en niet in semgrep zelf. De reden
/// dáárvoor is sinds #778 een andere dan er stond. Het argument was dat `make
/// sast` nergens automatisch draaide, dus dat een onderdrukking alleen
/// zichtbaar zou zijn voor wie semgrep toevallig geïnstalleerd had; dat is niet
/// meer zo, want `scans.yml` draait semgrep bij elke PR.
///
/// Wat overblijft is het echte argument, en dat is sterker: semgrep telt zijn
/// eigen onderdrukkingen niet. Een `// nosemgrep` maakt de bevinding weg én
/// haalt hem uit het beeld — een repo die er twintig verzamelt heeft een
/// groene `make sast` en geen enkel signaal daarover. Deze ratchet is het
/// signaal, en hij hoort daarom in de poort die bij élke `make check` draait,
/// niet in de scanner die hij bewaakt.
const int nosemgrepBaseline = 1;

final _nosemgrep = RegExp(r'//\s*nosemgrep\b');

/// De kop van een top-level type: `class`, `mixin`, `enum` of `extension`.
///
/// Bij een `extension … on Foo` telt `Foo` — dat is de klasse die groeit; de
/// naam van de extensie zelf zegt alleen wáár het stuk staat. Een naamloze
/// extensie valt terug op haar `on`-type.
final _typeDecl = RegExp(
  r'^(?:abstract\s+|sealed\s+|final\s+|base\s+|interface\s+|mixin\s+)*'
  r'(class|mixin|enum|extension)\s+([A-Za-z_$][\w$]*)?'
  r'(?:<[^>]*>)?\s*(?:on\s+([A-Za-z_$][\w$]*))?',
);

final _partOfDirective = RegExp("^part of '([^']+)';");

/// Het pad van [target], relatief aan de map van [from], genormaliseerd.
String _resolveRelative(String from, String target) {
  final base = from.substring(0, from.lastIndexOf('/'));
  final segments = <String>[];
  for (final s in '$base/$target'.split('/')) {
    if (s == '.' || s.isEmpty) continue;
    if (s == '..') {
      if (segments.isNotEmpty) segments.removeLast();
      continue;
    }
    segments.add(s);
  }
  return segments.join('/');
}

/// De library waar [path] toe behoort: zichzelf, of — bij een `part of` — het
/// bestand dat de library opent. Een `part` van een `part` bestaat niet in Dart,
/// maar de lus is er voor de zekerheid begrensd.
String _libraryOf(String path, Map<String, List<String>> linesByPath) {
  var current = path;
  for (var hop = 0; hop < 4; hop++) {
    String? target;
    for (final line in linesByPath[current] ?? const <String>[]) {
      final m = _partOfDirective.firstMatch(line);
      if (m != null) {
        target = m.group(1);
        break;
      }
    }
    if (target == null) return current;
    final next = _resolveRelative(current, target);
    if (!linesByPath.containsKey(next)) return current;
    current = next;
  }
  return current;
}

/// Telt per type hoeveel regels het beslaat, opgeteld over de hele library.
///
/// Een regelteller in plaats van een echte parse, en dat kan hier omdat
/// `make format-check` de opmaak vastlegt: een top-level declaratie begint op
/// kolom 0 en sluit met een `}` op kolom 0. Alleen een `'''`-string kan daar een
/// valse sluitregel in leggen, dus die worden overgeslagen.
///
/// Geeft de totalen terug plus, per type, waar de stukken staan — zodat een
/// overschrijding niet alleen zegt *dat* een klasse te groot is maar ook waar de
/// zeven brokken liggen.
///
/// [linesByPath] is pad → regels; publiek en zonder schijftoegang, zodat
/// `test/class_size_ratchet_test.dart` de teller met verzonnen bestanden kan
/// voeden in plaats van met de echte boom.
({Map<String, int> lines, Map<String, List<String>> sites}) classSizesIn(
  Map<String, List<String>> linesByPath,
) {
  final totals = <String, int>{};
  final sites = <String, List<String>>{};
  final tripleQuote = RegExp("r?('''|\"\"\")");

  linesByPath.forEach((path, lines) {
    final library = _libraryOf(path, linesByPath);
    String? open;
    var start = 0;
    String? inTriple;

    void close(int endIndex) {
      totals[open!] = (totals[open!] ?? 0) + (endIndex - start + 1);
      (sites[open!] ??= []).add('$path:${start + 1}');
      open = null;
    }

    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      final triple = inTriple;
      if (triple != null) {
        if (line.contains(triple)) inTriple = null;
        continue;
      }
      final quote = tripleQuote.firstMatch(line);
      if (quote != null &&
          !line.substring(quote.end).contains(quote.group(1)!)) {
        inTriple = quote.group(1);
        continue;
      }
      if (open != null) {
        if (line == '}') close(i);
        continue;
      }
      if (line.isEmpty || line.startsWith(' ') || line.startsWith('}')) {
        continue;
      }
      final m = _typeDecl.firstMatch(line);
      if (m == null) continue;
      final kind = m.group(1)!;
      final name = kind == 'extension'
          ? (m.group(3) ?? m.group(2))
          : m.group(2);
      if (name == null) continue;
      // `class Foo = Bar with Baz;` — een mixin-toepassing, geen body.
      if (line.trimRight().endsWith(';')) continue;
      // De kop mag over meer regels lopen (`class X extends Y\n    with Z {`).
      // De vervolgregels zijn ingesprongen, dus zodra er weer iets op kolom 0
      // begint is dit geen declaratie met een body.
      var head = i;
      while (head < lines.length && !lines[head].contains('{')) {
        head++;
        if (head < lines.length && !lines[head].startsWith(' ')) head = -1;
        if (head < 0) break;
      }
      if (head < 0 || head >= lines.length) continue;
      open = '$library#$name';
      start = i;
      // `enum NotesEditorMode { visual, markdown }` opent en sluit op één regel.
      if (lines[head].trimRight().endsWith('}')) {
        close(head);
      }
      i = head;
    }
  });

  return (lines: totals, sites: sites);
}

/// [classSizesIn] over de echte boom.
({Map<String, int> lines, Map<String, List<String>> sites}) _classSizes() {
  final linesByPath = <String, List<String>>{};
  for (final file in _dartFiles(Directory('lib'))) {
    linesByPath[file.path.replaceAll(r'\', '/')] = file.readAsLinesSync();
  }
  return classSizesIn(linesByPath);
}

bool _isAtomicFileLib(String path) =>
    path.replaceAll(r'\', '/') == 'lib/utils/atomic_file.dart';

bool _isTranslationData(String path) =>
    path.replaceAll(r'\', '/').contains('lib/l10n/translations/');

/// Tab, LF and CR are the only control bytes a source file may contain raw.
bool _isAllowedControlByte(int b) => b == 0x09 || b == 0x0a || b == 0x0d;

/// Every raw control byte in [file], as `path:line (0xNN)`. Scans BYTES, not
/// decoded lines: the point is exactly what the byte-oriented tools choke on.
Iterable<String> _controlBytesIn(File file) sync* {
  final bytes = file.readAsBytesSync();
  var line = 1;
  for (final b in bytes) {
    if (b == 0x0a) {
      line++;
      continue;
    }
    if ((b < 0x20 && !_isAllowedControlByte(b)) || b == 0x7f) {
      final hex = b.toRadixString(16).padLeft(2, '0');
      yield '${file.path}:$line (0x$hex)';
    }
  }
}

/// Achtergebleven conflictmarkeringen in [file].
///
/// Alleen `<<<<<<< ` en `>>>>>>> ` tellen, niet `=======`: dat laatste is in
/// Markdown een geldige onderstreping van een kop (setext-H1), en een poort die
/// daarop afgaat, roept wolf over gewone tekst.
///
/// Waarom dit een poort is en geen afspraak: het is precies één keer misgegaan,
/// en meteen twee bestanden tegelijk. Bij het oplossen van een rebase werden de
/// markeringen uit één bestand gehaald, waarna `git add -A` de twee andere
/// mét markeringen instageerde. Dat viel niemand op, want `docs/` compileert
/// niet — het reist alleen mee als asset en verschijnt in de ingebouwde lezer.
Iterable<String> _conflictMarkersIn(File file) sync* {
  final lines = file.readAsLinesSync();
  for (var i = 0; i < lines.length; i++) {
    final l = lines[i];
    if (l.startsWith('<<<<<<< ') || l.startsWith('>>>>>>> ')) {
      yield '${file.path}:${i + 1}: ${l.length > 60 ? '${l.substring(0, 60)}…' : l}';
    }
  }
}

/// De tekstbestanden waarin een achtergebleven markering schade doet: alles wat
/// meereist met de app of wat een bijdrager leest.
Iterable<File> _textFilesToScan() sync* {
  for (final entity in Directory('docs').listSync(recursive: true)) {
    if (entity is File && entity.path.endsWith('.md')) yield entity;
  }
  for (final entity in Directory('.').listSync()) {
    if (entity is File && entity.path.endsWith('.md')) yield entity;
  }
  for (final dir in ['lib', 'test', 'tool']) {
    yield* _dartFiles(Directory(dir));
  }
}

void main() {
  final printHits = <String>[];
  final debugPrintHits = <String>[];
  final plainWriteHits = <String>[];
  var catchCount = 0;
  var rawColorCount = 0;
  final oversize = <String>[];
  final shrunk = <String>[];
  final controlByteHits = <String>[];
  final quoteScanners = <String>[];
  final serviceUiImports = <String>[];
  final layerViolations = <String>[];
  final modelUiImports = <String>[];

  for (final file in _dartFiles(Directory('lib'))) {
    controlByteHits.addAll(_controlBytesIn(file));
    final path = file.path.replaceAll(r'\', '/');
    if (!_quoteScannerHomes.contains(path) &&
        file.readAsStringSync().contains("== '\"'")) {
      quoteScanners.add(path);
    }
    final isService = path.startsWith('lib/services/');
    final isModel = path.startsWith('lib/models/');
    final lines = file.readAsLinesSync();
    final countColors =
        !_isPaletteHome(file.path) && !_isTranslationData(file.path);
    for (var i = 0; i < lines.length; i++) {
      final line = lines[i];
      // Skip full-line comments — the patterns are referenced in docs/comments
      // (e.g. the logger's own docstring) but never appear as real code there.
      if (line.trimLeft().startsWith('//')) continue;
      if (_print.hasMatch(line)) printHits.add('${file.path}:${i + 1}');
      if (_debugPrint.hasMatch(line)) {
        debugPrintHits.add('${file.path}:${i + 1}');
      }
      if (_catchUnderscore.hasMatch(line)) catchCount++;
      if (_plainWrite.hasMatch(line) && !_isAtomicFileLib(file.path)) {
        plainWriteHits.add('${file.path}:${i + 1}');
      }
      if (countColors) rawColorCount += _rawColor.allMatches(line).length;
      if ((isService || isModel) && _uiImport.hasMatch(line)) {
        (isModel ? modelUiImports : serviceUiImports).add('$path:${i + 1}');
      }
      layerRules.forEach((from, forbidden) {
        if (!path.startsWith(from)) return;
        for (final dir in forbidden) {
          if (_forbiddenImport(dir).hasMatch(line)) {
            layerViolations.add('$path:${i + 1} → $dir');
          }
        }
      });
    }

    if (!_isTranslationData(path)) {
      final count = lines.length;
      final ceiling = fileSizeBaseline[path];
      if (ceiling != null) {
        if (count > ceiling) {
          oversize.add('$path: $count lines (ceiling $ceiling)');
        } else if (count < ceiling) {
          shrunk.add('$path: $count (ceiling $ceiling)');
        }
      } else if (count > maxFileLines) {
        oversize.add('$path: $count lines (max $maxFileLines)');
      }
    }
  }

  // A control byte hides a file from grep wherever it lives, so this one rule
  // reaches beyond lib/ — the size and colour ratchets deliberately do not.
  for (final dir in ['test', 'tool']) {
    for (final file in _dartFiles(Directory(dir))) {
      controlByteHits.addAll(_controlBytesIn(file));
    }
  }

  final conflictHits = <String>[];
  for (final file in _textFilesToScan()) {
    conflictHits.addAll(_conflictMarkersIn(file));
  }

  final classSizes = _classSizes();
  final fatClasses = <String>[];
  final shrunkClasses = <String>[];
  classSizes.lines.forEach((key, count) {
    final ceiling = classSizeBaseline[key];
    final where = (classSizes.sites[key] ?? const <String>[]).join(', ');
    if (ceiling != null) {
      if (count > ceiling) {
        fatClasses.add('$key: $count lines (ceiling $ceiling) — $where');
      } else if (count < ceiling) {
        shrunkClasses.add('$key: $count (ceiling $ceiling)');
      }
    } else if (count > maxClassLines) {
      fatClasses.add('$key: $count lines (max $maxClassLines) — $where');
    }
  });
  final staleClassBaseline = [
    for (final key in classSizeBaseline.keys)
      if (!classSizes.lines.containsKey(key)) key,
  ];

  final failures = <String>[];

  if (conflictHits.isNotEmpty) {
    failures.add(
      'Found ${conflictHits.length} leftover merge-conflict marker(s). Een '
      'half opgeloste samenvoeging is ingecheckt: los het conflict alsnog op '
      'en haal de markeringen weg. Let op dat `git add -A` na het opschonen '
      'van één bestand de andere ongemoeid instageert:\n'
      '    ${conflictHits.join('\n    ')}',
    );
  }

  final nosemgrepHits = <String>[];
  for (final file in Directory('lib').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final lines = file.readAsLinesSync();
    for (var i = 0; i < lines.length; i++) {
      if (_nosemgrep.hasMatch(lines[i])) {
        nosemgrepHits.add('${file.path}:${i + 1}');
      }
    }
  }
  if (nosemgrepHits.length > nosemgrepBaseline) {
    failures.add(
      'Er staan nu ${nosemgrepHits.length} onderdrukte SAST-bevindingen in '
      'lib/ (basislijn $nosemgrepBaseline). Eén is een afweging, tien is een '
      'gewoonte — en dan zegt een groene `make sast` niets meer. Los de '
      'bevinding op, of verhoog deze basislijn bewust en zet de reden bij de '
      'regel:\n'
      '    ${nosemgrepHits.join('\n    ')}',
    );
  }

  final delayHits = _fixedDelayInRunAsync();
  if (delayHits.isNotEmpty) {
    failures.add(
      'Een test wacht binnen `runAsync` op een vaste klok in plaats van op het '
      'resultaat. Zo\'n test slaagt los en faalt onder een volle `make check` — '
      'de duurste faalvorm die er is, want hij wordt opnieuw gedraaid, slaagt, '
      'en dan heet het toeval. Gebruik `pumpUntil` uit '
      'test/support/pump_until.dart: die wacht tot het er ís, met een '
      'bovengrens zodat een vastloper alsnog faalt:\n'
      '    ${delayHits.join('\n    ')}',
    );
  }

  final pickerHits = _filePickerPathViolations();
  if (pickerHits.isNotEmpty) {
    failures.add(
      'Een pad uit FilePicker zonder platformpoort. In de browser bestaat '
      '`getDirectoryPath` niet (stil null) en GOOIT `PlatformFile.path` een '
      'kale String — de knop doet dan niets, of hij laat een ongevangen fout '
      'omhoog vliegen. Dat was #150 en daarna '
      '#506. Noem `supportsLocalProjectFolders` (of `isWebPlatform`) in dit '
      'bestand, of gebruik `withData: true` en werk met de bytes. Zie '
      'filePickerPathBaseline in tool/check_conventions.dart — die lijst mag '
      'alleen krimpen:\n'
      '    ${pickerHits.join('\n    ')}',
    );
  }

  if (layerViolations.isNotEmpty) {
    failures.add(
      'De laagrichting is doorbroken in ${layerViolations.length} '
      'import(s). Een model of service dat de laag boven zich binnenhaalt is '
      'niet meer los te draaien of te testen, en een cyclus tussen de lagen is '
      'dan nog maar één import verderop. Verplaats de code naar beneden of '
      'geef de bovenlaag een parameter mee (zie layerRules in '
      'tool/check_conventions.dart):\n'
      '    ${layerViolations.join('\n    ')}',
    );
  }

  if (printHits.isNotEmpty) {
    failures.add(
      'Found ${printHits.length} `print(` call(s) — use the logger '
      '(lib/utils/log.dart):\n    ${printHits.join('\n    ')}',
    );
  }

  if (debugPrintHits.length > debugPrintBaseline) {
    failures.add(
      'Found ${debugPrintHits.length} `debugPrint(` call(s) (baseline '
      '$debugPrintBaseline) — stripped in release, invisible to operators and '
      'to users. Route the failure through logError/logWarning '
      '(lib/utils/log.dart), and tell the user when it is their problem:\n'
      '    ${debugPrintHits.join('\n    ')}',
    );
  }

  if (plainWriteHits.isNotEmpty) {
    failures.add(
      'Found ${plainWriteHits.length} plain `.writeAsString`/`.writeAsBytes` '
      'call(s) — a crash midway leaves a truncated file. Use '
      'writeStringAtomic/writeBytesAtomic (lib/utils/atomic_file.dart):\n'
      '    ${plainWriteHits.join('\n    ')}',
    );
  }

  if (catchCount > catchUnderscoreBaseline) {
    failures.add(
      'Bare `catch (_)` count rose to $catchCount (baseline '
      '$catchUnderscoreBaseline). Catch a typed error and call logError, '
      'or lower the baseline if you removed one.',
    );
  }

  if (rawColorCount > rawColorBaseline) {
    failures.add(
      'Raw `Color(0x…)` literal count rose to $rawColorCount (baseline '
      '$rawColorBaseline). Use a semantic AppTheme token '
      '(lib/theme/app_theme.dart), or lower the baseline if you removed one.',
    );
  }

  if (oversize.isNotEmpty) {
    failures.add(
      '${oversize.length} file(s) over their size ceiling — split the file, or '
      '(deliberately) raise its entry in fileSizeBaseline '
      '(tool/check_conventions.dart):\n    ${oversize.join('\n    ')}',
    );
  }

  if (fatClasses.isNotEmpty) {
    failures.add(
      '${fatClasses.length} klasse(n) boven hun plafond, geteld over álle '
      '`part`-bestanden van hun library. Een `part`-splitsing maakt de '
      'bestanden kleiner maar de klasse niet: haal er werkelijk gedrag uit — '
      'naar een service, een losse klasse of een widget — of verhoog bewust de '
      'regel in classSizeBaseline (tool/check_conventions.dart):\n'
      '    ${fatClasses.join('\n    ')}',
    );
  }

  if (staleClassBaseline.isNotEmpty) {
    failures.add(
      '${staleClassBaseline.length} regel(s) in classSizeBaseline wijzen naar '
      'een klasse die niet meer bestaat (hernoemd, verplaatst of weg). Haal ze '
      'eruit — een plafond zonder klasse dekt de volgende klasse niet af:\n'
      '    ${staleClassBaseline.join('\n    ')}',
    );
  }

  if (modelUiImports.length > modelUiImportBaseline) {
    failures.add(
      'lib/models/ imports the UI layer in ${modelUiImports.length} place(s). A '
      'model must stay plain Dart — move the widget/painting code into '
      'lib/widgets/ and keep the model free of it:\n'
      '    ${modelUiImports.join('\n    ')}',
    );
  }

  if (serviceUiImports.length > serviceUiImportBaseline) {
    failures.add(
      'UI imports in lib/services/ rose to ${serviceUiImports.length} (baseline '
      '$serviceUiImportBaseline). A service should run headless — without a '
      'widget tree, and testable without pumping one. Keep the widget code in '
      'lib/widgets/, or lower the baseline if you removed one:\n'
      '    ${serviceUiImports.join('\n    ')}',
    );
  }

  if (quoteScanners.isNotEmpty) {
    failures.add(
      'Hand-rolled double-quote scanning outside ${_quoteScannerHomes.join(' / ')}. '
      'This project grew three separate CSV field splitters before anyone '
      'noticed, each with its own quoting bugs, because nothing made the '
      'duplicate visible. Use parseCsvRows/parseCsvLine from lib/utils/csv.dart, '
      'or add the file here with a reason if it is genuinely doing something '
      'else:\n'
      '    ${quoteScanners.join('\n    ')}',
    );
  }

  if (controlByteHits.length > controlByteBaseline) {
    failures.add(
      'Found ${controlByteHits.length} raw control byte(s) — the file now reads '
      'as BINARY to grep and git diff, so it is invisible to a grep audit and '
      'unreviewable in a PR. Write the escape instead (e.g. the six characters '
      r'\u0000'
      ') — the resulting string is byte-identical:\n'
      '    ${controlByteHits.join('\n    ')}',
    );
  }

  if (failures.isEmpty) {
    stdout.writeln(
      'Conventions OK: no print(); debugPrint() at ${debugPrintHits.length} '
      '(baseline $debugPrintBaseline); no plain writeAs*; no raw control bytes; '
      'bare catch (_) at $catchCount (baseline $catchUnderscoreBaseline); raw '
      'Color(0x…) at $rawColorCount (baseline $rawColorBaseline); UI imports in '
      'lib/services at ${serviceUiImports.length} (baseline '
      '$serviceUiImportBaseline) and in lib/models at '
      '${modelUiImports.length}; layer direction clean; file sizes within '
      'ceilings; class sizes within ceilings (max $maxClassLines, '
      '${classSizeBaseline.length} baselined); FilePicker paths gated '
      '(baseline ${filePickerPathBaseline.length}).',
    );
    if (serviceUiImports.length < serviceUiImportBaseline) {
      stdout.writeln(
        'Tip: UI imports in lib/services dropped to ${serviceUiImports.length} '
        '— lower serviceUiImportBaseline in tool/check_conventions.dart to lock '
        'in the win.',
      );
    }
    if (rawColorCount < rawColorBaseline) {
      stdout.writeln(
        'Tip: raw Color(0x…) dropped to $rawColorCount — lower rawColorBaseline '
        'in tool/check_conventions.dart to lock in the win.',
      );
    }
    if (catchCount < catchUnderscoreBaseline) {
      stdout.writeln(
        'Tip: bare catch (_) dropped to $catchCount — lower '
        'catchUnderscoreBaseline in tool/check_conventions.dart to lock it in.',
      );
    }
    if (shrunk.isNotEmpty) {
      stdout.writeln(
        'Tip: ${shrunk.length} baselined file(s) shrank — lower their '
        'fileSizeBaseline to lock in the win:\n    ${shrunk.join('\n    ')}',
      );
    }
    if (shrunkClasses.isNotEmpty) {
      stdout.writeln(
        'Tip: ${shrunkClasses.length} baselined class(es) shrank — lower their '
        'classSizeBaseline to lock in the win:\n'
        '    ${shrunkClasses.join('\n    ')}',
      );
    }
    exit(0);
  }

  stderr.writeln('Convention check FAILED:');
  for (final f in failures) {
    stderr.writeln('  - $f');
  }
  exit(1);
}

Iterable<File> _dartFiles(Directory dir) sync* {
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is File && e.path.endsWith('.dart')) yield e;
  }
}
