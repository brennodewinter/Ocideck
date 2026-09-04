import '../services/document_page_setup.dart';

import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show EditorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../l10n/export_block_localization.dart';
import '../l10n/page_size_localization.dart';
import '../models/chart.dart';
import '../models/deck.dart';
import '../models/markdown_outline.dart';
import '../models/page_size.dart';
import '../models/privacy_disposition.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../services/caption_service.dart';
import '../services/classification_enforcement_policy.dart';
import '../services/description_service.dart';
import '../services/document_chart_hydration.dart';
import '../services/document_deck_bridge.dart';
import '../services/download_delivery.dart';
import '../services/document_export_service.dart';
import 'parts/document_export_pdf_support.dart';
import '../services/document_footnote_setup.dart';
import '../services/document_style.dart';
import '../services/export_metadata.dart';
import '../services/file_service.dart';
import '../services/html_image_embedder.dart';
import '../services/image_service.dart' show ImageImportFailure, ImageService;
import '../services/markdown_table_codec.dart';
import '../services/document_timeline.dart';
import '../services/marp_html_service.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../state/deck_provider.dart'
    show fileServiceProvider, imageServiceProvider, markdownServiceProvider;
import '../state/document_provider.dart';
import '../state/settings_provider.dart'
    show
        kDocumentEditorZoomMax,
        kDocumentEditorZoomMin,
        kDocumentEditorZoomStep,
        settingsProvider;
import '../state/tabs_provider.dart';
import '../theme/app_theme.dart';
import '../utils/doc_link.dart' show headingSlug;
import '../utils/document_front_matter.dart';
import '../utils/error_snackbar.dart';
import '../utils/file_extension.dart';
import '../utils/image_search_paths.dart';
import '../utils/footnotes.dart';
import '../utils/markdown_blocks.dart';
import '../utils/markdown_caret_map.dart';
import '../utils/physical_control_shortcut.dart';
import '../utils/text_search.dart';
import '../utils/url_launcher_util.dart';
import '../platform/clipboard_html.dart';
import '../utils/clipboard_markdown.dart';
import '../utils/markdown_visual_compatibility.dart'
    show
        firstVisualLimitation,
        MarkdownVisualLimitation,
        markdownRoundTripsVisually;
import 'dialogs/convert_to_presentation_dialog.dart';
import 'dialogs/document_export_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/settings_dialog.dart';
import 'document_page_chrome.dart';
import 'editors/_editor_field.dart' show reportImageImportFailure;
import 'editors/chart_editor.dart';
import 'editors/embed_editor_dialog.dart';
import 'editors/find_replace_session.dart';
import 'editors/markdown_find_bar.dart';
import 'editors/markdown_source_controller.dart';
import 'editors/table_editor.dart';
import 'markdown_editor/markdown_editor.dart';
import 'reader/document_markdown_view.dart';
import 'reader/paged_document_view.dart';
import 'reader/writing_page_breaks.dart';
import 'shell/document_save_actions.dart';

part 'parts/document_editor_toolbar.dart';
part 'parts/document_fields_dialog.dart';
part 'parts/document_editor_layouts.dart';
part 'parts/document_source_field.dart';
part 'parts/document_source_rewrites.dart';
part 'parts/document_editor_inserts.dart';

/// De schermvullende editor voor een documenttabblad: links de platte
/// Markdown-bron, rechts een live weergave. De bron *ís* de waarheid — elke
/// toetsaanslag stroomt direct naar de [DocumentNotifier] (geen 'Toepassen'-muur,
/// DOCUMENT_MODE.md §1.1), en de weergave hertekent mee.
///
/// Bewust nog kaal: dit is de rauw+preview-basis. De visuele (WYSIWYG) modus met
/// ingebedde kaarten, het invoeg-palet en de Overzicht-rail komen er in latere
/// fasen omheen — dit oppervlak is de spil waar ze op landen.
class DocumentEditorScreen extends ConsumerStatefulWidget {
  const DocumentEditorScreen({super.key});

  @override
  ConsumerState<DocumentEditorScreen> createState() =>
      _DocumentEditorScreenState();
}

class _DocumentEditorScreenState extends ConsumerState<DocumentEditorScreen> {
  late final MarkdownSourceController _controller;
  final ScrollController _previewScroll = ScrollController();

  /// De kop waar de Overzicht-rail naartoe scrollt: het blokindexnummer in de
  /// weergave dat [_anchorKey] draagt, of -1. Dezelfde één-verplaatsende-sleutel
  /// als de docs-lezer, zodat `ensureVisible` betrouwbaar landt.
  final GlobalKey _anchorKey = GlobalKey();
  int _anchorBlockIndex = -1;

  /// Actieve kop in de Overzicht-rail (−1 = geen), afgeleid van de caret.
  int _activeOutlineIndex = -1;

  /// Of de Overzicht-rail is ingeklapt tot een smalle strook.
  bool _outlineCollapsed = false;

  /// Signaal + doel voor springen in de visuele [MarkdownNotesEditor].
  int _revealSignal = 0;
  int? _revealMarkdownOffset;
  String? _revealTitle;

  /// Waar de cursor het laatst stond in de platte tekst van de visuele stand.
  /// Bij het wisselen naar de bron wordt hij hiermee teruggerekend naar een
  /// plek in de Markdown (#1566).
  int _visualCaret = 0;

  /// De actieve weergavemodus. [_DocViewMode.visual] is de standaard: de
  /// gedeelde Markdown-editor (WYSIWYG via Quill, of rauw bij constructies die
  /// de brug niet aankan) als schrijfoppervlak. [_DocViewMode.source] toont de
  /// platte bron naast een live weergave.
  _DocViewMode _viewMode = _DocViewMode.visual;

  /// Pagina-einden in de schrijfstand. Standaard aan: dat is de vraag waarvoor
  /// je een paginamaat kiest — wat komt er nog op deze bladzijde. Uit zetten
  /// kan, en dan geldt de ingestelde schrijfbreedte weer in plaats van de
  /// tekstbreedte van de pagina.
  bool _showPageBreaks = true;

