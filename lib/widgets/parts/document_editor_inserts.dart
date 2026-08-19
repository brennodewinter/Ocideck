// Part of the document-editor library — see ../document_editor_screen.dart.
//
// Het invoeg-palet van de documenteditor: grafiek, tabel, mermaid, pagina-einde,
// inhoudsopgave, voetnoot en afbeelding. Losgeknipt van document_editor_screen.dart
// omdat dat bestand voor de derde keer op zijn regelplafond stuitte — deze
// methoden horen bij elkaar en zijn samen een handgreep. Eén library, dus ze
// gebruiken de staat van het scherm ongewijzigd.
part of '../document_editor_screen.dart';

/// De invoegingen van [_DocumentEditorScreenState]. Een extensie op de staat
/// zelf (zelfde library), zodat de methoden ongewijzigd blijven werken —
/// hetzelfde patroon als de weergavestanden ernaast.
extension _DocumentEditorInserts on _DocumentEditorScreenState {
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

  /// Voeg een tijdlijn in via dezelfde tabeleditor als iedere andere tabel.
  /// Pas na Toepassen komt de draagbare marker erbij; annuleren verandert het
  /// document dus niet en de gebruiker hoeft nooit eerst een leeg blok te zoeken.
  Future<void> _insertTimeline() async {
    final l10n = context.l10n;
    final initialRows = [
      [l10n.d('Tijd'), l10n.d('Gebeurtenis'), l10n.d('Status')],
      ['', '', ''],
    ];
    final slide = Slide.create(SlideType.table);
    var rows = initialRows;
    while (mounted) {
      final apply = await showEmbedEditorDialog(
        context,
        TableEditor(
          slide: slide.copyWith(tableRows: rows),
          nestedInScrollView: true,
          documentContext: true,
          onUpdate: (s) => rows = s.tableRows,
        ),
      );
      if (apply != true || !mounted) return;
      final hasEvent = rows
          .skip(1)
          .any((row) => row.length > 1 && row[1].trim().isNotEmpty);
      if (hasEvent) break;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            l10n.d(
              'Voeg eerst minstens één gebeurtenis toe. Deze tabel blijft ongewijzigd.',
            ),
          ),
        ),
      );
    }
    if (!mounted) return;
    _insertBlock(markTableAsTimeline(encodeMarkdownTable(rows)));
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

  /// Voeg een voetnoot in: het merkteken op de cursor, de lege notenregel
  /// eronder om te vullen.
  ///
  /// Twee plekken in één handeling, en dus geen gewone blokinvoeging. Het label
  /// is het eerstvolgende vrije getal; wie liever `[^bron]` schrijft, doet dat
  /// met de hand en houdt dat label — de weergave nummert toch door op
  /// leesvolgorde.
  void _insertFootnote() {
    final label = nextFootnoteLabel(_controller.text);
    if (_viewMode == _DocViewMode.visual &&
        markdownRoundTripsVisually(_controller.text)) {
      _requestVisualInsert(footnoteLabel: label);
      return;
    }
    final sel = _controller.selection;
    final (next, cursor) = insertFootnoteIntoSource(
      _controller.text,
      sel.start,
      sel.end,
      label,
    );
    _applyingExternal = true;
    _controller.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: cursor),
    );
    _applyingExternal = false;
    _commitDocumentBody(ref, next, coalesceKey: null);
  }

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
}

/// Dubbelklik op een gerenderde grafiek → de volwaardige [ChartEditor] in een
/// dialoog (dezelfde editor als een dia, met een wegwerp-[Slide] om zijn bron
/// vast te houden). 'Toepassen' schrijft het bewerkte ```chart-blok terug op
/// zijn plek in de bron; de weergave hertekent mee. DOCUMENT_MODE.md §4.2.
Future<void> _editDocumentChart(
  BuildContext context,
  WidgetRef ref,
  int chartOrdinal,
  String block,
) async {
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
  if (apply != true || !context.mounted) return;
  final body = ref.read(documentProvider).document?.body ?? '';
  final next = replaceNthChartBlock(body, chartOrdinal, edited);
  if (next != body) _commitDocumentBody(ref, next, coalesceKey: null);
}

/// Dubbelklik op een gerenderde tabel → de volwaardige [TableEditor] in een
/// dialoog. Kop + scheidingsrij + body worden via [decodeMarkdownTableWithAlignment]
/// ontleed tot een celraster mét per-kolomuitlijning en in een wegwerp-[Slide]
/// gezet; 'Toepassen' serialiseert raster én uitlijning terug naar een
/// GFM-tabel en vervangt precies dat tabelblok in de bron. DOCUMENT_MODE.md §4.2.
Future<void> _editDocumentTable(
  BuildContext context,
  WidgetRef ref,
  int tableOrdinal,
  List<String> rawRows,
) async {
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
  if (apply != true || !context.mounted) return;
  final next = replaceNthTableBlock(
    body,
    tableOrdinal,
    encodeMarkdownTable(editedRows, alignments: editedAligns),
  );
  if (next != body) _commitDocumentBody(ref, next, coalesceKey: null);
}
