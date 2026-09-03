// Part of the document-editor library — see ../document_editor_screen.dart.
//
// De drie weergavestanden van de documenteditor: de bron naast de weergave,
// het document op echte pagina's, en het visuele schrijfvlak. Losgeknipt van
// document_editor_screen.dart omdat dat bestand twee keer op zijn regelplafond
// stuitte en elke toevoeging eerst een verhuizing kostte (#1509). Eén library,
// dus de standen gebruiken de staat van het scherm ongewijzigd.
part of '../document_editor_screen.dart';

/// De volledige bron van het document, mét frontmatter.
///
/// Het schrijfvlak krijgt `document.body` — de tekst zónder frontmatter, want
/// die hoort niet als tekst in de editor. Maar de paginaopmaak stáát in die
/// frontmatter, dus wie hem daar zoekt moet de hele bron hebben. Met de body
/// vond de app zijn eigen sleutels nooit terug: het speldje verscheen nooit, en
/// een document dat A4 had vastgelegd werd alsnog op de ingestelde maat
/// getoond. De bytes reisden mee, de app deed er niets mee.
///
/// Staat bewust top-level en niet op de staat: de klasse zat op haar plafond.
String _pageSetupSource(WidgetRef ref) =>
    ref.watch(documentProvider).document?.source ?? '';

/// De map waarin het document staat, voor het oplossen van een logo in de
/// kop- of voetband. `null` als het nog nergens is opgeslagen. Een padloos
/// conversie-document (presentatie → document) kan toch een projectPath hebben
/// die de map van het originele deck draagt (#1646).
String? _documentProjectPath(WidgetRef ref) {
  final state = ref.read(documentProvider);
  if (state.projectPath != null) return state.projectPath;
  final path = state.filePath;
  return path == null ? null : p.dirname(path);
}

/// De weergavestanden van [_DocumentEditorScreenState]. Een extensie op de
/// staat zelf (zelfde library), zodat de methoden ongewijzigd blijven werken —
/// hetzelfde patroon als de tabel-part van de documentweergave.
extension _DocumentEditorLayouts on _DocumentEditorScreenState {
  /// Markeer in de Overzicht-rail de kop waaronder de markdown-caret staat.
  void _syncOutlineToMarkdownCaret() {
    final sel = _controller.selection;
    if (!sel.isValid) return;
    _setActiveOutlineFromMarkdownOffset(sel.baseOffset);
  }