  /// Sleutel op de Quill-editor van de visuele stand, zodat de pagina-einden
  /// aan de echte blokgeometrie gemeten kunnen worden.
  final GlobalKey<EditorState> _visualEditorKey = GlobalKey<EditorState>();

  /// De focus van de rauwe editor. De opmaak-knoppenbalk geeft de focus hierheen
  /// terug na een klik, zodat je meteen verder typt.
  final FocusNode _editorFocus = FocusNode();

  /// Waar terwijl de controller van *buitenaf* wordt gelijkgetrokken aan de bron
  /// (ongedaan maken/opnieuw, of een invoeging): dan mag de controllerluisteraar
  /// niet terugstromen naar de notifier — dat zou een lus of dubbele bewerking
  /// geven.
  bool _applyingExternal = false;

  /// Signaal + inhoud voor een invoeging op de cursor van de visuele editor.
  /// Zie [_insertBlock] voor waarom de invoeging daar niet via de bron loopt.
  int _insertSignal = 0;
  String? _pendingInsertBlock;

  /// Het label van de voetnoot die op hetzelfde [_insertSignal] moet worden
  /// ingevoegd, of `null` wanneer de invoeging een gewoon blok is.
  String? _pendingFootnoteLabel;

  /// Waar tussen het aanvragen van zo'n invoeging en de controllerwijziging die
  /// eruit volgt: die ene wijziging is een eigen bewerking, geen voortzetting
  /// van het typen ervoor.
  bool _expectVisualInsert = false;

  /// De actieve documentstijl. Alleen documentoppervlakken lezen hem; de rauwe
  /// Markdownbron en de presentatie-editor houden hun eigen sobere chrome.
  ThemeProfile? _styleProfile;

  /// Zoek-/vervangbalk. Deelt de stand ([FindReplaceSession]) en de balk
  /// ([MarkdownFindBar]) met de presentatie-broneditor. De treffers leven op de
  /// Markdown-bron ([_controller].text) — dat is in beide modi dezelfde tekst,
  /// dus de teller klopt ongeacht of je in Visueel of Bron zoekt.
  late final FindReplaceSession _find;

  /// Signaal + Markdown-bereik voor de visuele stand: zet de Quill-cursor op de
  /// match. In de Bron-stand zet [_jumpToMatch] de controller-selectie direct;
  /// in Visueel leeft de cursor in Quill en vertaalt [MarkdownNotesEditor] de
  /// Markdown-offset via [MarkdownCaretMap].
  int _findSelectionSignal = 0;
  int? _findSelectionStart;
  int? _findSelectionEnd;

  @override
  void initState() {
    super.initState();
    // De editor bewerkt de *body*: de bron zonder het leidende stijl-frontmatter-
    // blok. De stijl (`theme:`) leeft in de frontmatter en wordt beheerd door de
    // Stijl-kiezer, niet als tekst getypt. Elke terugschrijf zet de frontmatter
    // er weer vóór, zodat `document.source` byte-getrouw blijft.
    final initialBody = stripLeadingFrontMatterLeakage(
      ref.read(documentProvider).document?.body ?? '',
    );
    _controller = MarkdownSourceController(text: initialBody);
    // Eén luisteraar vangt élke body-wijziging in de controller — typen én de
    // opmaak-knoppenbalk (die de controller rechtstreeks muteert en dus geen
    // onChanged afvuurt). Zo stroomt alles langs dezelfde weg naar de notifier.
    _controller.addListener(_onControllerChanged);
    _find = FindReplaceSession(
      controller: _controller,
      onChanged: () {
        if (mounted) setState(() {});
      },
      onReveal: _jumpToMatch,
    );
    // Bevat de body al bij het openen een constructie die de visuele editor niet
    // verliesvrij aankan, dan start direct in de Bron-modus. De gebruiker hoeft
    // niet eerst de visuele modus te zien falen om te begrijpen dat hij in de
    // bron hoort te werken.
    if (!markdownRoundTripsVisually(initialBody)) {
      _viewMode = _DocViewMode.source;
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_onControllerChanged);
    _controller.dispose();
    _editorFocus.dispose();
    _previewScroll.dispose();
    super.dispose();
  }

  /// Stroom een controllerwijziging naar de notifier. Slaat over wanneer de
  /// controller juist van búiten wordt bijgewerkt (`_applyingExternal`), en
  /// wanneer alleen de selectie/cursor verschoof (body gelijk) — anders zou een
  /// simpele cursorbeweging een lege bewerking worden.
  void _onControllerChanged() {
    _syncOutlineToMarkdownCaret();
    if (_applyingExternal) return;
    final body = _controller.text;
    final doc = ref.read(documentProvider).document;
    if (doc == null || doc.body == body) return;
    final ownStep = _expectVisualInsert;
    _expectVisualInsert = false;
    // In de visuele stand komt de body uit de Quill → Markdown round-trip, die
    // niet byte-getrouw is. De notifier moet dat weten, zodat opslaan alleen
    // de echte bewerkingen terug schrijft (#1613). Maar valt de visuele stand
    // terug op de platte broneditor (niet-rondreisbare Markdown), dan zijn
    // bewerkingen gewoon bronbewerkingen — niet door de Quill-baseline heen
    // sturen (#1649).
    final isVisualEdit =
        _viewMode == _DocViewMode.visual && markdownRoundTripsVisually(body);
    ref
        .read(documentProvider.notifier)
        .edit(
          doc.frontMatter + body,
          coalesceKey: ownStep ? null : 'doc',
          visualEdit: isVisualEdit,
        );
    // Houd de matchteller bij terwijl je typt — zonder te springen, net als de
    // presentatie-broneditor. De teller loopt mee via de provider-herbouw.
    _find.refreshWhileTyping();
  }

