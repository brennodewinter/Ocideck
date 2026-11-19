import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:path/path.dart' as p;
import '../../models/library_folder.dart';
import '../../models/markdown_kind.dart';
import '../../models/slide.dart';
import '../../platform/platform_features.dart';
import '../../services/duplicate_service.dart';
import '../../services/file_service.dart';
import '../../utils/display_path.dart';
import '../../utils/markdown_keywords.dart';
import '../../utils/table_dates.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../duplicate_badges.dart';
import '../resizable_dialog_box.dart';
import 'open_kind_chrome.dart';
import 'open_preview_pane.dart';

part 'open_presentation_file_row.dart';

/// What the open dialog returns: the chosen files and, optionally, the index of
/// a slide to jump to (when the user picked a search hit).
///
/// [paths] draagt er meestal één, maar meerdere zodra de gebruiker er meerdere
/// aanwees — elk bestand krijgt dan zijn eigen tabblad. Een dia-index hoort bij
/// één bestand: bij een stapel is er geen treffer om naartoe te springen.
///
/// [browseRequested] means the user chose "Bladeren…" — the dialog closes
/// *before* the native file picker runs. Nesting an `NSOpenPanel` under a
/// Flutter `AlertDialog` leaves `.md` greyed out on macOS even with a custom
/// panel; the caller must open the picker after this result.
class OpenSearchResult {
  final List<String> paths;
  final int? slideIndex;
  final bool browseRequested;

  OpenSearchResult(String path, {this.slideIndex})
    : paths = [path],
      browseRequested = false,
      kind = OpenKindFilter.all;

  /// Meerdere bestanden tegelijk, in de volgorde waarin de lijst ze toonde.
  OpenSearchResult.multiple(this.paths)
    : slideIndex = null,
      browseRequested = false,
      kind = OpenKindFilter.all;

  const OpenSearchResult.browse({this.kind = OpenKindFilter.all})
    : paths = const [],
      slideIndex = null,
      browseRequested = true;

  /// Het soortfilter op het moment van Bladeren, zodat de native kiezer in
  /// de startmap van dát soort opent (#2394).
  final OpenKindFilter kind;
}

/// Dialog that scans the configured libraries for editable Markdown files and
/// lets the user full-text search across them (file name, title and the text
/// inside) before opening one. Every library is walked deeply (subfolders
/// included) and results are merged, each row showing which library it came
/// from. The folder button narrows the search to one browsed folder;
/// "Bladeren…" falls back to the native file picker.
///
/// Presentaties én documenten staan in dezelfde lijst. De documentkant bewerkt
/// gewone `.md`-bestanden, dus een zoeklijst die alleen decks toont, verstopt
/// de helft van wat je met dit programma kunt openen; het filter bovenin haalt
/// de andere soort weg wanneer je wél gericht zoekt.
class OpenPresentationDialog extends StatefulWidget {
  final FileService fileService;

  /// The libraries to scan. Empty shows an inviting empty state.
  final List<LibraryFolder> libraries;

  /// Of er een gerenderd voorbeeld naast de lijst staat (instelling
  /// `showOpenPreview`, standaard uit).
  final bool showPreview;

  const OpenPresentationDialog({
    super.key,
    required this.fileService,
    required this.libraries,
    this.showPreview = false,
  });

  static Future<OpenSearchResult?> show(
    BuildContext context, {
    required FileService fileService,
    required List<LibraryFolder> libraries,
    bool showPreview = false,
  }) {
    return showDialog<OpenSearchResult>(
      context: context,
      builder: (_) => OpenPresentationDialog(
        fileService: fileService,
        libraries: libraries,
        showPreview: showPreview,
      ),
    );
  }

  @override
  State<OpenPresentationDialog> createState() => _OpenPresentationDialogState();
}

enum _OpenSort { name, newest, oldest }

class _OpenPresentationDialogState extends State<OpenPresentationDialog> {
  /// De te doorzoeken wortels. Start op de geconfigureerde bibliotheken; de
  /// mapkeuze-knop kan tijdelijk naar één specifieke map versmallen.
  late List<LibraryFolder> _roots;
  bool _loading = false;
  List<ScannedMarkdown> _files = const [];

