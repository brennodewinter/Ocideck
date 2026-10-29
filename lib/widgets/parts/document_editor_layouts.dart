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
String _pageSetupSource(WidgetRef ref) => ref.watch(
  documentProvider.select((state) => state.document?.frontMatter ?? ''),
);

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
    _setActiveOutlineIndex(
      activeOutlineIndexForOffset(
        buildMarkdownOutline(_controller.text),
        sel.baseOffset,
      ),
    );
  }

  /// Quill-caret → actieve Overzicht-kop via titelvolgorde in de platte tekst.
  void _syncOutlineToVisualCaret(String plain, int plainOffset) {
    _chrome.recordVisualCaret(plain, plainOffset);
  }

  void _applyVisualCaretToChrome(String plain, int plainOffset) {
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

  /// Slim plakken: afbeelding → `![](…)`, spreadsheet → GFM-tabel, HTML van
  /// het klembord → Markdown, anders opgeschoonde platte tekst. Geeft `true`
  /// als de plak is afgehandeld (dan mag de editor niet nóg eens plakken).
  /// De inhoud staat in [_smartPasteDocument]: top-level, want deze klasse
  /// zit op haar klasseplafond.
  Future<bool> _smartPaste() => _smartPasteDocument(this);

  /// Plakken zónder opmaak (Shift+Ctrl/Cmd+V): alleen de platte-tekstvariant
  /// van het klembord — geen afbeeldingsimport, geen tabelherkenning, geen
  /// HTML→Markdown. Zelfde atomaire route als [_smartPaste], anders plakt de
  /// Shift-variant anders dan Cmd/Ctrl+V beweert.
  Future<bool> _plainPaste() => _smartPasteDocument(this, plainOnly: true);

  /// Zet [text] op de cursor in de bron, het bestaande pad voor platte tekst.
  /// In de visuele stand landt geplakte tekst op de Quill-caret — het blokpad
  /// van [_insertBlock] zoekt bewust het einde van de regel, wat voor een
  /// tabel klopt maar een zin onder de cursor zou zetten (#2138).
  ///
  /// [visualCaret] en [sourceCaret] zijn de carets die [_smartPaste] vóór de
  /// async klembordlezing vastlegde (#2466); `null` betekent: de selectie
  /// van nu, zoals bij een synchrone invoeging.
  void _insertPastedMarkdown(
    String text, {
    TextSelection? visualCaret,
    TextSelection? sourceCaret,
  }) {
    final quill = _viewMode == _DocViewMode.visual
        ? _visualEditorKey.currentState?.widget.controller
        : null;
    if (_pasteInlineAtVisualCaret(
      quill,
      text,
      visualCaret,
      markInsert: () => _expectVisualInsert = true,
    )) {
      return;
    }
    _applyingExternal = true;
    _replaceSourceSelection(_controller, text, sel: sourceCaret);
    _applyingExternal = false;
    _commitDocumentBody(ref, _controller.text, coalesceKey: 'doc');
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
          Expanded(
            child: _editorAboveInfoStrip(context, ref, theme, editor, source),
          ),
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
        Expanded(
          child: _editorAboveInfoStrip(context, ref, theme, editor, source),
        ),
        VerticalDivider(width: 1, thickness: 1, color: divider),
        Expanded(child: preview),
      ],
    );
  }

  /// Visuele modus: één bewerkbaar schrijfoppervlak — nooit een leesmuur. De
  /// gedeelde [MarkdownNotesEditor] past zich aan de bron aan: gaat die verliesvrij
  /// door de WYSIWYG-laag (koppen, opmaak, lijsten, links én tabellen-als-embed),
  /// dan schrijf je in de rijke-tekstweergave. Bevat de bron een constructie die
  /// de brug nog niet verliesvrij aankan (rauwe HTML, ontsnapte leestekens, een
  /// losse tabelregel), dan wordt alleen dát stuk een bewerkbaar bronblok
  /// (`EmbeddableSourceFragment`) — de rest blijft rijke tekst.
  ///
  /// Bewust géén read-only leesweergave en géén documentbrede bronterugval
  /// meer: OciDeck kiest niet vóór de gebruiker dat een document niet visueel
  /// te bewerken valt. De rijke mogelijkheden (opmaakbalk + het invoeg-palet
  /// in [_DocEditorToolbar]) blijven altijd binnen bereik. Wie liever de
  /// gerenderde weergave ernaast heeft,
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
                    settings.documentEditorWidth == DocumentEditorWidth.page,
                child: _wysiwygEditor(theme),
              ),
            ),
            tlp: tlp,
            fields: fields,
            // Onder de tekst, boven de TLP-voet. Niet als Positioned in de
            // schrijfstack: dan dekt de strook de laatste regels (#2397).
            belowEditor: _documentInfoStripFor(context, ref, theme, source),
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
    insertCaret: _pendingInsertCaret,
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
    onPlainPaste: _plainPaste,
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
    tableEditorFor: (ordinal) => _sourceTableFor(this, ordinal),
    onTapLink: _handleEditorLink,
  );
}

