import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import '../../models/markdown_kind.dart';
import '../../platform/platform_features.dart';
import '../../services/duplicate_service.dart';
import '../../services/file_service.dart';
import '../../services/trash_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/display_path.dart';
import '../duplicate_badges.dart';
import '../resizable_dialog_box.dart';
import 'duplicate_cleanup_dialog.dart';
import 'open_kind_chrome.dart';
import 'open_preview_pane.dart';

/// Dialog that scans a fixed set of well-known locations (recent-file folders
/// plus the user's Documents/Desktop/Downloads/iCloud) for editable Markdown
/// files and lets the user pick one to open. Presentaties staan vooraan
/// (OciDeck-thema eerst), daarna de platte documenten; het filter bovenin toont
/// één soort.
///
/// Returns the chosen file path, or null when dismissed.
class ScanLibraryDialog extends StatefulWidget {
  final FileService fileService;
  final List<String> recentFiles;

  /// De thuismap voor presentaties (instelling); vindplaatsen daaronder
  /// worden er compact tegen afgezet in plaats van als volledig pad.
  final String? homeDir;

  /// Of er een gerenderd voorbeeld naast de lijst staat (instelling
  /// `showOpenPreview`, standaard uit).
  final bool showPreview;

  const ScanLibraryDialog({
    super.key,
    required this.fileService,
    required this.recentFiles,
    this.homeDir,
    this.showPreview = false,
  });

  static Future<String?> show(
    BuildContext context, {
    required FileService fileService,
    required List<String> recentFiles,
    String? homeDir,
    bool showPreview = false,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ScanLibraryDialog(
        fileService: fileService,
        recentFiles: recentFiles,
        homeDir: homeDir,
        showPreview: showPreview,
      ),
    );
  }

  @override
  State<ScanLibraryDialog> createState() => _ScanLibraryDialogState();
}

class _ScanLibraryDialogState extends State<ScanLibraryDialog> {
  bool _scanning = true;
  bool _cancelled = false;
  List<ScanHit> _hits = const [];

  /// Treffers gebundeld op identieke inhoud: één zichtbare vermelding per
  /// unieke presentatie, met haar andere vindplaatsen eronder gehangen.
  List<DuplicateInfo<ScanHit>> _groups = const [];
  String _phase = '';
  String _query = '';
  OpenKindFilter _kind = OpenKindFilter.all;

  /// Het bestand waarvan het voorbeeld getoond wordt; null zolang er niets is
  /// aangewezen. Alleen in gebruik als [ScanLibraryDialog.showPreview].
  String? _previewPath;

  /// De met het toetsenbord aangewezen rij (null = niets gekozen).
  int? _focusedIndex;

  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    _cancelled = true;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _scan() async {
    final results = await widget.fileService.scanKnownLocations(
      recentFiles: widget.recentFiles,
      isCancelled: () => _cancelled,
      onProgress: (phase, _) {
        if (mounted) setState(() => _phase = phase);
      },
    );
    if (!mounted) return;
    final groups = await DuplicateService().groupScanHits(results);
    if (!mounted) return;
    setState(() {
      _hits = results;
      _groups = groups;
      _scanning = false;
    });
  }

