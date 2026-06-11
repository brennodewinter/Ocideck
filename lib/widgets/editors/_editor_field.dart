import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import '../../services/caption_service.dart';
import '../../services/description_service.dart';
import '../../services/image_service.dart';
import '../../state/tabs_provider.dart';
import '../../l10n/app_localizations.dart';
import '../dialogs/image_carousel_picker.dart';

/// Shared layout helpers for slide editors.

class EditorField extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final String hint;
  final int maxLines;

  const EditorField({
    super.key,
    required this.label,
    required this.controller,
    this.hint = '',
    this.maxLines = 1,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l10n.d(label),
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: Color(0xFF64748B),
          ),
        ),
        const SizedBox(height: 5),
        TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: 1,
          decoration: InputDecoration(
            hintText: hint.isEmpty ? '' : l10n.d(hint),
          ),
        ),
      ],
    );
  }
}

class EditorFieldList extends StatelessWidget {
  final List<Widget> children;
  const EditorFieldList({super.key, required this.children});

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: children.length,
      separatorBuilder: (context, index) => const SizedBox(height: 16),
      itemBuilder: (_, i) => children[i],
    );
  }
}

/// Zoom-bediening voor afbeeldingen in slides.
/// De afbeelding vult ALTIJD de slide; de zoom bepaalt welk deel zichtbaar is.
///   0 of 100 = normaal (cover, Marp-standaard)
///   150      = ingezoomd: ziet alleen het midden van de foto
///   300      = flink ingezoomd: ziet 1/3 van de foto
class ImageZoomControl extends StatelessWidget {
  final int value; // 0 = auto/normaal, anders minValue–maxValue
  final ValueChanged<int> onChanged;
  final int step;
  final int minValue;
  final int maxValue;

  const ImageZoomControl({
    super.key,
    required this.value,
    required this.onChanged,
    this.step = 10,
    this.minValue = 20,
    this.maxValue = 300,
  });

  // Effectieve sliderwaarde: 0 behandelen als 100
  int get _effective => value == 0 ? 100 : value.clamp(minValue, maxValue);

