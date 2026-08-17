// Part of the document-editor library — see ../document_editor_screen.dart.
//
// De drie weergavestanden van de documenteditor: de bron naast de weergave,
// het document op echte pagina's, en het visuele schrijfvlak. Losgeknipt van
// document_editor_screen.dart omdat dat bestand twee keer op zijn regelplafond
// stuitte en elke toevoeging eerst een verhuizing kostte (#1509). Eén library,
// dus de standen gebruiken de staat van het scherm ongewijzigd.
part of '../document_editor_screen.dart';

/// De weergavestanden van [_DocumentEditorScreenState]. Een extensie op de
/// staat zelf (zelfde library), zodat de methoden ongewijzigd blijven werken —
/// hetzelfde patroon als de tabel-part van de documentweergave.
extension _DocumentEditorLayouts on _DocumentEditorScreenState {
  /// Bron-modus: de rauwe bron en de live weergave naast elkaar op een breed
  /// venster, onder elkaar wanneer het te smal wordt voor twee leesbare kolommen.
  /// De Overzicht-rail komt erbij zodra er breedte genoeg is.
  Widget _sourceLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final editor = _editor(theme);
    final preview = _preview(theme, source);
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

  /// De map waarin het document staat, voor het oplossen van een logo in de
  /// kop- of voetband. `null` als het nog nergens is opgeslagen.
  String? get _projectPath {
    final path = ref.read(documentProvider).filePath;
    return path == null ? null : p.dirname(path);
  }

  /// Pagina-modus: het document op echte vellen, met de paginamaat, de marges
  /// en een eventuele drukkersafloop uit de instellingen. Hier zie je wat er op
  /// welke bladzijde belandt — de vraag die een tekstverwerker beantwoordt en
  /// een doorlopende rol niet. Lezen en nakijken, niet typen: bewerken doe je
  /// in de visuele of de bron-stand.
  Widget _pagesLayout(ThemeData theme, String source) {
    final settings = ref.watch(settingsProvider);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      child: PagedDocumentView(
        markdown: source,
        pageSize: settings.documentPageSize,
        margins: settings.documentPageMargins,
        profile: _styleProfile,
        projectPath: _projectPath,
      ),
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
  Widget _visualLayout(ThemeData theme, String source, BoxConstraints c) {
    final divider = theme.colorScheme.outlineVariant;
    final showRail = c.maxWidth >= 940;
    // De paginamaat-indicator in de hoek toont op welk formaat en met welke
    // marges je schrijft; de streepjeslijnen in het schrijfvlak tonen waar dat
    // vel vol is. Die einden worden gemeten aan de blokken die er echt staan —
    // zie [WritingPageBreakOverlay].
    final settings = ref.watch(settingsProvider);
    final pageSize = settings.documentPageSize;
    final margins = settings.documentPageMargins;
    final (_, pageHeightMm) = pageSize.dimensions;
    final pageContentHeight =
        (pageHeightMm - margins.topMm - margins.bottomMm) * kPxPerMm;
    return Row(
      children: [
        if (showRail) ...[
          _outlineRail(theme, source),
          VerticalDivider(width: 1, thickness: 1, color: divider),
        ],
        Expanded(
          child: Stack(
            children: [
              WritingPageBreakOverlay(
                editorKey: _visualEditorKey,
                pageContentHeight: pageContentHeight,
                enabled: _showPageBreaks,
                child: _styledDocumentSurface(
                  _styleProfile,
                  _wysiwygEditor(theme),
                ),
              ),
              _documentPageIndicator(
                context,
                theme,
                pageSize: pageSize,
                margins: margins,
              ),
            ],
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
    // Met pagina-einden aan schrijf je op de tekstbreedte van de pagina: een
    // einde dat op een bredere kolom is uitgerekend zou ergens anders vallen
    // dan op papier, en dan wijst de lijn nergens naar. Staan de einden uit,
    // dan geldt de ingestelde schrijfbreedte.
    documentMaxWidth: _showPageBreaks
        ? pageTextWidthPx(
            ref.watch(settingsProvider).documentPageSize,
            ref.watch(settingsProvider).documentPageMargins,
          )
        : ref.watch(settingsProvider).documentEditorMaxWidth,
    editorKey: _visualEditorKey,
    bordered: false,
    insertSignal: _insertSignal,
    insertMarkdownBlock: _pendingInsertBlock,
    revealSignal: _revealSignal,
    revealMarkdownOffset: _revealMarkdownOffset,
    revealTitle: _revealTitle,
    onVisualCaret: _syncOutlineToVisualCaret,
    tryConsumePaste: _smartPaste,
    // Afbeelding-knop → carrousel, geen `![beschrijving](pad-of-url)`-dump.
    onInsertImage: () => unawaited(_insertImage()),
  );

  Widget _editor(ThemeData theme) => Shortcuts(
    shortcuts: const {
      SingleActivator(LogicalKeyboardKey.keyV, control: true):
          _DocSmartPasteIntent(),
      SingleActivator(LogicalKeyboardKey.keyV, meta: true):
          _DocSmartPasteIntent(),
    },
    child: Actions(
      actions: {
        _DocSmartPasteIntent: CallbackAction<_DocSmartPasteIntent>(
          onInvoke: (_) {
            unawaited(_smartPaste());
            return null;
          },
        ),
      },
      child: TextField(
        controller: _controller,
        focusNode: _editorFocus,
        maxLines: null,
        expands: true,
        textAlignVertical: TextAlignVertical.top,
        cursorColor: theme.colorScheme.primary,
        keyboardType: TextInputType.multiline,
        style: TextStyle(
          fontFamily: 'monospace',
          fontFamilyFallback: const ['Menlo', 'Consolas', 'Courier New'],
          fontSize: 14,
          height: 1.5,
          color: theme.colorScheme.onSurface,
        ),
        decoration: const InputDecoration(
          border: InputBorder.none,
          contentPadding: EdgeInsets.all(16),
        ),
      ),
    ),
  );

  Widget _preview(ThemeData theme, String source, {bool centered = false}) =>
      Container(
        color: theme.colorScheme.surface,
        alignment: centered ? Alignment.topCenter : Alignment.topLeft,
        child: SingleChildScrollView(
          controller: _previewScroll,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: _styledDocumentBody(
            _styleProfile,
            DocumentMarkdownView(
              source,
              maxTextWidth: 720,
              themeProfile: _styleProfile,
              chartTheme: _styleProfile,
              anchorBlockIndex: _anchorBlockIndex,
              anchorKey: _anchorKey,
              onEditChart: _editChart,
              onEditTable: _editTable,
            ),
          ),
        ),
      );
}