/// De inhoud van [_DocumentEditorScreenState._smartPaste]: plakken is één
/// atomaire handeling op de positie van het moment van de opdracht — stand,
/// controllers, beide carets én de revisie liggen vóór de eerste await vast
/// (#2466, uitbreiding op #2138). Verandert er iets tijdens de klembord-I/O —
/// een toetsaanslag, een standwissel, een andere controller — dan gokken we
/// niet naar een nieuwe plek maar melden we dat de bestemming is veranderd.
///
/// Top-level omdat de staat op zijn klasseplafond zit; private leden van
/// [_DocumentEditorScreenState] zijn binnen dezelfde library bereikbaar.
Future<bool> _smartPasteDocument(
  _DocumentEditorScreenState s, {
  bool plainOnly = false,
}) async {
  final mode = s._viewMode;
  final sourceController = s._controller;
  final sourceText = sourceController.text;
  final sourceCaret = sourceController.selection;
  final quill = mode == _DocViewMode.visual
      ? s._visualEditorKey.currentState?.widget.controller
      : null;
  final visualCaret = quill?.selection;
  var visualChanged = false;
  final visualWatch = quill?.document.changes.listen(
    (_) => visualChanged = true,
  );

  final messenger = ScaffoldMessenger.of(s.context);
  final l10n = s.context.l10n;

  // Veranderde de bestemming tijdens een await? Dan: melden, niet gokken.
  bool stale() =>
      !identical(s._controller, sourceController) ||
      sourceController.text != sourceText ||
      s._viewMode != mode ||
      visualChanged ||
      (quill != null &&
          !identical(
            s._visualEditorKey.currentState?.widget.controller,
            quill,
          ));

  bool bailIfStale() {
    if (!s.mounted) return true;
    if (!stale()) return false;
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          l10n.d(
            'Plakken overgeslagen: de invoegpositie is tussendoor gewijzigd.',
          ),
        ),
      ),
    );
    return true;
  }

  if (!plainOnly) {
    final state = s.ref.read(documentProvider);
    final projectPath = state.filePath == null
        ? null
        : p.dirname(state.filePath!);
    final imageService = s.ref.read(imageServiceProvider);
    final outcome = await imageService.pasteImageDetailed(
      projectPath: projectPath,
    );
    if (!s.mounted) {
      unawaited(visualWatch?.cancel() ?? Future<void>.value());
      return false;
    }
    if (outcome.path != null) {
      if (bailIfStale()) {
        unawaited(visualWatch?.cancel() ?? Future<void>.value());
        return true;
      }
      unawaited(visualWatch?.cancel() ?? Future<void>.value());
      s._insertBlock(
        '![](${outcome.path})',
        at: mode == _DocViewMode.visual ? visualCaret : sourceCaret,
      );
      if (s.mounted) {
        ScaffoldMessenger.of(s.context).showSnackBar(
          SnackBar(content: Text(s.context.l10n.d('Afbeelding geplakt'))),
        );
      }
      return true;
    }
    // Geen afbeelding: stil als "geen klembordbeeld", anders de echte fout.
    if (outcome.failure != null &&
        outcome.failure != ImageImportFailure.noClipboardImage &&
        s.mounted) {
      reportImageImportFailure(s.context, outcome.failure);
      unawaited(visualWatch?.cancel() ?? Future<void>.value());
      return true;
    }
  }

  final data = await Clipboard.getData(Clipboard.kTextPlain);
  final html = plainOnly ? null : await readClipboardHtml();
  unawaited(visualWatch?.cancel() ?? Future<void>.value());
  if (!s.mounted) return false;

  // Shift+Ctrl/Cmd+V: bewust géén tabel- of HTML-route, ook niet als de
  // platte tekst er als TSV uitziet — de gebruiker vroeg letterlijk wat er
  // op `text/plain` staat.
  if (plainOnly) {
    final raw = data?.text;
    if (raw == null || raw.isEmpty) return false;
    final text = sanitizeMarkdownPaste(raw);
    if (text.isEmpty) return false;
    if (bailIfStale()) return true;
    s._insertPastedMarkdown(
      text,
      visualCaret: visualCaret,
      sourceCaret: sourceCaret,
    );
    return true;
  }

  final resolved = resolveClipboardMarkdown(plain: data?.text, html: html);
  if (resolved == null) return false;

  if (bailIfStale()) return true;

  if (resolved.kind == ClipboardMarkdownKind.table) {
    s._insertBlock(
      resolved.text,
      at: mode == _DocViewMode.visual ? visualCaret : sourceCaret,
    );
    if (s.mounted) {
      ScaffoldMessenger.of(s.context).showSnackBar(
        SnackBar(content: Text(s.context.l10n.d('Tabel geplakt'))),
      );
    }
    return true;
  }

  s._insertPastedMarkdown(
    resolved.text,
    visualCaret: visualCaret,
    sourceCaret: sourceCaret,
  );
  return true;
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
  required TableEditController? Function(int ordinal)? tableEditorFor,
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
        tableEditorFor: tableEditorFor,
        onTapLink: onTapLink,
      ),
      tlp: tlp,
      fields: fields,
    ),
  ),
);

