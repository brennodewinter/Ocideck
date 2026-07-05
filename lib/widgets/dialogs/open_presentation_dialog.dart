import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/slide.dart';
import '../../platform/platform_features.dart';
import '../../services/duplicate_service.dart';
import '../../services/file_service.dart';
import '../../utils/display_path.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../duplicate_badges.dart';

/// What the open dialog returns: a presentation path and, optionally, the
/// index of a slide to jump to (when the user picked a search hit).
class OpenSearchResult {
  final String path;
  final int? slideIndex;
  const OpenSearchResult(this.path, {this.slideIndex});
}

/// Dialog that scans a directory for Marp presentations and lets the user
/// full-text search across the `.md` files (file name, title and slide text)
/// before opening one. "Bladeren…" falls back to the native file picker.
class OpenPresentationDialog extends StatefulWidget {
  final FileService fileService;
  final String? initialDirectory;

  const OpenPresentationDialog({
    super.key,
    required this.fileService,
    required this.initialDirectory,
  });

  static Future<OpenSearchResult?> show(
    BuildContext context, {
    required FileService fileService,
    required String? initialDirectory,
  }) {
    return showDialog<OpenSearchResult>(
      context: context,
      builder: (_) => OpenPresentationDialog(
        fileService: fileService,
        initialDirectory: initialDirectory,
      ),
    );
  }

  @override
  State<OpenPresentationDialog> createState() => _OpenPresentationDialogState();
}

class _OpenPresentationDialogState extends State<OpenPresentationDialog> {
  String? _directory;
  bool _loading = false;
  List<ScannedPresentation> _presentations = const [];

  /// Gevonden presentaties gebundeld op identieke inhoud (de markdown is bij
  /// het scannen al ingelezen, dus dit is puur rekenwerk).
  List<DuplicateInfo<ScannedPresentation>> _groups = const [];
  String _query = '';

  @override
  void initState() {
    super.initState();
    _directory = widget.initialDirectory;
    if (_directory != null) _scan();
  }

  Future<void> _scan() async {
    final dir = _directory;
    if (dir == null) return;
    setState(() => _loading = true);
    final results = await widget.fileService.scanPresentations(dir);
    if (!mounted) return;
    setState(() {
      _presentations = results;
      _groups = DuplicateService().groupScanned(results);
      _loading = false;
    });
  }

