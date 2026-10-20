/// De documentpresentatie van #2487: het bronbestand paginagewijs op het
/// grote scherm, met op vooraf aangewezen tabellen live bewerken.
///
/// De pagina's volgen [documentPresentationPages] — `---` en hoofdstukken,
/// dezelfde einden als de export. Live bewerken staat uit tenzij de auteur
/// een tabel vóór het presenteren aanwees; E (of het potlood) opent de
/// bewerkmodus, Esc sluit hem zonder de presentatie te verlaten. Alleen
/// bevestigde celwijzigingen gaan de bron in — via dezelfde chirurgische
/// terugschrijf als de Bron-preview — en pas dan ziet de beamer ze.
part of '../fullscreen_presenter.dart';

/// Wat de presentatie aan sessie-edits opleverde: de bewerkte body en de
/// afsluitkeuze. De aanroeper voert die uit — het scherm zelf schrijft
/// nooit naar het document.
enum DocumentExitChoice { keep, copy, discard }

class DocumentPresentationResult {
  final String body;
  final DocumentExitChoice choice;
  const DocumentPresentationResult(this.body, this.choice);
}

/// De openings-envelop voor het publieksvenster in documentmodus.
String documentAudienceArguments({
  required String markdown,
  required String? projectPath,
  required int initialIndex,
  required ThemeProfile? themeProfile,
  bool chapterBreaks = false,
}) => jsonEncode({
  'kind': 'document',
  'markdown': markdown,
  'pages': [
    for (final p in documentPresentationPages(
      markdown,
      chapterBreaks: chapterBreaks,
    ))
      [p.start, p.end],
  ],
  'index': initialIndex,
  'projectPath': projectPath,
  beamerStyleProfileKey: themeProfile?.toJson(),
});

/// Opent het publieksvenster voor een documentpresentatie; `null` als er
/// geen tweede scherm is of de vensterbrug faalt — dan is de presentatie
/// gewoon enkelscherm.
Future<AudienceWindowHandle?> openDocumentAudience({
  required String markdown,
  required String? projectPath,
  required int initialIndex,
  required ThemeProfile? themeProfile,
  bool chapterBreaks = false,
}) async {
  try {
    final controller = await WindowController.create(
      WindowConfiguration(
        arguments: documentAudienceArguments(
          markdown: markdown,
          projectPath: projectPath,
          initialIndex: initialIndex,
          themeProfile: themeProfile,
          chapterBreaks: chapterBreaks,
        ),
        hiddenAtLaunch: true,
      ),
    );
    final handle = AudienceWindowHandle(controller);
    await controller.coverScreen(presenterScreen: presenterScreenIndex());
    return handle;
  } catch (e) {
    logWarning('DocumentPresenter: publieksvenster niet geopend', e);
    return null;
  }
}

/// De presentatie-route van #2487: probeert het publieksvenster, duwt het
/// presenterscherm en ruimt het venster op als de route terugkeert. Geeft
/// de afsluitkeuze terug; `null` betekent dat de route nooit opende.
Future<DocumentPresentationResult?> presentDocument(
  BuildContext context, {
  required String body,
  required String? projectPath,
  required ThemeProfile? themeProfile,
  required Set<int> editableTables,
  required bool dualScreen,
  bool chapterBreaks = false,
}) async {
  final hadWakeLock = await _wakeLockEnabled();
  await _enableWakeLock();
  AudienceWindowHandle? audience;
  try {
    await setPresenterFullscreen(true);
    if (dualScreen) {
      audience = await openDocumentAudience(
        markdown: body,
        projectPath: projectPath,
        initialIndex: 0,
        themeProfile: themeProfile,
        chapterBreaks: chapterBreaks,
      );
    }
    if (!context.mounted) return null;
    return await Navigator.push<DocumentPresentationResult>(
      context,
      PageRouteBuilder<DocumentPresentationResult>(
        opaque: true,
        pageBuilder: (context, anim, anim2) => DocumentPresenterScreen(
          body: body,
          themeProfile: themeProfile,
          projectPath: projectPath,
          editableTables: editableTables,
          chapterBreaks: chapterBreaks,
          audience: audience,
        ),
        transitionsBuilder: (context, animation, secondary, child) =>
            FadeTransition(opacity: animation, child: child),
        transitionDuration: const Duration(milliseconds: 200),
      ),
    );
  } finally {
    await audience?.close();
    await setPresenterFullscreen(false);
    await _restoreWakeLock(hadWakeLock);
  }
}