  /// Gevonden bestanden gebundeld op identieke inhoud (de markdown is bij
  /// het scannen al ingelezen, dus dit is puur rekenwerk).
  List<DuplicateInfo<ScannedMarkdown>> _groups = const [];

  /// Genormaliseerd pad → de bibliotheek waaronder het valt, voor de
  /// vindplaats-weergave per rij (naam + map relatief aan die wortel).
  final Map<String, LibraryFolder> _rootOf = {};
  String _query = '';
  String _tagQuery = '';
  OpenKindFilter _kind = OpenKindFilter.all;
  _OpenSort _sort = _OpenSort.name;

  /// Het bestand waarvan het voorbeeld getoond wordt; null zolang er niets is
  /// aangewezen. Alleen in gebruik als [OpenPresentationDialog.showPreview].
  String? _previewPath;

  /// De bestanden die met Ctrl/Cmd- of Shift-klik zijn aangewezen om
  /// tegelijk te openen. Als pad bewaard en niet als rij-index: de zichtbare
  /// lijst verschuift bij elke aanslag in het zoekveld en bij elke wissel van
  /// het soortfilter, en een index zou dan een ander bestand aanwijzen.
  final Set<String> _selected = {};

  /// Waarvandaan Shift+klik zijn bereik meet: het laatst met Ctrl/Cmd
  /// aangewezen bestand. Null zolang er niets is aangewezen.
  String? _anchor;

  /// De met het toetsenbord aangewezen rij (null = niets gekozen). Pijltje
  /// omlaag vanuit null kiest de eerste rij; Enter opent hem. Visueel los
  /// van [_selected]: de focusrand markeert waar de pijl staat, de
  /// blauwe achtergrond markeert wat Ctrl/Cmd heeft aangewezen.
  int? _focusedIndex;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _roots = List.of(widget.libraries);
    if (_roots.isNotEmpty) _scan();
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  /// De eerste wortel als startmap voor de native pickers.
  String? get _firstRootPath => _roots.isEmpty ? null : _roots.first.path;

  Future<void> _scan() async {
    if (_roots.isEmpty) return;
    setState(() => _loading = true);
    final all = <ScannedMarkdown>[];
    final rootOf = <String, LibraryFolder>{};
    final seen = <String>{};
    for (final root in _roots) {
      final results = await widget.fileService.scanMarkdownFiles(root.path);
      for (final r in results) {
        final norm = p.normalize(r.path);
        // Overlappende bibliotheken: elk bestand één keer, onder de eerste
        // wortel die het opleverde.
        if (!seen.add(norm)) continue;
        all.add(r);
        rootOf[norm] = root;
      }
    }
    all.sort(
      (a, b) =>
          a.displayTitle.toLowerCase().compareTo(b.displayTitle.toLowerCase()),
    );
    if (!mounted) return;
    setState(() {
      _files = all;
      _rootOf
        ..clear()
        ..addAll(rootOf);
      _groups = DuplicateService().groupScanned(all);
      _loading = false;
    });
  }

  Future<void> _pickDirectory() async {
    // Ook hier, niet alleen bij de aanroeper in shell_actions.dart: op web
    // bestaat `getDirectoryPath` niet en geeft het stil null terug, en dan
    // doet de knop niets zonder één woord uitleg (#150). De poort bij de
    // aanroeper is vandaag correct, maar dit bestand kon dat niet zelf
    // bewijzen — en een garantie die elders staat, verdwijnt bij de
    // eerstvolgende nieuwe aanroeper.
    if (!supportsLocalProjectFolders) return;
    final result = localDirectoryPath(
      await FilePicker.pickDirectory(
        dialogTitle: context.l10n.d('Map met presentaties kiezen'),
        initialDirectory: _firstRootPath,
      ),
    );
    if (!mounted) return;
    if (result != null) {
      setState(
        () => _roots = [LibraryFolder(name: p.basename(result), path: result)],
      );
      await _scan();
    }
  }