/// De GFM-tabel [ordinal] in de Bron-preview: zelfde rekenblad als Visueel.
/// Undo coalescet per tabel zodat één zin typen geen tientallen stappen wordt.
TableEditController? _sourceTableFor(
  _DocumentEditorScreenState s,
  int ordinal,
) {
  final body = s._controller.text;
  final range = DocumentMarkdownView.nthTableBlockRange(body, ordinal);
  if (range == null) return null;
  final gfm = body.split('\n').sublist(range[0], range[1]).join('\n');
  return s._sourceTables
      .obtain(
        (surface: 'source-preview', ordinal: ordinal),
        gfm,
        onChanged: (rows, alignments) {
          final current = s._controller.text;
          final before = decodeMarkdownTableRows(
            current.split('\n').sublist(range[0], range[1]),
          );
          final next = replaceNthTableBlock(
            current,
            ordinal,
            encodeMarkdownTable(rows, alignments: alignments),
          );
          if (next != current) {
            // Een rijpermutatie (sorteren) is een discrete handeling: die mag
            // niet met de typstap ervoor samensmelten in één undo (#2486).
            _commitDocumentBody(
              s.ref,
              next,
              coalesceKey: isTableRowPermutation(before, rows)
                  ? null
                  : 'source-table-$ordinal',
            );
          }
        },
        onCellFocused: null,
      )
      .controller;
}

/// Plakt [markdown] als tekst op de Quill-caret van de visuele editor en
/// vervangt daarbij een actieve selectie. `false` als er geen visuele
/// editor staat — de aanroeper valt dan terug op de bronroute.
///
/// [caret] is de selectie zoals de aanroeper hem vóór de async
/// klembordlezing vastlegde; zonder die vangst landt een plak na
/// focusverlies op het documenteinde (#2138).
bool _pasteInlineAtVisualCaret(
  QuillController? quill,
  String markdown,
  TextSelection? caret, {
  required VoidCallback markInsert,
}) {
  if (quill == null) return false;
  // De kale documentafsluiter gaat eraf; een vinkje- of lijstafsluiter blijft.
  // Zie [operationsForVisualPaste].
  final ops = operationsForVisualPaste(markdown);
  if (ops.isEmpty) return true;
  final end = quill.document.length - 1;
  final sel = (caret != null && caret.isValid) ? caret : quill.selection;
  final at = sel.isValid ? sel.start.clamp(0, end) : end;
  final len = sel.isValid ? sel.end.clamp(at, end) - at : 0;
  final inserted = ops.fold<int>(0, (sum, op) => sum + (op.length ?? 0));
  // Een plak is een eigen bewerking, geen voortzetting van het typen ervoor
  // — net zoals [_requestVisualInsert] dat voor blokken regelt.
  markInsert();
  quill.replaceText(
    at,
    len,
    Delta.fromOperations(ops),
    TextSelection.collapsed(offset: at + inserted),
  );
  return true;
}