  String _label(BuildContext context) {
    final l10n = context.l10n;
    final v = _effective;
    if (maxValue <= 100) return '$v%'; // paneelbreedte-modus
    if (v == 100) return l10n.d('Volledig zichtbaar (100%)');
    if (v > 100) {
      return '${l10n.d('Ingezoomd')} $v% — ${((1 / (v / 100)) * 100).round()}% ${l10n.d('van de foto zichtbaar')}';
    }
    return '${l10n.d('Uitgezoomd')} $v%';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final zoomed = _effective != 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Tooltip(
              message: l10n.d('Uitzoomen (meer van de foto zichtbaar)'),
              child: const Icon(
                Icons.zoom_out,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ),
            Expanded(
              child: Slider(
                value: _effective.toDouble(),
                min: minValue.toDouble(),
                max: maxValue.toDouble(),
                divisions: (maxValue - minValue) ~/ step,
                label: _label(context),
                onChanged: (v) {
                  final snapped = ((v.round() / step).round() * step).clamp(
                    minValue,
                    maxValue,
                  );
                  onChanged(snapped);
                },
              ),
            ),
            Tooltip(
              message: l10n.d('Inzoomen (minder van de foto zichtbaar)'),
              child: const Icon(
                Icons.zoom_in,
                size: 16,
                color: Color(0xFF64748B),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 52,
              child: Text(
                '$_effective%',
                style: TextStyle(
                  fontSize: 12,
                  color: zoomed
                      ? const Color(0xFF2563EB)
                      : const Color(0xFF64748B),
                  fontWeight: zoomed ? FontWeight.w600 : FontWeight.normal,
                ),
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 4),
            Tooltip(
              message: l10n.d('Terugzetten (volledige afbeelding zichtbaar)'),
              child: IconButton(
                icon: const Icon(Icons.refresh, size: 16),
                onPressed: zoomed ? () => onChanged(100) : null,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                color: const Color(0xFF64748B),
              ),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, bottom: 4),
          child: Text(
            _label(context),
            style: const TextStyle(fontSize: 10, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }
}

/// Callback met pad én caption.
typedef ImagePickedCallback = void Function(String path, String caption);

/// Afbeeldingskiezer-balk met carousel-knop + optionele caption.
class ImagePickerBar extends ConsumerWidget {
  final String imagePath;
  final String imageCaption;
  final String? captionBasePath;
  final List<String> searchPaths;
  final ImagePickedCallback onPicked;
  final VoidCallback? onBrowse;
  final VoidCallback? onPaste;
  final VoidCallback? onClear;
  final ValueChanged<String>? onCaptionChanged;
  final String label;

  const ImagePickerBar({
    super.key,
    required this.imagePath,
    required this.searchPaths,
    required this.onPicked,
    this.imageCaption = '',
    this.captionBasePath,
    this.onBrowse,
    this.onPaste,
    this.onClear,
    this.onCaptionChanged,
    this.label = 'Geen afbeelding gekozen',
  });

  Future<void> _openCarousel(
    BuildContext context,
    WidgetRef ref,
    CaptionService captions,
  ) async {
    final result = await ImageCarouselPicker.show(
      context,
      searchPaths: searchPaths,
      initialPath: imagePath.isNotEmpty ? _resolveImagePath(imagePath) : null,
      captionService: captions,
      descriptionService: ref.read(descriptionServiceProvider),
      usageOf: (absolutePath) => _imageUsages(ref, absolutePath),
      onReplaceUsages: (from, to) => _replaceImageUsages(ref, from, to),
      openDeckFiles: [
        for (final tab in ref.read(tabsProvider).tabs)
          ?tab.deckNotifier.currentState.filePath,
      ],
    );
    if (result != null) onPicked(result.path, result.caption);
  }

  /// Wijs in alle open decks elke slideverwijzing naar [fromAbsolute] om naar
  /// [toAbsolute]. Gebruikt door de afbeeldingenbibliotheek wanneer een md5-
  /// duplicaat wordt opgeruimd, zodat slides het behouden bestand blijven tonen.
  Future<void> _replaceImageUsages(
    WidgetRef ref,
    String fromAbsolute,
    String toAbsolute,
  ) async {
    final target = p.normalize(fromAbsolute);
    for (final tab in ref.read(tabsProvider).tabs) {
      final notifier = tab.deckNotifier;
      final deck = notifier.currentState.deck;
      if (deck == null) continue;
      final projectPath = deck.projectPath ?? '';

      String resolve(String candidate) => p.normalize(
        p.isAbsolute(candidate) ? candidate : p.join(projectPath, candidate),
      );
      // Blijf relatief opslaan als de slide dat al deed en het nieuwe pad
      // binnen het project ligt; anders absoluut.
      String replacement(String candidate) {
        if (p.isAbsolute(candidate) || projectPath.isEmpty) return toAbsolute;
        return p.isWithin(projectPath, toAbsolute)
            ? p.relative(toAbsolute, from: projectPath)
            : toAbsolute;
      }

      for (var i = 0; i < deck.slides.length; i++) {
        final slide = deck.slides[i];
        var updated = slide;
        if (slide.imagePath.isNotEmpty && resolve(slide.imagePath) == target) {
          updated = updated.copyWith(imagePath: replacement(slide.imagePath));
        }
        if (slide.imagePath2.isNotEmpty &&
            resolve(slide.imagePath2) == target) {
          updated = updated.copyWith(
            imagePath2: replacement(slide.imagePath2),
          );
        }
        if (!identical(updated, slide)) notifier.updateSlide(i, updated);
      }
    }
  }

  /// Find every open-deck slide that references [absolutePath], so we can warn
  /// before deleting an image that is still in use.
  List<String> _imageUsages(WidgetRef ref, String absolutePath) {
    final target = p.normalize(absolutePath);
    final usages = <String>[];
    for (final tab in ref.read(tabsProvider).tabs) {
      final deck = tab.deckNotifier.currentState.deck;
      if (deck == null) continue;
      for (var i = 0; i < deck.slides.length; i++) {
        final slide = deck.slides[i];
        for (final candidate in [slide.imagePath, slide.imagePath2]) {
          if (candidate.isEmpty) continue;
          final resolved = p.normalize(
            p.isAbsolute(candidate)
                ? candidate
                : p.join(deck.projectPath ?? '', candidate),
          );
          if (resolved == target) {
            usages.add('${tab.label} · slide ${i + 1}');
            break;
          }
        }
      }
    }
    return usages;
  }

  String _resolveImagePath(String path) {
    if (p.isAbsolute(path) || captionBasePath == null) return path;
    return p.join(captionBasePath!, path);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final captions = ref.read(captionServiceProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Pad-display
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: const Color(0xFFCBD5E1)),
            borderRadius: BorderRadius.circular(6),
            color: Colors.white,
          ),
          child: Text(
            imagePath.isEmpty ? l10n.d(label) : imagePath,
            style: TextStyle(
              fontSize: 12,
              color: imagePath.isEmpty
                  ? const Color(0xFF64748B)
                  : const Color(0xFF334155),
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(height: 8),
        // Knoppen
        Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ElevatedButton.icon(
              onPressed: () => _openCarousel(context, ref, captions),
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(l10n.d('Uit bibliotheek…')),
            ),
            if (onBrowse != null)
              OutlinedButton.icon(
                onPressed: onBrowse,
                icon: const Icon(Icons.folder_open_outlined, size: 16),
                label: Text(l10n.d('Van computer…')),
              ),
            if (onPaste != null)
              Tooltip(
                message: l10n.d('Afbeelding plakken uit klembord'),
                child: IconButton(
                  onPressed: onPaste,
                  icon: const Icon(Icons.content_paste, size: 18),
                  color: const Color(0xFF64748B),
                ),
              ),
            if (imagePath.isNotEmpty)
              Tooltip(
                message: l10n.d('Kopieer afbeelding naar klembord'),
                child: IconButton(
                  onPressed: () async {
                    final ok = await ImageService().copyImageToClipboard(
                      _resolveImagePath(imagePath),
                    );
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            ok
                                ? l10n.d('Afbeelding gekopieerd naar klembord.')
                                : l10n.d('Kopiëren naar klembord mislukt.'),
                          ),
                        ),
                      );
                    }
                  },
                  icon: const Icon(Icons.content_copy_outlined, size: 18),
                  color: const Color(0xFF64748B),
                ),
              ),
            if (onClear != null && imagePath.isNotEmpty)
              Tooltip(
                message: l10n.d('Verwijder afbeelding'),
                child: IconButton(
                  onPressed: onClear,
                  icon: const Icon(Icons.clear, size: 18),
                  color: const Color(0xFF64748B),
                ),
              ),
          ],
        ),
        // Caption-veld
        if (imagePath.isNotEmpty && onCaptionChanged != null) ...[
          const SizedBox(height: 8),
          _CaptionField(
            caption: imageCaption,
            imagePath: imagePath,
            captionBasePath: captionBasePath,
            captionService: captions,
            onChanged: onCaptionChanged!,
          ),
        ],
      ],
    );
  }
}

