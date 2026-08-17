import '../services/document_page_setup.dart';
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_quill/flutter_quill.dart' show EditorState;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../l10n/app_localizations.dart';
import '../l10n/page_size_localization.dart';
import '../models/chart.dart';
import '../models/markdown_outline.dart';
import '../models/page_size.dart';
import '../models/privacy_disposition.dart';
import '../models/settings.dart';
import '../models/slide.dart';
import '../services/caption_service.dart';
import '../services/description_service.dart';
import '../services/document_deck_bridge.dart';
import '../services/document_export_service.dart';
import '../services/document_style.dart';
import '../services/export_bundle.dart';
import '../services/export_metadata.dart';
import '../services/file_service.dart';
import '../services/html_image_embedder.dart';
import '../services/image_service.dart' show ImageImportFailure;
import '../services/markdown_table_codec.dart';
import '../services/marp_html_service.dart';
import '../services/privacy/privacy_own_identity.dart';
import '../platform/platform_features.dart';
import '../state/deck_provider.dart'
    show fileServiceProvider, imageServiceProvider, markdownServiceProvider;
import '../state/document_provider.dart';
import '../state/settings_provider.dart' show settingsProvider;
import '../state/tabs_provider.dart';
import '../theme/app_theme.dart';
import '../utils/doc_link.dart' show headingSlug;
import '../utils/error_snackbar.dart';
import '../utils/image_search_paths.dart';
import '../utils/log.dart';
import '../utils/markdown_blocks.dart';
import '../utils/markdown_paste_cleanup.dart';
import '../utils/markdown_visual_compatibility.dart'
    show markdownRoundTripsVisually;
import '../utils/table_clipboard.dart';
import '../utils/user_facing_error.dart';
import 'dialogs/convert_to_presentation_dialog.dart';
import 'dialogs/document_export_dialog.dart';
import 'dialogs/image_carousel_picker.dart';
import 'dialogs/package_encrypt_dialog.dart';
import 'dialogs/settings_dialog.dart';
import 'document_page_chrome.dart';
import 'editors/_editor_field.dart' show reportImageImportFailure;
import 'editors/chart_editor.dart';
import 'editors/embed_editor_dialog.dart';
import 'editors/table_editor.dart';
import 'markdown_editor/markdown_editor.dart';
import 'reader/document_markdown_view.dart';
import 'reader/paged_document_view.dart';
import 'reader/writing_page_breaks.dart';
import 'shell/document_save_actions.dart';

