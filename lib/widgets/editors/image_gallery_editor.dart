import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/gallery_layout.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';

/// Editor van de afbeeldingsgroep (#2838): een titel, de lay-outkeuze
/// (raster/stapel) en de rij beelden met alt-tekst, herordenen en verwijderen.
///
/// Elke rij is één `![alt](pad)`-entry uit [Slide.galleryImages]; de alt-tekst
/// wijzigt in die entry zelf, zodat hij in de .md én in elke Markdown-lezer
/// meereist.
class ImageGalleryEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const ImageGalleryEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<ImageGalleryEditor> createState() => _ImageGalleryEditorState();
}

class _ImageGalleryEditorState extends ConsumerState<ImageGalleryEditor> {
  late final EditorTextController _title;

  /// Eén alt-tekstcontroller per galerijrij, op index — herordenen en
  /// verwijderen verplaatsen de rij-indexen, dus deze map bouwen we bij elke
  /// wijziging opnieuw op in [_syncAltControllers].
  final Map<int, EditorTextController> _alts = {};

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(
      text: widget.slide.title,
      searchFieldId: 'title',
    );
    _title.addTextListener(_emitTitle);
  }

  void _emitTitle() {
    widget.onUpdate(widget.slide.copyWith(title: _title.text));
  }

  @override
  void dispose() {
    _title.dispose();
    for (final c in _alts.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Haalt pad en alt-tekst uit een `![alt](pad)`-entry.
  static ({String path, String alt}) _entry(String raw) {
    final m = RegExp(r'!\[([^\]]*)\]\(([^)\n]+)\)').firstMatch(raw);
    return (path: (m?.group(2) ?? '').trim(), alt: (m?.group(1) ?? '').trim());
  }

  EditorTextController _altController(int index) => _alts.putIfAbsent(
    index,
    () => EditorTextController(
      text: _entry(widget.slide.galleryImages[index]).alt,
      searchFieldId: 'galleryAlt$index',
    )..addTextListener(() => _emitAlt(index)),
  );

  void _emitAlt(int index) {
    final images = [...widget.slide.galleryImages];
    if (index >= images.length) return;
    images[index] = '![${_alts[index]!.text}](${_entry(images[index]).path})';
    widget.onUpdate(widget.slide.copyWith(galleryImages: images));
  }

  /// Controllers afstemmen op de actuele rijset: overbodige opruimen (na
  /// verwijderen van een staartrij) en tekst bijwerken als de entry onder de
  /// rij veranderde (herordening van buitenaf, undo).
  void _syncAltControllers() {
    final images = widget.slide.galleryImages;
    _alts.removeWhere((i, c) {
      final drop = i >= images.length;
      if (drop) c.dispose();
      return drop;
    });
    for (var i = 0; i < images.length; i++) {
      final c = _alts[i];
      if (c == null) continue;
      final alt = _entry(images[i]).alt;
      if (c.text != alt) c.text = alt;
    }
  }

  Future<void> _addImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await pickImageWithFeedback(
      context,
      imgService,
      projectPath: widget.captionBasePath,
    );
    if (path == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        galleryImages: [...widget.slide.galleryImages, '![]($path)'],
      ),
    );
  }

  /// Indexen schuiven na een verwijdering/verplaatsing; de controllers
  /// horen bij hun oude rij en worden opgeruimd zodat `_syncAltControllers`
  /// ze op de nieuwe index vers aanmaakt.
  void _resetAltControllers() {
    for (final c in _alts.values) {
      c.dispose();
    }
    _alts.clear();
  }

  void _removeImage(int index) {
    final images = [...widget.slide.galleryImages]..removeAt(index);
    _resetAltControllers();
    widget.onUpdate(widget.slide.copyWith(galleryImages: images));
  }

  void _moveImage(int index, int delta) {
    final target = index + delta;
    final images = [...widget.slide.galleryImages];
    if (target < 0 || target >= images.length) return;
    images.insert(target, images.removeAt(index));
    _resetAltControllers();
    widget.onUpdate(widget.slide.copyWith(galleryImages: images));
  }

  Widget _imageRow(int index) {
    final l10n = context.l10n;
    final images = widget.slide.galleryImages;
    final entry = _entry(images[index]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${l10n.d('Afbeelding')} ${index + 1}: ${entry.path}',
                  style: TextStyle(fontSize: 11, color: AppTheme.slate400),
                  overflow: TextOverflow.ellipsis,
                ),
                EditorField(
                  label: 'Alt-tekst',
                  controller: _altController(index),
                ),
              ],
            ),
          ),
          Column(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                tooltip: l10n.d('Omhoog'),
                onPressed: index > 0 ? () => _moveImage(index, -1) : null,
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                tooltip: l10n.d('Omlaag'),
                onPressed: index < images.length - 1
                    ? () => _moveImage(index, 1)
                    : null,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline, size: 18),
                tooltip: l10n.d('Afbeelding verwijderen'),
                onPressed: () => _removeImage(index),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    _syncAltControllers();
    return EditorFieldList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(label: 'Titel', controller: _title),
        const SizedBox(height: 8),
        SegmentedButton<GalleryLayout>(
          segments: [
            ButtonSegment(
              value: GalleryLayout.grid,
              label: Text(l10n.d('Raster')),
            ),
            ButtonSegment(
              value: GalleryLayout.stack,
              label: Text(l10n.d('Stapel')),
            ),
          ],
          selected: {widget.slide.galleryLayout},
          onSelectionChanged: (sel) =>
              widget.onUpdate(widget.slide.copyWith(galleryLayout: sel.first)),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < widget.slide.galleryImages.length; i++)
          _imageRow(i),
        TextButton.icon(
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text(l10n.d('Afbeelding toevoegen')),
          onPressed: _addImage,
        ),
      ],
    );
  }
}