/// Captionveld met auto-save naar sidecar.
class _CaptionField extends StatefulWidget {
  final String caption;
  final String imagePath;
  final String? captionBasePath;
  final CaptionService captionService;
  final ValueChanged<String> onChanged;

  const _CaptionField({
    required this.caption,
    required this.imagePath,
    this.captionBasePath,
    required this.captionService,
    required this.onChanged,
  });

  @override
  State<_CaptionField> createState() => _CaptionFieldState();
}

class _CaptionFieldState extends State<_CaptionField> {
  late final TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(text: widget.caption);
    _ctrl.addListener(_onChanged);
    _loadStoredCaption();
  }

  @override
  void didUpdateWidget(_CaptionField old) {
    super.didUpdateWidget(old);
    if (old.imagePath != widget.imagePath) {
      _ctrl.removeListener(_onChanged);
      _ctrl.text = widget.caption;
      _ctrl.addListener(_onChanged);
      _loadStoredCaption();
    }
  }

  void _onChanged() {
    widget.onChanged(_ctrl.text);
    widget.captionService.saveCaption(
      widget.imagePath,
      _ctrl.text,
      basePath: widget.captionBasePath,
    );
  }

  Future<void> _loadStoredCaption() async {
    if (widget.caption.isNotEmpty) return;
    final stored = await widget.captionService.getCaption(
      widget.imagePath,
      basePath: widget.captionBasePath,
    );
    if (!mounted || stored == null || stored == _ctrl.text) return;
    _ctrl.removeListener(_onChanged);
    _ctrl.text = stored;
    _ctrl.addListener(_onChanged);
    widget.onChanged(stored);
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return TextField(
      controller: _ctrl,
      decoration: InputDecoration(
        hintText: l10n.d('Caption / bronvermelding (bijv. © Naam Fotograaf)'),
        hintStyle: const TextStyle(fontSize: 12, color: Color(0xFFB0BEC5)),
        prefixIcon: const Icon(
          Icons.copyright_outlined,
          size: 16,
          color: Color(0xFF64748B),
        ),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 10),
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(6),
          borderSide: const BorderSide(color: Color(0xFFCBD5E1)),
        ),
      ),
      style: const TextStyle(fontSize: 12),
    );
  }
}

class SectionLabel extends StatelessWidget {
  final String text;
  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Text(
        l10n.d(text),
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: Color(0xFF64748B),
        ),
      ),
    );
  }
}