  /// Quill-caret → actieve Overzicht-kop via titelvolgorde in de platte tekst.
  void _syncOutlineToVisualCaret(String plain, int plainOffset) {
    _visualCaret = plainOffset;
    final sourceOffset = MarkdownCaretMap.of(
      _controller.text,
    ).sourceOffsetOf(plainOffset).clamp(0, _controller.text.length);
    if (_controller.selection !=
        TextSelection.collapsed(offset: sourceOffset)) {
      _applyingExternal = true;
      _controller.selection = TextSelection.collapsed(offset: sourceOffset);
      _applyingExternal = false;
    }
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

  /// Slim plakken: afbeelding → `![](…)`, spreadsheet → GFM-tabel, HTML van
  /// het klembord → Markdown, anders opgeschoonde platte tekst. Geeft `true`
  /// als de plak is afgehandeld (dan mag de editor niet nóg eens plakken).
  Future<bool> _smartPaste() async {
    final state = ref.read(documentProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final imageService = ref.read(imageServiceProvider);
    final outcome = await imageService.pasteImageDetailed(
      projectPath: projectPath,
    );
    if (!mounted) return false;
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
    final html = await readClipboardHtml();
    if (!mounted) return false;
    final resolved = resolveClipboardMarkdown(plain: data?.text, html: html);
    if (resolved == null) return false;

    if (resolved.kind == ClipboardMarkdownKind.table) {
      _insertBlock(resolved.text);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.d('Tabel geplakt'))),
        );
      }
      return true;
    }

    _insertPastedMarkdown(resolved.text);
    return true;
  }

  /// Zet [text] op de cursor in de bron, het bestaande pad voor platte tekst.
  /// In de visuele stand gaat de invoeging via de Quill-cursor, net als
  /// [_insertBlock] — de bron-controller staat daar stil op een oude positie.
  void _insertPastedMarkdown(String text) {
    if (_viewMode == _DocViewMode.visual &&
        markdownRoundTripsVisually(_controller.text)) {
      _requestVisualInsert(block: text);
      return;
    }
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
  }

  /// Bron-modus: de rauwe bron en de live weergave naast elkaar op een breed
  /// venster, onder elkaar wanneer het te smal wordt voor twee leesbare kolommen.
  /// De Overzicht-rail komt erbij zodra er breedte genoeg is.
  Widget _sourceLayout(
    ThemeData theme,
    String source,
    BoxConstraints c, {
    required TlpLevel tlp,
    required Map<String, String> fields,
  }) {
    final divider = theme.colorScheme.outlineVariant;
    final editor = _editor(theme);
    final preview = _preview(theme, source, tlp, fields);
    if (c.maxWidth < 760) {
      return Column(
        children: [
          Expanded(child: editor),
          Divider(height: 1, thickness: 1, color: divider),
          Expanded(child: preview),
        ],
      );
    }
    // Waar een presentatie de diastrook heeft, toont een document zijn koppen —
    // maar alleen als er breedte genoeg is voor rail + twee leesbare kolommen.
    final showRail = c.maxWidth >= 940;
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(child: editor),
        VerticalDivider(width: 1, thickness: 1, color: divider),
        Expanded(child: preview),
      ],
    );
  }

  /// Visuele modus: één bewerkbaar schrijfoppervlak — nooit een leesmuur. De
  /// gedeelde [MarkdownNotesEditor] past zich aan de bron aan: gaat die verliesvrij
  /// door de WYSIWYG-laag (koppen, opmaak, lijsten, links én tabellen-als-embed),
  /// dan schrijf je in de rijke-tekstweergave. Bevat de bron een constructie die
  /// de brug nog niet verliesvrij aankan (rauwe HTML, voetnoten, ontsnapte
  /// leestekens), dan valt de editor terug op de **bewerkbare** brontekst mét de
  /// volledige opmaakknoppenbalk en een waarschuwingsregel ([markdownSourceModeHint]).
  ///
  /// Bewust géén read-only leesweergave meer: OciDeck kiest niet vóór de gebruiker
  /// dat een document niet te bewerken valt. De rijke mogelijkheden (opmaakbalk +
  /// het invoeg-palet in [_DocEditorToolbar]) blijven altijd binnen bereik; alleen
  /// de waarschuwing komt erbij. Wie liever de gerenderde weergave ernaast heeft,
  /// schakelt naar Bron (broneditor + live weergave, grafiek/tabel met dubbelklik).
  Widget _visualLayout(
    ThemeData theme,
    String source,
    BoxConstraints c, {
    required TlpLevel tlp,
    required Map<String, String> fields,
  }) {
    final divider = theme.colorScheme.outlineVariant;
    final showRail = c.maxWidth >= 940;
    // De paginamaat-indicator in de hoek toont op welk formaat en met welke
    // marges je schrijft; de streepjeslijnen in het schrijfvlak tonen waar dat
    // vel vol is. Die einden worden gemeten aan de blokken die er echt staan —
    // zie [WritingPageBreakOverlay].
    final settings = ref.watch(settingsProvider);
    final setup = effectiveDocumentPageSetup(settings, _pageSetupSource(ref));
    final pageSize = setup.size!;
    final margins = setup.margins!;
    final (_, pageHeightMm) = pageSize.dimensions;
    final zoom = settings.documentEditorZoom;
    // De zoom gaat óók in de paginahoogte. De tekst wordt namelijk met dezelfde
    // factor groter én de kolom met dezelfde factor breder, dus elk blok wordt
    // precies `zoom` keer zo hoog en de regelval blijft identiek. Zonder deze
    // vermenigvuldiging zou een pagina-einde bij 150% een derde te vroeg vallen
    // en de lijn dus iets aanwijzen wat op papier niet gebeurt.
    final pageContentHeight =
        (pageHeightMm - margins.topMm - margins.bottomMm) * kPxPerMm * zoom;
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(
          child: _styledDocumentSurface(
            _styleProfile,
            Stack(
              children: [
                MediaQuery(
                  // De zoom vermenigvuldigt wat het toestel en de app-brede
                  // interfaceschaal al vragen, zoals de documentatielezer het ook
                  // doet — één begrip van "groter", niet twee.
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(
                      MediaQuery.textScalerOf(context).scale(1) * zoom,
                    ),
                  ),
                  child: WritingPageBreakOverlay(
                    editorKey: _visualEditorKey,
                    pageContentHeight: pageContentHeight,
                    bodyFontSize: documentBodyFontSizeToCssPx(
                      _styleProfile?.documentBodyFontSize ??
                          kDocumentDefaultBodyFontSize,
                    ),
                    // De einden gelden alleen op paginabreedte: op een andere
                    // maat breekt het vel ergens anders dan de lijn zegt.
                    enabled:
                        _showPageBreaks &&
                        settings.documentEditorWidth ==
                            DocumentEditorWidth.page,
                    child: _wysiwygEditor(theme),
                  ),
                ),
                // Binnen het tekstvlak, niet over de vaste voetband. Zo blijft
                // zowel de paginamatenknop als een TLP- of stijlvoet leesbaar.
                _documentPageIndicator(
                  context,
                  theme,
                  pageSize: pageSize,
                  margins: margins,
                  fromDocument: documentCarriesPageSetup(_pageSetupSource(ref)),
                  onTap: () => unawaited(
                    _choosePageSetupScope(
                      context,
                      ref,
                      pageSize: pageSize,
                      margins: margins,
                    ),
                  ),
                ),
              ],
            ),
            tlp: tlp,
            fields: fields,
          ),
        ),
      ],
    );
  }

  /// Het bewerkbare oppervlak van de Visuele modus. De notes-editor toont zelf de
  /// passende opmaakbalk: de Quill-balk in de rijke-tekstweergave, of de
  /// markdown-opmaakbalk + waarschuwing wanneer de bron een niet-verliesvrije
  /// constructie bevat en hij terugvalt op bewerkbare brontekst.
  Widget _wysiwygEditor(ThemeData theme) => MarkdownNotesEditor(
    controller: _controller,
    focusNode: _editorFocus,
    editorTheme: _docSurfaceTheme(theme, _styleProfile),
    hintText: '',
    expand: true,
    // Opmaakbalk zit al in [_DocEditorToolbar] voor de bron; hier toont de
    // notes-editor zijn eigen balk passend bij de modus.
    showToolbar: true,
    showModeToggle: false,
    mode: NotesEditorMode.visual,
    surfaceStyle: NotesSurfaceStyle.document,
    // Op welke breedte je schrijft is een keuze, geen bijverschijnsel van de
    // pagina-einden. Dat was het wél: de einden trokken de breedte naar die van
    // het vel, en omdat ze standaard aanstaan deed de instelling "volledige
    // breedte" niets. Nu kiest de gebruiker de stand en volgen de einden hem —
    // op paginabreedte kloppen ze, daarbuiten worden ze niet getekend.
    documentMaxWidth: _documentWriteWidth(ref),
    editorKey: _visualEditorKey,
    onDiscreteVisualEdit: () => _expectVisualInsert = true,
    onTapLink: _handleEditorLink,
    bordered: false,
    insertSignal: _insertSignal,
    insertMarkdownBlock: _pendingInsertBlock,
    insertFootnoteLabel: _pendingFootnoteLabel,
    revealSignal: _revealSignal,
    revealMarkdownOffset: _revealMarkdownOffset,
    revealTitle: _revealTitle,
    findSelectionSignal: _findSelectionSignal,
    findSelectionStart: _findSelectionStart,
    findSelectionEnd: _findSelectionEnd,
    onVisualCaret: _syncOutlineToVisualCaret,
    tryConsumePaste: _smartPaste,
    // Afbeelding-knop → carrousel, geen `![beschrijving](pad-of-url)`-dump.
    onInsertImage: () => unawaited(_insertImage()),
  );

  Widget _editor(ThemeData theme) => _documentSourceField(
    theme,
    controller: _controller,
    focusNode: _editorFocus,
    onSmartPaste: _smartPaste,
  );

  Widget _preview(
    ThemeData theme,
    String source,
    TlpLevel tlp,
    Map<String, String> fields,
  ) => _documentLivePreview(
    theme,
    source,
    scrollController: _previewScroll,
    style: _styleProfile,
    tlp: tlp,
    fields: fields,
    anchorBlockIndex: _anchorBlockIndex,
    anchorKey: _anchorKey,
    onEditChart: _editChart,
    onEditTable: _editTable,
    onTapLink: _handleEditorLink,
  );
}

