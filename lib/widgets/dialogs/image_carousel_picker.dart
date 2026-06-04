import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as p;
import '../../services/caption_service.dart';
import '../../services/description_service.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';

/// Resultaat van de afbeeldingencarousel.
class ImagePickResult {
  final String path;
  final String caption;
  const ImagePickResult(this.path, this.caption);
}

/// Geeft per absoluut afbeeldingspad terug waar het in gebruik is
/// (bijv. "Presentatie X · slide 3"). Lege lijst = nergens gevonden.
typedef ImageUsageLookup = List<String> Function(String absolutePath);

/// Manier waarop de afbeeldingen worden getoond. Tussen beide kan in de
/// header gewisseld worden.
enum _ViewMode {
  /// Compact raster — veel afbeeldingen tegelijk in beeld.
  grid,

  /// Spectaculaire coverflow — één grote centrale afbeelding met de buren
  /// die schuin en geschaald opzij wegvloeien.
  cover,
}

/// Spectaculaire afbeeldingencarousel.
/// Toont alle afbeeldingen uit de opgegeven mappen in een mooi grid.
class ImageCarouselPicker extends StatefulWidget {
  final List<String> searchPaths;
  final String? initialPath;
  final CaptionService captionService;
  final DescriptionService descriptionService;
  final ImageUsageLookup? usageOf;

  const ImageCarouselPicker({
    super.key,
    required this.searchPaths,
    required this.captionService,
    required this.descriptionService,
    this.initialPath,
    this.usageOf,
  });

  static Future<ImagePickResult?> show(
    BuildContext context, {
    List<String> searchPaths = const [],
    String? initialPath,
    CaptionService? captionService,
    DescriptionService? descriptionService,
    ImageUsageLookup? usageOf,
  }) {
    return showDialog<ImagePickResult>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.88),
      builder: (_) => ImageCarouselPicker(
        searchPaths: searchPaths,
        initialPath: initialPath,
        captionService: captionService ?? CaptionService(),
        descriptionService: descriptionService ?? DescriptionService(),
        usageOf: usageOf,
      ),
    );
  }

  @override
  State<ImageCarouselPicker> createState() => _ImageCarouselPickerState();
}

class _ImageCarouselPickerState extends State<ImageCarouselPicker> {
  static const _exts = {
    '.jpg',
    '.jpeg',
    '.png',
    '.gif',
    '.webp',
    '.bmp',
    '.heic',
    '.tiff',
    '.tif',
  };

  /// All discovered images (newest first).
  List<String> _images = [];

  /// Images matching the current search query (subset of [_images]).
  List<String> _filtered = [];

  /// Absolute image path → searchable description.
  Map<String, String> _descriptions = {};

  String? _selected;
  String _caption = '';
  String _query = '';
  String? _descEditing; // path the description field currently edits
  bool _loading = true;
  bool _justCopied = false; // korte feedback na kopiëren naar klembord
  int _hoveredIndex = -1;
  _ViewMode _viewMode = _ViewMode.grid;

  /// Alleen actief in coverflow-modus; bestuurt de horizontale "flow".
  PageController? _pageController;