/// Open de document-export-dialoog (DOCUMENT_MODE.md §11.2). De dialoog kiest
/// profiel en formaat; het echte bouwen-en-wegschrijven gebeurt in de closure
/// hieronder, die de bron langs `buildDocumentExportBundle → AudienceDeck`
/// projecteert (nooit de rauwe bron), een pad laat kiezen en atomisch
/// wegschrijft. De bron zelf blijft ongemoeid — export is een afgeleid
/// bestand.
Future<void> _exportDocument(_DocumentEditorScreenState s) async {
  final state = s.ref.read(documentProvider);
  final document = state.document;
  if (document == null) return;
  final settings = s.ref.read(settingsProvider);
  await DocumentExportDialog.show(
    s.context,
    privacyChecksEnabled: settings.privacyChecksEnabled,
    onExport: (profile, format, {required isCancelled}) => _writeDocumentExport(
      s.ref,
      s.context,
      profile,
      format,
      isCancelled: isCancelled,
    ),
  );
}

/// Converteer dit document naar een NIEUWE presentatie in een nieuw tabblad
/// (DOCUMENT_MODE.md §11.3). De dialoog toont het voorgestelde aantal dia's
/// en de drop-lijst vóór het committen; pas bij bevestigen ontstaat het
/// nieuwe tabblad.
Future<void> _convertDocumentToPresentation(
  _DocumentEditorScreenState s,
) async {
  final state = s.ref.read(documentProvider);
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
  final projectPath = _documentProjectPath(s.ref);
  final hydrated = await hydrateDocumentChartData(
    body,
    projectPath: projectPath,
  );
  if (!s.mounted) return;
  final deck = DocumentDeckBridge.documentToDeck(
    hydrated,
    projectPath: projectPath,
    title: title,
    tlp: documentTlp,
  );
  final confirmed = await ConvertToPresentationDialog.show(
    s.context,
    slideCount: deck.slides.length,
  );
  if (confirmed != true || !s.mounted) return;
  s.ref
      .read(tabsProvider.notifier)
      .newDeckInNewTab(
        title,
        tlp: deck.tlp,
        slides: deck.slides,
        projectPath: projectPath,
      );
}

/// Zet [text] op de selectie van [controller] — het plakpad voor de
/// bronstand en voor blokken. [sel] is de selectie van het moment van de
/// opdracht (#2466); `null` gebruikt de selectie van nu.
void _replaceSourceSelection(
  TextEditingController controller,
  String text, {
  TextSelection? sel,
}) {
  final s = sel ?? controller.selection;
  final start = s.isValid ? s.start : controller.text.length;
  final end = s.isValid ? s.end : start;
  controller.value = TextEditingValue(
    text: controller.text.replaceRange(start, end, text),
    selection: TextSelection.collapsed(offset: start + text.length),
  );
}

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
    // Interne koplinks landen via [_scrollToHeading] op de bódy — de tekst
    // die de controller bewerkt. De source is hier dezelfde tekst mét het
    // stijl-frontmatter er nog vóór en zou elke ankersprong verkeerd leggen
    // (#2465).
    source: _controller.text,
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
  required Future<bool> Function() onPlainPaste,
}) => _DocumentSourceField(
  theme: theme,
  controller: controller,
  focusNode: focusNode,
  onSmartPaste: onSmartPaste,
  onPlainPaste: onPlainPaste,
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
        _documentInfoStripFor(context, ref, theme, source),
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