/// De live weergave naast de bron: hetzelfde document als de lezer tekent, in
/// de documentstijl, met de anker- en bewerk-haken van de editor eraan.
///
/// Top-level en niet op de staat: het is een zuivere tekenfunctie van wat het
/// meekrijgt, en het bewerkscherm zit op zijn klasseplafond.
Widget _documentLivePreview(
  ThemeData theme,
  String source, {
  required ScrollController scrollController,
  required ThemeProfile? style,
  required TlpLevel tlp,
  required Map<String, String> fields,
  required int anchorBlockIndex,
  required GlobalKey? anchorKey,
  required void Function(int, String) onEditChart,
  required void Function(int, List<String>) onEditTable,
  required ValueChanged<String> onTapLink,
}) => Container(
  color: theme.colorScheme.surface,
  // Boven-links, niet gecentreerd: de weergave vult het paneel en de tekst
  // begint waar hij op het vel ook zou beginnen.
  alignment: Alignment.topLeft,
  child: SingleChildScrollView(
    controller: scrollController,
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
    child: _styledDocumentBody(
      style,
      DocumentMarkdownView(
        source,
        maxTextWidth: 720,
        themeProfile: style,
        chartTheme: style,
        anchorBlockIndex: anchorBlockIndex,
        anchorKey: anchorKey,
        onEditChart: onEditChart,
        onEditTable: onEditTable,
        onTapLink: onTapLink,
      ),
      tlp: tlp,
      fields: fields,
    ),
  ),
);

