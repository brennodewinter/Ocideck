import '../../utils/image_limits.dart' show boundedFileImage;
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../theme/image_picker_palette.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import '../../services/ai_client_service.dart';
import '../../services/caption_service.dart';
import '../../services/description_service.dart';
import '../../services/image_library_scanner.dart';
import '../../services/image_alt_ai_service.dart';
import '../../services/image_dedup_service.dart';
import '../../services/image_reference_service.dart';
import '../../services/image_service.dart';
import '../../services/secret_store.dart';
import '../../state/consent_provider.dart';
import '../../state/settings_provider.dart';
import '../../l10n/app_localizations.dart';
import '../../platform/platform_features.dart';
import '../../utils/log.dart';
import '../../theme/app_theme.dart';
import 'ai_image_outbound_dialog.dart';

part 'parts/image_carousel_picker_actions.dart';
part 'parts/image_carousel_picker_delete.dart';
part 'parts/image_carousel_picker_chrome.dart';
part 'parts/image_carousel_picker_grid.dart';
part 'parts/image_carousel_picker_preview.dart';

/// Het tweede tekstniveau van de kiezer, kort genoeg om in een `TextStyle` op
/// één regel te passen.
///
/// Het niveau eronder (`iconDim`, ooit `textDim`) mag geen tekst kleuren: als
/// tekst haalt het op geen enkel oppervlak van dit palet de 4,5:1 (#779). Beide
/// grenzen worden gemeten in `test/standalone_palette_contrast_test.dart`.
Color get _muted => ImagePickerPalette.textMuted;

/// Resultaat van de afbeeldingencarousel.
class ImagePickResult {
  final String path;
  final String caption;
  const ImagePickResult(this.path, this.caption);
}

/// Geeft per absoluut afbeeldingspad terug waar het in gebruik is
/// (bijv. "Presentatie X · slide 3"). Lege lijst = nergens gevonden.
typedef ImageUsageLookup = List<String> Function(String absolutePath);

/// Vervangt in alle open decks elke slideverwijzing naar [fromAbsolute] door
/// [toAbsolute]. Gebruikt bij het opruimen van duplicaten, zodat slides niet
/// leeg raken wanneer hun kopie wordt verwijderd.
typedef ImageUsageReplace =
    Future<void> Function(String fromAbsolute, String toAbsolute);

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
class ImageCarouselPicker extends ConsumerStatefulWidget {
  final List<String> searchPaths;
  final String? initialPath;
  final CaptionService captionService;
  final DescriptionService descriptionService;
  final ImageUsageLookup? usageOf;
  final ImageUsageReplace? onReplaceUsages;

  /// Bestandspaden van de presentaties die nu in tabs geopend zijn. Die zijn
  /// al gedekt door [usageOf]; bij het scannen van decks op schijf worden ze
  /// overgeslagen om dubbeltellingen te voorkomen.
  final List<String> openDeckFiles;

  /// Beheer-/onderhoudsmodus: de bibliotheek staat op zichzelf, zonder open
  /// presentatie om een afbeelding voor te kiezen. Dan vervalt het kiezen
  /// (knoppen "Kiezen"/"Bladeren", Enter/dubbelklik) en blijft alleen het
  /// onderhoud over: verwijderen en duplicaten opruimen. Zie beginscherm (#1108).
  final bool manageOnly;

  const ImageCarouselPicker({
    super.key,
    required this.searchPaths,
    required this.captionService,
    required this.descriptionService,
    this.initialPath,
    this.usageOf,
    this.onReplaceUsages,
    this.openDeckFiles = const [],
    this.manageOnly = false,
  });

  static Future<ImagePickResult?> show(
    BuildContext context, {
    List<String> searchPaths = const [],
    String? initialPath,
    CaptionService? captionService,
    DescriptionService? descriptionService,
    ImageUsageLookup? usageOf,
    ImageUsageReplace? onReplaceUsages,
    List<String> openDeckFiles = const [],
    bool manageOnly = false,
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
        onReplaceUsages: onReplaceUsages,
        openDeckFiles: openDeckFiles,
        manageOnly: manageOnly,
      ),
    );
  }

  @override
  ConsumerState<ImageCarouselPicker> createState() =>
      _ImageCarouselPickerState();
}

class _ImageCarouselPickerState extends ConsumerState<ImageCarouselPicker> {
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
  bool _untaggedOnly = false; // toon alleen afbeeldingen zonder tags
  bool _deduping = false; // duplicaten-opruimactie bezig
  String? _dedupePhase; // huidige fase van de opruimactie, voor op de knop
  bool _autoTagging = false; // AI-auto-tag-actie bezig
  String? _autoTagPhase; // huidige fase van het auto-taggen, voor op de knop
  int _hoveredIndex = -1;
  _ViewMode _viewMode = _ViewMode.grid;

  /// Extra zoekwortels die de gebruiker in deze sessie via "Map toevoegen…"
  /// koos — naast [widget.searchPaths]. Blijven tot de dialoog dichtgaat.
  final List<String> _extraRoots = [];

  /// True wanneer de laatste scan alleen onbereikbare wortels had (lege
  /// carrousel door een weggeschoven/niet-gemounte bibliotheek).
  bool _rootsUnreachable = false;

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

  /// Trigger a rebuild from the extension methods in the `parts/` files. They
  /// cannot call the `@protected` [setState] directly (it is only callable from
  /// instance members of a State subclass), so they route through this wrapper.
  void _rebuild(VoidCallback fn) => setState(fn);

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
                  color: ImagePickerPalette.bg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: ImagePickerPalette.surface2,
                    width: 1,
                  ),
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
    } catch (e) {
      logWarning('_FileSizeState._load: compute size label', e);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_size.isEmpty) return const SizedBox.shrink();
    return Text(
      _size,
      style: const TextStyle(
        color: AppTheme.blue500,
        fontSize: 11,
        fontWeight: FontWeight.w500,
      ),
    );
  }
}
