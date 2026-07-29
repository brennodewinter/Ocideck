import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/library_folder.dart';
import '../../models/slide.dart';
import '../../services/file_service.dart';
import '../../services/presentation_search/presentation_source.dart';
import '../../services/slide_dedup_service.dart';
import '../../services/slide_image_refs.dart';
import '../../theme/app_theme.dart';
import '../../utils/log.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';
import 'slide_diff_dialog.dart';
import '../../platform/platform_features.dart';

/// A single search hit: one slide from a scanned presentation.
class _Hit {
  final ScannedPresentation source;
  final int slideIndex;
  final Slide slide;
  const _Hit(this.source, this.slideIndex, this.slide);

  String get key => '${source.path}#$slideIndex';

  /// The deck's title, or its file name when untitled — used to label where a
  /// slide came from.
  String get sourceName =>
      source.deck.title.isEmpty ? source.fileName : source.deck.title;
}

/// "Slide finder": search across every presentation in the configured
/// libraries (and the open deck's own folder) and add matching, fully-rendered
/// slides to the current presentation. Every root is walked deeply and results
/// are merged, so slides from *all* designated sources are searched — not only
/// the folder the current deck happens to live in. The dialog stays open so
/// several slides can be gathered in one session.
class SlideFinderDialog extends StatefulWidget {
  final FileService fileService;

  /// The roots to scan (libraries plus the open deck's folder). Empty shows an
  /// inviting empty state. Overlapping roots are de-duplicated per file.
  final List<LibraryFolder> roots;

  /// Remote bronnen (git, WebDAV, S3) die naast de lokale mappen worden
  /// doorzocht. Elke bron scant op de achtergrond bij het openen; treffers
  /// verschijnen zodra ze binnen zijn.
  final List<PresentationSource> remoteSources;
  final String? excludePath;

  /// Called with a slide (image paths already resolved to absolute) that the
  /// user wants to add to the current presentation.
  final void Function(Slide slide) onAdd;

  const SlideFinderDialog({
    super.key,
    required this.fileService,
    required this.roots,
    required this.onAdd,
    this.remoteSources = const [],
    this.excludePath,
  });

  static Future<void> show(
    BuildContext context, {
    required FileService fileService,
    required List<LibraryFolder> roots,
    required void Function(Slide slide) onAdd,
    List<PresentationSource> remoteSources = const [],
    String? excludePath,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SlideFinderDialog(
        fileService: fileService,
        roots: roots,
        onAdd: onAdd,
        remoteSources: remoteSources,
        excludePath: excludePath,
      ),
    );
  }

  @override
  State<SlideFinderDialog> createState() => _SlideFinderDialogState();
}

class _SlideFinderDialogState extends State<SlideFinderDialog> {
  static const _maxResults = 200;

  final _dedup = SlideDedupService();

  /// De te doorzoeken lokale wortels. Start op alle aangewezen bibliotheken; de
  /// mapkeuze-knop kan tijdelijk naar één specifieke map versmallen.
  late List<LibraryFolder> _roots;
  bool _localLoading = false;

  /// Lokale treffers (herladen bij een mapkeuze) en remote treffers (druppelen
  /// binnen per bron). Apart gehouden zodat een nieuwe lokale scan de remote
  /// resultaten niet weggooit.
  List<ScannedPresentation> _local = const [];
  List<ScannedPresentation> _remote = const [];

  /// Labels van remote bronnen die nog scannen, en die faalden — voor de
  /// voortgangs- en foutmelding boven het raster.
  final Set<String> _remotePending = {};
  final Set<String> _remoteFailed = {};

  String _query = '';
  int _addedCount = 0;

  /// Added slides, keyed by their content signature so every identical copy of
  /// an added slide shows as added — not just the one card that was clicked.
  final _addedSignatures = <String>{};

  @override
  void initState() {
    super.initState();
    _roots = List.of(widget.roots);
    _scanLocal();
    _remotePending.addAll(widget.remoteSources.map((s) => s.label));
    for (final source in widget.remoteSources) {
      _scanRemote(source);
    }
  }

  /// De eerste wortel als startmap voor de native mapkiezer.
  String? get _firstRootPath => _roots.isEmpty ? null : _roots.first.path;

  /// Alle presentaties, lokaal plus remote, in scan-volgorde.
  List<ScannedPresentation> get _all => [..._local, ..._remote];

  Future<void> _scanLocal() async {
    if (_roots.isEmpty) {
      setState(() => _local = const []);
      return;
    }
    setState(() => _localLoading = true);
    final all = <ScannedPresentation>[];
    final seen = <String>{};
    for (final root in _roots) {
      final results = await widget.fileService.scanPresentations(
        root.path,
        excludePath: widget.excludePath,
      );
      for (final r in results) {
        // Overlappende bronmappen: elk bestand hooguit één keer.
        if (seen.add(p.normalize(r.path))) all.add(r);
      }
    }
    if (!mounted) return;
    setState(() {
      _local = all;
      _localLoading = false;
    });
  }