Future<void> _followEditorDocumentLink(
  String href, {
  required String source,
  required ValueChanged<MarkdownOutlineEntry> onAnchor,
}) async {
  final target = href.trim();
  if (target.isEmpty) return;
  if (!target.startsWith('#')) return openExternalUrl(target);
  String slug;
  try {
    slug = Uri.decodeComponent(target.substring(1));
  } on FormatException {
    return;
  }
  final outline = buildMarkdownOutline(source);
  final index = outline.indexWhere((entry) => headingSlug(entry.title) == slug);
  if (index >= 0) onAnchor(outline[index]);
}

extension on _DocumentEditorScreenState {
  Future<void> _handleEditorLink(String href) => _followEditorDocumentLink(
    href,
    source: ref.read(documentProvider).document?.source ?? '',
    onAnchor: _scrollToHeading,
  );
}

/// De sneltoetsen van de documentbewerker om [child] heen: opslaan, ongedaan
/// maken, opnieuw, en de zoom.
///
/// [Actions] én [CallbackShortcuts]: de eerste vangt de intenties die Flutter
/// zelf uitstuurt (het bewerkmenu van macOS stuurt `UndoTextIntent`), de tweede
/// de toetsen die niemand anders bindt. Top-level omdat het bewerkscherm op zijn
/// klasseplafond zit en dit een omhulsel is, geen gedrag van het scherm.
Widget _withDocumentShortcuts(
  WidgetRef ref, {
  required VoidCallback onUndo,
  required VoidCallback onRedo,
  required VoidCallback onSave,
  required VoidCallback onFind,
  required VoidCallback onReplace,
  required Widget child,
}) => Actions(
  actions: {
    UndoTextIntent: CallbackAction<UndoTextIntent>(
      onInvoke: (_) {
        onUndo();
        return null;
      },
    ),
    RedoTextIntent: CallbackAction<RedoTextIntent>(
      onInvoke: (_) {
        onRedo();
        return null;
      },
    ),
  },
  child: CallbackShortcuts(
    bindings: {
      // Cmd op macOS, Ctrl elders — net als het opslaan van een deck.
      const SingleActivator(LogicalKeyboardKey.keyS, meta: true): onSave,
      const SingleActivator(LogicalKeyboardKey.keyS, control: true): onSave,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true): onUndo,
      const SingleActivator(LogicalKeyboardKey.keyZ, control: true): onUndo,
      const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
          onRedo,
      const SingleActivator(
        LogicalKeyboardKey.keyZ,
        control: true,
        shift: true,
      ): onRedo,
      const SingleActivator(LogicalKeyboardKey.keyY, control: true): onRedo,
      // Zoeken en zoeken-en-vervangen — dezelfde toetsen als de presentatie-
      // broneditor, zodat er één gewoonte is.
      const SingleActivator(LogicalKeyboardKey.keyF, meta: true): onFind,
      const SingleActivator(LogicalKeyboardKey.keyF, control: true): onFind,
      const SingleActivator(LogicalKeyboardKey.keyH, meta: true): onReplace,
      const SingleActivator(LogicalKeyboardKey.keyH, control: true): onReplace,
      const ControlHActivator(): onReplace,
      // Zoomen zoals overal: Cmd/Ctrl met + of −, en 0 terug naar ware grootte.
      // Beide plustoetsen, want op de meeste indelingen zit + op shift-= en
      // levert het toetsenbord `equal` in plaats van `add`.
      ..._documentZoomShortcuts(ref),
    },
    child: child,
  ),
);