class DocumentPresenterScreen extends StatefulWidget {
  const DocumentPresenterScreen({
    super.key,
    required this.body,
    required this.themeProfile,
    required this.projectPath,
    required this.editableTables,
    this.chapterBreaks = false,
    this.audience,
  });

  /// De documentbody zonder frontmatter, zoals de editor hem beheert.
  final String body;
  final ThemeProfile? themeProfile;
  final String? projectPath;

  /// De tabel-ordinals (documenttelling) die live bewerkt mogen worden —
  /// vooraf aangewezen, nooit impliciet.
  final Set<int> editableTables;

  /// De documentinstelling "nieuw hoofdstuk op een nieuwe pagina" — de
  /// paginatie volgt dezelfde einden als de export (FILE_FORMAT.md §14.6).
  final bool chapterBreaks;
  final AudienceWindowHandle? audience;

  @override
  State<DocumentPresenterScreen> createState() =>
      _DocumentPresenterScreenState();
}

class _DocumentPresenterScreenState extends State<DocumentPresenterScreen> {
  late String _source = widget.body;
  late List<DocumentPageRange> _pages = documentPresentationPages(
    _source,
    chapterBreaks: widget.chapterBreaks,
  );
  final _undo = <String>[];
  final _focusNode = FocusNode();
  var _page = 0;
  var _rev = 0;
  var _seq = 0;

  /// De documenttabel die in bewerkmodus staat, of `null`. De controller
  /// hoort bij die ene tabel; de rest van de pagina blijft leesweergave.
  int? _editOrdinal;
  TableEditController? _editor;

  /// Beamerstatus: `null` = enkelscherm, anders of de laatste push
  /// bevestigd is. Een mislukte sync is zichtbaar, nooit stil (#2487).
  bool? _syncOk;
  var _exitOpen = false;

  String get _pageMarkdown {
    final lines = _source.split('\n');
    final p = _pages[_page.clamp(0, _pages.length - 1)];
    return lines.sublist(p.start, p.end).join('\n');
  }

  /// De documentordinals van de tabellen op pagina [page], op volgorde.
  /// De telling loopt over de bron met dezelfde grammatica als de
  /// weergave, dus wat hier `n` heet is wat `nthTableBlockRange` als `n`
  /// terugvindt — en de `local`-de tabel van de paginarenderer is de
  /// `local`-de van deze lijst.
  List<int> _tablesOnPage(int page) {
    final p = _pages[page];
    final ordinals = <int>[];
    for (var o = 0; ; o++) {
      final r = DocumentMarkdownView.nthTableBlockRange(_source, o);
      if (r == null) break;
      if (r[0] >= p.start && r[1] <= p.end) ordinals.add(o);
    }
    return ordinals;
  }

  /// De eerste op deze pagina bewerkbare tabel, of `null`.
  int? get _editableOnPage {
    for (final o in _tablesOnPage(_page)) {
      if (widget.editableTables.contains(o)) return o;
    }
    return null;
  }

  void _setPage(int next) {
    if (_editOrdinal != null) return; // nooit midden in een edit bladeren
    _page = next.clamp(0, _pages.length - 1);
    setState(() {});
    _pushToAudience();
  }

