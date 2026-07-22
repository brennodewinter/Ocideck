import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../services/file_service.dart';
import '../../services/slide_dedup_service.dart';
import '../../services/slide_image_refs.dart';
import '../../theme/app_theme.dart';
import '../../l10n/app_localizations.dart';
import '../slides/slide_preview.dart';
import 'slide_diff_dialog.dart';

/// One place a slide was found while scanning: the deck plus the slide. Used to
/// de-duplicate identical slides across decks and to label where they live.
class _Occ {
  final ScannedPresentation pres;
  final Slide slide;
  const _Occ(this.pres, this.slide);

  String get sourceName =>
      pres.deck.title.isEmpty ? pres.fileName : pres.deck.title;

  /// 1-based position of the slide in its deck, for labels/tooltips.
  int get slideNumber => pres.deck.slides.indexOf(slide) + 1;

  String label(AppLocalizations l10n) =>
      '$sourceName · ${l10n.d('slide')} $slideNumber';
}

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
  final _dedup = SlideDedupService();

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
    if (!mounted) return;
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
        // Élke verwijzing wordt absoluut gemaakt tegen het bron-deck, ook een
        // `![…](…)` in de vrije tekst. Een relatief pad betekent hier iets
        // anders dan in de presentatie waar de dia naartoe gaat, dus zonder
        // deze stap wijst het na de import naar de verkeerde map.
        result.add(
          rewriteSlideImagePaths(
            slide,
            (path) => _resolveImage(path, pres.deck.projectPath),
          ),
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

  /// Open the side-by-side comparison for a shown slide and its look-alikes.
  void _compare(
    AppLocalizations l10n,
    _Occ primary,
    List<SlideGroup<_Occ>> similar,
  ) {
    SlideDiffRef refOf(_Occ o) => SlideDiffRef(
      label: o.label(l10n),
      slide: o.slide,
      projectPath: o.pres.deck.projectPath,
      themeProfile: o.pres.deck.themeProfile,
    );

    SlideDiffDialog.show(
      context,
      primary: refOf(primary),
      others: [for (final g in similar) refOf(g.primary)],
    );
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
          Flexible(
            child: Text(
              l10n.d('Slides importeren'),
              overflow: TextOverflow.ellipsis,
            ),
          ),
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

    // De-duplicate identical slides across the whole (query-filtered) view: the
    // slide is shown once, at its first occurrence, and hidden from later decks.
    final occs = [
      for (final (pres, slides) in visible)
        for (final s in slides) _Occ(pres, s),
    ];
    final result = _dedup.dedupe(occs, (o) => o.slide);
    final groupByPrimaryId = <String, SlideGroup<_Occ>>{};
    final similarByPrimaryId = <String, List<SlideGroup<_Occ>>>{};
    for (var i = 0; i < result.groups.length; i++) {
      final g = result.groups[i];
      groupByPrimaryId[g.primary.slide.id] = g;
      similarByPrimaryId[g.primary.slide.id] = [
        for (final j in result.similar[i]) result.groups[j],
      ];
    }

    // Re-project onto the per-deck sections, keeping only primary occurrences.
    final sections = <(ScannedPresentation, List<Slide>)>[];
    for (final (pres, slides) in visible) {
      final kept = slides
          .where((s) => groupByPrimaryId.containsKey(s.id))
          .toList();
      if (kept.isNotEmpty) sections.add((pres, kept));
    }

    return ListView.builder(
      itemCount: sections.length,
      itemBuilder: (_, i) {
        final (pres, slides) = sections[i];
        return _PresentationSection(
          presentation: pres,
          slides: slides,
          selectedIds: _selectedIds,
          groupByPrimaryId: groupByPrimaryId,
          similarByPrimaryId: similarByPrimaryId,
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
          onCompare: (primary, similar) => _compare(l10n, primary, similar),
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

// ── One presentation with its (filtered) slides ──────────────────────────────

class _PresentationSection extends StatelessWidget {
  final ScannedPresentation presentation;
  final List<Slide> slides;
  final Set<String> selectedIds;
  final Map<String, SlideGroup<_Occ>> groupByPrimaryId;
  final Map<String, List<SlideGroup<_Occ>>> similarByPrimaryId;
  final ValueChanged<Slide> onToggle;
  final ValueChanged<bool> onToggleAll;
  final void Function(_Occ primary, List<SlideGroup<_Occ>> similar) onCompare;

  const _PresentationSection({
    required this.presentation,
    required this.slides,
    required this.selectedIds,
    required this.groupByPrimaryId,
    required this.similarByPrimaryId,
    required this.onToggle,
    required this.onToggleAll,
    required this.onCompare,
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
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.slate800,
                        ),
                      ),
                      TextSpan(
                        text: '   ${presentation.fileName}',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppTheme.slate400,
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
                _slideCardFor(slide, deck.projectPath, deck.themeProfile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slideCardFor(Slide slide, String? projectPath, ThemeProfile theme) {
    final group = groupByPrimaryId[slide.id];
    final similar = similarByPrimaryId[slide.id] ?? const [];
    return _SlideCard(
      slide: slide,
      projectPath: projectPath,
      themeProfile: theme,
      selected: selectedIds.contains(slide.id),
      occurrences: group?.occurrences ?? const [],
      onTap: () => onToggle(slide),
      onCompare: (similar.isEmpty || group == null)
          ? null
          : () => onCompare(group.primary, similar),
    );
  }
}

// ── Selectable slide thumbnail ───────────────────────────────────────────────

class _SlideCard extends StatelessWidget {
  final Slide slide;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final bool selected;

  /// Every place this exact slide was found (length > 1 ⇒ a duplicate hidden
  /// from other decks; drives the "in N presentaties" badge).
  final List<_Occ> occurrences;
  final VoidCallback onTap;
  final VoidCallback? onCompare;

  const _SlideCard({
    required this.slide,
    required this.projectPath,
    required this.themeProfile,
    required this.selected,
    required this.occurrences,
    required this.onTap,
    required this.onCompare,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SizedBox(
      width: 168,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          GestureDetector(
            onTap: onTap,
            child: Stack(
              children: [
                Container(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: selected ? AppTheme.accent : AppTheme.slate300,
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
                if (occurrences.length > 1)
                  Positioned(top: 4, left: 4, child: _copiesBadge(l10n)),
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
          if (onCompare != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: onCompare,
                icon: const Icon(Icons.difference_outlined, size: 13),
                label: Text(l10n.d('Verschillen')),
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
      ),
    );
  }

  /// "In N presentaties" chip listing every deck this exact slide was found in.
  Widget _copiesBadge(AppLocalizations l10n) {
    return PopupMenuButton<void>(
      tooltip: l10n.d('In meerdere presentaties'),
      itemBuilder: (_) => [
        for (final o in occurrences)
          PopupMenuItem<void>(
            enabled: false,
            height: 32,
            child: Tooltip(
              message: o.pres.path,
              child: Text(
                o.label(l10n),
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
              '${occurrences.length}',
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
