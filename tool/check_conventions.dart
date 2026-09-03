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

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';

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
/// Waarom een plafond niet exact op de huidige telling hoort te staan, in één
/// regel — de tips onderaan de run halen hem op.
const String _headroomWhy =
    'two PRs touching the same file are each green against the main they saw, '
    'and the merge lands over the ceiling';

/// De lucht die een plafond hoort te houden boven de werkelijke telling, en
/// tegelijk de drempel waarboven de run erover begint.
///
/// Zonder die drempel meldde de tip élke krimp, ook die van twee regels. Dat
/// leest als een opdracht om het plafond strak op de telling te zetten, en
/// precies dát maakte `main` breekbaar: twee sessies in hetzelfde bestand, elk
/// groen, samen één regel over de rand. Nu zwijgt de run zolang de lucht binnen
/// het dubbele van deze waarde blijft, en meldt hij pas wanneer er een echte
/// winst te verzilveren valt — een splitsing, geen regel of twee.
const int _baselineHeadroom = 25;

const int maxFileLines = 1000;

/// Files already above [maxFileLines] when the ratchet was introduced. Each
/// value is the file's ceiling: it may SHRINK (split the file, then lower the
/// number — the run prints a tip) but never grow. Add a new entry only with a
/// deliberate reason; the goal is fewer and smaller entries over time.
/// `lib/l10n/translations/*` is exempt — those files grow with every UI string.
///
/// **Zet een plafond niet exact op de huidige regeltelling.** Dat leest als
/// strak maar is het niet: twee PR's die tegelijk in hetzelfde bestand werken
/// zijn allebei groen tegen de `main` die ze zagen, en de samenvoeging staat er
/// dan één regel over. Op 21-08-2026 gebeurde dat vijf keer op rij — `main` rood
/// op één of twee regels, telkens pas zichtbaar in de post-merge Linux-poort.
/// Laat bij een verhoging of verlaging een handvol regels lucht (de reden mag in
/// het commentaar erboven staan, net als de rest). De ratchet houdt zijn tanden:
/// hij weigert nog steeds groei voorbij het plafond.
const Map<String, int> fileSizeBaseline = {
  // +23 (#1643): fail-closed MarkdownSafetyScanner.scan in restoreRecovered.
  // De scan is cohesief met de herstel-lus (leest snap-velden, zet het
  // beveiligingsalarm via _ref/importSecurityAlarmProvider) en verhuizen naar
  // een part-file vereist zes params door een helper — fragmentatie zonder
  // winst. Zie de classSizeBaseline-verhoging voor dezelfde motivatie.
  // +12 (#1637): notPresentation→document-router in openDeckFromBytes
  // (spiegelt openFileByPath). Eén guard + newDocumentFromMarkdown-aanroep,
  // cohesief met de bytes-open-lus.
  // +11 (#1646): projectPath-parameter door newDocumentFromMarkdown en
  // _placeDocumentTab — cohesief met de tab-aanmaak-lus.
  'lib/state/tabs_provider.dart':
      1052, // +10 (#1953): recoveryWriteErrorProvider
  // + onWriteError-callback bedrading in de constructor.
  // +19: LaTeX-Beamer-export — de enum-uitbreiding (label/extension), de
  // latex-case in de switch, en _buildLatex (8 regels thin wrapper naar
  // buildBeamerBody + beamerPreamble). Het gedrag zit in lib/services/latex/;
  // dit is de chokepoint die elk formaat langskomt.
  // +5: LaTeX-export — de `ocideck`-case in de extensie-switch (de early-return
  // hierboven voorkomt dat hij ooit bereikt wordt, maar de analyzer eist
  // exhaustiveness). Eén regel toegevoegd; onherleidbare plumbing.
  'lib/services/export_service.dart': 485,
  // −75 (#1707): de find/replace-staat is naar FindReplaceSession gegaan, een
  // gewone klasse die de documenteditor en de presentatie-broneditor nu delen.
  // De regel hiervóór zei dat dat niet kon zonder private-veldtoegang; dat bleek
  // mee te vallen — de sessie krijgt de controller mee, en waar de cursor heen
  // moet blijft bij de gastheer (die weet van Visueel/Bron). Inclusief de
  // fence-state uit #1679 en de visualEdit-logica uit #1649 staat het bestand
  // op 1113 (was 1225).
  //
  // De lucht boven die telling is bewust: dit plafond stond drie keer op rij
  // exact op de toenmalige telling, en toen liep `main` vijf keer rood op één of
  // twee regels doordat twee sessies tegelijk in dit bestand werkten. Zie de kop
  // van [fileSizeBaseline].
  // +11 (#1670): body i.p.v. source voor headingBlockIndex in _scrollToHeading.
  // +3 (#1759): stripLeadingFrontMatterLeakage op drie plekken in de editor.
  'lib/widgets/document_editor_screen.dart': 1153,
  // +27 (#1758): keep-with-next voor sub-hoofdstukken — alinea-split en
  // orland-guard in build(), de split-functie staat in document_pdf_blocks.dart.
  'lib/services/pdf/document_pdf_widgets.dart': 850,
  // +16 (#1235): de `onSessionEdit`-callback rijgt door vier lagen (present →
  // show/showDualScreen → constructor) — onherleidbare plumbing om session-data-
  // edits (checklist/tabel) apart van de live-fix terug te melden. Geen gedrag
  // dat uit te liften valt; de call-sites zitten in de part-bestanden.
  // +20: grafiek-hover spiegelen naar het publieksvenster — het `_chartHover`-
  // veld, de listener-registratie en de `chartHover`-tak in de presenterChannel-
  // handler die in initState (dus in dit bestand) leeft. Het zendhulpje
  // (`_sendChartHover`) en de ontvang-afhandeling (`_applyBeamerChartHover`)
  // staan al in het part-bestand presenter_beamer_payload.dart.
  // +9 (#1162): het menucategorie-veld met doc, de laatst-verzonden waarde en
  // de drie regels die hem in de beamer-sync meenemen.
  'lib/widgets/presentation/fullscreen_presenter.dart': 1066,
  // +60 (#1824): callout-checker — §2.6 binding table (orphan, duplicate,
  // invalid geometry, missing anchor). Cohesief met de analyzer-staat.
  'lib/services/slide_quality_analyzer.dart': 1110,
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
  // +9 (#1162): menuLayout-veld + doc + constructor/copyFrom/copyWith-doorvoer
  // en de import van models/menu.dart.
  // +27 (#1824): callouts, calloutPresentation, calloutReveal-velden + doc +
  // constructor/duplicate/copyWith-doorvoer voor image callouts.
  'lib/models/slide.dart': 1115,
  // Procesverbetering category tab + engine types in the add-slide picker.
  // +18 (#1162): de menu-wireframe (2×2 raster van keuzeblokken) als eigen helper
  // `_paintMenuWireframe` (uit `paint` getild voor de methode-ratchet) plus de
  // `menu`-takken in de kiezer-switches.
  // Verlaagd van 1115 naar 1112: het bestand meet 1110.
  'lib/widgets/dialogs/add_slide_dialog.dart': 1112,
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
  // Verlaagd van 1027 naar 1023: het bestand meet 1023.
  // +15 (#1162): de menucategorie en zijn terugroep (velden + doc + constructor
  // + doorgifte), plus de import en het `part` van menu_preview_layouts.dart.
  // De indelingen zelf staan in dat part-bestand, niet hier.
  // +4 (#1162): de tekst- en achtergrondkleur van de dia meegeven aan de
  // link-scope, zodat de plaatshouders het thema volgen.
  // +1 (#1162): de import van `services.dart` voor de toetsen van een
  // toetsenbord-bedienbaar menublok. De afhandeling zelf staat in het
  // part-bestand menu_preview_layouts.dart.
  // +8 (#1828): calloutRevealedBulletCount veld + doc + constructor-param +
  // doorgeven aan _BulletsImagePreview, en de image_callout import.
  'lib/widgets/slides/slide_preview.dart': 1052,
  // +57 (#1240): LibrePlan-connector — setLibreplanPassword/deleteLibreplanPassword/
  // readLibreplanPassword methodes op SettingsNotifier (keychain-toegang).
  // +3: `setShowOpenPreview` — de zetter van de instelling "Voorbeeld tonen bij
  // openen". Eén zetter met zijn dartdoc; er valt niets uit te halen dat hem
  // kleiner maakt.
  'lib/state/settings_provider.dart': 1076,
  // +31 (#1240): LibrePlan-connector — form-velden, init, dispose, save, import-
  // dialoog-import in de settings_dialog library-head.
  // +2 (#1500): twee part-declaraties erbij (tabelstijl-controls) plus de
  // import van de paginamaat-lokalisatie.
  // Verlaagd van 1034 naar 1033: het bestand meet 1033.
  // +16 (#1931): _pickLogoDark + _resolveLogoDarkPath.
  'lib/widgets/dialogs/settings_dialog.dart': 1046,
  // +24 (#1931): _resolveLogoDarkPath voor donkere logo-variant.
  'lib/services/file_service.dart':
      1050, // +26 (#1951): fileMtime + fileChangedSince.
  // +82 (#1859/#1863/#1864): layout-herstructurering met _buildSlideSettings,
  // _buildBulletList en _buildWorkSurface; State-level controller + geselecteerd
  // doel; venstermaat-klemming en Nederlandse termen. De build-methode kromp
  // van 154 naar 41 regels; de filegrootte is de grenswaarde.
  // +11 (#1854): stage in echte slot-aspectratio + alle callouts tonen (§6).
  // Statische markeringen staan in callout_marker_helpers.dart; hier is de
  // null-image guard (beeld toont altijd, ook zonder selectie) en de
  // for-loop die alle callouts doorloopt.
  // +161 (#1860): click-to-place (_placeTarget, _cancelPlacing,
  // plaatsingsmodus in gesture layer + instructie-overlay), hernummeren in
  // leesvolgorde (_renumberReferences), hint onder presentatiewijze.
  'lib/widgets/editors/callout_editor.dart': 1227,
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
  // +8 (#1605): het afbeeldingsblok in _buildWidget (één _Kind.image-tak) en
  // de herkenning van een afbeelding op eigen regel in _parse. Beide horen bij
  // de blokverwerking van deze klasse — net als de tabel-, tijdlijn- en
  // mermaid-takken die er al zaten. De resolver en de widget staan buiten de
  // klasse (parts/document_markdown_image.dart), maar de blokselectie zelf
  // kan niet zonder de interne _Kind-enum en de _parse-lus.
  // +23 (#1647): Setext-kopherkenning in _parse — _isSetextUnderline helper
  // en de check in de paragraaf-fallback. Cohesief met de _parse-lus.
  // +5 (#1921): scaleMermaidToFit parameter for paginated Mermaid scaling.
  'lib/widgets/reader/document_markdown_view.dart#DocumentMarkdownView': 1036,
  // −78 (#1707): find/replace-staat naar FindReplaceSession. Wat de klasse aan
  // die methoden hield was `_controller` (gaat mee als parameter), `_viewMode`
  // (blijft hier: alleen de gastheer weet of de cursor in de bron of in Quill
  // staat) en `setState` (een callback). Klasse staat op 1115 (was 1228); net
  // als bij het bestand met lucht erboven, om dezelfde reden.
  // +11 (#1670): body i.p.v. source voor headingBlockIndex in _scrollToHeading.
  // +3 (#1759): stripLeadingFrontMatterLeakage op drie plekken in de editor.
  'lib/widgets/document_editor_screen.dart#_DocumentEditorScreenState': 1153,
  // +1 (#1098): de uitbreidingskaart voor afbeeldingsrechten in de bestaande
  // modulelijst; de kaart zelf is een losse widget.
  // +43 (#1931): _pickLogoDark + donkere-logo-UI in settings_dialog_colors.
  'lib/widgets/dialogs/settings_dialog.dart#_SettingsDialogState':
      // +78 (#1500): de tabelstijl-controls (randstijl, zebra, celopvulling,
      // accentlijn) en de paginamaat-/margecontrols. Ze staan in eigen parts
      // (settings_dialog_table_style.dart, settings_dialog_general.dart), maar
      // blijven extensies op deze klasse — een part-splitsing verkleint het
      // bestand, niet de klasse. De laatste +10 komt van het opsplitsen van
      // `_checklistTableColorSettings`: met de zes stijlvelden erbij liep dat
      // ene blok over de methodelengte-grens, dus staan de tabelkleuren nu in
      // een eigen `_tableColorSettings` — twee onderwerpen, twee methodes.
      // +29: de sectie "Openen" op het Opslag-tabblad met de schakelaar
      // "Voorbeeld tonen bij openen" (`_openPreviewSection`). Hij hoort bij de
      // andere secties van dat tabblad en leest als zij; hem als enige buiten de
      // klasse zetten zou de sectie-opbouw daar inconsistent maken voor drie
      // regels winst.
      // −53: het kleurvlakje van een kleurkiezer (`_colorSwatchButton`) en de
      // lettertype-stijlhulp (`_fontStyle`) staan nu top-level. Geen van beide
      // leest een veld van dit scherm, dus ze hoorden er ook niet in — de
      // driedeling van de stijlbouwer (algemeen/document/presentatie) betaalde
      // zichzelf zo terug.
      // +26 (#1885): flexibel zoekveld (ConstrainedBox i.p.v. vaste 260 px),
      // SegmentedButton-iconen weg op smal, _profileSelector in Wrap op smal.
      // +43 (#1931): _pickLogoDark + donkere-logo-UI in settings_dialog_colors.
      6246,
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
  // +26 (#1162): de menucategorie — veld, `_setMenuCategory` (in het part-bestand
  // presenter_content.dart, maar lid van deze State), de beamer-sync en het
  // terugzetten bij een diawissel.
  // +37 (#1828): PresentationStepPlan-migratie — _stepIndex hernoemd van
  // _timelineStep, _announceStep voor schermlezer, plan-gebaseerde helpers
  // in presenter_content/navigation/playback/views.
  'lib/widgets/presentation/fullscreen_presenter.dart#_FullscreenPresenterState':
      3478,
  // +34 (#1350, #1351, #1355): truncatie-check in openDeckFromContent,
  // versleutelde-zip-streaming via writeContent(capped), en automatische
  // zegelverificatie bij openen. Security-fixes die in het open-pad landen
  // — onherleidbaar aan dit chokepoint-bestand.
  // −12: de mapwandeling van `scanMarkdownFiles` ging naar de top-level
  // `walkMarkdownFiles` in de part `file/file_service_scan.dart` — hij raakt
  // geen veld van deze klasse aan. Netto krimpt de klasse ondanks dat diezelfde
  // scan er de documentkant bij kreeg.
  // +34 (#1804): `_writeMarpConfig` + `.marprc.yml`-lid in het pakket, zodat
  // een gewone `marp deck.md` de gegenereerde thema-CSS laadt. Beide horen bij
  // het opslaan/pakken en raken velden die al in deze klasse leven.
  // +58 (#1931): _resolveLogoDarkPath voor donkere logo-variant.
  // +26 (#1928): `pickMarkdownFiles`, de meervoudige kiezer. Het werk zelf ligt
  // al top-level (`_pickPathsGated`); wat hier overblijft is de dialoogtitel,
  // en die komt uit `_d()` — een instantiemethode, want de taalcode hangt aan
  // deze klasse. Een top-level variant zou de titel of de taal moeten
  // doorgeven en de andere kiezers uit de rij halen.
  'lib/services/file_service.dart#FileService':
      2875, // +26 (#1951): fileMtime + fileChangedSince.
  // vóór de .md schrijven (commit-punt) — markdown + recordWrittenBytes
  // gaan vooraf, zodat het zegel de juiste hash draagt.
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
  // Verlaagd van 3160 naar 3159: de klasse meet 3159.
  'lib/widgets/slides/slide_preview.dart#_ChartPreviewState': 3159,
  // Procesverbetering: improvement-slide discovery + save paths.
  // +4: Y-01/framework-args op newDeck + improvement-module-prompt.
  // Verlaagd van 2235 naar 2232: de klasse meet 2227.
  // +22 (#1643): fail-closed MarkdownSafetyScanner.scan in restoreRecovered —
  // documentherstel is dezelfde invoerklasse als een bestand en mag de poort
  // niet omzeilen. De scan is cohesief met de herstel-lus (leest snap-velden,
  // zet het beveiligingsalarm) en verhuizen naar een part-file vereist zes
  // params door een helper — fragmentatie zonder winst.
  // +12 (#1637): notPresentation→document-router in openDeckFromBytes.
  // +11 (#1646): projectPath-parameter door newDocumentFromMarkdown en
  // _placeDocumentTab — cohesief met de tab-aanmaak-lus.
  'lib/state/tabs_provider.dart#TabsNotifier': 2284, // +5 (#1953): onWriteError
  // bedrading in constructor + recoveryWriteErrorProvider.
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
  // +8 (#1162): het menu-indelingstoken schrijven en teruglezen, plus het
  // filteren ervan uit `effectiveClass`. De body-regelverwerking verhuisde
  // hierbij naar markdown_parse/markdown_service_parse_body.dart — dat maakt de
  // bestanden kleiner, maar de klasse niet.
  // +29 (#1824): callout front-matter block schrijven + callout-anchor koppeling
  // in parse (ocideck_callouts: block inlesen en per-slide callouts invullen).
  'lib/services/markdown_service.dart#MarkdownService': 2455,
  'lib/widgets/dialogs/image_carousel_picker.dart#_ImageCarouselPickerState':
      2437, // +228 (#1404): hernoem-actie + dialoog; testbare logica zit in
  // ImageRenameService, hier blijft alleen UI-orchestratie
  'lib/services/privacy/privacy_scanner.dart#PrivacyScanner': 1616,
  // +12 (#1845): calloutDescription fragments — descriptions are scannable
  // content per IMAGE_CALLOUTS.md §8; the privacy scanner now yields one
  // fragment per callout description.
  // +7 (#1098): menu- en dialoogaanroepen voor het rechtenoverzicht; de scan en
  // beoordeling leven buiten de State in providers en services.
  // Verlaagd van 1449 naar 1447, en van 1447 naar 1439: de exportfabriek is
  // naar een top-level functie in hetzelfde part-bestand gegaan (#1589). Hij
  // raakte geen enkel veld van de State, dus hij hoorde er ook niet in te
  // tellen.
  'lib/widgets/app_shell.dart#_MainLayoutState':
      // +10 (#1881): showRail-guard die de rail laat invallen op smal web,
      // anders gooit num.clamp ArgumentError onder 210 px vensterbreedte.
      1449,
  // Bewust verhoogd van 1331 naar 1344: het app-globale Matrix-account
  // (setMatrixAccount + de keychain-getters voor het access-token) spiegelt
  // bewust de bestaande AI- en git-account-setters. Het gedrag staat in de
  // part `settings_provider_matrix.dart`, maar telt mee voor de klasse; het
  // laadwerk (aiSettings + matrixAccount) ging in dezelfde wijziging naar
  // top-level helpers, wat de netto groei drukte.
  'lib/state/settings_provider.dart#SettingsNotifier':
      // +13 (#1500): setDocumentEditorMaxWidth, setDocumentPageSize en
      // setDocumentPageMargins — drie zetters voor de documentmodus-instellingen.
      // +3: `setShowOpenPreview`, de zetter van "Voorbeeld tonen bij openen".
      // Een zetter móét de state van deze notifier aanraken, dus top-level
      // halen zou hem alleen omslachtiger maken, niet kleiner.
      1401,
  // Bewust verhoogd van 1256 naar 1261 (#651): `setDismissals` is een nieuwe
  // openbare mogelijkheid, geen drift. In dezelfde wijziging ging er 24 regels
  // uit — de vier identieke regels die annotaties, notities en terzijdeleggingen
  // deelden staan nu één keer in `_updateSidecarLayer`, en het opschonen en
  // zetten van een notitie is top-level geworden. Wat overblijft raakt allemaal
  // `state` en is dus niet uit de klasse te tillen zonder een eigen laag te
  // bouwen die groter is dan de functie die hem vraagt.
  'lib/state/deck_provider.dart#DeckNotifier':
      1460, // +57 (#1951): _fileMtime, fileChangedExternally, reloadFromDisk.
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
  // +4 (#1950): _reportChartWarnings retourneert of er grafiekdata-waarschuwingen
  // waren, zodat _saveToPath/saveAs het tabblad vuil kunnen houden — de cijfers
  // staan dan inline in de .md als vangnet. Twee var-declaraties + één return.
  // +16 (#1952): _saveQueued-wachtrij in save() — een tweede Cmd/Ctrl+S tijdens
  // een lopende opslag wordt onthouden en opnieuw uitgevoerd als het tabblad nog
  // vuil is. Eén veld + vijf regels in save() + import dart:async.
  'lib/widgets/slides/slide_preview.dart#_QuestionPreview': 1213,
  // +10 (#1162): de `menu`-tak in de drie kwaliteitsswitches (contrast, alt-tekst,
  // ontbrekend bestand) + de dichtheidsswitch — menublokken zijn een raster, geen
  // doorlopende tekst; de blokafbeeldingen zitten in de bullet-tekst, niet in
  // [Slide.imagePath], dus de generieke controles slaan er (vooralsnog) niet op.
  // Verlaagd van 1130 naar 1125: de klasse meet 1118.
  // Verlaagd van 1125 naar 1040: de thema-contrastreeks staat sinds de
  // document-kleurparen als top-level `_checkThemeContrast` naast
  // [_addSlidePairIssue] — zij hangt aan het thema, niet aan de analyzer-staat.
  // De klasse meet 1037.
  // +60 (#1824): callout-checker — §2.6 binding table (orphan, duplicate,
  // invalid geometry, missing anchor) met tekst-ref-telling en entry-vergelijking.
  // De klasse meet 1097.
  'lib/services/slide_quality_analyzer.dart#SlideQualityAnalyzer': 1110,
  // Procesverbetering: Y-01-UI, type-toolbar, plaklogica en DOE-dialoog zijn
  // naar losse widgets/helpers getild (chart_histogram_limits,
  // chart_type_toolbar, table_clipboard, DoeDesignDialog). Plafond verlaagd
  // van 1198 naar 1081.
  // Verlaagd van 1081 naar 1080: de klasse meet 1079.
  'lib/widgets/editors/chart_editor.dart#_ChartEditorState': 1080,
  // +10 (#977): each thumbnail reads collab presence and wraps in the presence
  // overlay. The overlay's real work (filter + Stack + dots) lives in the
  // top-level `slideWithPresence` in slide_presence_dots.dart; only the per-item
  // read and the wrap call remain in the state class.
  // +1 (#1164): splitRunPosition-doorvoer naar de thumbnail voor de (2/3)-teller.
  'lib/widgets/panels/slide_list_panel.dart#_SlideListPanelState': 1025,
  // +9 (#1854): null-image guard (beeld toont altijd) + for-loop die alle
  // callouts doorloopt in _buildImageStack. Statische markeringen staan in
  // callout_marker_helpers.dart; de klasse houdt de loop en de guard.
  // +161 (#1860): click-to-place, _renumberReferences, hint tekst.
  'lib/widgets/editors/callout_editor.dart#_CalloutEditorDialogState': 1180,
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
///
/// `deliversByDownload` (services/download_delivery.dart) telt sinds #1902 mee.
/// Het is dezelfde vraag in de vorm waarin de exportpaden hem stellen — "komt
/// dit als download aan of als bestand op schijf" — en de productiewaarde ís
/// `kIsWeb`. Alleen een test kan hem omzetten, en dat is precies waarvoor hij
/// bestaat: zonder die haak lag de hele webtak buiten bereik van de suite.
final _platformFlag = RegExp(
  r'\b(supportsLocalProjectFolders|isWebPlatform|kIsWeb|deliversByDownload)\b',
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

/// Wachtpunten die vandaag nog op een vaste klok staan.
/// RATCHET: mag krimpen, nooit groeien.
///
/// De sleutel is het pad, de waarde het aantal treffers dat daar nu staat. Deze
/// lijst is ontstaan toen de poort hierboven eindelijk zag wat er stond; hij is
/// geen vrijbrief maar een meetpunt. Twee soorten staan erin, en het verschil
/// hoort zichtbaar te blijven:
///
/// * **Bewuste uitzondering** — er valt niets aan te wijzen dat "klaar"
///   betekent, dus een vaste flush is daar de eerlijke vorm. Welke dat zijn en
///   waaróm staat in het doc-commentaar van `test/support/pump_until.dart`,
///   onder "Waar dit bewust níét gebruikt wordt". Die entries mogen blijven.
/// * **Schuld** — een gok die nog naar `pumpUntil` moet. Elke daarvan is een
///   linux-gate die op een drukke dag rood kan lopen.
const Map<String, int> fixedDelayBaseline = {
  // ── Bewuste uitzonderingen (zie pump_until.dart) ──
  // Een nep-videoplatform waarvan de stream-subscription leegloopt: een
  // wachtrij, geen zwaar werk, en geen gedeelde uitkomst om op te wachten.
  'test/media_lifecycle_test.dart': 1,
  'test/media_previews_video_coverage_test.dart': 1,
  // `settle` na een klik of een zoekterm: tot rust laten komen, niet wachten op
  // een aanwijsbaar resultaat. De mapscan in ditzelfde bestand wacht wél.
  'test/image_carousel_picker_smoke_test.dart': 1,
  // De handeling zelf moet bínnen runAsync beginnen: een isolate die daarbuiten
  // start hangt in een testproces na de eerste keer. Die volgorde omdraaien
  // maakt deze tests stuk.
  'test/shell_s3_actions_test.dart': 2,
  'test/shell_webdav_actions_test.dart': 2,

  // ── Schuld: nog te vertalen naar pumpUntil ──
  // Alles wat ooit rood op de linux-gate stond, is inmiddels omgezet:
  // image_carousel_delete (9×), callout_accessibility (2×), callout_reveal (1×),
  // document_editor_screen (5×) en export_dialog_pdf (1×). Wat hier nog staat,
  // is nog niet rood gezien — maar het draagt dezelfde vorm en dus dezelfde
  // kans, en dat is precies waarom het geteld wordt in plaats van vergeten.
  'test/bullets_image_preview_test.dart': 1,
  'test/callout_raster_export_frame_test.dart': 1,
  'test/document_new_and_save_as_test.dart': 1,
  'test/image_carousel_picker_actions_test.dart': 3,
  'test/image_carousel_rename_test.dart': 1,
  'test/image_crop_dialog_test.dart': 1,
  'test/image_slides_preview_test.dart': 2,
  'test/info_safety_prompt_test.dart': 1,
  'test/pdf_export_slide_types_test.dart': 1,
  'test/shell_export_actions_test.dart': 1,
  'test/shell_git_actions_extra_test.dart': 1,
  'test/shell_git_actions_test.dart': 1,
  'test/shell_present_and_close_test.dart': 2,
  'test/shell_url_import_test.dart': 1,
  'test/slide_rasterizer_test.dart': 2,
  'test/slide_thumbnail_remote_media_test.dart': 1,
  'test/split_bullets_image_page_target_test.dart': 1,
};

/// Wat de poort over de vaste wachtpunten te melden heeft.
class _DelayScan {
  const _DelayScan(this.overBasislijn, this.gekrompen);

  /// Bestanden die meer treffers dragen dan hun basislijn toestaat — of die er
  /// helemaal niet in staan. Dit is de faal.
  final List<String> overBasislijn;

  /// Bestanden die minder treffers dragen dan hun basislijn: winst die nog
  /// vastgezet moet worden. Adviserend, zoals bij de andere ratchets.
  final List<String> gekrompen;
}

/// Is dit knooppunt een `Future.delayed(…)` — in welke schrijfwijze dan ook?
///
/// Twee vormen, want de parser maakt er niet één van: `Future.delayed(x)` wordt
/// een [MethodInvocation] met `Future` als doel, `Future<void>.delayed(x)` een
/// [InstanceCreationExpression] met een expliciet typeargument. De poort zocht
/// tot 2026-09-01 alleen de eerste — en 126 van de 129 wachtpunten in `test/`
/// schrijven de tweede.
bool _isFutureDelayed(AstNode node) {
  if (node is MethodInvocation) {
    return node.methodName.name == 'delayed' &&
        (node.target?.toSource().startsWith('Future') ?? false);
  }
  if (node is InstanceCreationExpression) {
    final naam = node.constructorName.toSource();
    return naam.startsWith('Future') && naam.endsWith('.delayed');
  }
  return false;
}

/// Verzamelt per bestand welke declaraties een vast wachtpunt dragen, welke
/// declaraties elkaar aanroepen, en waar de `runAsync`-aanroepen staan.
class _DelayVisitor extends RecursiveAstVisitor<void> {
  /// De declaratie waar de bezoeker nu in zit, of `null` op bestandsniveau.
  String? _huidige;

  /// Declaraties met een `Future.delayed` rechtstreeks in hun lichaam.
  final Set<String> wacht = {};

  /// Declaratie → de namen die zij aanroept. De basis van de call-graph.
  final Map<String, Set<String>> roept = {};

  /// De `runAsync`-aanroepen: hun offset plus de namen die erbinnen worden
  /// aangeroepen, en of er rechtstreeks een wachtpunt in zit.
  final List<({int offset, Set<String> roept, bool direct})> runAsyncs = [];

  void _inDeclaratie(String naam, void Function() body) {
    final vorige = _huidige;
    _huidige = naam;
    roept.putIfAbsent(naam, () => <String>{});
    body();
    _huidige = vorige;
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _inDeclaratie(node.name.lexeme, () => super.visitFunctionDeclaration(node));
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _inDeclaratie(node.name.lexeme, () => super.visitMethodDeclaration(node));
  }

  /// Een lokale hulp in een testbestand is meestal een `Future<void> foo()`
  /// binnen `main()`; die telt als eigen declaratie, niet als deel van `main`.
  @override
  void visitFunctionDeclarationStatement(FunctionDeclarationStatement node) {
    _inDeclaratie(
      node.functionDeclaration.name.lexeme,
      () => super.visitFunctionDeclarationStatement(node),
    );
  }

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isFutureDelayed(node) && _huidige != null) wacht.add(_huidige!);
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isFutureDelayed(node)) {
      if (_huidige != null) wacht.add(_huidige!);
    } else if (node.methodName.name == 'runAsync') {
      final binnen = _AanroepVerzamelaar();
      node.argumentList.accept(binnen);
      runAsyncs.add((
        offset: node.offset,
        roept: binnen.namen,
        direct: binnen.wachtpunt,
      ));
    } else if (_huidige != null) {
      roept[_huidige]!.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}

/// De namen die binnen één stuk boom worden aangeroepen, plus of er een
/// wachtpunt rechtstreeks in staat.
class _AanroepVerzamelaar extends RecursiveAstVisitor<void> {
  final Set<String> namen = {};
  bool wachtpunt = false;

  @override
  void visitInstanceCreationExpression(InstanceCreationExpression node) {
    if (_isFutureDelayed(node)) wachtpunt = true;
    super.visitInstanceCreationExpression(node);
  }

  @override
  void visitMethodInvocation(MethodInvocation node) {
    if (_isFutureDelayed(node)) {
      wachtpunt = true;
    } else {
      namen.add(node.methodName.name);
    }
    super.visitMethodInvocation(node);
  }
}

/// De regelnummers per bestand waar een `runAsync` op een vaste klok wacht.
///
/// Los van de schijf zodat de meting zelf toetsbaar is; zie
/// `test/fixed_delay_ratchet_test.dart`. Het regelnummer is dat van de
/// `runAsync`, niet van de `Future.delayed` erbinnen: dát is het punt waar de
/// lezer de vervanging moet aanbrengen.
///
/// ── Waarom dit over de AST loopt en niet over tekst ──
///
/// De vorige versie zocht `runAsync(` met een reguliere uitdrukking en las
/// vandaar tot het sluithaakje. Dat mist twee dingen die allebei echt gebeurd
/// zijn. Ten eerste de schrijfwijze: `Future<void>.delayed` glipte langs een
/// patroon dat alleen `Future.delayed` kende. Ten tweede — en dat is de reden
/// voor deze herschrijving — een wachtpunt dat níet lexicaal binnen de
/// `runAsync` staat maar in een hulp die daarvandaan wordt **aangeroepen**.
/// `callout_reveal_test._pumpOverlay` had precies die vorm en is nooit gezien.
///
/// De call-graph blijft binnen één bestand en dat is genoeg: een testhulp die
/// echte tijd laat verstrijken hoort bij de test die hem gebruikt. Reikt hij
/// verder (zoals `pump_until.dart`), dan is dat een gedeelde hulp met een eigen
/// doc-comment, en die staat hier bewust buiten.
///
/// Commentaar en stringliteralen vallen vanzelf weg: de parser maakt er geen
/// aanroepknooppunten van. De twee tekstfilters die daarvoor nodig waren zijn
/// daarmee verdwenen.
Map<String, List<int>> fixedDelaysIn(Map<String, String> sources) {
  final perBestand = <String, List<int>>{};
  sources.forEach((path, raw) {
    if (!raw.contains('runAsync')) return;
    final ontleed = parseString(
      content: raw,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    final regels = ontleed.lineInfo;
    if (ontleed.errors.isNotEmpty) {
      // Een testbestand dat niet parseert is geen groen bestand. Zonder deze
      // tak zou de poort er stil overheen lopen — en "stil niets meten" is
      // precies de faalvorm die deze poort in september 2026 anderhalve maand
      // liet doorgaan. `analyze` vangt dit normaal eerder; komt het hier toch
      // langs, dan moet het opvallen.
      perBestand[path] = [
        regels.getLocation(ontleed.errors.first.offset).lineNumber,
      ];
      return;
    }
    final bezoeker = _DelayVisitor();
    ontleed.unit.accept(bezoeker);

    // Welke declaraties leiden — direct of via een andere hulp in dit bestand —
    // tot een vast wachtpunt? Herhaal tot er niets meer bij komt.
    final wacht = {...bezoeker.wacht};
    for (var ronde = 0; ronde < 10; ronde++) {
      final voor = wacht.length;
      bezoeker.roept.forEach((naam, aangeroepen) {
        if (aangeroepen.any(wacht.contains)) wacht.add(naam);
      });
      if (wacht.length == voor) break;
    }

    final hits = perBestand.putIfAbsent(path, () => <int>[]);
    for (final aanroep in bezoeker.runAsyncs) {
      if (!aanroep.direct && !aanroep.roept.any(wacht.contains)) continue;
      hits.add(regels.getLocation(aanroep.offset).lineNumber);
    }
    hits.sort();
  });
  return perBestand;
}

/// Tests die binnen een `runAsync` op een vaste klok wachten.
_DelayScan _fixedDelayInRunAsync() {
  final sources = <String, String>{};
  for (final file in Directory('test').listSync(recursive: true)) {
    if (file is! File || !file.path.endsWith('.dart')) continue;
    final path = file.path.replaceAll(r'\', '/');
    // De hulp zelf wisselt per ontwerp korte stapjes echte tijd af met een
    // `pump`. Dat is niet het antipatroon, dat is het alternatief.
    if (path == 'test/support/pump_until.dart') continue;
    sources[path] = file.readAsStringSync();
  }
  final perBestand = fixedDelaysIn(sources);

  final over = <String>[];
  final gekrompen = <String>[];
  perBestand.forEach((path, hits) {
    final toegestaan = fixedDelayBaseline[path] ?? 0;
    if (hits.length > toegestaan) {
      over.add(
        '$path: ${hits.length} wachtpunt(en), basislijn $toegestaan — regel '
        '${hits.join(', ')}',
      );
    } else if (hits.length < toegestaan) {
      gekrompen.add('$path: ${hits.length} (basislijn $toegestaan)');
    }
  });
  for (final path in fixedDelayBaseline.keys) {
    if (!perBestand.containsKey(path)) {
      gekrompen.add('$path: 0 (basislijn ${fixedDelayBaseline[path]})');
    }
  }
  return _DelayScan(over, gekrompen);
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
        } else if (ceiling - count > 2 * _baselineHeadroom) {
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
      } else if (ceiling - count > 2 * _baselineHeadroom) {
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

  final delays = _fixedDelayInRunAsync();
  if (delays.overBasislijn.isNotEmpty) {
    failures.add(
      'Een test wacht binnen `runAsync` op een vaste klok in plaats van op het '
      'resultaat. Zo\'n test slaagt los en faalt onder een volle `make check` — '
      'de duurste faalvorm die er is, want hij wordt opnieuw gedraaid, slaagt, '
      'en dan heet het toeval. Gebruik `pumpUntil` uit '
      'test/support/pump_until.dart: die wacht tot het er ís, met een '
      'bovengrens zodat een vastloper alsnog faalt. Verhoog '
      '`fixedDelayBaseline` niet om dit stil te krijgen — die lijst mag alleen '
      'krimpen:\n'
      '    ${delays.overBasislijn.join('\n    ')}',
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
      '(baseline ${filePickerPathBaseline.length}); vaste wachtpunten in '
      'test/ binnen de basislijn (${fixedDelayBaseline.length} bestand(en)).',
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
        'fileSizeBaseline to lock in the win — to about '
        '$_baselineHeadroom lines above the new count, not exactly onto it '
        '($_headroomWhy):\n'
        '    ${shrunk.join('\n    ')}',
      );
    }
    if (delays.gekrompen.isNotEmpty) {
      stdout.writeln(
        'Tip: ${delays.gekrompen.length} bestand(en) dragen minder vaste '
        'wachtpunten dan hun fixedDelayBaseline — verlaag de basislijn (of haal '
        'de regel weg bij 0) om de winst vast te zetten. Hier geen lucht laten: '
        'een wachtpunt komt niet vanzelf terug:\n'
        '    ${delays.gekrompen.join('\n    ')}',
      );
    }
    if (shrunkClasses.isNotEmpty) {
      stdout.writeln(
        'Tip: ${shrunkClasses.length} baselined class(es) shrank — lower their '
        'classSizeBaseline to lock in the win — same bit of air, about '
        '$_baselineHeadroom lines ($_headroomWhy):\n'
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