/// De breedte waarop het schrijfvlak staat: de tekstbreedte van het vel, de
/// ingestelde leeskolom, of niets (het hele venster) — allemaal maal de zoom.
///
/// De zoom zit erin omdat hij anders liegt: schaalt alleen de tekst mee en niet
/// de kolom, dan valt de regelval anders dan op papier en klopt geen enkel
/// pagina-einde meer. Tekst en kolom groeien met dezelfde factor, dus wat er op
/// een regel past blijft precies gelijk.
double? _documentWriteWidth(WidgetRef ref) {
  final settings = ref.watch(settingsProvider);
  final zoom = settings.documentEditorZoom;
  return switch (settings.documentEditorWidth) {
    DocumentEditorWidth.page => _documentPageTextWidthPx(ref) * zoom,
    DocumentEditorWidth.column => switch (settings.documentEditorMaxWidth) {
      null => null,
      final width => width * zoom,
    },
    DocumentEditorWidth.full => null,
  };
}

/// Het rauwe schrijfvlak van de Bron-stand: monospace-bron met een
/// niet-bewerkbare regelnummerkolom, en het slimme plakken eraan geknoopt.
///
/// Top-level en niet op de staat: het heeft niets nodig behalve de controller,
/// de focus en de plak-afhandeling, en het bewerkscherm zit op zijn
/// klasseplafond.
Widget _documentSourceField(
  ThemeData theme, {
  required TextEditingController controller,
  required FocusNode focusNode,
  required Future<bool> Function() onSmartPaste,
}) => _DocumentSourceField(
  theme: theme,
  controller: controller,
  focusNode: focusNode,
  onSmartPaste: onSmartPaste,
);

