import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../slides/image_crop_dialog.dart';
import '_editor_field.dart';
import 'markdown_editor_field.dart';
import '../../theme/app_theme.dart';

/// De tussentitel-editor. Draagt dezelfde achtergrondafbeelding-bediening als de
/// titeldia: een tussenkop is óók een kopdia, en dat de een wél een achtergrond
/// kon krijgen en de ander niet was gewoon een gat, geen keuze. De inhoud (twee
/// tekstvelden) blijft; het beeldblok eronder is één-op-één dat van [TitleEditor].
class SectionEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const SectionEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<SectionEditor> createState() => _SectionEditorState();
}

class _SectionEditorState extends ConsumerState<SectionEditor>
    with EditorTextControllers, BgImageHandlers {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  /// Zoom to restore when the user turns "fill slide" back off — same per-slide
  /// state as [TitleEditor], and safe because the editor is keyed per slide id.
  int _zoomBeforeFill = 100;

  @override
  Slide get editorSlide => widget.slide;
  @override
  ValueChanged<Slide> get onSlideUpdate => widget.onUpdate;
  @override
  String? get bgImageBasePath => widget.captionBasePath;

  @override
  void initState() {
    super.initState();
    _title = newController(widget.slide.title, _emit);
    _subtitle = newController(widget.slide.subtitle, _emit);
    if (widget.slide.imageSize > 0) _zoomBeforeFill = widget.slide.imageSize;
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(title: _title.text, subtitle: _subtitle.text),
    );
  }

  Widget _cropButton(String imagePath) {
    if (!imageIsCroppable(imagePath)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.crop, size: 18),
          label: Text(context.l10n.d('Afbeelding aanpassen')),
          onPressed: _openCrop,
        ),
      ),
    );
  }

  Future<void> _openCrop() async {
    // Full-bleed (16:9); crop tunes zoom + focal point — same as the title dia.
    final result = await showImageCropDialog(
      context,
      imagePath: widget.slide.imagePath,
      projectPath: widget.captionBasePath,
      frameAspect: 16 / 9,
      imageSize: widget.slide.imageSize,
      focalX: widget.slide.imageFocalX,
      focalY: widget.slide.imageFocalY,
    );
    if (result == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        imageSize: result.imageSize,
        imageFocalX: result.focalX,
        imageFocalY: result.focalY,
        // Draaien schrijft een afgeleide kopie en laat het origineel staan
        // (IMAGE_ROTATION.md, optie A), dus de dia moet naar dat nieuwe bestand
        // gaan wijzen. Null betekent: er is niet gedraaid, pad blijft.
        imagePath: result.rotatedImagePath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final imagePath = widget.slide.imagePath;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Tussentitel (H1)',
          controller: _title,
          hint: 'Sectienaam',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        MarkdownEditorField(
          label: 'Ondertitel / toelichting',
          controller: _subtitle,
          hint: 'Optionele toelichting',
          minLines: 2,
          maxLines: 3,
        ),
        const SizedBox(height: 20),

        // ── Background image ─────────────────────────────────────────────
        const SectionLabel('Achtergrondafbeelding (optioneel)'),
        const SizedBox(height: 4),
        Text(
          l10n.d(
            'De afbeelding wordt schermvullend als achtergrond getoond. Gebruik de waas als de titel meer rust of contrast nodig heeft.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        const SizedBox(height: 8),
        ImagePickerBar(
          imagePath: imagePath,
          imageCaption: widget.slide.imageCaption,
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => widget.onUpdate(
            widget.slide.copyWith(imagePath: path, imageCaption: caption),
          ),
          onBrowse: pickBgImage,
          onPaste: pasteBgImage,
          onClear: imagePath.isNotEmpty ? clearBgImage : null,
          onCaptionChanged: (caption) =>
              widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
          label: 'Geen achtergrondafbeelding',
        ),
        if (imagePath.isNotEmpty) ...[
          const SizedBox(height: 12),
          CheckboxListTile(
            value: widget.slide.imageSize == 0,
            onChanged: (value) {
              final fill = value ?? false;
              if (fill) {
                if (widget.slide.imageSize > 0) {
                  _zoomBeforeFill = widget.slide.imageSize;
                }
                widget.onUpdate(widget.slide.copyWith(imageSize: 0));
              } else {
                widget.onUpdate(
                  widget.slide.copyWith(imageSize: _zoomBeforeFill),
                );
              }
            },
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.d('Afbeelding vult hele slide')),
            subtitle: Text(
              context.l10n.d(
                'Aan: vult de hele slide, titel eroverheen (bijgesneden). Uit: beeld bovenaan, titel in een band eronder.',
              ),
            ),
          ),
          if (widget.slide.imageSize != 0) ...[
            const SizedBox(height: 12),
            const SectionLabel('Zoom achtergrond'),
            ImageZoomControl(
              value: widget.slide.imageSize,
              onChanged: (v) =>
                  widget.onUpdate(widget.slide.copyWith(imageSize: v)),
            ),
          ],
          _cropButton(imagePath),
          const SizedBox(height: 12),
          CheckboxListTile(
            value: widget.slide.titleImageOverlay,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(titleImageOverlay: value ?? true),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(context.l10n.d('Grijze waas over afbeelding')),
            subtitle: Text(
              context.l10n.d(
                'Maakt de achtergrond rustiger achter titel en subtitel.',
              ),
            ),
          ),
          const SizedBox(height: 12),
          const SectionLabel('Titeltekstkleur'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              ChoiceChip(
                label: Text(context.l10n.d('Thema')),
                selected: widget.slide.titleTextColorOverride.isEmpty,
                onSelected: (_) => widget.onUpdate(
                  widget.slide.copyWith(titleTextColorOverride: ''),
                ),
              ),
              ChoiceChip(
                label: Text(context.l10n.d('Licht')),
                selected:
                    widget.slide.titleTextColorOverride.toUpperCase() ==
                    '#FFFFFF',
                onSelected: (_) => widget.onUpdate(
                  widget.slide.copyWith(titleTextColorOverride: '#FFFFFF'),
                ),
              ),
              ChoiceChip(
                label: Text(context.l10n.d('Donker')),
                selected:
                    widget.slide.titleTextColorOverride.toUpperCase() ==
                    '#111827',
                onSelected: (_) => widget.onUpdate(
                  widget.slide.copyWith(titleTextColorOverride: '#111827'),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