  void _toggleEdit() {
    final l10n = context.l10n;
    if (_editOrdinal != null) {
      _exitEdit();
      return;
    }
    final ordinal = _editableOnPage;
    if (ordinal == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.d('Geen bewerkbare tabel op deze pagina'))),
      );
      return;
    }
    final range = DocumentMarkdownView.nthTableBlockRange(_source, ordinal);
    if (range == null) return;
    final lines = _source.split('\n');
    final table = decodeMarkdownTableWithAlignment(
      lines.sublist(range[0], range[1]),
    );
    final editor = TableEditController(
      rows: table.rows,
      alignments: table.alignments,
      onChanged: (rows, alignments) =>
          _applyTableEdit(ordinal, rows, alignments),
    );
    setState(() {
      _editOrdinal = ordinal;
      _editor = editor;
    });
    // De cel-velden vangen Esc en Cmd/Ctrl+Z zelf af vóór de Focus-keten —
    // daarom zit de edit-afsluiter op de hardware-handler die vóór de
    // velden komt (#2487: Esc sluit de tabel, niet de presentatie).
    HardwareKeyboard.instance.addHandler(_hardwareKeyDuringEdit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _editor == editor) editor.focusCell(0, 0);
    });
  }

  /// Toetsen tijdens celbewerking, vóór het tekstveld zelf. Geeft `true`
  /// alleen voor de toetsen die de presentator afhandelt; de rest valt
  /// gewoon door naar het veld.
  bool _hardwareKeyDuringEdit(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey == LogicalKeyboardKey.escape) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _editOrdinal != null) _exitEdit();
      });
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyZ &&
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _sessionUndo();
      });
      return true;
    }
    return false;
  }

  void _exitEdit() {
    final hadEdits = _editOrdinal != null;
    HardwareKeyboard.instance.removeHandler(_hardwareKeyDuringEdit);
    _editor?.dispose();
    setState(() {
      _editor = null;
      _editOrdinal = null;
    });
    _focusNode.requestFocus();
    // Pas nu gaat de tabel publiek: gedeelde celinvoer tijdens bewerken
    // blijft privé op de laptop, de beamer ziet uitsluitend afgeronde
    // revisies (#2487). Eén snapshot per sessie-edit, in volgorde.
    if (hadEdits) _pushToAudience();
  }

  /// Een bevestigde celwijziging: dezelfde chirurgische terugschrijf als
  /// de Bron-preview, één undo-stap per commit, en pas dán naar de beamer.
  void _applyTableEdit(
    int ordinal,
    List<List<String>> rows,
    List<TableAlign> alignments,
  ) {
    final next = _replaceTable(
      _source,
      ordinal,
      encodeMarkdownTable(rows, alignments: alignments),
    );
    if (next == _source) return;
    _undo.add(_source);
    setState(() {
      _source = next;
      _rev++;
    });
    // Niet naar de beamer: de invoer is nog privé tot de edit sluit.
  }

  String _replaceTable(String source, int ordinal, String gfm) {
    final range = DocumentMarkdownView.nthTableBlockRange(source, ordinal);
    if (range == null) return source;
    final lines = source.split('\n');
    lines.replaceRange(range[0], range[1], gfm.split('\n'));
    return lines.join('\n');
  }

  void _sessionUndo() {
    if (_undo.isEmpty) return;
    setState(() {
      _source = _undo.removeLast();
      _rev++;
      _pages = documentPresentationPages(
        _source,
        chapterBreaks: widget.chapterBreaks,
      );
      _page = _page.clamp(0, _pages.length - 1);
    });
    // De editor leest opnieuw uit de bron bij de volgende build; sluit hem
    // zodat hij geen oude celbuffer terugschrijft.
    if (_editor != null) _exitEdit();
    _pushToAudience();
  }

  /// De beamer krijgt bij elke bevestigde wijziging én elke paginawissel de
  /// volledige huidige pagina met revisie- en volgnummer — een gemiste
  /// update heelt zichzelf bij de volgende, en een herstart krijgt de
  /// volledige bron mee (#2487). Falen is zichtbaar, nooit stil.
  void _pushToAudience() {
    final audience = widget.audience;
    if (audience == null || audience.isClosed) return;
    setState(() => _syncOk = null);
    audienceChannel
        .invokeMethod('docUpdate', {
          'seq': ++_seq,
          'index': _page,
          'markdown': _pageMarkdown,
          'rev': _rev,
        })
        .then<void>((_) {
          if (mounted) setState(() => _syncOk = true);
        })
        .catchError((Object e) {
          logWarning('DocumentPresenter: beamersync mislukt', e);
          if (mounted) setState(() => _syncOk = false);
          return null;
        });
  }

  /// De afsluitkeuze van #2487: sessiewijzigingen bewaren in het document,
  /// als kopie bewaren of verwerpen — expliciet, nooit stilletjes. Sluit de
  /// route zelf af; bij een annulering blijft de presentatie staan.
  Future<void> _requestExit() async {
    if (_exitOpen || !mounted) return;
    if (_undo.isEmpty) {
      Navigator.pop(context); // geen sessie-edits: gewoon sluiten
      return;
    }
    _exitOpen = true;
    final l10n = context.l10n;
    final choice = await showDialog<DocumentExitChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: Text(l10n.d('Presentatie afsluiten')),
        content: Text(
          l10n.d(
            'Er zijn wijzigingen gemaakt tijdens de sessie. Wat moet daarmee gebeuren?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, DocumentExitChoice.discard),
            child: Text(l10n.d('Verwerpen')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, DocumentExitChoice.copy),
            child: Text(l10n.d('Bewaren als kopie')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, DocumentExitChoice.keep),
            child: Text(l10n.d('Bewaren in document')),
          ),
        ],
      ),
    );
    _exitOpen = false;
    if (choice == null || !mounted) return;
    Navigator.pop(
      context,
      DocumentPresentationResult(
        // Verwerpen geeft de onaangetaste body terug — daar hoort niets
        // mee te gebeuren, maar de aanroeper hoeft dan nooit null te lezen.
        choice == DocumentExitChoice.discard ? widget.body : _source,
        choice,
      ),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_editOrdinal != null) {
      if (key == LogicalKeyboardKey.escape) {
        _exitEdit();
        return KeyEventResult.handled;
      }
      final undo =
          key == LogicalKeyboardKey.keyZ &&
          (HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed);
      if (undo) {
        _sessionUndo();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }
    switch (key) {
      case LogicalKeyboardKey.escape:
        unawaited(_requestExit());
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyE:
        _toggleEdit();
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowRight:
      case LogicalKeyboardKey.pageDown:
      case LogicalKeyboardKey.space:
        _setPage(_page + 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.pageUp:
        _setPage(_page - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _setPage(0);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _setPage(_pages.length - 1);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.keyZ
          when HardwareKeyboard.instance.isControlPressed ||
              HardwareKeyboard.instance.isMetaPressed:
        _sessionUndo();
        return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final editing = _editOrdinal != null;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_requestExit());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Focus(
          focusNode: _focusNode,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              Positioned.fill(
                child: ColoredBox(
                  color: Theme.of(context).colorScheme.surface,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 48,
                      vertical: 32,
                    ),
                    child: DocumentMarkdownView(
                      _pageMarkdown,
                      maxTextWidth: null,
                      themeProfile: widget.themeProfile,
                      chartTheme: widget.themeProfile,
                      // Alleen de aangewezen tabel is bewerkbaar, en alleen
                      // terwijl de bewerkmodus aan staat; de ordinal op deze
                      // pagina wijst via [_tablesOnPage] naar dezelfde tabel
                      // in het document.
                      tableEditorFor: editing
                          ? (local) {
                              final tables = _tablesOnPage(_page);
                              return local < tables.length &&
                                      tables[local] == _editOrdinal
                                  ? _editor
                                  : null;
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              // Paginateller + beamerstatus + editknop: de bediening blijft
              // bij de facilitator, de beamer ziet alleen de weergave.
              Positioned(
                left: 16,
                bottom: 14,
                child: _chip(
                  context,
                  '${_page + 1} / ${_pages.length}'
                  '${widget.audience == null
                      ? ''
                      : _syncOk == null
                      ? ' · ${l10n.d('beamer')}…'
                      : _syncOk!
                      ? ' · ${l10n.d('beamer')} ✓'
                      : ' · ${l10n.d('beamer: niet bereikbaar')}'}',
                ),
              ),
              Positioned(
                right: 16,
                bottom: 14,
                child: Row(
                  children: [
                    if (_editableOnPage != null)
                      _actionChip(
                        context,
                        editing
                            ? l10n.d('Bewerken sluiten (Esc)')
                            : l10n.d('Tabel bewerken (E)'),
                        editing ? Icons.edit_note_rounded : Icons.edit_outlined,
                        _toggleEdit,
                        active: editing,
                      ),
                    const SizedBox(width: 8),
                    _actionChip(
                      context,
                      l10n.t('close'),
                      Icons.close,
                      () => unawaited(_requestExit()),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _chip(BuildContext context, String text) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: Colors.black.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(999),
    ),
    child: Text(
      text,
      style: const TextStyle(color: PresenterPalette.text, fontSize: 12),
    ),
  );

  Widget _actionChip(
    BuildContext context,
    String label,
    IconData icon,
    VoidCallback onTap, {
    bool active = false,
  }) => Material(
    color: active
        ? Theme.of(context).colorScheme.primary
        : Colors.black.withValues(alpha: 0.55),
    borderRadius: BorderRadius.circular(999),
    child: InkWell(
      borderRadius: BorderRadius.circular(999),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ],
        ),
      ),
    ),
  );

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_hardwareKeyDuringEdit);
    _editor?.dispose();
    _focusNode.dispose();
    super.dispose();
  }
}