part 'parts/document_editor_toolbar.dart';
part 'parts/document_editor_layouts.dart';
part 'parts/document_source_rewrites.dart';

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
  late final TextEditingController _controller;
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

  /// Waar tussen het aanvragen van zo'n invoeging en de controllerwijziging die
  /// eruit volgt: die ene wijziging is een eigen bewerking, geen voortzetting
  /// van het typen ervoor.
  bool _expectVisualInsert = false;

  /// De actieve documentstijl. Alleen documentoppervlakken lezen hem; de rauwe
  /// Markdownbron en de presentatie-editor houden hun eigen sobere chrome.
  ThemeProfile? _styleProfile;

  @override
  void initState() {
    super.initState();
    // De editor bewerkt de *body*: de bron zonder het leidende stijl-frontmatter-
    // blok. De stijl (`theme:`) leeft in de frontmatter en wordt beheerd door de
    // Stijl-kiezer, niet als tekst getypt. Elke terugschrijf zet de frontmatter
    // er weer vóór, zodat `document.source` byte-getrouw blijft.
    _controller = TextEditingController(
      text: ref.read(documentProvider).document?.body ?? '',
    );
    // Eén luisteraar vangt élke body-wijziging in de controller — typen én de
    // opmaak-knoppenbalk (die de controller rechtstreeks muteert en dus geen
    // onChanged afvuurt). Zo stroomt alles langs dezelfde weg naar de notifier.
    _controller.addListener(_onControllerChanged);
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
    ref
        .read(documentProvider.notifier)
        .edit(doc.frontMatter + body, coalesceKey: ownStep ? null : 'doc');
  }

  void _setActiveOutlineIndex(int active) {
    if (active == _activeOutlineIndex) return;
    // Nooit setState vanuit een controller/Quill-listener tijdens build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || active == _activeOutlineIndex) return;
      setState(() => _activeOutlineIndex = active);
    });
  }

  /// Markeer in de Overzicht-rail de kop waaronder de markdown-caret staat.
  void _syncOutlineToMarkdownCaret() {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    _setActiveOutlineFromMarkdownOffset(sel.baseOffset);
  }

  /// Quill-caret → actieve Overzicht-kop via titelvolgorde in de platte tekst.
  void _syncOutlineToVisualCaret(String plain, int plainOffset) {
    _setActiveOutlineIndex(
      activeOutlineIndexInPlainText(
        buildMarkdownOutline(_controller.text),
        plain,
        plainOffset,
      ),
    );
  }

  void _setActiveOutlineFromMarkdownOffset(int offset) {
    _setActiveOutlineIndex(
      activeOutlineIndexForOffset(
        buildMarkdownOutline(_controller.text),
        offset,
      ),
    );
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
      onExport: (profile, format) => _writeExport(profile, format),
    );
  }

  /// Bouwt de exportbundel voor het gekozen [profile], laat een pad kiezen met
  /// de juiste extensie, en schrijft de export weg. Geeft het geschreven pad
  /// terug, of `null` als de gebruiker de bestandskiezer wegklikte of het
  /// schrijven mislukte.
  Future<String?> _writeExport(
    PrivacyExportProfile profile,
    DocumentExportFormat format,
  ) async {
    final state = ref.read(documentProvider);
    // Exporteer de *body* (zonder het stijl-frontmatter-blok): de `theme:`-regel
    // is een OciDeck-aanwijzing, geen inhoud, en de stijl reist als het gekozen
    // profiel mee via `theme:` hieronder — niet als tekst in de uitvoer.
    final body = state.document?.body ?? '';
    final filePath = state.filePath;
    final projectPath = filePath == null ? null : p.dirname(filePath);
    final settings = ref.read(settingsProvider);
    final exportSetup = effectiveDocumentPageSetup(
      settings,
      state.document?.source ?? '',
    );
    final fileService = ref.read(fileServiceProvider);
    final imageService = ref.read(imageServiceProvider);
    final markdownService = ref.read(markdownServiceProvider);
    final l10n = context.l10n;
    final title = _documentTitle(body, filePath);
    final effectiveTheme =
        resolveDocumentStyleProfile(settings, state.document?.styleName) ??
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
    );

    if (format == DocumentExportFormat.ocideck) {
      return _writePackageExport(bundle);
    }

    // Kies een pad. De extensie én het profiel staan in de naam, zodat een
    // verwisseling (volledig ↔ geredigeerd) zichtbaar is.
    final ext = switch (format) {
      DocumentExportFormat.md => 'md',
      DocumentExportFormat.html => 'html',
      DocumentExportFormat.latex => 'tex',
      DocumentExportFormat.ocideck => 'ocideck',
    };
    final tag = profile == PrivacyExportProfile.redacted
        ? l10n.d('geredigeerd')
        : l10n.d('volledig');
    final base = _safeExportName(title.isEmpty ? l10n.d('document') : title);
    final dest = await pickDocumentExportDestination(
      dialogTitle: l10n.t('export'),
      fileName: '$base-$tag.$ext',
      initialDirectory: projectPath,
    );
    if (dest == null) return null;
    final outputPath = dest.endsWith('.$ext') ? dest : '$dest.$ext';

    // Afbeeldingen ingesloten als data:-URI, begrensd binnen de projectmap —
    // dezelfde regel als de deck-HTML-export: een pad buiten de map wordt
    // geweigerd, niet gevolgd.
    Future<String?> embed(String src) async {
      final bytes = src == effectiveTheme.logoPath
          ? await readStyleLogoBytes(src, projectPath: projectPath)
          : await imageService.readSlideImageBytes(
              src,
              projectPath: projectPath,
            );
      if (bytes == null) return null;
      final encoded = encodeForHtmlEmbed(bytes, src);
      return encoded == null ? null : htmlImageDataUri(encoded);
    }

    return writeDocumentExport(
      bundle,
      format,
      html: MarpHtmlService(),
      // De documentstijl stuurt de export: het opgeloste profiel (afdwingen →
      // per-document `theme:` → standaard), en anders het projectprofiel zoals
      // voorheen — zo verandert een plat document zonder stijl niets.
      theme: bundle.audience.deck.themeProfile,
      metadata: ExportDocumentMetadata(
        title: title,
        language: l10n.languageCode,
      ),
      embedImage: embed,
      chapterPageBreak: settings.documentChapterPageBreak,
      // De export volgt dezelfde volgorde als het scherm: draagt het document
      // zelf een paginaopmaak, dan geldt die.
      pageSize: exportSetup.size!,
      pageMargins: exportSetup.margins!,
      outputPath: outputPath,
    );
  }

  /// Exporteer het geprojecteerde document als `.ocideck`-pakket (markdown +
  /// assets), met dezelfde versleutelingsdialoog als bij een presentatie.
  Future<String?> _writePackageExport(ExportBundle bundle) async {
    if (!mounted) return null;
    final choice = await PackageEncryptDialog.show(context);
    if (choice == null || !mounted) return null;
    final password = choice.encrypt ? choice.password : null;
    final fileService = ref.read(fileServiceProvider);
    final l10n = context.l10n;
    final deck = bundle.audience.deck;
    try {
      if (isWebPlatform) {
        return await fileService.downloadPackage(deck, password: password);
      }
      final picked = await fileService.pickPackageDestination(deck);
      if (picked == null) return null;
      await fileService.exportPackage(deck, picked, password: password);
      return picked;
    } catch (e) {
      logError('DocumentEditor: pakketexport mislukt', e);
      if (!mounted) return null;
      showErrorSnackBar(
        ScaffoldMessenger.of(context),
        l10n,
        '${l10n.d('Export mislukt:')} ${userFacingError(l10n, e)}',
      );
      return null;
    }
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
    // kopie; er reist geen zegel mee.
    final deck = DocumentDeckBridge.documentToDeck(body, title: title);
    final confirmed = await ConvertToPresentationDialog.show(
      context,
      slideCount: deck.slides.length,
    );
    if (confirmed != true || !mounted) return;
    ref.read(tabsProvider.notifier).newDeckInNewTab(title, slides: deck.slides);
  }

  /// Scroll / spring naar de aangeklikte kop uit de Overzicht-rail.
  ///
  /// Visueel: cursor in de notes-editor (markdown-offset of Quill-titel).
  /// Bron: cursor in de bron-editor + anker in de live weergave (docs-lezer-
  /// mechanisme).
  void _scrollToHeading(MarkdownOutlineEntry entry) {
    final source = ref.read(documentProvider).document?.source ?? '';
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
    final index = DocumentMarkdownView.headingBlockIndex(
      source,
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
    // Wanneer de body van búiten de editor verandert (ongedaan maken/opnieuw),
    // de controller bijwerken. Bij gewoon typen is de body na de `edit` al gelijk
    // aan de controllertekst, dus dan doet dit niets — geen terugkoppellus. Een
    // stijlwijziging raakt alleen de frontmatter, niet de body, dus die triggert
    // dit terecht niet.
    ref.listen(documentProvider.select((s) => s.document?.body ?? ''), (
      _,
      body,
    ) {
      if (body != _controller.text) {
        _applyingExternal = true;
        _controller.value = TextEditingValue(
          text: body,
          selection: TextSelection.collapsed(offset: body.length),
        );
        _applyingExternal = false;
      }
    });
    final source = ref.watch(
      documentProvider.select((s) => s.document?.body ?? ''),
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
    final styleProfile = resolveDocumentStyleProfile(settings, docStyleName);
    _styleProfile = styleProfile;
    final theme = Theme.of(context);
    return Actions(
      actions: {
        UndoTextIntent: CallbackAction<UndoTextIntent>(
          onInvoke: (_) {
            _undo();
            return null;
          },
        ),
        RedoTextIntent: CallbackAction<RedoTextIntent>(
          onInvoke: (_) {
            _redo();
            return null;
          },
        ),
      },
      child: CallbackShortcuts(
        bindings: {
          // Cmd op macOS, Ctrl elders — net als het opslaan van een deck.
          const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
              unawaited(_save()),
          const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): _undo,
          const SingleActivator(LogicalKeyboardKey.keyZ, control: true): _undo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            meta: true,
            shift: true,
          ): _redo,
          const SingleActivator(
            LogicalKeyboardKey.keyZ,
            control: true,
            shift: true,
          ): _redo,
          const SingleActivator(LogicalKeyboardKey.keyY, control: true): _redo,
        },
        child: Scaffold(
          body: Column(
            children: [
              _DocEditorToolbar(
                mode: _viewMode,
                onModeChanged: (m) => setState(() => _viewMode = m),
                onInsertChart: _insertChart,
                onInsertPageBreak: _insertPageBreak,
                onInsertToc: _insertToc,
                onInsertTable: _insertTable,
                onInsertMermaid: _insertMermaid,
                onInsertImage: _insertImage,
                onPaste: () => unawaited(_smartPaste()),
                onUndo: canUndo ? _undo : null,
                onRedo: canRedo ? _redo : null,
                onExport: _export,
                onOpenSettings: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.presentation,
                ),
                onConvertToPresentation: _convertToPresentation,
                controller: _controller,
                editorFocus: _editorFocus,
                docTheme: _docSurfaceTheme(theme, _styleProfile),
                styleNames: [for (final p in settings.themeProfiles) p.name],
                currentStyleName: effectiveDocumentStyleName(
                  settings,
                  docStyleName,
                ),
                styleEnforced: settings.documentStyleEnforced,
                enforcedStyleName: settings.documentStyleEnforced
                    ? settings.documentDefaultStyle
                    : null,
                onStyleChanged: (name) => _setDocumentStyle(ref, name),
                showPageBreaks: _showPageBreaks,
                onShowPageBreaksChanged: (v) =>
                    setState(() => _showPageBreaks = v),
              ),
              Divider(
                height: 1,
                thickness: 1,
                color: theme.colorScheme.outlineVariant,
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => switch (_viewMode) {
                    _DocViewMode.visual => _visualLayout(
                      theme,
                      source,
                      constraints,
                    ),
                    _DocViewMode.source => _sourceLayout(
                      theme,
                      source,
                      constraints,
                    ),
                    _DocViewMode.pages => _pagesLayout(theme, source),
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Dubbelklik op een gerenderde grafiek → de volwaardige [ChartEditor] in een
  /// dialoog (dezelfde editor als een dia, met een wegwerp-[Slide] om zijn bron
  /// vast te houden). 'Toepassen' schrijft het bewerkte ```chart-blok terug op
  /// zijn plek in de bron; de weergave hertekent mee. DOCUMENT_MODE.md §4.2.
  Future<void> _editChart(int chartOrdinal, String block) async {
    var edited = block;
    final slide = Slide.create(SlideType.chart).copyWith(customMarkdown: block);
    final apply = await showEmbedEditorDialog(
      context,
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => edited = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    final body = ref.read(documentProvider).document?.body ?? '';
    final next = replaceNthChartBlock(body, chartOrdinal, edited);
    if (next != body) _commitDocumentBody(ref, next, coalesceKey: null);
  }

  /// Dubbelklik op een gerenderde tabel → de volwaardige [TableEditor] in een
  /// dialoog. Kop + scheidingsrij + body worden via [decodeMarkdownTableWithAlignment]
  /// ontleed tot een celraster mét per-kolomuitlijning en in een wegwerp-[Slide]
  /// gezet; 'Toepassen' serialiseert raster én uitlijning terug naar een
  /// GFM-tabel en vervangt precies dat tabelblok in de bron. DOCUMENT_MODE.md §4.2.
  Future<void> _editTable(int tableOrdinal, List<String> rawRows) async {
    final body = ref.read(documentProvider).document?.body ?? '';
    // rawRows draagt de scheidingsrij niet; die haalt de uitlijning. Lees daarom
    // het volledige tabelblok (kop + scheiding + body) uit de body.
    final range = DocumentMarkdownView.nthTableBlockRange(body, tableOrdinal);
    final tableLines = range == null
        ? rawRows
        : body.split('\n').sublist(range[0], range[1]);
    final decoded = decodeMarkdownTableWithAlignment(tableLines);
    var editedRows = decoded.rows;
    var editedAligns = decoded.alignments;
    final slide = Slide.create(SlideType.table).copyWith(
      tableRows: decoded.rows,
      tableColumnAlignments: decoded.alignments,
    );
    final apply = await showEmbedEditorDialog(
      context,
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        documentContext: true,
        onUpdate: (s) {
          editedRows = s.tableRows;
          editedAligns = s.tableColumnAlignments;
        },
      ),
    );
    if (apply != true || !mounted) return;
    final next = replaceNthTableBlock(
      body,
      tableOrdinal,
      encodeMarkdownTable(editedRows, alignments: editedAligns),
    );
    if (next != body) _commitDocumentBody(ref, next, coalesceKey: null);
  }

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
      _expectVisualInsert = true;
      setState(() {
        _pendingInsertBlock = block;
        _insertSignal++;
      });
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

  /// Slim plakken: herkent afbeelding → `![](…)`, spreadsheet/tabel → GFM-
  /// tabel, anders opgeschoonde tekst. Geeft `true` als de plak is afgehandeld
  /// (dan mag de editor niet nóg eens plakken).
  Future<bool> _smartPaste() async {
    final state = ref.read(documentProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final imageService = ref.read(imageServiceProvider);
    final outcome = await imageService.pasteImageDetailed(
      projectPath: projectPath,
    );
    if (outcome.path != null) {
      _insertBlock('![](${outcome.path})');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Afbeelding geplakt'))),
        );
      }
      return true;
    }
    // Geen afbeelding: stil als "geen klembordbeeld", anders de echte fout.
    if (outcome.failure != null &&
        outcome.failure != ImageImportFailure.noClipboardImage &&
        mounted) {
      reportImageImportFailure(context, outcome.failure);
      return true;
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return false;

    final table = parseClipboardTable(raw);
    if (table != null && table.isNotEmpty) {
      _insertBlock(encodeMarkdownTable(table));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Tabel geplakt'))),
        );
      }
      return true;
    }

    final text = sanitizeMarkdownPaste(raw);
    final sel = _controller.selection;
    final start = sel.isValid ? sel.start : _controller.text.length;
    final end = sel.isValid ? sel.end : start;
    final next = _controller.text.replaceRange(start, end, text);
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    _applyingExternal = false;
    _commitDocumentBody(ref, next, coalesceKey: 'doc');
    return true;
  }

  void _undo() => ref.read(documentProvider.notifier).undo();
  void _redo() => ref.read(documentProvider.notifier).redo();

  /// Voeg een verse grafiek in: dezelfde [ChartEditor] als een dia (met een
  /// wegwerp-[Slide]), en bij 'Toepassen' een ```chart-blok op de cursorpositie.
  /// Identiek aan het dia-mechanisme — geen tweede grafiekweg (DOCUMENT_MODE.md
  /// §4.2). Zonder ingevulde data blijft het een geldig, later invulbaar blok.
  Future<void> _insertChart() async {
    final slide = Slide.create(SlideType.chart);
    var spec = ChartSpec.parse(slide.customMarkdown).toBlock();
    final apply = await showEmbedEditorDialog(
      context,
      ChartEditor(
        slide: slide,
        themeAnimationDurationMs: 0,
        nestedInScrollView: true,
        onUpdate: (s) => spec = s.customMarkdown,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock('```chart\n$spec\n```');
  }

  /// Voeg een verse tabel in: de [TableEditor] met een leeg 2×2-raster, en bij
  /// 'Toepassen' een GFM-pijptabel op de cursorpositie.
  Future<void> _insertTable() async {
    final slide = Slide.create(SlideType.table);
    var rows = slide.tableRows;
    final apply = await showEmbedEditorDialog(
      context,
      TableEditor(
        slide: slide,
        nestedInScrollView: true,
        documentContext: true,
        onUpdate: (s) => rows = s.tableRows,
      ),
    );
    if (apply != true || !mounted) return;
    _insertBlock(encodeMarkdownTable(rows));
  }

  /// Voeg een verse ```mermaid-fence in met een minimaal, taal-neutraal
  /// startdiagram (knoop-id's, geen tekst om te vertalen). Bewerken gaat via de
  /// bron — de dubbelklik is voor mermaid bewust overgeslagen (DOCUMENT_MODE.md).
  void _insertMermaid() =>
      _insertBlock('```mermaid\nflowchart TD\n  A --> B\n```');

  /// Voeg een pagina-einde in: een `---`-scheiding (een gewone Markdown-thematische
  /// breuk). Een document blijft doorlopend op het scherm; de export (HTML/PDF/
  /// LaTeX) maakt er een echt nieuw blad van. Draagbaar: elke Markdown-lezer toont
  /// `---` als scheidingslijn.
  void _insertPageBreak() => _insertBlock('---');

  /// Feature 4: voeg een inhoudsopgave-marker in op de cursorpositie. De
  /// marker `<!-- toc -->` is een HTML-commentaar dat elke vreemde
  /// Markdown-lezer negeert; OciDeck regenereert de TOC op deze plek bij
  /// export. De gegenereerde inhoud wordt niet in de `.md` opgeslagen.
  void _insertToc() => _insertBlock('<!-- toc -->');

  /// Voeg een afbeelding in via de carrousel (bibliotheken + open presentaties
  /// + Bladeren…). De gekozen file gaat door [ImageService.importIntoDeck]
  /// (grootte-cap, magic-bytes, kopie naar `images/` of staging) en landt als
  /// `![…](…)` op de cursorpositie — geen aparte assetweg naast de dia-import.
  Future<void> _insertImage() async {
    final state = ref.read(documentProvider);
    final settings = ref.read(settingsProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final tabs = ref.read(tabsProvider).tabs;
    // Zelfde afbeeldingspool als presentatiemodus: open decks + bibliotheek.
    // Recente presentaties leveren hun images/logos (niet de hele map).
    final searchPaths = documentImageSearchPaths(
      projectPath,
      settings.libraryPaths,
      openDeckProjectPaths: [
        for (final tab in tabs)
          ?tab.deckNotifierOrNull?.currentState.deck?.projectPath,
      ],
      recentPresentationDirectories: [
        for (final recent in settings.recentFiles)
          if (recent.kind.isPresentation) p.dirname(recent.path),
      ],
    );
    final picked = await ImageCarouselPicker.show(
      context,
      searchPaths: searchPaths,
      captionService: ref.read(captionServiceProvider),
      descriptionService: ref.read(descriptionServiceProvider),
      // Alleen deck-tabs: documenttabs hebben geen deckNotifier (gooit anders).
      openDeckFiles: [
        for (final tab in tabs) ?tab.deckNotifierOrNull?.currentState.filePath,
      ],
    );
    if (picked == null || !mounted) return;
    final reference = await ref
        .read(imageServiceProvider)
        .importIntoDeck(picked.path, projectPath: projectPath);
    if (!mounted) return;
    final alt = markdownImageAlt(picked.caption);
    _insertBlock('![$alt]($reference)');
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

Widget _styledDocumentSurface(ThemeProfile? profile, Widget editor) {
  if (profile == null || !_hasDocumentChrome(profile)) return editor;
  return ColoredBox(
    color: AppTheme.parseHexColor(profile.slideBackgroundColor),
    child: Column(
      children: [
        DocumentChromeBand(profile: profile, header: true),
        Expanded(child: editor),
        DocumentChromeBand(profile: profile, header: false),
      ],
    ),
  );
}

Widget _styledDocumentBody(ThemeProfile? profile, Widget body) {
  if (profile == null || !_hasDocumentChrome(profile)) return body;
  return Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      DocumentChromeBand(profile: profile, header: true),
      body,
      DocumentChromeBand(profile: profile, header: false),
    ],
  );
}

bool _hasDocumentChrome(ThemeProfile profile) =>
    profile.effectiveDocumentLogoPath?.trim().isNotEmpty == true ||
    profile.documentHeaderText.trim().isNotEmpty ||
    profile.documentFooterText.trim().isNotEmpty ||
    profile.documentShowPageNumbers;

/// De documenttitel voor export en conversie: de eerste `# `-kop, anders de
/// bestandsnaam zonder extensie, anders leeg. Top-level zodat het bewerkscherm
/// zelf onder zijn regelplafond blijft.
String _documentTitle(String source, String? filePath) {
  for (final line in source.split('\n')) {
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