/// Pagina-modus: het document op echte vellen, met de paginamaat, de marges en
/// een eventuele drukkersafloop. Hier zie je wat er op welke bladzijde belandt
/// — de vraag die een tekstverwerker beantwoordt en een doorlopende rol niet.
/// Lezen en nakijken, niet typen: bewerken doe je in de visuele of de bron-stand.
///
/// Top-level en niet op de staat: hij heeft alleen de instellingen, de tekst en
/// de stijl nodig, en het bewerkscherm zit op zijn klasseplafond.
Widget _documentPagesLayout(
  BuildContext context,
  WidgetRef ref,
  ThemeData theme,
  String source, {
  required ThemeProfile? style,
  required String? projectPath,
  required TlpLevel tlp,
  required Map<String, String> fields,
}) {
  final settings = ref.watch(settingsProvider);
  // Draagt het document zelf een paginaopmaak, dan wint die van de instelling —
  // zie [effectiveDocumentPageSetup].
  final setup = effectiveDocumentPageSetup(settings, _pageSetupSource(ref));
  // Is de geometry-frontmatter ongeldig (negatief, NaN, of marges die samen
  // breder zijn dan het vel), dan is die genegeerd en gelden de instellingen.
  // Dat hoort de gebruiker te weten — niet stíl vervangen (#1681).
  final invalidReason = documentPageSetupInvalidReason(_pageSetupSource(ref));
  return Container(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Column(
      children: [
        if (invalidReason != null)
          MaterialBanner(
            content: Text(
              context.l10n.d(
                'De paginaopmaak in dit document bevat ongeldige waarden en is genegeerd. De instellingen worden gebruikt.',
              ),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface,
              ),
            ),
            leading: Icon(
              Icons.warning_amber_rounded,
              color: theme.colorScheme.error,
            ),
            actions: const [SizedBox.shrink()],
          ),
        Expanded(
          child: PagedDocumentView(
            markdown: source,
            pageSize: setup.size!,
            margins: setup.margins!,
            profile: style,
            tlp: tlp,
            fields: fields,
            projectPath: projectPath,
            chapterPageBreak: settings.documentChapterPageBreak,
            // Waar de noten komen staat in het document zelf; zie
            // [documentFootnotePlacement].
            footnotePlacement: documentFootnotePlacement(_pageSetupSource(ref)),
            // Hier is de zoom meetkundig: het vel wordt groter of kleiner
            // getekend, de indeling erop blijft die van het papier. Precies
            // waarom je in deze stand inzoomt — om beter te zien wat er staat,
            // niet om iets anders te laten breken.
            scale: settings.documentEditorZoom,
          ),
        ),
      ],
    ),
  );
}

/// Zet de zoom van de documenteditor; de notifier klemt hem op zijn grenzen.
void _setDocumentZoom(WidgetRef ref, double zoom) =>
    unawaited(ref.read(settingsProvider.notifier).setDocumentEditorZoom(zoom));