  final _gridScrollController = ScrollController();
  final _captionController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _loadImages();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _focusNode.requestFocus(),
    );
  }

  @override
  void dispose() {
    _pageController?.dispose();
    _gridScrollController.dispose();
    _captionController.dispose();
    _descriptionController.dispose();
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadImages() async {
    final found = <String>{};

    for (final path in widget.searchPaths) {
      if (path.isEmpty) continue;
      final dir = Directory(path);
      if (!dir.existsSync()) continue;
      try {
        await for (final e in dir.list(recursive: true, followLinks: false)) {
          if (e is File) {
            final ext = p.extension(e.path).toLowerCase();
            if (_exts.contains(ext)) found.add(e.path);
          }
        }
      } catch (_) {}
    }

    // Stat each file exactly once (instead of repeatedly inside the sort
    // comparator) so large libraries stay responsive.
    final withTimes = <(String, DateTime)>[];
    for (final path in found) {
      DateTime modified;
      try {
        modified = File(path).statSync().modified;
      } catch (_) {
        modified = DateTime.fromMillisecondsSinceEpoch(0);
      }
      withTimes.add((path, modified));
    }
    withTimes.sort((a, b) => b.$2.compareTo(a.$2));
    final sorted = [for (final e in withTimes) e.$1];

    final descriptions = await widget.descriptionService.loadFor(sorted);

    if (!mounted) return;
    setState(() {
      _images = sorted;
      _descriptions = descriptions;
      _loading = false;
      _selected =
          widget.initialPath ?? (sorted.isNotEmpty ? sorted.first : null);
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
  }

  /// Recompute [_filtered] from [_images] and the current query. Matches on
  /// file name and stored description (case-insensitive, all terms must hit)
  /// and ranks the hits on relevance so dat een korte zoekterm als "kl" de
  /// KLM-afbeelding meteen bovenaan toont in plaats van verzopen tussen alle
  /// andere "kl"-woorden. Bij gelijke score blijft de datumvolgorde van
  /// [_images] (nieuwste eerst) behouden.
  void _applyFilter() {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) {
      _filtered = _images;
      return;
    }
    final terms = q
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList(growable: false);

    final hits = <({String path, int score, int order})>[];
    for (var i = 0; i < _images.length; i++) {
      final score = _relevance(_images[i], terms);
      if (score > 0) hits.add((path: _images[i], score: score, order: i));
    }
    hits.sort((a, b) {
      final byScore = b.score.compareTo(a.score);
      return byScore != 0 ? byScore : a.order.compareTo(b.order);
    });
    _filtered = [for (final h in hits) h.path];
  }

  /// Relevantiescore voor één afbeelding tegen alle zoektermen. Geeft 0 terug
  /// zodra één term nergens voorkomt (dan valt de afbeelding uit het filter).
  /// Hoger = relevanter; per term telt de sterkste match mee.
  int _relevance(String path, List<String> terms) {
    final name = p.basenameWithoutExtension(path).toLowerCase();
    final desc = (_descriptions[path] ?? '').toLowerCase();
    final splitter = RegExp(r'[^a-z0-9]+');
    final nameWords = name.split(splitter).where((w) => w.isNotEmpty);
    final descWords = desc.split(splitter).where((w) => w.isNotEmpty);

    var total = 0;
    for (final t in terms) {
      var best = 0;
      if (name == t) {
        best = 1000; // bestandsnaam is exact de zoekterm
      } else if (nameWords.contains(t)) {
        best = 600; // heel woord in de naam ("klm")
      } else if (nameWords.any((w) => w.startsWith(t))) {
        best = 400; // woord in de naam begint met de term ("kl" → "klm")
      } else if (name.contains(t)) {
        best = 200; // term zit ergens in de naam
      }
      if (best < 600) {
        if (descWords.contains(t)) {
          best = best < 500 ? 500 : best; // heel woord in de beschrijving
        } else if (descWords.any((w) => w.startsWith(t))) {
          best = best < 300 ? 300 : best; // woord-prefix in de beschrijving
        } else if (desc.contains(t)) {
          best = best < 100 ? 100 : best; // substring in de beschrijving
        }
      }
      if (best == 0) return 0; // deze term matcht nergens → wegfilteren
      total += best;
    }
    return total;
  }

  void _onSearchChanged(String value) {
    setState(() {
      _query = value;
      _applyFilter();
    });
    // De indexen zijn verschoven; coverflow opnieuw uitlijnen na de rebuild.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => _syncCoverToSelection(),
    );
  }

  Future<void> _confirm() async {
    if (_selected == null) return;
    await _persistDescription();
    await widget.captionService.saveCaption(_selected!, _caption);
    if (mounted) {
      Navigator.pop(context, ImagePickResult(_selected!, _caption.trim()));
    }
  }

  /// Persist the description currently in the editor, then close the dialog.
  Future<void> _close([ImagePickResult? result]) async {
    await _persistDescription();
    if (mounted) Navigator.pop(context, result);
  }

  Future<void> _persistDescription() async {
    final path = _descEditing;
    if (path == null) return;
    final text = _descriptionController.text.trim();
    _descriptions[path] = text;
    await widget.descriptionService.saveDescription(path, text);
  }

  void _loadDescriptionForSelection() {
    final path = _selected;
    _descEditing = path;
    _descriptionController.text = path == null
        ? ''
        : (_descriptions[path] ?? '');
  }

  Future<void> _browse() async {
    final result = await FilePicker.pickFiles(
      type: FileType.image,
      dialogTitle: context.l10n.d('Kies een afbeelding'),
    );
    if (result?.files.single.path != null && mounted) {
      final path = result!.files.single.path!;
      final caption = await widget.captionService.getCaption(path) ?? '';
      await _close(ImagePickResult(path, caption));
    }
  }

  Future<void> _select(String path) async {
    await _persistDescription();
    setState(() => _selected = path);
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
  }

  Future<void> _loadCaptionForSelection() async {
    final path = _selected;
    final caption = path == null
        ? ''
        : (await widget.captionService.getCaption(path) ?? '');
    if (!mounted || path != _selected) return;
    setState(() {
      _caption = caption;
      _captionController.text = caption;
    });
  }

  void _moveSelection(int delta) {
    if (_filtered.isEmpty) return;
    final current = _selected == null ? -1 : _filtered.indexOf(_selected!);
    final next = (current + delta).clamp(0, _filtered.length - 1);
    if (_viewMode == _ViewMode.cover && _pageController?.hasClients == true) {
      // De PageView is leidend: animeren triggert onPageChanged → _select.
      _pageController!.animateToPage(
        next,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
      return;
    }
    _select(_filtered[next]);
    _scrollToIndex(next);
  }

  /// Wissel tussen raster- en coverflow-weergave. Maakt (of ruimt) de
  /// PageController op en zet de flow op de huidige selectie.
  void _setViewMode(_ViewMode mode) {
    if (mode == _viewMode) return;
    setState(() {
      _viewMode = mode;
      _pageController?.dispose();
      if (mode == _ViewMode.cover) {
        final idx = _selected == null ? 0 : _filtered.indexOf(_selected!);
        _pageController = PageController(
          initialPage: idx < 0 ? 0 : idx,
          viewportFraction: 0.62,
        );
      } else {
        _pageController = null;
      }
    });
  }

  /// Zet de coverflow zonder animatie op de huidige selectie. Nodig nadat het
  /// filter de lijst (en dus de indexen) heeft veranderd.
  void _syncCoverToSelection() {
    if (_viewMode != _ViewMode.cover) return;
    final controller = _pageController;
    if (controller == null || !controller.hasClients) return;
    final idx = _selected == null ? 0 : _filtered.indexOf(_selected!);
    controller.jumpToPage(idx < 0 ? 0 : idx);
  }

  /// Kopieer de geselecteerde afbeelding naar het klembord (om elders te
  /// plakken) met korte "Gekopieerd"-feedback op de knop.
  Future<void> _copySelectedToClipboard() async {
    final path = _selected;
    if (path == null) return;
    final ok = await ImageService().copyImageToClipboard(path);
    if (!mounted) return;
    if (ok) {
      setState(() => _justCopied = true);
      Future.delayed(const Duration(milliseconds: 1500), () {
        if (mounted) setState(() => _justCopied = false);
      });
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.d('Kopiëren naar klembord mislukt.')),
        ),
      );
    }
  }

  Future<void> _deleteSelected() async {
    final path = _selected;
    if (path == null) return;
    final usages = widget.usageOf?.call(path) ?? const [];
    final confirmed = await _showDeleteDialog(path, usages);
    if (confirmed != true) return;

    try {
      final file = File(path);
      if (file.existsSync()) await file.delete();
    } catch (_) {}
    // Drop the sidecar metadata too.
    await widget.captionService.saveCaption(path, '');
    await widget.descriptionService.removeDescription(path);

    if (!mounted) return;
    final idx = _images.indexOf(path);
    setState(() {
      _images = List.of(_images)..remove(path);
      _descriptions.remove(path);
      _descEditing = null;
      if (_selected == path) {
        _selected = _images.isEmpty
            ? null
            : _images[idx.clamp(0, _images.length - 1)];
      }
      _applyFilter();
    });
    await _loadCaptionForSelection();
    _loadDescriptionForSelection();
  }

  Future<bool?> _showDeleteDialog(String path, List<String> usages) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) {
        final l10n = ctx.l10n;
        return AlertDialog(
          backgroundColor: const Color(0xFF161B22),
          title: Row(
            children: [
              Icon(
                usages.isEmpty
                    ? Icons.delete_outline
                    : Icons.warning_amber_rounded,
                color: usages.isEmpty
                    ? const Color(0xFFE5534B)
                    : const Color(0xFFF0B429),
                size: 20,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  l10n.d('Afbeelding verwijderen?'),
                  style: const TextStyle(color: Colors.white, fontSize: 16),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                p.basename(path),
                style: const TextStyle(
                  color: Color(0xFFCDD9E5),
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 10),
              if (usages.isEmpty)
                Text(
                  l10n.d(
                    'Het bestand wordt permanent van schijf verwijderd. Deze actie kan niet ongedaan worden gemaakt.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 13,
                  ),
                )
              else ...[
                Text(
                  '${l10n.d('Let op: deze afbeelding wordt nog gebruikt in')} ${usages.length} ${usages.length == 1 ? l10n.d("slide") : l10n.t("slides")}:',
                  style: const TextStyle(
                    color: Color(0xFFF0B429),
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        for (final u in usages)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 3),
                            child: Text(
                              '•  $u',
                              style: const TextStyle(
                                color: Color(0xFFCDD9E5),
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  l10n.d(
                    'Verwijderen maakt die slides leeg. Dit kan niet ongedaan worden gemaakt.',
                  ),
                  style: const TextStyle(
                    color: Color(0xFF8B949E),
                    fontSize: 13,
                  ),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFF8B949E),
              ),
              child: Text(l10n.t('cancel')),
            ),
            ElevatedButton.icon(
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline, size: 16),
              label: Text(l10n.d('Verwijderen')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFB62324),
                foregroundColor: Colors.white,
              ),
            ),
          ],
        );
      },
    );
  }

  void _scrollToIndex(int index) {
    // Approximate thumbnail height for 3-column grid
    const cols = 3;
    const thumbH = 160.0;
    const spacing = 12.0;
    final row = index ~/ cols;
    final offset = row * (thumbH + spacing);
    _gridScrollController.animateTo(
      offset.clamp(0.0, _gridScrollController.position.maxScrollExtent),
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () => _close(),
        const SingleActivator(LogicalKeyboardKey.enter): () => _confirm(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _moveSelection(1),
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _moveSelection(-1),
        const SingleActivator(LogicalKeyboardKey.arrowDown): () =>
            _moveSelection(3),
        const SingleActivator(LogicalKeyboardKey.arrowUp): () =>
            _moveSelection(-3),
      },
      child: Focus(
        focusNode: _focusNode,
        child: Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1160, maxHeight: 780),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: Container(
                decoration: BoxDecoration(
                  color: const Color(0xFF0D1117),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF21262D), width: 1),
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    Expanded(
                      child: _loading
                          ? _buildLoading()
                          : Row(
                              children: [
                                _viewMode == _ViewMode.cover
                                    ? _buildCover()
                                    : _buildGrid(),
                                _buildPreview(),
                              ],
                            ),
                    ),
                    _buildFooter(),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLoading() {
    final l10n = context.l10n;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(color: Color(0xFF3B82F6)),
          const SizedBox(height: 16),
          Text(
            l10n.d('Afbeeldingen laden…'),
            style: const TextStyle(color: Color(0xFF8B949E), fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final l10n = context.l10n;
    return Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF1D2433),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(
              Icons.photo_library_outlined,
              color: Color(0xFF60A5FA),
              size: 18,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            l10n.d('Afbeelding kiezen'),
            style: const TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.3,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: const Color(0xFF21262D),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              _query.trim().isEmpty
                  ? '${_images.length}'
                  : '${_filtered.length} / ${_images.length}',
              style: const TextStyle(
                color: Color(0xFF8B949E),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(child: _buildSearchField()),
          const SizedBox(width: 12),
          _buildViewToggle(),
          const SizedBox(width: 12),
          IconButton(
            icon: const Icon(Icons.close, color: Color(0xFF6E7681), size: 20),
            onPressed: () => _close(),
            tooltip: l10n.d('Sluiten (Esc)'),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    final l10n = context.l10n;
    return SizedBox(
      height: 36,
      child: TextField(
        controller: _searchController,
        onChanged: _onSearchChanged,
        style: const TextStyle(color: Color(0xFFCDD9E5), fontSize: 13),
        decoration: InputDecoration(
          hintText: l10n.d('Zoek op naam of beschrijving…'),
          hintStyle: const TextStyle(color: Color(0xFF6E7681), fontSize: 13),
          prefixIcon: const Icon(
            Icons.search,
            color: Color(0xFF6E7681),
            size: 18,
          ),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(
                    Icons.clear,
                    color: Color(0xFF6E7681),
                    size: 16,
                  ),
                  onPressed: () {
                    _searchController.clear();
                    _onSearchChanged('');
                  },
                ),
          isDense: true,
          filled: true,
          fillColor: const Color(0xFF0D1117),
          contentPadding: const EdgeInsets.symmetric(vertical: 0),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF30363D)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Color(0xFF3B82F6)),
          ),
        ),
      ),
    );
  }

  /// Segmented control om tussen raster- en coverflow-weergave te wisselen.
  Widget _buildViewToggle() {
    final l10n = context.l10n;
    Widget seg(_ViewMode mode, IconData icon, String tip) {
      final active = _viewMode == mode;
      return Tooltip(
        message: tip,
        child: GestureDetector(
          onTap: () => _setViewMode(mode),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: active ? const Color(0xFF1D2433) : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              icon,
              size: 17,
              color: active ? const Color(0xFF60A5FA) : const Color(0xFF6E7681),
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(color: const Color(0xFF30363D)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          seg(_ViewMode.grid, Icons.grid_view_rounded, l10n.d('Raster')),
          const SizedBox(width: 3),
          seg(
            _ViewMode.cover,
            Icons.view_carousel_rounded,
            l10n.d('Coverflow'),
          ),
        ],
      ),
    );
  }

  /// Lege staat — gedeeld door raster- en coverflow-weergave.
  Widget _buildEmptyState() {
    final l10n = context.l10n;
    final filtering = _query.trim().isNotEmpty;
    return Expanded(
      flex: 13,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF161B22),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.image_search_outlined,
                size: 56,
                color: Color(0xFF30363D),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              filtering
                  ? '${l10n.d('Geen resultaten voor')} "${_query.trim()}"'
                  : l10n.d('Geen afbeeldingen gevonden'),
              style: const TextStyle(
                color: Color(0xFFCDD9E5),
                fontSize: 16,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              filtering
                  ? l10n.d('Pas je zoekterm aan of voeg een beschrijving toe.')
                  : l10n.d(
                      'Gebruik "Bladeren" om afbeeldingen van elke locatie te kiezen.',
                    ),
              style: const TextStyle(color: Color(0xFF6E7681), fontSize: 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGrid() {
    if (_filtered.isEmpty) return _buildEmptyState();

    return Expanded(
      flex: 13,
      child: Container(
        decoration: const BoxDecoration(
          border: Border(right: BorderSide(color: Color(0xFF21262D))),
        ),
        child: GridView.builder(
          controller: _gridScrollController,
          padding: const EdgeInsets.all(16),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 3,
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 4 / 3,
          ),
          itemCount: _filtered.length,
          itemBuilder: (_, i) => _buildThumbnail(i),
        ),
      ),
    );
  }

  Widget _buildThumbnail(int index) {
    final path = _filtered[index];
    final isSelected = path == _selected;
    final isHovered = index == _hoveredIndex;
    final name = p.basenameWithoutExtension(path);

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredIndex = index),
      onExit: (_) => setState(() => _hoveredIndex = -1),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () => _select(path),
        onDoubleTap: () async {
          await _select(path);
          await _confirm();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          transform: Matrix4.identity()
            ..scaleByDouble(
              isHovered && !isSelected ? 1.03 : 1.0,
              isHovered && !isSelected ? 1.03 : 1.0,
              1,
              1,
            ),
          transformAlignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFF3B82F6)
                  : isHovered
                  ? const Color(0xFF58A6FF)
                  : const Color(0xFF21262D),
              width: isSelected
                  ? 2.5
                  : isHovered
                  ? 1.5
                  : 1,
            ),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: const Color(0xFF3B82F6).withValues(alpha: 0.35),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(8.5),
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Thumbnail
                Image.file(
                  File(path),
                  fit: BoxFit.cover,
                  cacheWidth: 360,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF161B22),
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFF30363D),
                      size: 32,
                    ),
                  ),
                ),
                // Hover-glans overlay
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 120),
                  opacity: isHovered && !isSelected ? 0.12 : 0,
                  child: Container(color: Colors.white),
                ),
                // Naam onderaan
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: isHovered || isSelected ? 1 : 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(8, 18, 8, 7),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.82),
                          ],
                        ),
                      ),
                      child: Text(
                        name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.1,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
                // Selectie-vinkje
                if (isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: const BoxDecoration(
                        color: Color(0xFF3B82F6),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(color: Color(0xFF1D4ED8), blurRadius: 6),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 13,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Coverflow ───────────────────────────────────────────────────────────

  Widget _buildCover() {
    if (_filtered.isEmpty) return _buildEmptyState();

    final controller = _pageController;
    final selectedIndex = _selected == null
        ? -1
        : _filtered.indexOf(_selected!);

    return Expanded(
      flex: 13,
      child: Container(
        decoration: const BoxDecoration(
          // Subtiele verticale gloed voor de "podium"-look.
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.1,
            colors: [Color(0xFF161D2B), Color(0xFF0B0F16)],
          ),
          border: Border(right: BorderSide(color: Color(0xFF21262D))),
        ),
        child: Column(
          children: [
            Expanded(
              child: Stack(
                alignment: Alignment.center,
                children: [
                  if (controller != null)
                    PageView.builder(
                      controller: controller,
                      itemCount: _filtered.length,
                      onPageChanged: (i) {
                        if (i >= 0 && i < _filtered.length) {
                          _select(_filtered[i]);
                        }
                      },
                      itemBuilder: (_, i) => _buildCoverCard(i, controller),
                    ),
                  // Navigatiepijlen links/rechts.
                  Positioned(
                    left: 12,
                    child: _coverArrow(
                      Icons.chevron_left_rounded,
                      selectedIndex > 0,
                      () => _moveSelection(-1),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    child: _coverArrow(
                      Icons.chevron_right_rounded,
                      selectedIndex >= 0 &&
                          selectedIndex < _filtered.length - 1,
                      () => _moveSelection(1),
                    ),
                  ),
                ],
              ),
            ),
            _buildCoverStrip(selectedIndex),
          ],
        ),
      ),
    );
  }

  /// Eén kaart in de flow. De schaal, perspectiefdraaiing en transparantie
  /// hangen af van de afstand tot het midden van de viewport.
  Widget _buildCoverCard(int index, PageController controller) {
    final path = _filtered[index];
    final isSelected = path == _selected;
    final name = p.basenameWithoutExtension(path);

    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Hoever staat deze kaart van het midden? (0 = gecentreerd)
        double page;
        if (controller.hasClients && controller.position.haveDimensions) {
          page = controller.page ?? controller.initialPage.toDouble();
        } else {
          page = controller.initialPage.toDouble();
        }
        final delta = (page - index).clamp(-1.5, 1.5);
        final dist = delta.abs();
        final centered = (1 - dist.clamp(0.0, 1.0));

        final scale = 0.74 + 0.26 * centered;
        final opacity = 0.35 + 0.65 * centered;
        final rotateY = delta * 0.55; // radialen, perspectief

        return Center(
          child: Opacity(
            opacity: opacity.clamp(0.0, 1.0),
            child: Transform(
              alignment: Alignment.center,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0014) // perspectief
                ..rotateY(-rotateY)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 8),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            // Klik op een buur centreert die; klik op het midden bevestigt.
            onTap: () {
              if (isSelected) {
                _confirm();
              } else {
                final target = _filtered.indexOf(path);
                if (target >= 0 && controller.hasClients) {
                  controller.animateToPage(
                    target,
                    duration: const Duration(milliseconds: 320),
                    curve: Curves.easeOutCubic,
                  );
                }
              }
            },
            onDoubleTap: () async {
              await _select(path);
              await _confirm();
            },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF3B82F6)
                      : const Color(0xFF21262D),
                  width: isSelected ? 2.5 : 1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: isSelected
                        ? const Color(0xFF3B82F6).withValues(alpha: 0.45)
                        : Colors.black.withValues(alpha: 0.55),
                    blurRadius: isSelected ? 40 : 24,
                    spreadRadius: isSelected ? 2 : 0,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.file(
                      File(path),
                      fit: BoxFit.cover,
                      cacheWidth: 1000,
                      errorBuilder: (context, error, stackTrace) => Container(
                        color: const Color(0xFF161B22),
                        child: const Icon(
                          Icons.broken_image_outlined,
                          color: Color(0xFF30363D),
                          size: 48,
                        ),
                      ),
                    ),
                    // Naamlabel onderaan de centrale kaart.
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: AnimatedOpacity(
                        duration: const Duration(milliseconds: 200),
                        opacity: isSelected ? 1 : 0,
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(16, 30, 16, 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Colors.transparent,
                                Colors.black.withValues(alpha: 0.78),
                              ],
                            ),
                          ),
                          child: Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 0.1,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _coverArrow(IconData icon, bool enabled, VoidCallback onTap) {
    return AnimatedOpacity(
      duration: const Duration(milliseconds: 150),
      opacity: enabled ? 1 : 0.0,
      child: IgnorePointer(
        ignoring: !enabled,
        child: Material(
          color: const Color(0xFF161B22).withValues(alpha: 0.85),
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: const Color(0xFF30363D)),
              ),
              child: Icon(icon, color: const Color(0xFFCDD9E5), size: 24),
            ),
          ),
        ),
      ),
    );
  }

  /// Positie-indicator onder de flow ("3 / 28") plus een dunne voortgangsbalk.
  Widget _buildCoverStrip(int selectedIndex) {
    final total = _filtered.length;
    final pos = selectedIndex < 0 ? 0 : selectedIndex;
    final progress = total <= 1 ? 1.0 : pos / (total - 1);

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 0, 40, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: Stack(
              children: [
                Container(height: 3, color: const Color(0xFF21262D)),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(
                    height: 3,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFF3B82F6), Color(0xFF60A5FA)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            '${pos + 1} / $total',
            style: const TextStyle(
              color: Color(0xFF8B949E),
              fontSize: 12,
              fontWeight: FontWeight.w500,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    final l10n = context.l10n;
    return SizedBox(
      width: 300,
      child: Container(
        color: const Color(0xFF080D14),
        child: _selected == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.touch_app_outlined,
                      size: 40,
                      color: Color(0xFF30363D),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      l10n.d('Selecteer een\nafbeelding'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF6E7681),
                        fontSize: 13,
                        height: 1.5,
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  // Grote preview
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.file(
                          File(_selected!),
                          fit: BoxFit.contain,
                          // Cap decode resolution: the preview pane is narrow,
                          // so full-resolution decodes would waste memory.
                          cacheWidth: 720,
                          errorBuilder: (context, error, stackTrace) =>
                              const Center(
                                child: Icon(
                                  Icons.broken_image,
                                  color: Color(0xFF30363D),
                                  size: 48,
                                ),
                              ),
                        ),
                      ),
                    ),
                  ),
                  // Bestandsinfo
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                    child: Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF161B22),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF21262D),
                          width: 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            p.basename(_selected!),
                            style: const TextStyle(
                              color: Color(0xFFCDD9E5),
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _formatPath(_selected!),
                            style: const TextStyle(
                              color: Color(0xFF6E7681),
                              fontSize: 10.5,
                            ),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 6),
                          _FileSize(path: _selected!),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _captionController,
                            minLines: 1,
                            maxLines: 3,
                            onChanged: (value) => _caption = value,
                            style: const TextStyle(
                              color: Color(0xFFCDD9E5),
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.d('Caption / bronvermelding'),
                              hintStyle: const TextStyle(
                                color: Color(0xFF6E7681),
                                fontSize: 12,
                              ),
                              prefixIcon: const Icon(
                                Icons.copyright_outlined,
                                color: Color(0xFF6E7681),
                                size: 16,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFF0D1117),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF30363D),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF30363D),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          TextField(
                            controller: _descriptionController,
                            minLines: 1,
                            maxLines: 3,
                            onChanged: (value) =>
                                _descriptions[_selected!] = value.trim(),
                            style: const TextStyle(
                              color: Color(0xFFCDD9E5),
                              fontSize: 12,
                            ),
                            decoration: InputDecoration(
                              hintText: l10n.d('Beschrijving (doorzoekbaar)'),
                              hintStyle: const TextStyle(
                                color: Color(0xFF6E7681),
                                fontSize: 12,
                              ),
                              prefixIcon: const Icon(
                                Icons.sell_outlined,
                                color: Color(0xFF6E7681),
                                size: 16,
                              ),
                              isDense: true,
                              filled: true,
                              fillColor: const Color(0xFF0D1117),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF30363D),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF30363D),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                                borderSide: const BorderSide(
                                  color: Color(0xFF3B82F6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              TextButton.icon(
                                onPressed: _justCopied
                                    ? null
                                    : _copySelectedToClipboard,
                                icon: Icon(
                                  _justCopied
                                      ? Icons.check
                                      : Icons.content_copy_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                  _justCopied
                                      ? l10n.d('Gekopieerd')
                                      : l10n.d('Kopiëren'),
                                ),
                                style: TextButton.styleFrom(
                                  foregroundColor: _justCopied
                                      ? const Color(0xFF22C55E)
                                      : const Color(0xFF8B949E),
                                  disabledForegroundColor: const Color(
                                    0xFF22C55E,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                              const Spacer(),
                              TextButton.icon(
                                onPressed: _deleteSelected,
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 16,
                                ),
                                label: Text(l10n.d('Verwijderen')),
                                style: TextButton.styleFrom(
                                  foregroundColor: const Color(0xFFE5746E),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildFooter() {
    final l10n = context.l10n;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFF21262D))),
      ),
      child: Row(
        children: [
          // Bladeren knop
          OutlinedButton.icon(
            onPressed: _browse,
            icon: const Icon(Icons.folder_open_outlined, size: 16),
            label: Text(l10n.d('Bladeren…')),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF8B949E),
              side: const BorderSide(color: Color(0xFF30363D)),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            ),
          ),
          const SizedBox(width: 8),
          // Hint
          Text(
            l10n.d('↑↓←→ navigeren  ·  Enter kiezen  ·  Dubbelklik selecteert'),
            style: const TextStyle(color: Color(0xFF484F58), fontSize: 11),
          ),
          const Spacer(),
          // Annuleren
          TextButton(
            onPressed: () => _close(),
            style: TextButton.styleFrom(
              foregroundColor: const Color(0xFF8B949E),
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            ),
            child: Text(l10n.t('cancel')),
          ),
          const SizedBox(width: 10),
          // Kiezen
          ElevatedButton.icon(
            onPressed: _selected != null ? () => _confirm() : null,
            icon: const Icon(Icons.check_circle_outline, size: 17),
            label: Text(l10n.d('Kiezen')),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF238636),
              foregroundColor: Colors.white,
              disabledBackgroundColor: const Color(0xFF21262D),
              disabledForegroundColor: const Color(0xFF484F58),
              padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 10),
              textStyle: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatPath(String path) {
    final home = Platform.environment['HOME'] ?? '';
    if (home.isNotEmpty && path.startsWith(home)) {
      return '~${path.substring(home.length)}';
    }
    return path;
  }
}

// ── Bestandsgrootte widget ────────────────────────────────────────────────────

class _FileSize extends StatefulWidget {
  final String path;
  const _FileSize({required this.path});

  @override
  State<_FileSize> createState() => _FileSizeState();
}

class _FileSizeState extends State<_FileSize> {
  String _size = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_FileSize old) {
    super.didUpdateWidget(old);
    if (old.path != widget.path) _load();
  }

  Future<void> _load() async {
    try {
      final stat = await File(widget.path).stat();
      final bytes = stat.size;
      final kb = bytes / 1024;
      final mb = kb / 1024;
      final label = mb >= 1
          ? '${mb.toStringAsFixed(1)} MB'
          : '${kb.toStringAsFixed(0)} KB';
      if (mounted) setState(() => _size = label);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (_size.isEmpty) return const SizedBox.shrink();
    return Text(
      _size,
      style: const TextStyle(
        color: Color(0xFF3B82F6),
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