  void _setActiveOutlineIndex(int active) {
    if (active == _activeOutlineIndex) return;
    // Nooit setState vanuit een controller/Quill-listener tijdens build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || active == _activeOutlineIndex) return;
      setState(() => _activeOutlineIndex = active);
    });
  }

  /// Sla het document op. Cmd/Ctrl+S én de Opslaan-knop in de werkbalk, net als
  /// een deck. Feedback is de dirty-stip op het tabblad die verdwijnt.
  ///
  /// Deelt één opslagweg met de app-brede Cmd/Ctrl+S ([saveDocumentWithDestination]):
  /// byte-getrouw terug naar het pad, of — bij een nog niet opgeslagen document —
  /// 'Opslaan als…' zodat werk altijd als kopie te bewaren is.
  Future<void> _save() => saveDocumentWithDestination(
    context,
    ref,
    ref.read(documentProvider.notifier),
  );

  /// De titel van dit document: de eerste H1, anders de bestandsnaam, anders
  /// leeg. Bepaalt de voorgestelde exportnaam en de HTML-`<title>` — net als een
  /// tekstverwerker een document naar zijn kop noemt.
  /// Open de document-export-dialoog (DOCUMENT_MODE.md §11.2). De dialoog kiest
  /// profiel en formaat; het echte bouwen-en-wegschrijven gebeurt in de closure
  /// hieronder, die de bron langs `buildDocumentExportBundle → AudienceDeck`
  /// projecteert (nooit de rauwe bron), een pad laat kiezen en atomisch
  /// wegschrijft. De bron zelf blijft ongemoeid — export is een afgeleid bestand.
  Future<void> _export() async {
    final state = ref.read(documentProvider);
    final document = state.document;
    if (document == null) return;
    final settings = ref.read(settingsProvider);
    await DocumentExportDialog.show(
      context,
      privacyChecksEnabled: settings.privacyChecksEnabled,
      onExport: (profile, format) =>
          _writeDocumentExport(ref, context, profile, format),
    );
  }

  /// Converteer dit document naar een NIEUWE presentatie in een nieuw tabblad
  /// (DOCUMENT_MODE.md §11.3). Een expliciete kopie: dit document blijft
  /// ongemoeid. De dialoog toont het voorgestelde aantal dia's en de drop-lijst
  /// vóór het committen; pas bij bevestigen ontstaat het nieuwe tabblad.
  Future<void> _convertToPresentation() async {
    final state = ref.read(documentProvider);
    // De body zonder het stijl-frontmatter-blok: de `theme:`-regel is geen
    // slide-inhoud. Een presentatie krijgt zijn eigen thema; de documentstijl
    // reist bewust niet mee (§11.3).
    final body = state.document?.body ?? '';
    final title = _documentTitle(body, state.filePath);
    // De getypeerde, zero-loss deconstructie ís de bron van waarheid — voor het
    // voorgestelde aantal dia's én voor het nieuwe deck. Bewust niet
    // generateDeck→parseDeck: dat zou een kop-geleide sectie via `_inferSlideType`
    // weer stil kunnen laten vallen (§11.3, §11.5). De nieuwe presentatie is een
    // kopie. De documentclassificatie blijft gelden voor alle ontstane dia's;
    // alleen documentvelden en documentstijl zijn geen presentatiegegevens.
    final documentTlp = state.document?.tlp ?? TlpLevel.none;
    // Grafiekdata inline vouwen vóór de brug, gelijk aan het exportpad
    // (buildDocumentExportBundle). Zonder dit staat een `source: data/….json`
    // chart-dia leeg in het nieuwe tabblad — de cijfers reizen niet mee (#1639).
    final projectPath = _documentProjectPath(ref);
    final hydrated = await hydrateDocumentChartData(
      body,
      projectPath: projectPath,
    );
    if (!mounted) return;
    final deck = DocumentDeckBridge.documentToDeck(
      hydrated,
      projectPath: projectPath,
      title: title,
      tlp: documentTlp,
    );
    final confirmed = await ConvertToPresentationDialog.show(
      context,
      slideCount: deck.slides.length,
    );
    if (confirmed != true || !mounted) return;
    ref
        .read(tabsProvider.notifier)
        .newDeckInNewTab(
          title,
          tlp: deck.tlp,
          slides: deck.slides,
          projectPath: projectPath,
        );
  }

  /// Scroll / spring naar de aangeklikte kop uit de Overzicht-rail.
  ///
  /// Visueel: cursor in de notes-editor (markdown-offset of Quill-titel).
  /// Bron: cursor in de bron-editor + anker in de live weergave (docs-lezer-
  /// mechanisme).
  void _scrollToHeading(MarkdownOutlineEntry entry) {
    final doc = ref.read(documentProvider).document;
    final source = doc?.source ?? '';
    final body = doc?.body ?? '';
    final outline = buildMarkdownOutline(source);
    final outlineIndex = outline.indexWhere(
      (e) => e.offset == entry.offset && e.title == entry.title,
    );
    final offset = entry.offset.clamp(0, _controller.text.length);
    _controller.selection = TextSelection.collapsed(offset: offset);
    _editorFocus.requestFocus();
    setState(() {
      _activeOutlineIndex = outlineIndex;
      _revealMarkdownOffset = entry.offset;
      _revealTitle = entry.title;
      _revealSignal++;
    });

    if (_viewMode != _DocViewMode.source) return;
    // headingBlockIndex op de body, niet op de source: de preview rendert de
    // body, en frontmatter-blokken (thematische ---, sleutelregels) tellen
    // anders mee en verschuiven het bloknummer (#1670).
    final index = DocumentMarkdownView.headingBlockIndex(
      body,
      headingSlug(entry.title),
    );
    if (index < 0) return;
    setState(() => _anchorBlockIndex = index);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _anchorKey.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.08,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      documentProvider.select(
        (state) => (state.findRequestId, state.findShowReplace),
      ),
      (previous, next) {
        if (previous?.$1 != next.$1 && next.$1 > 0) {
          _openFind(showReplace: next.$2);
        }
      },
    );
    // Wanneer de body van búiten de editor verandert (ongedaan maken/opnieuw),
    // de controller bijwerken. Bij gewoon typen is de body na de `edit` al gelijk
    // aan de controllertekst, dus dan doet dit niets — geen terugkoppellus. Een
    // stijlwijziging raakt alleen de frontmatter, niet de body, dus die triggert
    // dit terecht niet.
    ref.listen(documentProvider.select((s) => s.document?.body ?? ''), (
      _,
      rawBody,
    ) {
      final body = stripLeadingFrontMatterLeakage(rawBody);
      if (body != _controller.text) {
        _applyingExternal = true;
        // Behoud de huidige cursorpositie, geklemd op de nieuwe lengte —
        // spring niet naar het einde bij undo/redo (#1672).
        final prevOffset = _controller.selection.baseOffset.clamp(
          0,
          body.length,
        );
        _controller.value = TextEditingValue(
          text: body,
          selection: TextSelection.collapsed(offset: prevOffset),
        );
        _applyingExternal = false;
      }
      // Externe body-wijziging (ongedaan maken/opnieuw, of een ander tabblad
      // dat hetzelfde document bewerkt) die de visuele modus niet aankan:
      // wissel automatisch naar Bron en wijs de probleemregel aan. Bij gewoon
      // typen in de visuele stand is de body altijd verliesvrij (de editor
      // produceert alleen ronde-trip-Markdown), dus dit triggert niet per
      // toetsaanslag.
      if (_viewMode == _DocViewMode.visual &&
          !markdownRoundTripsVisually(body)) {
        _autoFallbackToSource(body);
      }
    });
    final source = stripLeadingFrontMatterLeakage(
      ref.watch(documentProvider.select((s) => s.document?.body ?? '')),
    );
    final canUndo = ref.watch(documentProvider.select((s) => s.canUndo));
    final canRedo = ref.watch(documentProvider.select((s) => s.canRedo));
    // De actieve documentstijl: de per-document `theme:` (of de afgedwongen/
    // standaardstijl uit de instellingen). Stuurt het lettertype van het
    // schrijfoppervlak; de kiezer toont hem en laat wisselen.
    final settings = ref.watch(settingsProvider);
    final docStyleName = ref.watch(
      documentProvider.select((s) => s.document?.styleName),
    );
    final documentTlp = _documentTlp(ref);
    final fields = ref.watch(
      documentProvider.select((state) => state.document?.fields ?? const {}),
    );
    final styleProfile = resolveDocumentStyleProfile(settings, docStyleName);
    _styleProfile = styleProfile;
    final theme = Theme.of(context);
    return _withDocumentShortcuts(
      ref,
      onUndo: _undo,
      onRedo: _redo,
      onSave: () => unawaited(_save()),
      onFind: () => _openFind(showReplace: false),
      onReplace: () => _openFind(showReplace: true),
      child: Scaffold(
        body: Column(
          children: [
            _docToolbar(
              theme,
              settings,
              canUndo,
              canRedo,
              documentTlp,
              docStyleName,
            ),
            Divider(
              height: 1,
              thickness: 1,
              color: theme.colorScheme.outlineVariant,
            ),
            if (_find.visible) _findBar(),
            Expanded(
              child: DocumentImageScope(
                projectPath: _documentProjectPath(ref),
                child: LayoutBuilder(
                  builder: (context, constraints) => switch (_viewMode) {
                    _DocViewMode.visual => _visualLayout(
                      theme,
                      source,
                      constraints,
                      tlp: documentTlp,
                      fields: fields,
                    ),
                    _DocViewMode.source => _sourceLayout(
                      theme,
                      source,
                      constraints,
                      tlp: documentTlp,
                      fields: fields,
                    ),
                    _DocViewMode.pages => _documentPagesLayout(
                      context,
                      ref,
                      theme,
                      source,
                      style: _styleProfile,
                      projectPath: _documentProjectPath(ref),
                      tlp: documentTlp,
                      fields: fields,
                    ),
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Wissel van weergave — en neem je plek in de tekst mee.
  ///
  /// Wisselen doe je omdat je op één plek iets in de bron wilt zien of zetten.
  /// Kwam je bovenaan uit, dan moest je je plek in een lang document opnieuw
  /// zoeken en werd de bronstand iets om te vermijden (#1566). De andere kant
  /// op regelt de visuele editor zelf: die leest bij het openen de cursor van
  /// de bron-controller.
  void _changeViewMode(_DocViewMode mode) {
    if (mode == _viewMode) return;
    // De gebruiker kiest Visueel, maar de bron bevat een constructie die de
    // rijke-tekstlaag niet verliesvrij aankan. In plaats van de visuele modus
    // te openen en daarin stilletjes terug te vallen op brontekst, blijven we
    // in de Bron-modus en wijzen we de probleemregel aan — dat is waar de
    // gebruiker iets aan kan doen.
    if (mode == _DocViewMode.visual) {
      final body = _controller.text;
      if (!markdownRoundTripsVisually(body)) {
        _autoFallbackToSource(body);
        return;
      }
    }
    if (_viewMode == _DocViewMode.visual) {
      final text = _controller.text;
      final offset = MarkdownCaretMap.of(
        text,
      ).sourceOffsetOf(_visualCaret).clamp(0, text.length);
      // Alleen de cursor verzet, geen bewerking: de luisteraar mag hier niets
      // naar de notifier schrijven.
      _applyingExternal = true;
      _controller.selection = TextSelection.collapsed(offset: offset);
      _applyingExternal = false;
    }
    setState(() => _viewMode = mode);
    if (mode != _DocViewMode.pages) {
      // Het schrijfvlak bestaat pas ná deze opbouw; focussen kan dus niet
      // eerder, en zonder focus schuift het de cursor niet in beeld — dan zou
      // de cursor wel goed staan maar buiten het venster.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _editorFocus.requestFocus();
      });
    }
  }

  /// Wissel automatisch naar de Bron-modus en plaats de cursor op de eerste
  /// regel die de visuele editor niet aankan. Toont een snackbar die zegt
  /// *wat* er mis is en op welke regel, en scrollt naar de probleemregel.
  void _autoFallbackToSource(String body) {
    final hit = firstVisualLimitation(body);
    // Direct, zonder door [_changeViewMode] — we zijn al aan het verlaten.
    setState(() => _viewMode = _DocViewMode.source);
    if (hit == null) return;
    final lines = body.split('\n');
    final offset = lines
        .take(hit.lineIndex)
        .fold<int>(0, (sum, line) => sum + line.length + 1);
    _applyingExternal = true;
    _controller.selection = TextSelection.collapsed(
      offset: offset.clamp(0, body.length),
    );
    _applyingExternal = false;
    final l10n = context.l10n;
    final lineNo = hit.lineIndex + 1;
    final message = switch (hit.limitation) {
      MarkdownVisualLimitation.rawHtml =>
        l10n
            .d(
              'Regel {n} bevat HTML-commentaar of HTML-tags. De visuele editor kan dit niet weergeven — Bron-modus is geactiveerd.',
            )
            .replaceAll('{n}', '$lineNo'),
      MarkdownVisualLimitation.escapedPunctuation =>
        l10n
            .d(
              'Regel {n} bevat ontsnapte leestekens (zoals \\*). De visuele editor kan dit niet verliesvrij weergeven — Bron-modus is geactiveerd.',
            )
            .replaceAll('{n}', '$lineNo'),
      MarkdownVisualLimitation.looseTableLine =>
        l10n
            .d(
              'Regel {n} is een losse tabelregel buiten een tabelblok. De visuele editor kan dit niet weergeven — Bron-modus is geactiveerd.',
            )
            .replaceAll('{n}', '$lineNo'),
    };
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _editorFocus.requestFocus();
      ScaffoldMessenger.maybeOf(
        context,
      )?.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  /// Dubbelklik op een gerenderde grafiek → de volwaardige [ChartEditor] in een
  /// dialoog. Zie [_editDocumentChart]; hier alleen de doorgeefluik-methode,
  /// zodat de weergave hem als callback kan meegeven.
  Future<void> _editChart(int chartOrdinal, String block) =>
      _editDocumentChart(context, ref, chartOrdinal, block);

  /// Dubbelklik op een gerenderde tabel → de volwaardige [TableEditor] in een
  /// dialoog. Zie [_editDocumentTable]; hier alleen de doorgeefluik-methode.
  Future<void> _editTable(int tableOrdinal, List<String> rawRows) =>
      _editDocumentTable(context, ref, tableOrdinal, rawRows);

  /// Voeg [block] als een verse alinea in op de cursorpositie (of achteraan als
  /// er geen selectie is). De pure [insertBlockIntoSource] regelt de lege regels
  /// eromheen; hier zetten we de controller en de bron gelijk en plaatsen we de
  /// cursor ná het blok, zodat je meteen verder kunt typen. Een expliciete
  /// bewerking (`coalesceKey: null`) — geen samenvoeging met eerder typen.
  void _insertBlock(String block) {
    // In de visuele stand leeft de tekst in het Quill-document en staat de
    // cursor van de bron-controller stil op waar hij toevallig het laatst was.
    // Invoegen via de bron zette het blok daardoor onderaan het document in
    // plaats van waar je stond — wat leest als "er gebeurt niets". Daar vraagt
    // de editor het zelf, op zijn eigen cursor.
    if (_viewMode == _DocViewMode.visual &&
        markdownRoundTripsVisually(_controller.text)) {
      _requestVisualInsert(block: block);
      return;
    }
    final sel = _controller.selection;
    final (next, cursor) = insertBlockIntoSource(
      _controller.text,
      sel.start,
      sel.end,
      block,
    );
    // Zet de controller (met cursor ná het blok) los van de luisteraar en dien de
    // bewerking als een eigen stap in (`coalesceKey: null`), zodat een invoeging
    // niet met eerder typen samenvloeit in de ongedaan-maken-geschiedenis.
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _applyingExternal = false;
    _commitDocumentBody(ref, next, coalesceKey: null);
  }

  /// Vraagt de visuele editor om een invoeging op zíjn cursor: een blok, of een
  /// voetnoot (merkteken op de cursor, notenregel onderaan).
  ///
  /// Staat in de klasse en niet bij de andere invoegingen, omdat alleen een
  /// `State` zijn eigen [setState] mag aanroepen — een extensie ernaast niet.
  void _requestVisualInsert({String? block, String? footnoteLabel}) {
    _expectVisualInsert = true;
    setState(() {
      _pendingInsertBlock = block;
      _pendingFootnoteLabel = footnoteLabel;
      _insertSignal++;
    });
  }

  void _undo() => ref.read(documentProvider.notifier).undo();
  void _redo() => ref.read(documentProvider.notifier).redo();

  // --- Zoeken en vervangen -----------------------------------------------

  Widget _docToolbar(
    ThemeData theme,
    AppSettings settings,
    bool canUndo,
    bool canRedo,
    TlpLevel documentTlp,
    String? docStyleName,
  ) => _DocEditorToolbar(
    mode: _viewMode,
    onModeChanged: _changeViewMode,
    onInsertChart: _insertChart,
    onInsertPageBreak: _insertPageBreak,
    onInsertToc: _insertToc,
    onInsertFootnote: _insertFootnote,
    footnotesAtEnd:
        documentFootnotePlacement(_pageSetupSource(ref)) ==
        FootnotePlacement.document,
    onFootnotesAtEndChanged: (v) => _setFootnotePlacement(ref, v),
    onApplyChapterBreaks: () => applyChapterBreaksToDocument(context, ref),
    onInsertTable: _insertTable,
    onInsertTimeline: _insertTimeline,
    onInsertMermaid: _insertMermaid,
    onInsertImage: _insertImage,
    onPaste: () => unawaited(_smartPaste()),
    onUndo: canUndo ? _undo : null,
    onRedo: canRedo ? _redo : null,
    onFind: () => _openFind(showReplace: false),
    onExport: _export,
    onOpenSettings: () => SettingsDialog.show(
      context,
      initialSection: SettingsSection.appearance,
    ),
    onEditFields: () => unawaited(_editDocumentFields(context, ref)),
    onConvertToPresentation: _convertToPresentation,
    controller: _controller,
    editorFocus: _editorFocus,
    docTheme: _docSurfaceTheme(theme, _styleProfile),
    styleNames: [for (final p in settings.themeProfiles) p.name],
    currentStyleName: effectiveDocumentStyleName(settings, docStyleName),
    styleEnforced: settings.documentStyleEnforced,
    enforcedStyleName: settings.documentStyleEnforced
        ? settings.documentDefaultStyle
        : null,
    onStyleChanged: (name) => _setDocumentStyle(ref, name),
    tlp: documentTlp,
    onTlpChanged: (level) => _setDocumentTlp(ref, level),
    showPageBreaks: _showPageBreaks,
    onShowPageBreaksChanged: (v) => setState(() => _showPageBreaks = v),
    width: settings.documentEditorWidth,
    onWidthChanged: (v) => unawaited(
      ref.read(settingsProvider.notifier).setDocumentEditorWidth(v),
    ),
    zoom: settings.documentEditorZoom,
    onZoomChanged: (zoom) => _setDocumentZoom(ref, zoom),
  );

  Widget _findBar() => MarkdownFindBar(
    key: ValueKey('doc-find-${_find.showReplace}'),
    query: _find.query,
    replace: _find.replacement,
    caseSensitive: _find.caseSensitive,
    showReplace: _find.showReplace,
    matchCount: _find.matchCount,
    matchIndex: _find.matchIndex,
    onQueryChanged: _find.onQueryFieldChanged,
    onReplaceChanged: _find.setReplacement,
    onCaseSensitiveChanged: _find.setCaseSensitive,
    onNext: _find.next,
    onPrevious: _find.previous,
    onReplaceCurrent: _find.replaceCurrent,
    onReplaceAll: _find.replaceAll,
    onClose: _find.close,
  );

  void _openFind({required bool showReplace}) {
    // Pagina's is alleen-lezen: zoeken heeft daar geen schrijfvlak. Ga naar
    // Bron, waar de zoekbalk en de markering hun plek hebben.
    if (_viewMode == _DocViewMode.pages) {
      setState(() => _viewMode = _DocViewMode.source);
    }
    _find.open(showReplace: showReplace);
  }

  /// Spring naar een treffer. In Bron staat de selectie direct op de controller
  /// (met zoekmarkering eromheen); in Visueel leeft de cursor in Quill en
  /// vragen we [MarkdownNotesEditor] via een signaal om hem erheen te verplaatsen.
  void _jumpToMatch(TextMatchRange match) {
    if (_viewMode == _DocViewMode.source) {
      _controller.selection = TextSelection(
        baseOffset: match.start,
        extentOffset: match.end,
      );
      return;
    }
    setState(() {
      _findSelectionStart = match.start;
      _findSelectionEnd = match.end;
      _findSelectionSignal++;
    });
  }

  /// De Overzicht-rail. De rail zelf staat top-level in dezelfde library
  /// ([_documentOutlineRail]); het scherm levert alleen de stand en wat er bij
  /// een tik moet gebeuren.
  Widget _outlineRail(ThemeData theme, String source) => _documentOutlineRail(
    context,
    theme,
    source,
    collapsed: _outlineCollapsed,
    activeIndex: _activeOutlineIndex,
    onCollapsedChanged: (v) => setState(() => _outlineCollapsed = v),
    onSelect: _scrollToHeading,
  );
}

/// Bouwt de exportbundel voor het gekozen [profile], laat een pad kiezen met
/// de juiste extensie, en schrijft de export weg. Geeft het geschreven pad
/// terug, of `null` als de gebruiker de bestandskiezer wegklikte of het
/// schrijven mislukte.
Future<String?> _writeDocumentExport(
  WidgetRef ref,
  BuildContext context,
  PrivacyExportProfile profile,
  DocumentExportFormat format,
) async {
  final state = ref.read(documentProvider);
  final document = state.document;
  if (document == null) return null;
  // Exporteer de *body* (zonder het stijl-frontmatter-blok): de `theme:`-regel
  // is een OciDeck-aanwijzing, geen inhoud, en de stijl reist als het gekozen
  // profiel mee via `theme:` hieronder — niet als tekst in de uitvoer.
  // Strip ook eventueel gelekte front matter-regels uit de body — een bestand
  // dat door herhaald plakken meerdere blokken heeft, lekt ze anders als tekst
  // in de uitvoer (#1726).
  final body = stripLeadingFrontMatterLeakage(document.body);
  final filePath = state.filePath;
  final projectPath = filePath == null ? null : p.dirname(filePath);
  final settings = ref.read(settingsProvider);
  final exportSetup = effectiveDocumentPageSetup(settings, document.source);
  final fileService = ref.read(fileServiceProvider);
  final imageService = ref.read(imageServiceProvider);
  final markdownService = ref.read(markdownServiceProvider);
  final l10n = context.l10n;
  final messenger = ScaffoldMessenger.of(context);
  final title = document.fields['title'] ?? _documentTitle(body, filePath);
  final effectiveTheme =
      resolveDocumentStyleProfile(settings, document.styleName) ??
      fileService.activeProfileFor(projectPath: projectPath);

  // Bouw de bundel langs de audited projectiegrens. Vanaf hier raakt geen
  // uitvoerpad de rauwe bron nog aan.
  final bundle = await buildDocumentExportBundle(
    body,
    projectPath: projectPath,
    profile: profile,
    ownIdentity: OwnIdentity.fromLines(settings.privacyOwnIdentity),
    regions: settings.privacyRegions,
    disabledRules: settings.privacyDisabledRules,
    markdownService: markdownService,
    title: title,
    theme: effectiveTheme,
    tlp: document.tlp,
    fields: document.fields,
  );

  final classificationDecision =
      ClassificationEnforcementPolicy.fromAppSettings(
        settings,
      ).evaluate(bundle.audience.deck.tlp);
  if (!classificationDecision.allowed) {
    if (!context.mounted) return null;
    showErrorSnackBar(
      ScaffoldMessenger.of(context),
      l10n,
      exportBlockMessage(l10n, classificationDecision) ?? '',
    );
    return null;
  }

  // Op web kan de bestandskiezer geen pad vragen zonder de bytes al te hebben
  // — de browser wil de bytes up front als download. Op desktop kiezen we eerst
  // een pad, dan schrijft writeDocumentExport daar atomisch naartoe.
  final String? outputPath;
  final String? webFileName;
  if (deliversByDownload) {
    outputPath = null;
    webFileName = suggestedDocumentExportFileName(
      title: bundle.audience.deck.title,
      format: format,
      profile: profile,
      redactedLabel: l10n.d('geredigeerd'),
      fullLabel: l10n.d('volledig'),
      fallbackLabel: l10n.d('document'),
    );
  } else {
    outputPath = await _pickDocumentExportPath(
      l10n,
      format: format,
      profile: profile,
      title: bundle.audience.deck.title,
      projectPath: projectPath,
    );
    if (outputPath == null) return null;
    webFileName = null;
  }

  final delivered = await writeDocumentExport(
    bundle,
    format,
    html: MarpHtmlService(),
    enforcementPolicy: ClassificationEnforcementPolicy.fromAppSettings(
      settings,
    ),
    metadata: ExportDocumentMetadata(language: l10n.languageCode),
    embedImage: (src) => _embedDocumentExportImage(
      src,
      imageService: imageService,
      logoPath: effectiveTheme.logoPath,
      projectPath: projectPath,
    ),
    chapterPageBreak: settings.documentChapterPageBreak,
    // De export volgt dezelfde volgorde als het scherm: draagt het document
    // zelf een paginaopmaak, dan geldt die.
    cropMarks: settings.documentCropMarks,
    pageSize: exportSetup.size!,
    pageMargins: exportSetup.margins!,
    // Waar de noten komen staat in het document zelf; de kop erboven komt uit
    // de interfacetaal, want de converter kent geen vertalingen.
    footnotePlacement: documentFootnotePlacement(_pageSetupSource(ref)),
    footnotesTitle: l10n.d('Noten'),
    // Alleen de PDF-tak gebruikt deze waarden; de andere formaten laten ze
    // ongemoeid liggen.
    pdfLabels: documentPdfLabels(l10n),
    pdfFallbackFonts: format == DocumentExportFormat.pdf
        ? await loadPdfFallbackFonts()
        : const [],
    onPdfUnsupportedCharacters: (runes) =>
        warnAboutUnsupportedCharacters(messenger, l10n, runes),
    onPdfCoarseLogo: (logo) => warnAboutCoarseLogo(messenger, l10n, logo),
    onPdfTablesTooWide: (count) =>
        warnAboutTablesTooWide(messenger, l10n, count),
    renderMermaid: renderMermaidForPdf,
    renderMath: renderMathForPdf,
    outputPath: outputPath,
    sourcePath: filePath,
    webFileName: webFileName,
  );
  // Op web is `null` hier de mislukte download — de andere twee null-redenen
  // (geen pad, doel is de bron) horen bij het schijfpad. Zonder deze melding
  // sloot de dialoog terug naar zijn opties zonder één woord, terwijl de
  // gebruiker net op Exporteren had gedrukt (#1902).
  if (delivered == null && deliversByDownload) {
    showErrorSnackBar(
      messenger,
      l10n,
      l10n.d(
        'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.',
      ),
    );
  }
  return delivered;
}

/// Kiest het uitvoerpad voor een documentexport. De extensie én het profiel
/// staan in de naam, zodat een verwisseling (volledig ↔ geredigeerd) zichtbaar
/// is. `null` wanneer de gebruiker de bestandskiezer wegklikt. Top-level zodat
/// het bewerkscherm zelf onder zijn regelplafond blijft.
Future<String?> _pickDocumentExportPath(
  AppLocalizations l10n, {
  required DocumentExportFormat format,
  required PrivacyExportProfile profile,
  required String title,
  required String? projectPath,
}) async {
  final fileName = suggestedDocumentExportFileName(
    title: title,
    format: format,
    profile: profile,
    redactedLabel: l10n.d('geredigeerd'),
    fullLabel: l10n.d('volledig'),
    fallbackLabel: l10n.d('document'),
  );
  final ext = fileName.split('.').last;
  final dest = await pickDocumentExportDestination(
    dialogTitle: l10n.t('export'),
    fileName: fileName,
    initialDirectory: projectPath,
  );
  if (dest == null) return null;
  return withExtension(dest, '.$ext');
}

/// Afbeeldingen ingesloten als data:-URI, begrensd binnen de projectmap —
/// dezelfde regel als de deck-HTML-export: een pad buiten de map wordt
/// geweigerd, niet gevolgd. Top-level zodat het bewerkscherm zelf onder zijn
/// regelplafond blijft.
Future<String?> _embedDocumentExportImage(
  String src, {
  required ImageService imageService,
  required String? logoPath,
  required String? projectPath,
}) async {
  final bytes = src == logoPath
      ? await readStyleLogoBytes(src, projectPath: projectPath)
      : await imageService.readSlideImageBytes(src, projectPath: projectPath);
  if (bytes == null) return null;
  final encoded = encodeForHtmlEmbed(bytes, src);
  return encoded == null ? null : htmlImageDataUri(encoded);
}

Widget _styledDocumentSurface(
  ThemeProfile? profile,
  Widget editor, {
  required TlpLevel tlp,
  required Map<String, String> fields,
}) {
  final chromeProfile = profile ?? const ThemeProfile();
  if (!_hasDocumentChrome(chromeProfile, tlp)) return editor;
  return ColoredBox(
    color: AppTheme.parseHexColor(chromeProfile.slideBackgroundColor),
    child: Column(
      children: [
        DocumentChromeBand(
          profile: chromeProfile,
          header: true,
          tlp: tlp,
          fields: fields,
        ),
        Expanded(child: editor),
        DocumentChromeBand(
          profile: chromeProfile,
          header: false,
          tlp: tlp,
          fields: fields,
        ),
      ],
    ),
  );
}

Widget _styledDocumentBody(
  ThemeProfile? profile,
  Widget body, {
  required TlpLevel tlp,
  required Map<String, String> fields,
}) {
  final chromeProfile = profile ?? const ThemeProfile();
  if (!_hasDocumentChrome(chromeProfile, tlp)) return body;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DocumentChromeBand(
        profile: chromeProfile,
        header: true,
        tlp: tlp,
        fields: fields,
      ),
      body,
      DocumentChromeBand(
        profile: chromeProfile,
        header: false,
        tlp: tlp,
        fields: fields,
      ),
    ],
  );
}

bool _hasDocumentChrome(ThemeProfile profile, TlpLevel tlp) =>
    profile.effectiveDocumentLogoPath?.trim().isNotEmpty == true ||
    profile.documentHeaderText.trim().isNotEmpty ||
    profile.documentFooterText.trim().isNotEmpty ||
    profile.documentShowPageNumbers ||
    tlp != TlpLevel.none;

/// De documenttitel voor export en conversie: de eerste `# `-kop buiten een
/// fenced codeblock, anders de bestandsnaam zonder extensie, anders leeg.
/// Top-level zodat het bewerkscherm zelf onder zijn regelplafond blijft.
String _documentTitle(String source, String? filePath) {
  final fence = RegExp(r'^\s*(```|~~~)');
  var fenced = false;
  for (final line in source.split('\n')) {
    if (fence.hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    final m = RegExp(r'^#\s+(.+)$').firstMatch(line.trim());
    if (m != null) return m.group(1)!.trim();
  }
  if (filePath != null) return p.basenameWithoutExtension(filePath);
  return '';
}

/// Het schrijfoppervlak-thema met het lettertype van de actieve documentstijl
/// ([fontFamily]) erin. Zonder stijl valt het terug op het app-lettertype, zodat
/// een plat document precies leest als voorheen.
MarkdownEditorTheme _docSurfaceTheme(ThemeData theme, ThemeProfile? profile) =>
    MarkdownEditorTheme.documentSurface(
      scheme: theme.colorScheme,
      fontFamily: profile?.fontFamily,
      profile: profile,
      // In de documentmodus schrijf je op een pagina, dus in de typografie van
      // die pagina — zie [MarkdownEditorTheme.documentTypography].
      documentTypography: true,
    );

Future<void> _editDocumentFields(BuildContext context, WidgetRef ref) async {
  final document = ref.read(documentProvider).document;
  if (document == null) return;
  final fields = await _showDocumentFieldsDialog(context, document.fields);
  if (fields == null || !context.mounted) return;
  ref
      .read(documentProvider.notifier)
      .edit(document.withFields(fields).source, coalesceKey: null);
}

/// Dien een nieuwe body in bij de notifier, met de stijl-frontmatter ervoor. De
/// editor bewerkt alleen de body; elke terugschrijf zet de frontmatter er weer
/// vóór zodat `document.source` byte-getrouw blijft.
void _commitDocumentBody(WidgetRef ref, String body, {String? coalesceKey}) {
  final frontMatter = ref.read(documentProvider).document?.frontMatter ?? '';
  ref
      .read(documentProvider.notifier)
      .edit(frontMatter + body, coalesceKey: coalesceKey);
}

/// Zet (of wis met `null`) de documentstijl. Een discrete ongedaan-stap;
/// [MarkdownDocument.withStyleName] raakt byte-chirurgisch alleen de `theme:`-
/// regel, dus 'Geen' op een document zonder stijl laat het byte-getrouw.
void _setDocumentStyle(WidgetRef ref, String? name) {
  final doc = ref.read(documentProvider).document;
  if (doc == null) return;
  ref
      .read(documentProvider.notifier)
      .edit(doc.withStyleName(name).source, coalesceKey: null);
}

TlpLevel _documentTlp(WidgetRef ref) => ref.watch(
  documentProvider.select((state) => state.document?.tlp ?? TlpLevel.none),
);

/// Eén bewuste classificatiekeuze is één ongedaan-stap. De broneditor krijgt
/// alleen de body en hoeft dus niet te verspringen wanneer de front matter wijzigt.
void _setDocumentTlp(WidgetRef ref, TlpLevel level) {
  final doc = ref.read(documentProvider).document;
  if (doc == null || doc.tlp == level) return;
  ref
      .read(documentProvider.notifier)
      .edit(doc.withTlp(level).source, coalesceKey: null);
}

/// De weergavemodus van de documenteditor. Manieren om naar hetzelfde document
/// te kijken, nooit een extra renderpad (DOCUMENT_MODE.md §2.1): de bron als
/// tekst, de weergave als hoofdoppervlak, of diezelfde weergave verdeeld over
/// echte pagina's. [pages] gebruikt letterlijk dezelfde `DocumentMarkdownView`
/// als de andere twee — alleen op vellen van de gekozen maat, met de marges en
/// de pagina-einden erin. Een eigen tekenaar voor pagina's zou precies de
/// afwijking opleveren die §2.1 verbiedt.
enum _DocViewMode { visual, source, pages }

class _DocSmartPasteIntent extends Intent {
  const _DocSmartPasteIntent();
}