/// Cmd/Ctrl met + of −, en 0 terug naar ware grootte.
///
/// Twee plustoetsen en twee mintoetsen: op de meeste indelingen zit + op
/// shift-=, en dan levert het toetsenbord `equal` in plaats van `add`. Alleen
/// `add` binden werkt op een cijferblok en nergens anders.
Map<ShortcutActivator, VoidCallback> _documentZoomShortcuts(WidgetRef ref) {
  final zoom = ref.read(settingsProvider).documentEditorZoom;
  const step = kDocumentEditorZoomStep;
  void bigger() => _setDocumentZoom(ref, zoom + step);
  void smaller() => _setDocumentZoom(ref, zoom - step);
  return {
    for (final key in const [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ]) ...{
      SingleActivator(key, meta: true): bigger,
      SingleActivator(key, control: true): bigger,
    },
    for (final key in const [
      LogicalKeyboardKey.minus,
      LogicalKeyboardKey.numpadSubtract,
    ]) ...{
      SingleActivator(key, meta: true): smaller,
      SingleActivator(key, control: true): smaller,
    },
    for (final key in const [
      LogicalKeyboardKey.digit0,
      LogicalKeyboardKey.numpad0,
    ]) ...{
      SingleActivator(key, meta: true): () => _setDocumentZoom(ref, 1),
      SingleActivator(key, control: true): () => _setDocumentZoom(ref, 1),
    },
  };
}

/// De tekstbreedte van de pagina die nu geldt: die van het document zelf als
/// het er een paginaopmaak draagt, anders die van de app-instelling. Top-level
/// zodat het bewerkscherm zelf onder zijn regelplafond blijft.
double _documentPageTextWidthPx(WidgetRef ref) {
  final setup = effectiveDocumentPageSetup(
    ref.read(settingsProvider),
    ref.read(documentProvider).document?.source ?? '',
  );
  return pageTextWidthPx(setup.size!, setup.margins!);
}

/// Zet de voetnoten van dít document achterin (`reference-location: document`)
/// of weer onderaan de bladzijde.
///
/// Schrijft in de front matter van het bestand van de gebruiker — maar alleen
/// de afwijking: "onderaan de bladzijde" is wat elke lezer zonder aanwijzing al
/// doet, dus die keuze haalt de sleutel juist weg. Een document dat er niets
/// over zegt, blijft een `.md` zonder front matter.
void _setFootnotePlacement(WidgetRef ref, bool atEnd) {
  final doc = ref.read(documentProvider).document;
  if (doc == null) return;
  final next = withDocumentFootnotePlacement(
    doc.source,
    atEnd ? FootnotePlacement.document : FootnotePlacement.page,
  );
  if (next == doc.source) return;
  ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
}

/// Laat kiezen of de huidige paginaopmaak in dít document komt te staan of uit
/// de instellingen blijft komen.
///
/// Bewust een expliciete keuze en geen schakelaar die meteen schrijft: de
/// sleutels landen in het bestand van de gebruiker, en dat hoort een besluit te
/// zijn dat je neemt, niet een dat je per ongeluk aanzet. Top-level zodat het
/// bewerkscherm zelf onder zijn regelplafond blijft.
Future<void> _choosePageSetupScope(
  BuildContext context,
  WidgetRef ref, {
  required PageSizeSpec pageSize,
  required PageMargins margins,
}) async {
  final l10n = context.l10n;
  final doc = ref.read(documentProvider).document;
  if (doc == null) return;
  final inDocument = documentCarriesPageSetup(doc.source);
  final choice = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(l10n.d('Paginaopmaak')),
      content: Text(
        inDocument
            ? l10n.d(
                'De paginamaat en marges staan nu in dit document; wie het opent krijgt dezelfde pagina. Haal ze eruit om je eigen instelling te laten gelden.',
              )
            : l10n.d(
                'De paginamaat en marges komen nu uit je instellingen, dus bij een ander kan het document anders uitvallen. Zet ze in het document om dat vast te leggen.',
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.d('Annuleren')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(!inDocument),
          child: Text(
            inDocument
                ? l10n.d('Uit het document halen')
                : l10n.d('In dit document vastleggen'),
          ),
        ),
      ],
    ),
  );
  if (choice == null) return;
  final next = withDocumentPageSetup(
    doc.source,
    size: choice ? pageSize : null,
    margins: choice ? margins : null,
  );
  if (next == doc.source) return;
  ref.read(documentProvider.notifier).edit(next, coalesceKey: null);
}