  Future<void> _pickDirectory() async {
    final result = await FilePicker.getDirectoryPath(
      dialogTitle: context.l10n.d('Map met presentaties kiezen'),
      initialDirectory: _directory,
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _directory = result);
      await _scan();
    }
  }

  Future<void> _browse() async {
    final path = await widget.fileService.pickMarkdownFile(
      initialDirectory: _directory,
    );
    if (path != null && mounted) {
      Navigator.pop(context, OpenSearchResult(path));
    }
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

  /// Per visible presentation: the matching slide hits for the current query
  /// (empty when the match was on the file name / title, or no query).
  List<(DuplicateInfo<ScannedPresentation>, List<_SlideHit>)> _visible() {
    final q = _query.trim().toLowerCase();
    final out = <(DuplicateInfo<ScannedPresentation>, List<_SlideHit>)>[];
    if (q.isEmpty) {
      for (final info in _groups) {
        out.add((info, const []));
      }
      return out;
    }
    // Multi-word AND: every term must appear somewhere, not necessarily
    // adjacent — maximises what you can find.
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final first = terms.first;
    bool matchesAll(String hay) => terms.every(hay.contains);

    for (final info in _groups) {
      final pres = info.primary;
      // A file qualifies on its name/title or anywhere in the raw markdown
      // (front matter, comments, image paths, …) — maximal reach. Paden van
      // samengevouwen identieke kopieën zoeken mee.
      final fileHay =
          '${pres.fileName.toLowerCase()} '
          '${pres.deck.title.toLowerCase()} '
          '${info.identical.map((c) => c.path.toLowerCase()).join(' ')} '
          '${pres.content.toLowerCase()}';
      final fileMatch = matchesAll(fileHay);
      final hits = <_SlideHit>[];
      for (var i = 0; i < pres.deck.slides.length; i++) {
        final text = _slideText(pres.deck.slides[i]);
        if (matchesAll(text.toLowerCase())) {
          hits.add(_SlideHit(i, _snippet(text, first)));
        }
      }
      if (fileMatch || hits.isNotEmpty) out.add((info, hits));
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = _visible();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.folder_open_outlined, size: 20),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              l10n.d('Presentatie openen'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      contentPadding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
      content: SizedBox(
        width: 760,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _toolbar(),
            const SizedBox(height: 12),
            Expanded(child: _body(visible)),
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
      ],
      // Knoppen uit elkaar: Bladeren links, Annuleren rechts. (Geen Spacer in
      // de actions — die gaan in een OverflowBar en accepteren geen Expanded.)
      actionsAlignment: MainAxisAlignment.spaceBetween,
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
                'Zoek op bestandsnaam, titel of tekst in de slides…',
              ),
            ),
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 8),
        Tooltip(
          message: _directory ?? l10n.d('Geen map gekozen'),
          child: OutlinedButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_outlined, size: 16),
            label: Text(
              _directory == null
                  ? l10n.d('Map kiezen')
                  : p.basename(_directory!),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ],
    );
  }

  Widget _body(
    List<(DuplicateInfo<ScannedPresentation>, List<_SlideHit>)> visible,
  ) {
    final l10n = context.l10n;
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_directory == null) {
      return _empty(
        Icons.folder_off_outlined,
        l10n.d('Kies een map met presentaties om te beginnen.'),
      );
    }
    if (_presentations.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        l10n.d('Geen presentaties (.md) in deze map gevonden.'),
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen presentaties gevonden voor')} "$_query".',
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final (info, hits) = visible[i];
        return _PresentationRow(
          info: info,
          scanRoot: _directory,
          hits: hits,
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
            style: const TextStyle(color: AppTheme.slate500, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _SlideHit {
  final int index;
  final String snippet;
  const _SlideHit(this.index, this.snippet);
}

class _PresentationRow extends StatelessWidget {
  final DuplicateInfo<ScannedPresentation> info;

  /// De gescande map; de rij toont de vindplaats relatief hieraan zodat in
  /// een boom met submappen zichtbaar is wáár elk bestand staat.
  final String? scanRoot;
  final List<_SlideHit> hits;
  final ValueChanged<String> onOpen;
  final ValueChanged<int> onOpenAt;

  const _PresentationRow({
    required this.info,
    required this.scanRoot,
    required this.hits,
    required this.onOpen,
    required this.onOpenAt,
  });

  ScannedPresentation get presentation => info.primary;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = presentation.deck;
    final title = deck.title.isEmpty ? presentation.fileName : deck.title;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onOpen(presentation.path),
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
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
                                title,
                                style: const TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.slate800,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (info.hasIdenticalCopies) ...[
                              const SizedBox(width: 6),
                              IdenticalCopiesChip(
                                otherPaths: [
                                  for (final copy in info.identical) copy.path,
                                ],
                                homeDir: scanRoot,
                                onOpen: onOpen,
                              ),
                            ],
                          ],
                        ),
                        // Vindplaats relatief aan de gescande map, zodat bij
                        // submappen zichtbaar is wáár het bestand staat; het
                        // volledige pad zit in de tooltip.
                        Tooltip(
                          message: presentation.path,
                          waitDuration: const Duration(milliseconds: 400),
                          child: Text(
                            '${displayFolder(presentation.path, homeDir: scanRoot, osHome: osHomeDirectory)}'
                            '  ·  ${presentation.fileName}'
                            '  ·  ${deck.slides.length} ${l10n.t('slides')}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.slate400,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (info.hasTitleConflict) ...[
                          const SizedBox(height: 2),
                          TitleConflictMarker(modified: presentation.modified),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.north_east, size: 16, color: Colors.grey.shade500),
                ],
              ),
            ),
          ),
          if (hits.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 34, top: 2, bottom: 2),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final hit in hits.take(4))
                    InkWell(
                      onTap: () => onOpenAt(hit.index),
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 3,
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${l10n.d('Slide')} ${hit.index + 1}',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.accent,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                hit.snippet,
                                style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.slate600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  if (hits.length > 4)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, top: 2),
                      child: Text(
                        '+ ${hits.length - 4} ${l10n.d('meer treffer(s)')}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