  /// De groepen die aan de zoekterm voldoen — nog zonder het soortfilter, zodat
  /// de aantallen op de filterknoppen bij dezelfde zoekactie horen als de lijst.
  List<DuplicateInfo<ScanHit>> _matching() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _groups;
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    bool matchesAll(String hay) => terms.every(hay.contains);
    return _groups.where((info) {
      // De vindplaatsen van identieke kopieën zoeken mee, zodat een pad van
      // een samengevouwen kopie de groep gewoon vindt.
      final h = info.primary;
      final hay =
          '${h.displayTitle.toLowerCase()} '
          '${h.path.toLowerCase()} '
          '${info.identical.map((c) => c.path.toLowerCase()).join(' ')} '
          '${h.theme?.toLowerCase() ?? ''}';
      return matchesAll(hay);
    }).toList();
  }

  /// Pijltje/Enter/Home/End op de dialoog — zie [OpenPresentationDialog].
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
        Navigator.pop(context, visible[i].primary.path);
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _focusIndex(int i, List<DuplicateInfo<ScanHit>> visible) {
    final clamped = i.clamp(0, visible.length - 1);
    setState(() {
      _focusedIndex = clamped;
      if (widget.showPreview) {
        _previewPath = visible[clamped].primary.path;
      }
    });
    _scrollToIndex(clamped, visible.length);
  }

  List<DuplicateInfo<ScanHit>> _visibleList() {
    final found = _matching();
    return [
      for (final info in found)
        if (_kind.accepts(info.primary.kind)) info,
    ];
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final found = _matching();
    final visible = [
      for (final info in found)
        if (_kind.accepts(info.primary.kind)) info,
    ];
    final documents = found.where((i) => i.primary.kind.isDocument).length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.d('Bestanden zoeken op deze computer'))),
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
              TextField(
                autofocus: true,
                decoration: InputDecoration(
                  isDense: true,
                  prefixIcon: const Icon(Icons.search, size: 18),
                  hintText: l10n.d('Zoek op titel, pad of thema…'),
                ),
                onChanged: (v) => setState(() {
                  _query = v;
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
              _status(l10n),
              const SizedBox(height: 8),
              Expanded(
                child: _withPreview(
                  // Zie [OpenPresentationDialog]: het soortlabel hoort bij een
                  // gemengde lijst, niet bij een lijst met één soort erin.
                  (previewShown) => _body(
                    visible,
                    previewShown,
                    documents > 0 && documents < found.length,
                  ),
                ),
              ),
              Align(alignment: Alignment.centerRight, child: handle),
            ],
          ),
        ),
      ),
      actions: [
        if (!_scanning &&
            TrashService().isSupported &&
            _groups.any((info) => info.hasIdenticalCopies))
          OutlinedButton.icon(
            onPressed: _openCleanup,
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(l10n.d('Dubbele bestanden opruimen')),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
      ],
      actionsAlignment: MainAxisAlignment.spaceBetween,
    );
  }

  Widget _status(AppLocalizations l10n) {
    if (_scanning) {
      final phase = _phase.isEmpty ? '' : '  ·  $_phase';
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const LinearProgressIndicator(minHeight: 4),
          const SizedBox(height: 6),
          Text(
            '${l10n.d('Bekende mappen worden doorzocht…')}'
            '$phase  ·  ${_hits.length} ${l10n.d('gevonden')}',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    return Text(
      '${_hits.length} ${l10n.d('bestand(en) gevonden')}',
      style: TextStyle(fontSize: 11, color: AppTheme.slate500),
    );
  }

  /// De lijst, met het voorbeeld ernaast wanneer de instelling aan staat én er
  /// ruimte voor is. Zie [OpenPresentationDialog]: past het voorbeeld niet, dan
  /// dragen de rijen ook geen voorbeeldknop.
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

  Widget _body(
    List<DuplicateInfo<ScanHit>> visible,
    bool previewShown,
    bool showKind,
  ) {
    final l10n = context.l10n;
    if (_scanning && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_scanning && _hits.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        l10n.d(
          'Geen presentaties of documenten gevonden in de bekende mappen.',
        ),
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen resultaten voor')} "$_query".',
      );
    }
    return ListView.separated(
      controller: _scrollController,
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _HitRow(
        info: visible[i],
        homeDir: widget.homeDir,
        showKind: showKind,
        showPreview: previewShown,
        focused: _focusedIndex == i,
        onPreview: (path) => setState(() => _previewPath = path),
        onOpen: (path) => Navigator.pop(context, path),
      ),
    );
  }

  /// Groepen met échte kopieën, klaar voor de opruimdialoog.
  List<CleanupGroup> _cleanupGroups() {
    return [
      for (final info in _groups)
        if (info.hasIdenticalCopies)
          CleanupGroup(
            title: info.primary.displayTitle,
            paths: [for (final hit in info.all) hit.path],
          ),
    ];
  }

  Future<void> _openCleanup() async {
    final changed = await DuplicateCleanupDialog.show(
      context,
      groups: _cleanupGroups(),
      homeDir: widget.homeDir,
    );
    if (changed && mounted) {
      setState(() {
        _scanning = true;
        _hits = const [];
        _groups = const [];
      });
      await _scan();
    }
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

class _HitRow extends StatelessWidget {
  final DuplicateInfo<ScanHit> info;
  final String? homeDir;

  /// Of het soortlabel achter de titel staat; zie de aanroeper.
  final bool showKind;
  final bool showPreview;

  /// Of deze rij de toetsenbordfocus draagt — de zichtbare focusrand.
  final bool focused;

  final ValueChanged<String> onPreview;
  final ValueChanged<String> onOpen;

  const _HitRow({
    required this.info,
    required this.homeDir,
    required this.showKind,
    required this.showPreview,
    required this.focused,
    required this.onPreview,
    required this.onOpen,
  });

  ScanHit get hit => info.primary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final row = InkWell(
      onTap: () => onOpen(hit.path),
      borderRadius: BorderRadius.circular(6),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: focused
              ? Border.all(color: AppTheme.accentFg, width: 1.6)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Icon(markdownKindIcon(hit.kind), size: 18, color: AppTheme.brandFg),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          hit.displayTitle,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.slate800,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (showKind) ...[
                        const SizedBox(width: 8),
                        MarkdownKindBadge(kind: hit.kind),
                      ],
                      // Het thema is een Marp-eigenschap; bij een document zou
                      // "Geen thema" een gemis suggereren dat er niet is.
                      if (hit.kind.isPresentation) ...[
                        const SizedBox(width: 6),
                        _ThemeBadge(hit: hit, l10n: l10n),
                      ],
                      if (info.hasIdenticalCopies) ...[
                        const SizedBox(width: 6),
                        IdenticalCopiesChip(
                          otherPaths: [
                            for (final copy in info.identical) copy.path,
                          ],
                          homeDir: homeDir,
                          onOpen: onOpen,
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 2),
                  // Vindplaats compact (thuismap-relatief of ~-afgekort);
                  // het volledige pad zit in de tooltip.
                  Tooltip(
                    message: hit.path,
                    waitDuration: const Duration(milliseconds: 400),
                    child: Text(
                      '${displayFolder(hit.path, homeDir: homeDir, osHome: osHomeDirectory)}'
                      '  ·  ${hit.fileName}',
                      style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (info.hasTitleConflict) ...[
                    const SizedBox(height: 2),
                    TitleConflictMarker(modified: hit.modified),
                  ],
                ],
              ),
            ),
            if (showPreview) ...[
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.visibility_outlined, size: 16),
                tooltip: l10n.d('Voorbeeld tonen'),
                visualDensity: VisualDensity.compact,
                onPressed: () => onPreview(hit.path),
              ),
            ],
            const SizedBox(width: 8),
            Icon(Icons.north_east, size: 16, color: AppTheme.slate500),
          ],
        ),
      ),
    );
    if (!showPreview) return row;
    // Aanwijzen met de muis laat het voorbeeld meelopen; de knop hierboven doet
    // hetzelfde voor wie met het toetsenbord of op een aanraakscherm werkt.
    return MouseRegion(onEnter: (_) => onPreview(hit.path), child: row);
  }
}

class _ThemeBadge extends StatelessWidget {
  final ScanHit hit;
  final AppLocalizations l10n;

  const _ThemeBadge({required this.hit, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final isOci = hit.isOcideckTheme;
    final label = isOci ? 'OciDeck' : (hit.theme ?? l10n.d('Geen thema'));
    final color = isOci ? AppTheme.accentFg : AppTheme.slate400;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