  /// Klik met modifier: Shift = bereik, Ctrl/Cmd = toevoegen/verwijderen,
  /// anders openen. Spiegelt de slidelijst, waar de gebruiker dezelfde
  /// handgreep al kent — zie `SlideListPanel._onSlideTap`.
  ///
  /// Een kale klik opent meteen, ook wanneer er al iets is aangewezen: dat is
  /// het gedrag dat deze lijst altijd had, en het is de handeling die de
  /// gebruiker hier in negen van de tien gevallen wil. Wie meerdere bestanden
  /// bedoelt, houdt een modificatietoets vast en drukt daarna op "Openen (n)".
  void _onRowTap(List<String> visiblePaths, int index) {
    final keys = HardwareKeyboard.instance;
    final path = visiblePaths[index];
    if (keys.isShiftPressed) {
      // Zonder anker (Shift als eerste handeling) is het bereik die ene rij.
      final anchorIndex = _anchor == null ? -1 : visiblePaths.indexOf(_anchor!);
      final from = anchorIndex < 0 ? index : anchorIndex;
      final lo = from < index ? from : index;
      final hi = from < index ? index : from;
      setState(() {
        _selected.addAll(visiblePaths.sublist(lo, hi + 1));
        _anchor ??= path;
      });
    } else if (keys.isControlPressed || keys.isMetaPressed) {
      setState(() {
        if (!_selected.remove(path)) _selected.add(path);
        _anchor = path;
      });
    } else {
      Navigator.pop(context, OpenSearchResult(path));
    }
  }

  /// Open alles wat is aangewezen, in de volgorde waarin de lijst het toonde.
  void _openSelection(List<String> visiblePaths) {
    final chosen = [
      for (final path in visiblePaths)
        if (_selected.contains(path)) path,
    ];
    if (chosen.isEmpty) return;
    Navigator.pop(context, OpenSearchResult.multiple(chosen));
  }

  Future<void> _browse() async {
    // Sluit eerst: zie [OpenSearchResult.browseRequested]. De startmap geeft
    // de aanroeper mee via de geconfigureerde wortels (eerste bibliotheek).
    Navigator.pop(context, OpenSearchResult.browse(kind: _kind));
  }

