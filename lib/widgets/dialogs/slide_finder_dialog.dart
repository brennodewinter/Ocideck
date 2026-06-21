import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/slide.dart';
import '../../services/file_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';

/// A single search hit: one slide from a scanned presentation.
class _Hit {
  final ScannedPresentation source;
  final int slideIndex;
  final Slide slide;
  const _Hit(this.source, this.slideIndex, this.slide);

  String get key => '${source.path}#$slideIndex';
}

/// "Slide finder": search across every presentation in a directory and add
/// matching, fully-rendered slides to the current presentation. The dialog
/// stays open so several slides can be gathered in one session.
class SlideFinderDialog extends StatefulWidget {
  final FileService fileService;
  final String? initialDirectory;
  final String? excludePath;

  /// Called with a slide (image paths already resolved to absolute) that the
  /// user wants to add to the current presentation.
  final void Function(Slide slide) onAdd;

  const SlideFinderDialog({
    super.key,
    required this.fileService,
    required this.initialDirectory,
    required this.onAdd,
    this.excludePath,
  });

  static Future<void> show(
    BuildContext context, {
    required FileService fileService,
    required String? initialDirectory,
    required void Function(Slide slide) onAdd,
    String? excludePath,
  }) {
    return showDialog<void>(
      context: context,
      builder: (_) => SlideFinderDialog(
        fileService: fileService,
        initialDirectory: initialDirectory,
        onAdd: onAdd,
        excludePath: excludePath,
      ),
    );
  }

  @override
  State<SlideFinderDialog> createState() => _SlideFinderDialogState();
}

class _SlideFinderDialogState extends State<SlideFinderDialog> {
  static const _maxResults = 200;

  String? _directory;
  bool _loading = false;
  List<ScannedPresentation> _presentations = const [];
  String _query = '';
  int _addedCount = 0;
  final _addedKeys = <String>{};

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
    final results = await widget.fileService.scanPresentations(
      dir,
      excludePath: widget.excludePath,
    );
    if (!mounted) return;
    setState(() {
      _presentations = results;
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

  /// Flat, capped list of slides matching the current query (every term must
  /// appear somewhere in the slide).
  List<_Hit> _hits() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    final terms = q.split(RegExp(r'\s+')).where((t) => t.isNotEmpty).toList();
    final hits = <_Hit>[];
    for (final pres in _presentations) {
      for (var i = 0; i < pres.deck.slides.length; i++) {
        final text = _slideText(pres.deck.slides[i]);
        if (terms.every(text.contains)) {
          hits.add(_Hit(pres, i, pres.deck.slides[i]));
          if (hits.length >= _maxResults) return hits;
        }
      }
    }
    return hits;
  }

  void _add(_Hit hit) {
    final projectPath = hit.source.deck.projectPath;
    final resolved = hit.slide.copyWith(
      imagePath: _resolve(hit.slide.imagePath, projectPath),
      imagePath2: _resolve(hit.slide.imagePath2, projectPath),
    );
    widget.onAdd(resolved);
    setState(() {
      _addedKeys.add(hit.key);
      _addedCount++;
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final hits = _hits();

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.travel_explore_outlined, size: 20),
          const SizedBox(width: 8),
          Text(l10n.d('Slide zoeken')),
          const Spacer(),
          if (_addedCount > 0)
            Text(
              '$_addedCount ${l10n.d('toegevoegd')}',
              style: const TextStyle(
                fontSize: 12,
                color: AppTheme.accent,
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
            Expanded(child: _body(hits)),
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
          message: _directory ?? l10n.d('Geen map gekozen'),
          child: OutlinedButton.icon(
            onPressed: _pickDirectory,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
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

  Widget _body(List<_Hit> hits) {
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
    if (_query.trim().isEmpty) {
      return _empty(
        Icons.travel_explore_outlined,
        l10n.d('Typ zoektermen om slides uit al je presentaties te vinden.'),
      );
    }
    if (hits.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen slides gevonden voor')} "${_query.trim()}".',
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 8, left: 2),
          child: Text(
            hits.length >= _maxResults
                ? '${l10n.d('Eerste')} $_maxResults ${l10n.d('treffers — verfijn je zoekopdracht')}'
                : '${hits.length} ${l10n.d('treffer(s)')}',
            style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
          ),
        ),
        Expanded(
          child: GridView.builder(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 280,
              mainAxisSpacing: 14,
              crossAxisSpacing: 14,
              childAspectRatio: 0.78,
            ),
            itemCount: hits.length,
            itemBuilder: (_, i) => _SlideHitCard(
              hit: hits[i],
              added: _addedKeys.contains(hits[i].key),
              onAdd: () => _add(hits[i]),
            ),
          ),
        ),
      ],
    );
  }

  Widget _empty(IconData icon, String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: const Color(0xFF94A3B8)),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF64748B), fontSize: 13),
          ),
        ],
      ),
    );
  }
}

// ── A rendered slide result with an add button ───────────────────────────────

class _SlideHitCard extends StatelessWidget {
  final _Hit hit;
  final bool added;
  final VoidCallback onAdd;

  const _SlideHitCard({
    required this.hit,
    required this.added,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final deck = hit.source.deck;
    final sourceName = deck.title.isEmpty ? hit.source.fileName : deck.title;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Expanded(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                color: added ? AppTheme.accent : const Color(0xFFCBD5E1),
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
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '$sourceName · ${l10n.d('slide')} ${hit.slideIndex + 1}',
          style: const TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 4),
        SizedBox(
          height: 28,
          child: added
              ? OutlinedButton.icon(
                  onPressed: onAdd,
                  icon: const Icon(Icons.check, size: 14),
                  label: Text(l10n.d('Toegevoegd')),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.accent,
                    side: const BorderSide(color: AppTheme.accent),
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
}
