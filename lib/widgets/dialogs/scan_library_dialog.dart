import 'package:flutter/material.dart';
import '../../platform/platform_features.dart';
import '../../services/file_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/display_path.dart';

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
    setState(() {
      _hits = results;
      _scanning = false;
    });
  }

  List<ScanHit> _visible() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return _hits;
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    bool matchesAll(String hay) => terms.every(hay.contains);
    return _hits.where((h) {
      final hay =
          '${h.displayTitle.toLowerCase()} '
          '${h.path.toLowerCase()} '
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
      content: SizedBox(
        width: 760,
        height: 560,
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
              onChanged: (v) => setState(() => _query = v),
            ),
            const SizedBox(height: 8),
            _status(l10n),
            const SizedBox(height: 8),
            Expanded(child: _body(visible)),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
      ],
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
            style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      );
    }
    return Text(
      '${_hits.length} ${l10n.d('presentatie(s) gevonden')}',
      style: const TextStyle(fontSize: 11, color: AppTheme.slate500),
    );
  }

  Widget _body(List<ScanHit> visible) {
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
        hit: visible[i],
        homeDir: widget.homeDir,
        onOpen: () => Navigator.pop(context, visible[i].path),
      ),
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
            style: const TextStyle(color: AppTheme.slate500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _HitRow extends StatelessWidget {
  final ScanHit hit;
  final String? homeDir;
  final VoidCallback onOpen;

  const _HitRow({
    required this.hit,
    required this.homeDir,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return InkWell(
      onTap: onOpen,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 10),
        child: Row(
          children: [
            const Icon(
              Icons.slideshow_outlined,
              size: 18,
              color: AppTheme.navy,
            ),
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
                          style: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF1E293B),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ThemeBadge(hit: hit, l10n: l10n),
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
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppTheme.slate400,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(Icons.north_east, size: 16, color: Colors.grey.shade500),
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
    final color = isOci ? AppTheme.accent : AppTheme.slate400;
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
