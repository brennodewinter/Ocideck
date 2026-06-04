import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/file_service.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';

/// Dialog that scans a directory for other Marp presentations, lets the user
/// search across them and pick individual slides to import. Returns the
/// selected slides (with image paths resolved to absolute paths) or null when
/// the dialog was cancelled.
class ImportSlidesDialog extends StatefulWidget {
  final FileService fileService;
  final String? initialDirectory;
  final String? excludePath;

  const ImportSlidesDialog({
    super.key,
    required this.fileService,
    required this.initialDirectory,
    this.excludePath,
  });

  static Future<List<Slide>?> show(
    BuildContext context, {
    required FileService fileService,
    required String? initialDirectory,
    String? excludePath,
  }) {
    return showDialog<List<Slide>>(
      context: context,
      builder: (_) => ImportSlidesDialog(
        fileService: fileService,
        initialDirectory: initialDirectory,
        excludePath: excludePath,
      ),
    );
  }

  @override
  State<ImportSlidesDialog> createState() => _ImportSlidesDialogState();
}

class _ImportSlidesDialogState extends State<ImportSlidesDialog> {
  String? _directory;
  bool _loading = false;
  List<ScannedPresentation> _presentations = const [];
  final Set<String> _selectedIds = {};
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
    if (result != null) {
      setState(() {
        _directory = result;
        _selectedIds.clear();
      });
      await _scan();
    }
  }

  String _searchText(Slide slide) {
    return [
      slide.title,
      slide.subtitle,
      ...slide.bullets,
      slide.quote,
      slide.quoteAuthor,
      slide.customMarkdown,
      slide.type.label,
    ].join(' ').toLowerCase();
  }

  /// Returns, per presentation, the slides that should be shown for the
  /// current query (preserving document order).
  List<(ScannedPresentation, List<Slide>)> _visible() {
    final q = _query.trim().toLowerCase();
    final out = <(ScannedPresentation, List<Slide>)>[];
    for (final pres in _presentations) {
      if (q.isEmpty) {
        out.add((pres, pres.deck.slides));
        continue;
      }
      final nameMatch =
          pres.deck.title.toLowerCase().contains(q) ||
          pres.fileName.toLowerCase().contains(q);
      if (nameMatch) {
        out.add((pres, pres.deck.slides));
        continue;
      }
      final matching = pres.deck.slides
          .where((s) => _searchText(s).contains(q))
          .toList();
      if (matching.isNotEmpty) out.add((pres, matching));
    }
    return out;
  }

  List<Slide> _collectSelected() {
    final result = <Slide>[];
    for (final pres in _presentations) {
      for (final slide in pres.deck.slides) {
        if (!_selectedIds.contains(slide.id)) continue;
        final resolved = _resolveImage(slide.imagePath, pres.deck.projectPath);
        result.add(
          resolved == slide.imagePath
              ? slide
              : slide.copyWith(imagePath: resolved),
        );
      }
    }
    return result;
  }

  String _resolveImage(String imagePath, String? projectPath) {
    if (imagePath.isEmpty) return imagePath;
    if (p.isAbsolute(imagePath)) return imagePath;
    if (projectPath != null) return p.join(projectPath, imagePath);
    return imagePath;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final visible = _visible();
    final selectedCount = _selectedIds.length;

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.library_add_outlined, size: 20),
          const SizedBox(width: 8),
          Text(l10n.d('Slides importeren')),
          const Spacer(),
          if (selectedCount > 0)
            Text(
              '$selectedCount ${l10n.d('geselecteerd')}',
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
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.t('cancel')),
        ),
        ElevatedButton.icon(
          onPressed: selectedCount == 0
              ? null
              : () => Navigator.pop(context, _collectSelected()),
          icon: const Icon(Icons.download_done, size: 16),
          label: Text(
            selectedCount == 0
                ? l10n.d('Importeren')
                : '${l10n.d('Importeren')} ($selectedCount)',
          ),
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
              hintText: l10n.d('Zoek op presentatie, titel of tekst…'),
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

  Widget _body(List<(ScannedPresentation, List<Slide>)> visible) {
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
        l10n.d('Geen andere presentaties (.md) in deze map gevonden.'),
      );
    }
    if (visible.isEmpty) {
      return _empty(
        Icons.search_off_outlined,
        '${l10n.d('Geen slides gevonden voor')} "$_query".',
      );
    }

    return ListView.builder(
      itemCount: visible.length,
      itemBuilder: (_, i) {
        final (pres, slides) = visible[i];
        return _PresentationSection(
          presentation: pres,
          slides: slides,
          selectedIds: _selectedIds,
          onToggle: (slide) => setState(() {
            if (!_selectedIds.remove(slide.id)) _selectedIds.add(slide.id);
          }),
          onToggleAll: (sel) => setState(() {
            for (final s in slides) {
              if (sel) {
                _selectedIds.add(s.id);
              } else {
                _selectedIds.remove(s.id);
              }
            }
          }),
        );
      },
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

// ── One presentation with its (filtered) slides ──────────────────────────────

class _PresentationSection extends StatelessWidget {
  final ScannedPresentation presentation;
  final List<Slide> slides;
  final Set<String> selectedIds;
  final ValueChanged<Slide> onToggle;
  final ValueChanged<bool> onToggleAll;

  const _PresentationSection({
    required this.presentation,
    required this.slides,
    required this.selectedIds,
    required this.onToggle,
    required this.onToggleAll,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final allSelected =
        slides.isNotEmpty && slides.every((s) => selectedIds.contains(s.id));
    final deck = presentation.deck;

    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.slideshow_outlined,
                size: 16,
                color: AppTheme.navy,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: deck.title.isEmpty
                            ? presentation.fileName
                            : deck.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF1E293B),
                        ),
                      ),
                      TextSpan(
                        text: '   ${presentation.fileName}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TextButton(
                onPressed: () => onToggleAll(!allSelected),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  textStyle: const TextStyle(fontSize: 11),
                ),
                child: Text(
                  allSelected
                      ? l10n.d('Deselecteer alles')
                      : l10n.d('Selecteer alles'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final slide in slides)
                _SlideCard(
                  slide: slide,
                  projectPath: deck.projectPath,
                  themeProfile: deck.themeProfile,
                  selected: selectedIds.contains(slide.id),
                  onTap: () => onToggle(slide),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Selectable slide thumbnail ───────────────────────────────────────────────

class _SlideCard extends StatelessWidget {
  final Slide slide;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final bool selected;
  final VoidCallback onTap;

  const _SlideCard({
    required this.slide,
    required this.projectPath,
    required this.themeProfile,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 168,
        child: Stack(
          children: [
            Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: selected ? AppTheme.accent : const Color(0xFFCBD5E1),
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(5),
                child: AspectRatio(
                  aspectRatio: 16 / 9,
                  child: SlidePreviewWidget(
                    slide: slide,
                    projectPath: projectPath,
                    themeProfile: themeProfile,
                  ),
                ),
              ),
            ),
            Positioned(
              top: 4,
              right: 4,
              child: AnimatedOpacity(
                opacity: selected ? 1 : 0.55,
                duration: const Duration(milliseconds: 120),
                child: Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: selected ? AppTheme.accent : Colors.black38,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Icon(
                    selected ? Icons.check : Icons.add,
                    size: 14,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