  /// Scan één remote bron op de achtergrond; de treffers verschijnen zodra ze
  /// er zijn. Een fout blijft bij deze bron — hij verhuist van "bezig" naar
  /// "mislukt" — zonder de andere bronnen of het lokale zoeken te blokkeren.
  Future<void> _scanRemote(PresentationSource source) async {
    try {
      final results = await source.scan();
      if (!mounted) return;
      final seen = _remote.map((e) => e.path).toSet();
      final fresh = [
        for (final r in results)
          if (seen.add(r.path)) r,
      ];
      setState(() {
        _remote = [..._remote, ...fresh];
        _remotePending.remove(source.label);
      });
    } catch (e) {
      logWarning(
        'SlideFinder: bron kon niet worden doorzocht (${source.label})',
        e,
      );
      if (!mounted) return;
      setState(() {
        _remotePending.remove(source.label);
        _remoteFailed.add(source.label);
      });
    }
  }

  Future<void> _pickDirectory() async {
    // Ook hier, niet alleen bij de aanroeper in slide_list_panel.dart: op web
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
      await _scanLocal();
    }
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
      slide.type.label,
    ].join(' ').toLowerCase();
  }

  String _resolve(String imagePath, String? projectPath) {
    if (imagePath.isEmpty || p.isAbsolute(imagePath)) return imagePath;
    if (projectPath != null) return p.join(projectPath, imagePath);
    return imagePath;
  }

  /// Every slide matching the current query (each term must appear somewhere in
  /// the slide), in scan order. De-duplication happens afterwards in [_dedup].
  List<_Hit> _matches() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final matches = <_Hit>[];
    for (final pres in _all) {
      for (var i = 0; i < pres.deck.slides.length; i++) {
        final text = _slideText(pres.deck.slides[i]);
        if (terms.every(text.contains)) {
          matches.add(_Hit(pres, i, pres.deck.slides[i]));
        }
      }
    }
    return matches;
  }

  void _add(SlideGroup<_Hit> group) {
    final hit = group.primary;
    final projectPath = hit.source.deck.projectPath;
    // Élke verwijzing wordt absoluut gemaakt tegen het bron-deck, ook een
    // `![…](…)` in de vrije tekst — anders wijst een relatief pad na het
    // toevoegen naar de map van de ontvangende presentatie.
    final resolved = rewriteSlideImagePaths(
      hit.slide,
      (path) => _resolve(path, projectPath),
    );
    widget.onAdd(resolved);
    setState(() {
      _addedSignatures.add(group.signature);
      _addedCount++;
    });
  }

  /// Open the side-by-side comparison for a group and its look-alikes.
  void _compare(
    AppLocalizations l10n,
    SlideGroup<_Hit> group,
    List<SlideGroup<_Hit>> similar,
  ) {
    SlideDiffRef refOf(_Hit h) => SlideDiffRef(
      label: '${h.sourceName} · ${l10n.d('slide')} ${h.slideIndex + 1}',
      slide: h.slide,
      projectPath: h.source.deck.projectPath,
      themeProfile: h.source.deck.themeProfile,
    );

    SlideDiffDialog.show(
      context,
      primary: refOf(group.primary),
      others: [for (final g in similar) refOf(g.primary)],
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final result = _dedup.dedupe(
      _matches(),
      (h) => h.slide,
      maxGroups: _maxResults,
    );

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.d('Slide zoeken'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const Spacer(),
          if (_addedCount > 0)
            Text(
              '$_addedCount ${l10n.d('toegevoegd')}',
              style: TextStyle(
                fontSize: 12,
                color: AppTheme.accentFg,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 900,
        height: 600,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            const SizedBox(height: 12),
            Expanded(child: _body(result)),
          ],
        ),
      ),
      actions: [
        ElevatedButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.d('Klaar')),
        ),
      ],
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
                'Zoek slides op tekst, titel, onderschrift, pad…',
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
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(
              _rootsButtonLabel(l10n),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(SlideDedupResult<_Hit> result) {
    final l10n = context.l10n;
    final scanning = _localLoading || _remotePending.isNotEmpty;
    // Alleen een vol scherm-spinner zolang er nog niets te tonen is; zodra er
    // treffers zijn scant de rest op de achtergrond verder (voortgangsregel).
    if (scanning && _all.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_roots.isEmpty && widget.remoteSources.isEmpty) {
      return _empty(
        Icons.folder_off_outlined,
        l10n.d(
          'Nog geen bibliotheek. Voeg er een toe bij Instellingen, of kies hierboven een map om te doorzoeken.',
        ),
      );
    }
    if (_query.trim().isEmpty) {
      return _empty(
        Icons.travel_explore_outlined,
        l10n.d('Typ zoektermen om slides uit al je presentaties te vinden.'),
      );
    }
    final groups = result.groups;
    if (groups.isEmpty) {
      // Nog niet alles doorzocht: "niets gevonden" zou misleiden.
      if (scanning) {
        return _empty(
          Icons.travel_explore_outlined,
          l10n.d('Bronnen doorzoeken…'),
        );
      }
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen slides gevonden voor')} "${_query.trim()}".',
      );
    }

    final hidden = groups.fold<int>(0, (n, g) => n + g.copies) - groups.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Row(
            children: [
              Flexible(
                child: Text(
                  _resultSummary(l10n, groups.length, hidden, result.truncated),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (scanning) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 11,
                  height: 11,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 6),
                Text(
                  l10n.d('Bronnen doorzoeken…'),
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                ),
              ],
              if (_remoteFailed.isNotEmpty) ...[
                const SizedBox(width: 10),
                Tooltip(
                  message:
                      '${l10n.d('Niet doorzocht')}:\n${_remoteFailed.join('\n')}',
                  child: Icon(
                    Icons.error_outline,
                    size: 14,
                    color: AppTheme.amber700,
                  ),
                ),
              ],
            ],
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.72,
            ),
            itemCount: groups.length,
            itemBuilder: (_, i) {
              final group = groups[i];
              final similar = [for (final j in result.similar[i]) groups[j]];
              return _SlideHitCard(
                group: group,
                similar: similar,
                added: _addedSignatures.contains(group.signature),
                onAdd: () => _add(group),
                onCompare: similar.isEmpty
                    ? null
                    : () => _compare(l10n, group, similar),
              );
            },
          ),
        ),
      ],
    );
  }

  /// One-line count above the grid: distinct slides, how many duplicates were
  /// merged away, and whether the list was capped.
  String _resultSummary(
    AppLocalizations l10n,
    int distinct,
    int hidden,
    bool truncated,
  ) {
    if (truncated) {
      return '${l10n.d('Eerste')} $_maxResults ${l10n.d('slides — verfijn je zoekopdracht')}';
    }
    final base = '$distinct ${l10n.d('unieke slide(s)')}';
    if (hidden <= 0) return base;
    return '$base · $hidden ${l10n.d('duplica(a)t(en) verborgen')}';
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

// ── A de-duplicated slide result with add and compare actions ────────────────

class _SlideHitCard extends StatelessWidget {
  /// The slides collapsed onto one card (identical content across decks).
  final SlideGroup<_Hit> group;

  /// Distinct-but-look-alike slides, offered via the "differences" action.
  final List<SlideGroup<_Hit>> similar;
  final bool added;
  final VoidCallback onAdd;
  final VoidCallback? onCompare;

  const _SlideHitCard({
    required this.group,
    required this.similar,
    required this.added,
    required this.onAdd,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hit = group.primary;
    final deck = hit.source.deck;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Stack(
            children: [
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: added ? AppTheme.accentFg : AppTheme.slate300,
                      width: added ? 2 : 1,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(5),
                    child: AspectRatio(
                      aspectRatio: 16 / 9,
                      child: SlidePreviewWidget(
                        slide: hit.slide,
                        projectPath: deck.projectPath,
                        themeProfile: deck.themeProfile,
                        improvementY01: deck.improvementY01Metric,
                      ),
                    ),
                  ),
                ),
              ),
              if (group.hasCopies)
                Positioned(top: 4, left: 4, child: _copiesBadge(l10n)),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          group.hasCopies
              ? '${hit.sourceName} · ${l10n.d('slide')} ${hit.slideIndex + 1} +${group.copies - 1}'
              : '${hit.sourceName} · ${l10n.d('slide')} ${hit.slideIndex + 1}',
          style: TextStyle(fontSize: 10.5, color: AppTheme.slate400),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (onCompare != null) ...[
          const SizedBox(height: 2),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: onCompare,
              icon: const Icon(Icons.difference_outlined, size: 13),
              label: Text(
                similar.length == 1
                    ? l10n.d('Verschillen')
                    : '${l10n.d('Verschillen')} (${similar.length})',
              ),
              style: TextButton.styleFrom(
                foregroundColor: AppTheme.amber700,
                padding: const EdgeInsets.symmetric(horizontal: 4),
                minimumSize: const Size(0, 24),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                textStyle: const TextStyle(fontSize: 11),
              ),
            ),
          ),
        ],
        SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: added
              ? OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: Icon(Icons.check, size: 14),
                  label: Text(l10n.d('Toegevoegd')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accentFg,
                    side: BorderSide(color: AppTheme.accentFg),
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                )
              : ElevatedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.add, size: 14),
                  label: Text(l10n.d('Toevoegen')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    textStyle: const TextStyle(fontSize: 11),
                  ),
                ),
        ),
      ],
    );
  }

  /// "In N presentaties" chip listing every deck this exact slide was found in.
  Widget _copiesBadge(AppLocalizations l10n) {
    return PopupMenuButton<void>(
      tooltip: l10n.d('In meerdere presentaties'),
      itemBuilder: (_) => [
        for (final h in group.occurrences)
          PopupMenuItem<void>(
            enabled: false,
            height: 32,
            child: Tooltip(
              message: h.source.path,
              child: Text(
                '${h.sourceName} · ${l10n.d('slide')} ${h.slideIndex + 1}',
                style: const TextStyle(fontSize: 12),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: AppTheme.accent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.copy_all_outlined, size: 11, color: Colors.white),
            const SizedBox(width: 3),
            Text(
              '${group.copies}',
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
