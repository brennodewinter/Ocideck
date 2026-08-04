import 'package:flutter/material.dart';
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

/// Dialog that scans a fixed set of well-known locations (recent-file folders
/// plus the user's Documents/Desktop/Downloads/iCloud) for Marp presentations
/// and lets the user pick one to open. OciDeck-themed decks are listed first.
///
/// Returns the chosen file path, or null when dismissed.
class ScanLibraryDialog extends StatefulWidget {
  final FileService fileService;
  final List<String> recentFiles;

  /// De thuismap voor presentaties (instelling); vindplaatsen daaronder
  /// worden er compact tegen afgezet in plaats van als volledig pad.
  final String? homeDir;

  const ScanLibraryDialog({
    super.key,
    required this.fileService,
    required this.recentFiles,
    this.homeDir,
  });

  static Future<String?> show(
    BuildContext context, {
    required FileService fileService,
    required List<String> recentFiles,
    String? homeDir,
  }) {
    return showDialog<String>(
      context: context,
      builder: (_) => ScanLibraryDialog(
        fileService: fileService,
        recentFiles: recentFiles,
        homeDir: homeDir,
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

  @override
  void initState() {
    super.initState();
    _scan();
  }

  @override
  void dispose() {
    // Stop the background walk if the dialog is closed mid-scan.
    _cancelled = true;
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

  List<DuplicateInfo<ScanHit>> _visible() {
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

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = _visible();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore, size: 20),
          const SizedBox(width: 8),
          Expanded(child: Text(l10n.d('Presentaties zoeken op deze computer'))),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: ResizableDialogBox(
        initialWidth: 760,
        height: 560,
        builder: (context, handle) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              autofocus: true,
              decoration: InputDecoration(
                isDense: true,
                prefixIcon: const Icon(Icons.search, size: 18),
                hintText: l10n.d('Zoek op titel, pad of thema…'),
              ),
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            _status(l10n),
            const SizedBox(height: 8),
            Expanded(child: _body(visible)),
            Align(alignment: Alignment.centerRight, child: handle),
          ],
        ),
      ),
      actions: [
        if (!_scanning &&
            TrashService().isSupported &&
            _groups.any((info) => info.hasIdenticalCopies))
          OutlinedButton.icon(
            onPressed: _openCleanup,
            icon: const Icon(Icons.cleaning_services_outlined, size: 16),
            label: Text(l10n.d('Dubbele presentaties opruimen')),
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
      '${_hits.length} ${l10n.d('presentatie(s) gevonden')}',
      style: TextStyle(fontSize: 11, color: AppTheme.slate500),
    );
  }

  Widget _body(List<DuplicateInfo<ScanHit>> visible) {
    final l10n = context.l10n;
    if (_scanning && _hits.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (!_scanning && _hits.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        l10n.d('Geen Marp-presentaties gevonden in de bekende mappen.'),
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen resultaten voor')} "$_query".',
      );
    }
    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) => _HitRow(
        info: visible[i],
        homeDir: widget.homeDir,
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
  final ValueChanged<String> onOpen;

  const _HitRow({
    required this.info,
    required this.homeDir,
    required this.onOpen,
  });

  ScanHit get hit => info.primary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      onTap: () => onOpen(hit.path),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            Icon(Icons.slideshow_outlined, size: 18, color: AppTheme.brandFg),
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
                      const SizedBox(width: 8),
                      _ThemeBadge(hit: hit, l10n: l10n),
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
            const SizedBox(width: 8),
            Icon(Icons.north_east, size: 16, color: AppTheme.slate500),
          ],
        ),
      ),
    );
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
