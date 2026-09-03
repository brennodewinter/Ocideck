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
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../duplicate_badges.dart';
import '../resizable_dialog_box.dart';
import 'open_kind_chrome.dart';
import 'open_preview_pane.dart';

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
      browseRequested = false;

  /// Meerdere bestanden tegelijk, in de volgorde waarin de lijst ze toonde.
  OpenSearchResult.multiple(this.paths)
    : slideIndex = null,
      browseRequested = false;

  const OpenSearchResult.browse()
    : paths = const [],
      slideIndex = null,
      browseRequested = true;
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
  OpenKindFilter _kind = OpenKindFilter.all;

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

  @override
  void initState() {
    super.initState();
    _roots = List.of(widget.libraries);
    if (_roots.isNotEmpty) _scan();
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
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met presentaties kiezen'),
      initialDirectory: _firstRootPath,
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
    Navigator.pop(context, const OpenSearchResult.browse());
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
  List<(DuplicateInfo<ScannedMarkdown>, List<_Hit>)> _matching() {
    final q = _query.trim().toLowerCase();
    final out = <(DuplicateInfo<ScannedMarkdown>, List<_Hit>)>[];
    final groups = _groups;
    if (q.isEmpty) {
      for (final info in groups) {
        out.add((info, const []));
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
      if (fileMatch || hits.isNotEmpty) out.add((info, hits));
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
    final visible = [
      for (final entry in found)
        if (_kind.accepts(entry.$1.primary.kind)) entry,
    ];
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
        builder: (context, handle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            const SizedBox(height: 8),
            OpenKindFilterBar(
              value: _kind,
              onChanged: (v) => setState(() => _kind = v),
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
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 8),
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
        l10n.d('Geen presentaties of documenten gevonden.'),
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

  Widget _empty(IconData icon, String message) {
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
        ],
      ),
    );
  }
}

/// Eén treffer binnen een bestand: het fragment, en — alleen bij een
/// presentatie — de dia waar het staat.
class _Hit {
  final int? slideIndex;
  final String snippet;
  const _Hit(this.snippet, {this.slideIndex});
}

class _FileRow extends StatelessWidget {
  final DuplicateInfo<ScannedMarkdown> info;

  /// De gescande map; de rij toont de vindplaats relatief hieraan zodat in
  /// een boom met submappen zichtbaar is wáár elk bestand staat.
  final String? scanRoot;

  /// Naam van de bibliotheek waaronder dit bestand valt; leeg wanneer er maar
  /// één wortel in beeld is (dan voegt de naam niets toe).
  final String rootName;
  final List<_Hit> hits;

  /// Of het soortlabel achter de titel staat; zie de aanroeper.
  final bool showKind;
  final bool showPreview;

  /// Of dit bestand is aangewezen om samen met andere geopend te worden.
  final bool selected;

  /// Klik op de rij. De dialoog leest de modificatietoetsen: kaal openen,
  /// met Ctrl/Cmd of Shift de selectie veranderen.
  final VoidCallback onTap;
  final ValueChanged<String> onPreview;

  /// Open dit ene bestand meteen, buiten de selectie om — de identieke-kopie-
  /// chip en een trefferregel in een document wijzen elk één bestand aan.
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onOpenAt;

  const _FileRow({
    required this.info,
    required this.scanRoot,
    required this.rootName,
    required this.hits,
    required this.showKind,
    required this.showPreview,
    required this.selected,
    required this.onTap,
    required this.onPreview,
    required this.onOpen,
    required this.onOpenAt,
  });

  ScannedMarkdown get file => info.primary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            selected: selected,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(6),
              child: Container(
                decoration: BoxDecoration(
                  // Aangewezen rijen krijgen dezelfde blauwe tint die de app
                  // elders voor een info-vlak gebruikt; die schakelt mee met
                  // licht en donker.
                  color: selected ? AppTheme.infoBg : null,
                  borderRadius: BorderRadius.circular(6),
                ),
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                child: Row(
                  children: [
                    Icon(
                      markdownKindIcon(file.kind),
                      size: 18,
                      color: AppTheme.brandFg,
                    ),
                    const SizedBox(width: 10),
                    Expanded(child: _titleAndPlace(l10n)),
                    if (showPreview) ...[
                      const SizedBox(width: 4),
                      IconButton(
                        icon: const Icon(Icons.visibility_outlined, size: 16),
                        tooltip: l10n.d('Voorbeeld tonen'),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => onPreview(file.path),
                      ),
                    ],
                    const SizedBox(width: 8),
                    // Het pijltje belooft "dit opent"; bij een aangewezen rij
                    // is dat niet meer waar — die wacht op "Openen (n)".
                    selected
                        ? Icon(
                            Icons.check_circle,
                            size: 16,
                            color: AppTheme.accentFg,
                          )
                        : Icon(
                            Icons.north_east,
                            size: 16,
                            color: AppTheme.slate500,
                          ),
                  ],
                ),
              ),
            ),
          ),
          if (hits.isNotEmpty) _hitList(l10n),
        ],
      ),
    );
    if (!showPreview) return row;
    // Aanwijzen met de muis laat het voorbeeld meelopen; de knop hierboven doet
    // hetzelfde voor wie met het toetsenbord of op een aanraakscherm werkt.
    return MouseRegion(onEnter: (_) => onPreview(file.path), child: row);
  }

  Widget _titleAndPlace(AppLocalizations l10n) {
    final deck = file.deck;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Flexible(
              child: Text(
                file.displayTitle,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: AppTheme.slate800,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (showKind) ...[
              const SizedBox(width: 6),
              MarkdownKindBadge(kind: file.kind),
            ],
            if (info.hasIdenticalCopies) ...[
              const SizedBox(width: 6),
              IdenticalCopiesChip(
                otherPaths: [for (final copy in info.identical) copy.path],
                homeDir: scanRoot,
                onOpen: onOpen,
              ),
            ],
          ],
        ),
        // Vindplaats relatief aan de gescande map, zodat bij submappen
        // zichtbaar is wáár het bestand staat; het volledige pad zit in de
        // tooltip.
        Tooltip(
          message: file.path,
          waitDuration: const Duration(milliseconds: 400),
          child: Text(
            '${rootName.isEmpty ? '' : '$rootName  ·  '}'
            '${displayFolder(file.path, homeDir: scanRoot, osHome: osHomeDirectory)}'
            '  ·  ${file.fileName}'
            '${deck == null ? '' : '  ·  ${deck.slides.length} ${l10n.t('slides')}'}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate400),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (info.hasTitleConflict) ...[
          const SizedBox(height: 2),
          TitleConflictMarker(modified: file.modified),
        ],
      ],
    );
  }

  Widget _hitList(AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.only(left: 34, top: 2, bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final hit in hits.take(4)) _hitRow(l10n, hit),
          if (hits.length > 4)
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 2),
              child: Text(
                '+ ${hits.length - 4} ${l10n.d('meer treffer(s)')}',
                style: TextStyle(fontSize: 11, color: AppTheme.slate400),
              ),
            ),
        ],
      ),
    );
  }

  /// Eén trefferregel. Bij een presentatie springt hij naar de dia; bij een
  /// document opent hij het bestand — daar is geen dia om naartoe te gaan, en
  /// een label dat een sprong belooft die niet bestaat, is erger dan geen label.
  Widget _hitRow(AppLocalizations l10n, _Hit hit) {
    final index = hit.slideIndex;
    return InkWell(
      onTap: () => index == null ? onOpen(file.path) : onOpenAt(index),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (index != null) ...[
              Text(
                '${l10n.d('Slide')} ${index + 1}',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: AppTheme.accentFg,
                ),
              ),
              const SizedBox(width: 8),
            ],
            Expanded(
              child: Text(
                hit.snippet,
                style: TextStyle(fontSize: 12, color: AppTheme.slate600),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