  /// Pijltje/Enter/Home/End op de dialoog. Deze handler zit op een `Focus`
  /// om de hele dialoog-content, dus hij krijgt alleen toetsen die het
  /// gefocuste widget (bijv. het zoekveld) niet zelf consumeert — pijltjes
  /// in het zoekveld bewegen de cursor en borrelen niet op, Enter wel.
  KeyEventResult _onDialogKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final visible = _visibleList();
    if (visible.isEmpty) return KeyEventResult.ignored;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
      case LogicalKeyboardKey.arrowRight:
        _focusIndex((_focusedIndex ?? -1) + 1, visible);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
      case LogicalKeyboardKey.arrowLeft:
        _focusIndex((_focusedIndex ?? visible.length) - 1, visible);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.home:
        _focusIndex(0, visible);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.end:
        _focusIndex(visible.length - 1, visible);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
        final i = _focusedIndex ?? 0;
        if (i >= visible.length) return KeyEventResult.ignored;
        Navigator.pop(context, OpenSearchResult(visible[i].$1.primary.path));
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _focusIndex(
    int i,
    List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)> visible,
  ) {
    final clamped = i.clamp(0, visible.length - 1);
    setState(() {
      _focusedIndex = clamped;
      if (widget.showPreview) {
        _previewPath = visible[clamped].$1.primary.path;
      }
    });
    _scrollToIndex(clamped, visible.length);
  }

  List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)> _visibleList([
    List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)>? matches,
  ]) {
    final visible = [
      for (final entry in matches ?? _matching())
        if (_kind.accepts(entry.$1.primary.kind)) entry,
    ];
    if (_sort == _OpenSort.name) return visible;

    final dates = {
      for (final entry in visible)
        entry.$1.primary.path: _sortDate(entry.$1.primary),
    };
    return visible..sort((a, b) {
      final left = a.$1.primary;
      final right = b.$1.primary;
      final l = dates[left.path];
      final r = dates[right.path];
      if (l == null && r != null) return 1;
      if (l != null && r == null) return -1;
      if (l != null && r != null) {
        final order = _sort == _OpenSort.newest
            ? r.compareTo(l)
            : l.compareTo(r);
        if (order != 0) return order;
      }
      final titleOrder = left.displayTitle.toLowerCase().compareTo(
        right.displayTitle.toLowerCase(),
      );
      return titleOrder == 0 ? left.path.compareTo(right.path) : titleOrder;
    });
  }

  void _scrollToIndex(int index, int total) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final position = _scrollController.position;
      if (total <= 1) return;
      final avgItem =
          (position.maxScrollExtent + position.viewportDimension) / total;
      _scrollController.animateTo(
        (avgItem * index).clamp(0.0, position.maxScrollExtent),
        duration: const Duration(milliseconds: 100),
        curve: Curves.easeOut,
      );
    });
  }

  /// Label van de mapkeuze-knop: bij meerdere wortels "Alle bibliotheken", bij
  /// één de bibliotheeknaam (of mapnaam), en anders de uitnodiging om te kiezen.
  String _rootsButtonLabel(AppLocalizations l10n) {
    if (_roots.isEmpty) return l10n.d('Map kiezen');
    if (_roots.length > 1) return l10n.d('Alle bibliotheken');
    final only = _roots.first;
    return only.name.trim().isEmpty ? p.basename(only.path) : only.name;
  }

  String _slideText(Slide slide) {
    return [
      slide.title,
      slide.subtitle,
      ...slide.bullets,
      slide.quote,
      slide.quoteAuthor,
      slide.customMarkdown,
      slide.imageCaption,
      slide.imageCaption2,
      slide.imagePath,
      slide.imagePath2,
      slide.videoPath,
      slide.videoCaptions,
      slide.audioPath,
      slide.notes,
    ].where((s) => s.isNotEmpty).join('  ·  ');
  }

  /// A short excerpt of [text] centred on the first occurrence of [query].
  String _snippet(String text, String query) {
    final lower = text.toLowerCase();
    final idx = lower.indexOf(query);
    if (idx < 0) return text.length <= 80 ? text : '${text.substring(0, 80)}…';
    final start = (idx - 24).clamp(0, text.length);
    final end = (idx + query.length + 48).clamp(0, text.length);
    final prefix = start > 0 ? '…' : '';
    final suffix = end < text.length ? '…' : '';
    return '$prefix${text.substring(start, end).trim()}$suffix';
  }

  /// Per gevonden bestand: de treffers binnenin voor de huidige zoekterm (leeg
  /// wanneer de match op de bestandsnaam/titel viel, of zonder zoekterm).
  ///
  /// Het soortfilter zit hier bewust niet in: het scherm heeft zowel de
  /// gefilterde lijst als de aantallen per soort nodig, en dat zijn twee kijken
  /// op één zoekactie — geen twee zoekacties.
  List<String> get _requiredTags => [
    for (final part in _tagQuery.split(','))
      if (part.trim().isNotEmpty) part.trim(),
  ];

  bool _tagsMatch(String content) =>
      markdownHasKeywords(content, _requiredTags);

  List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)> _matching() {
    final q = _query.trim().toLowerCase();
    final out = <(DuplicateInfo<ScannedMarkdown>, List<_Hit>)>[];
    final groups = _groups;
    if (q.isEmpty) {
      for (final info in groups) {
        if (_tagsMatch(info.primary.content)) out.add((info, const []));
      }
      return out;
    }
    // Multi-word AND: every term must appear somewhere, not necessarily
    // adjacent — maximises what you can find.
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final first = terms.first;
    bool matchesAll(String hay) => terms.every(hay.contains);

    for (final info in groups) {
      final file = info.primary;
      // Eén keer verlagen per bestand: de bron kan megabytes zijn en dit loopt
      // bij élke aanslag opnieuw.
      final contentLower = file.content.toLowerCase();
      // A file qualifies on its name/title or anywhere in the raw markdown
      // (front matter, comments, image paths, …) — maximal reach. Paden van
      // samengevouwen identieke kopieën zoeken mee.
      final fileHay =
          '${file.fileName.toLowerCase()} '
          '${file.displayTitle.toLowerCase()} '
          '${info.identical.map((c) => c.path.toLowerCase()).join(' ')} '
          '$contentLower';
      final fileMatch = matchesAll(fileHay);
      final hits = _hitsIn(file, first, matchesAll, contentLower);
      if ((fileMatch || hits.isNotEmpty) && _tagsMatch(file.content)) {
        out.add((info, hits));
      }
    }
    return out;
  }

  /// De treffers binnen één bestand: per dia bij een presentatie, per regel bij
  /// een document. Een document kent geen dia om naartoe te springen, dus daar
  /// is de treffer een leesbaar fragment zonder sprongdoel.
  List<_Hit> _hitsIn(
    ScannedMarkdown file,
    String first,
    bool Function(String) matchesAll,
    String contentLower,
  ) {
    final hits = <_Hit>[];
    final deck = file.deck;
    if (deck != null) {
      for (var i = 0; i < deck.slides.length; i++) {
        final text = _slideText(deck.slides[i]);
        if (matchesAll(text.toLowerCase())) {
          hits.add(_Hit(_snippet(text, first), slideIndex: i));
        }
      }
      return hits;
    }
    // Staat de term niet in het bestand, dan hoeft het er ook niet regel voor
    // regel doorheen — dat scheelt bij elke aanslag een wandeling per bestand.
    if (!contentLower.contains(first)) return const [];
    for (final line in file.content.split('\n')) {
      final text = line.trim();
      if (text.isEmpty) continue;
      // Eén term is genoeg per regel: de AND geldt over het hele bestand, dat
      // hierboven al is vastgesteld.
      if (text.toLowerCase().contains(first)) {
        hits.add(_Hit(_snippet(text, first)));
      }
      if (hits.length >= 8) break;
    }
    return hits;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final found = _matching();
    final visible = _visibleList(found);
    final documents = found.where((e) => e.$1.primary.kind.isDocument).length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.folder_open_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(l10n.d('Openen'), overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: ResizableDialogBox(
        initialWidth: widget.showPreview ? 1020 : 760,
        height: 560,
        builder: (context, handle) => Focus(
          onKeyEvent: _onDialogKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _toolbar(),
              const SizedBox(height: 8),
              TextField(
                key: const Key('open-tag-filter'),
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.label_outline, size: 18),
                  hintText: l10n.d('Filter op trefwoorden, komma-gescheiden…'),
                ),
                onChanged: (v) => setState(() {
                  _tagQuery = v;
                  _focusedIndex = null;
                }),
              ),
              const SizedBox(height: 8),
              OpenKindFilterBar(
                value: _kind,
                onChanged: (v) => setState(() {
                  _kind = v;
                  _focusedIndex = null;
                }),
                presentationCount: found.length - documents,
                documentCount: documents,
              ),
              const SizedBox(height: 8),
              Expanded(
                child: _withPreview(
                  // Het soortlabel per rij alleen wanneer er écht twee soorten
                  // gevonden zijn: in een lijst waarin alles een presentatie is,
                  // zegt "Presentatie" bij elke regel niets meer.
                  (previewShown) => _body(
                    visible,
                    previewShown,
                    documents > 0 && documents < found.length,
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      l10n.d(
                        'Klik met Ctrl/Cmd of Shift om meerdere bestanden te kiezen.',
                      ),
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  handle,
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: _browse,
          icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
          label: Text(l10n.d('Bladeren…')),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        // Alleen zichtbaar zodra er meerdere aangewezen zijn: zonder selectie
        // opent een klik op de rij al, en een knop die hetzelfde nog eens
        // belooft maakt het scherm alleen drukker.
        if (_selected.isNotEmpty)
          FilledButton.icon(
            onPressed: () =>
                _openSelection([for (final e in visible) e.$1.primary.path]),
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text('${l10n.d('Openen')} (${_selected.length})'),
          ),
      ],
      // Knoppen uit elkaar: Bladeren links, Annuleren rechts. (Geen Spacer in
      // de actions — die gaan in een OverflowBar en accepteren geen Expanded.)
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }

  /// De lijst, met het voorbeeld ernaast wanneer de instelling aan staat én er
  /// ruimte voor is. Of het past, gaat de lijst in: staat het voorbeeld er niet,
  /// dan hoort een rij ook geen voorbeeldknop te dragen die nergens toe leidt.
  Widget _withPreview(Widget Function(bool previewShown) body) {
    if (!widget.showPreview) return body(false);
    return LayoutBuilder(
      builder: (context, constraints) {
        if (!OpenPreviewSplit.fitsBeside(constraints.maxWidth)) {
          return body(false);
        }
        return OpenPreviewSplit(
          list: body(true),
          pane: OpenPreviewPane(
            fileService: widget.fileService,
            path: _previewPath,
          ),
        );
      },
    );
  }

  Widget _toolbar() {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: TextField(
            autofocus: true,
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search, size: 18),
              hintText: l10n.d(
                'Zoek op bestandsnaam, titel of tekst in het bestand…',
              ),
            ),
            onChanged: (v) => setState(() {
              _query = v;
              _focusedIndex = null;
            }),
          ),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: l10n.d('Vernieuwen'),
          onPressed: _roots.isEmpty || _loading ? null : _scan,
          icon: const Icon(Icons.refresh),
        ),
        PopupMenuButton<_OpenSort>(
          tooltip: l10n.d('Sorteren'),
          icon: const Icon(Icons.sort),
          onSelected: (sort) {
            setState(() {
              _sort = sort;
              _focusedIndex = null;
            });
            if (_scrollController.hasClients) _scrollController.jumpTo(0);
          },
          itemBuilder: (_) => [
            CheckedPopupMenuItem(
              value: _OpenSort.name,
              checked: _sort == _OpenSort.name,
              child: Text(l10n.d('Naam')),
            ),
            CheckedPopupMenuItem(
              value: _OpenSort.newest,
              checked: _sort == _OpenSort.newest,
              child: Text(l10n.d('Nieuwste eerst')),
            ),
            CheckedPopupMenuItem(
              value: _OpenSort.oldest,
              checked: _sort == _OpenSort.oldest,
              child: Text(l10n.d('Oudste eerst')),
            ),
          ],
        ),
        Tooltip(
          message: _roots.isEmpty
              ? l10n.d('Geen bibliotheek')
              : _roots.map((r) => r.path).join('\n'),
          child: OutlinedButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(
              _rootsButtonLabel(l10n),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(
    List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)> visible,
    bool previewShown,
    bool showKind,
  ) {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_roots.isEmpty) {
      return _empty(
        Icons.folder_off_outlined,
        l10n.d(
          'Nog geen bibliotheek. Voeg er een toe bij Instellingen, of kies hierboven een map om te doorzoeken.',
        ),
      );
    }
    if (_files.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        l10n.d(
          'Geen presentaties of documenten gevonden in deze map(pen). Kies hierboven een andere map, of bladeren naar een bestand op deze computer.',
        ),
        action: OutlinedButton.icon(
          onPressed: _browse,
          icon: const Icon(Icons.insert_drive_file_outlined, size: 16),
          label: Text(l10n.d('Bladeren…')),
        ),
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen resultaten voor')} "$_query".',
      );
    }

    final visiblePaths = [for (final e in visible) e.$1.primary.path];
    return ListView.separated(
      controller: _scrollController,
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final (info, hits) = visible[i];
        final root = _rootOf[p.normalize(info.primary.path)];
        return _FileRow(
          info: info,
          scanRoot: root?.path,
          // Toon de bibliotheeknaam alleen als er meerdere in beeld zijn.
          rootName: _roots.length > 1 ? (root?.name ?? '') : '',
          hits: hits,
          showKind: showKind,
          showPreview: previewShown,
          selected: _selected.contains(info.primary.path),
          focused: _focusedIndex == i,
          onTap: () => _onRowTap(visiblePaths, i),
          onPreview: (path) => setState(() => _previewPath = path),
          onOpen: (path) => Navigator.pop(context, OpenSearchResult(path)),
          onOpenAt: (index) => Navigator.pop(
            context,
            OpenSearchResult(info.primary.path, slideIndex: index),
          ),
        );
      },
    );
  }

  Widget _empty(IconData icon, String message, {Widget? action}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: AppTheme.slate400),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.slate500, fontSize: 13),
          ),
          if (action != null) ...[const SizedBox(height: 16), action],
        ],
      ),
    );
  }
}

DateTime? _presentationDate(ScannedMarkdown file) =>
    parseIsoDateCell(file.deck?.date ?? '');

DateTime? _sortDate(ScannedMarkdown file) =>
    _presentationDate(file) ?? file.modified;

/// Eén treffer binnen een bestand: het fragment, en — alleen bij een
/// presentatie — de dia waar het staat.
class _Hit {
  final int? slideIndex;
  final String snippet;
  const _Hit(this.snippet, {this.slideIndex});
}
