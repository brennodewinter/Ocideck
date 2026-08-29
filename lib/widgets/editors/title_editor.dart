import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '../slides/image_crop_dialog.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';

class TitleEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const TitleEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<TitleEditor> createState() => _TitleEditorState();
}

class _TitleEditorState extends ConsumerState<TitleEditor>
    with EditorTextControllers, BgImageHandlers {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  /// Zoom to restore when the user turns "fill slide" back off, so toggling the
  /// checkbox doesn't discard the zoom they had dialled in. The editor is keyed
  /// per slide (ValueKey(slide.id)), so this state is naturally per-slide.
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

  void _setLayout(TitleColumnLayout layout) {
    widget.onUpdate(widget.slide.copyWith(titleColumnLayout: layout));
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
    // The title background is full-bleed (16:9); crop tunes zoom + focal point.
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
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final layout = widget.slide.titleColumnLayout;
    final imagePath = widget.slide.imagePath;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Titel (H1)',
          controller: _title,
          hint: 'Presentatietitel',
          maxLines: 2,
        ),
        const SizedBox(height: 16),
        EditorField(
          label: 'Subtitel (H2)',
          controller: _subtitle,
          hint: 'Optionele subtitel',
          maxLines: 2,
        ),
        const SizedBox(height: 20),

        // ── Layout chooser: full-bleed vs. image columns (#1405) ─────────
        const SectionLabel('Afbeeldingslay-out'),
        const SizedBox(height: 4),
        Text(
          l10n.d(
            'Volvlak: de afbeelding als schermvullende achtergrond. Links/Rechts/Beide: één of twee beeldkolommen naast de titeltekst.',
          ),
          style: TextStyle(fontSize: 11, color: AppTheme.slate500),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          children: [
            ChoiceChip(
              label: Text(l10n.d('Volvlak')),
              selected: layout == TitleColumnLayout.none,
              onSelected: (_) => _setLayout(TitleColumnLayout.none),
            ),
            ChoiceChip(
              label: Text(l10n.d('Links')),
              selected: layout == TitleColumnLayout.left,
              onSelected: (_) => _setLayout(TitleColumnLayout.left),
            ),
            ChoiceChip(
              label: Text(l10n.d('Rechts')),
              selected: layout == TitleColumnLayout.right,
              onSelected: (_) => _setLayout(TitleColumnLayout.right),
            ),
            ChoiceChip(
              label: Text(l10n.d('Beide')),
              selected: layout == TitleColumnLayout.both,
              onSelected: (_) => _setLayout(TitleColumnLayout.both),
            ),
          ],
        ),

        // ── Column mode: left/right image pickers + width slider ─────────
        if (layout != TitleColumnLayout.none) ...[
          const SizedBox(height: 16),
          if (layout == TitleColumnLayout.left ||
              layout == TitleColumnLayout.both) ...[
            const SectionLabel('Linker kolomafbeelding'),
            const SizedBox(height: 8),
            ImagePickerBar(
              imagePath: widget.slide.imagePath,
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
              label: 'Geen linker kolomafbeelding',
            ),
            const SizedBox(height: 12),
          ],
          if (layout == TitleColumnLayout.right ||
              layout == TitleColumnLayout.both) ...[
            const SectionLabel('Rechter kolomafbeelding'),
            const SizedBox(height: 8),
            ImagePickerBar(
              imagePath: widget.slide.imagePath2,
              imageCaption: widget.slide.imageCaption2,
              searchPaths: widget.searchPaths,
              captionBasePath: widget.captionBasePath,
              onPicked: (path, caption) => widget.onUpdate(
                widget.slide.copyWith(imagePath2: path, imageCaption2: caption),
              ),
              onBrowse: pickBgImage2,
              onPaste: pasteBgImage2,
              onClear: widget.slide.imagePath2.isNotEmpty
                  ? clearBgImage2
                  : null,
              onCaptionChanged: (caption) => widget.onUpdate(
                widget.slide.copyWith(imageCaption2: caption),
              ),
              label: 'Geen rechter kolomafbeelding',
            ),
            const SizedBox(height: 12),
          ],
          const SectionLabel('Kolombreedte'),
          const SizedBox(height: 8),
          ImageZoomControl(
            value: widget.slide.titleColumnWidth,
            minValue: 10,
            maxValue: 40,
            step: 5,
            onChanged: (v) =>
                widget.onUpdate(widget.slide.copyWith(titleColumnWidth: v)),
          ),
          Text(
            '${widget.slide.titleColumnWidth.clamp(10, 40)}%',
            style: TextStyle(fontSize: 11, color: AppTheme.slate500),
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

        // ── Full-bleed background image (existing) ───────────────────────
        if (layout == TitleColumnLayout.none) ...[
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
            // imageSize == 0 renders the image with BoxFit.cover: it fills the
            // whole slide and crops whatever falls outside. Any other value
            // switches to the zoom/contain control below.
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
                // Eén letterlijke string: de l10n-test herkent geen
                // aaneengeplakte stringdelen als één bronsleutel.
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
      ],
    );
  }
}
