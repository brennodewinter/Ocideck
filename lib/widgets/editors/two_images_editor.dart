import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../models/slide_format.dart';
import '../../state/deck_provider.dart';
import '../slides/image_crop_dialog.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';
import 'editor_text_controller.dart';

class TwoImagesEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  /// De diaverhouding van het deck (#2433) — elke beeldhelft levert
  /// `fraction × slideAspect` als sleufverhouding voor de crop-stage.
  final double slideAspect;

  const TwoImagesEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
    this.slideAspect = kScreenSlideAspect,
  });

  @override
  ConsumerState<TwoImagesEditor> createState() => _TwoImagesEditorState();
}

/// De drie weergavestanden van een twoImages-dia (#2867). `manual` en `fill`
/// zijn de bestaande paneelverdeling — verschillend alleen in imageZoom
/// (contain/zoom resp. cover); `equalHeight` is de eigen layoutmodus waarin
/// verdeling, zoom en bijsnijden bewust niets doen.
enum _TwoImageViewMode { manual, equalHeight, fill }

class _TwoImagesEditorState extends ConsumerState<TwoImagesEditor> {
  late final EditorTextController _title;

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
    super.dispose();
  }

  Future<void> _pasteImage(bool isSecond) async {
    final imgService = ref.read(imageServiceProvider);
    final path = await pasteImageWithFeedback(
      context,
      imgService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(
        isSecond
            ? widget.slide.copyWith(imagePath2: path, imageCaption2: '')
            : widget.slide.copyWith(imagePath: path, imageCaption: ''),
      );
    }
  }

  Future<void> _pickImage(bool isSecond) async {
    final imgService = ref.read(imageServiceProvider);
    final path = await pickImageWithFeedback(
      context,
      imgService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(
        isSecond
            ? widget.slide.copyWith(imagePath2: path, imageCaption2: '')
            : widget.slide.copyWith(imagePath: path, imageCaption: ''),
      );
    }
  }

  void _clearImage(bool isSecond) {
    widget.onUpdate(
      isSecond
          ? widget.slide.copyWith(imagePath2: '', imageCaption2: '')
          : widget.slide.copyWith(imagePath: '', imageCaption: ''),
    );
  }

  void _swapImages() {
    final slide = widget.slide;
    String swapDraftField(String field) => switch (field) {
      'imageCaption' => 'imageCaption2',
      'imageCaption2' => 'imageCaption',
      'imageAltText' => 'imageAltText2',
      'imageAltText2' => 'imageAltText',
      _ => field,
    };
    widget.onUpdate(
      slide.copyWith(
        imagePath: slide.imagePath2,
        imagePath2: slide.imagePath,
        imageCaption: slide.imageCaption2,
        imageCaption2: slide.imageCaption,
        imageAltText: slide.imageAltText2,
        imageAltText2: slide.imageAltText,
        imageFocalX: slide.imageFocalX2,
        imageFocalY: slide.imageFocalY2,
        imageFocalX2: slide.imageFocalX,
        imageFocalY2: slide.imageFocalY,
        imageSize: slide.imageSize == 0 ? 0 : 100 - slide.imageSize,
        aiAssistedFields: slide.aiAssistedFields.map(swapDraftField).toList(),
      ),
    );
  }

  Future<void> _openCrop(bool isSecond) async {
    // Each picture covers its half-panel; the split (imageSize) sets the widths.
    // Crop adjusts both the zoom (0=cover, 100=contain, >100=zoom in) and the
    // focal point of that one image.
    final leftFraction =
        (widget.slide.imageSize > 0 ? widget.slide.imageSize / 100.0 : 0.5)
            .clamp(0.1, 0.9);
    final fraction = isSecond ? 1 - leftFraction : leftFraction;
    final result = await showImageCropDialog(
      context,
      imagePath: isSecond ? widget.slide.imagePath2 : widget.slide.imagePath,
      projectPath: widget.captionBasePath,
      frameAspect: fraction * widget.slideAspect,
      imageSize: widget.slide.imageZoom,
      focalX: isSecond ? widget.slide.imageFocalX2 : widget.slide.imageFocalX,
      focalY: isSecond ? widget.slide.imageFocalY2 : widget.slide.imageFocalY,
    );
    if (result == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        imageFocalX: isSecond ? null : result.focalX,
        imageFocalY: isSecond ? null : result.focalY,
        imageFocalX2: isSecond ? result.focalX : null,
        imageFocalY2: isSecond ? result.focalY : null,
        imageZoom: result.imageSize,
        // Draaien levert een afgeleide kopie op (IMAGE_ROTATION.md, optie A);
        // die hoort bij de afbeelding die zojuist openstond, niet bij de andere.
        imagePath: isSecond ? null : result.rotatedImagePath,
        imagePath2: isSecond ? result.rotatedImagePath : null,
      ),
    );
  }

  _TwoImageViewMode get _viewMode {
    if (widget.slide.twoImagesLayout == TwoImagesLayout.equalHeight) {
      return _TwoImageViewMode.equalHeight;
    }
    return widget.slide.imageZoom == 0
        ? _TwoImageViewMode.fill
        : _TwoImageViewMode.manual;
  }

  void _setViewMode(_TwoImageViewMode mode) {
    final slide = widget.slide;
    widget.onUpdate(switch (mode) {
      // Verdeling, zoom en focuspunten worden nooit overschreven — ze
      // blijven bewaard zodat terugschakelen de eerdere compositie herstelt.
      _TwoImageViewMode.equalHeight => slide.copyWith(
        twoImagesLayout: TwoImagesLayout.equalHeight,
      ),
      _TwoImageViewMode.fill => slide.copyWith(
        twoImagesLayout: TwoImagesLayout.panels,
        imageZoom: 0,
      ),
      _TwoImageViewMode.manual => slide.copyWith(
        twoImagesLayout: TwoImagesLayout.panels,
        imageZoom: slide.imageZoom == 0 ? 100 : slide.imageZoom,
      ),
    });
  }

  Widget _cropButton(bool isSecond) {
    final path = isSecond ? widget.slide.imagePath2 : widget.slide.imagePath;
    if (!imageIsCroppable(path)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Tooltip(
          message: _viewMode == _TwoImageViewMode.equalHeight
              ? context.l10n.d(
                  'Bijsnijden doet niets in Gelijke hoogte — kies eerst een andere weergave',
                )
              : '',
          child: OutlinedButton.icon(
            icon: const Icon(Icons.crop, size: 18),
            label: Text(context.l10n.d('Afbeelding aanpassen')),
            onPressed: _viewMode == _TwoImageViewMode.equalHeight
                ? null
                : () => _openCrop(isSecond),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Ondertitel (optioneel)',
          controller: _title,
          hint: 'Tekst onder de afbeeldingen',
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          icon: const Icon(Icons.swap_horiz, size: 18),
          label: Text(context.l10n.d('Afbeeldingen omwisselen')),
          onPressed: _swapImages,
        ),
        const SizedBox(height: 12),
        const SectionLabel('Linker afbeelding'),
        ImagePickerBar(
          imagePath: widget.slide.imagePath,
          imageCaption: widget.slide.imageCaption,
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => widget.onUpdate(
            widget.slide.copyWith(imagePath: path, imageCaption: caption),
          ),
          onBrowse: () => _pickImage(false),
          onPaste: () => _pasteImage(false),
          onClear: widget.slide.imagePath.isNotEmpty
              ? () => _clearImage(false)
              : null,
          onCaptionChanged: (caption) =>
              widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
          imageAltText: widget.slide.imageAltText,
          onAltTextChanged: (alt) => widget.onUpdate(
            widget.slide
                .copyWith(imageAltText: alt)
                .withAiAssistedField('imageAltText', present: false),
          ),
          onAltTextSuggested: (alt) => widget.onUpdate(
            widget.slide
                .copyWith(imageAltText: alt)
                .withAiAssistedField('imageAltText', present: true),
          ),
          imageAltIsAiDraft: widget.slide.aiAssistedFields.contains(
            'imageAltText',
          ),
          onAltTextAccepted: () => widget.onUpdate(
            widget.slide.withAiAssistedField('imageAltText', present: false),
          ),
        ),
        _cropButton(false),
        const SizedBox(height: 20),
        const SectionLabel('Rechter afbeelding'),
        ImagePickerBar(
          imagePath: widget.slide.imagePath2,
          imageCaption: widget.slide.imageCaption2,
          captionField: 'imageCaption2',
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => widget.onUpdate(
            widget.slide.copyWith(imagePath2: path, imageCaption2: caption),
          ),
          onBrowse: () => _pickImage(true),
          onPaste: () => _pasteImage(true),
          onClear: widget.slide.imagePath2.isNotEmpty
              ? () => _clearImage(true)
              : null,
          onCaptionChanged: (caption) =>
              widget.onUpdate(widget.slide.copyWith(imageCaption2: caption)),
          imageAltText: widget.slide.imageAltText2,
          onAltTextChanged: (alt) => widget.onUpdate(
            widget.slide
                .copyWith(imageAltText2: alt)
                .withAiAssistedField('imageAltText2', present: false),
          ),
          onAltTextSuggested: (alt) => widget.onUpdate(
            widget.slide
                .copyWith(imageAltText2: alt)
                .withAiAssistedField('imageAltText2', present: true),
          ),
          imageAltIsAiDraft: widget.slide.aiAssistedFields.contains(
            'imageAltText2',
          ),
          onAltTextAccepted: () => widget.onUpdate(
            widget.slide.withAiAssistedField('imageAltText2', present: false),
          ),
        ),
        _cropButton(true),
        const SizedBox(height: 20),
        _viewModeSection(),
      ],
    );
  }

  /// De weergavekeuze (#2867): één SegmentedButton voor de drie standen, zodat
  /// geen twee schakelaars elkaar tegenspreken. imageZoom 0 = cover (panelen
  /// vullen), 100 = contain (eigen verdeling), >100 = inzoomen via de
  /// bijsnijddialoog (#1879).
  Widget _viewModeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Weergave'),
        SegmentedButton<_TwoImageViewMode>(
          segments: [
            ButtonSegment(
              value: _TwoImageViewMode.manual,
              label: Text(context.l10n.d('Eigen verdeling')),
            ),
            ButtonSegment(
              value: _TwoImageViewMode.equalHeight,
              label: Text(context.l10n.d('Gelijke hoogte')),
            ),
            ButtonSegment(
              value: _TwoImageViewMode.fill,
              label: Text(context.l10n.d('Panelen vullen')),
            ),
          ],
          selected: {_viewMode},
          onSelectionChanged:
              (widget.slide.imagePath.isEmpty &&
                  widget.slide.imagePath2.isEmpty)
              ? null
              : (sel) => _setViewMode(sel.first),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 8, top: 4),
          child: Text(switch (_viewMode) {
            _TwoImageViewMode.manual => context.l10n.d(
              'Verdeel de breedte zelf; elke afbeelding past in haar paneel',
            ),
            _TwoImageViewMode.equalHeight => context.l10n.d(
              'Beide afbeeldingen even hoog en volledig zichtbaar — verdelen en bijsnijden doen niets',
            ),
            _TwoImageViewMode.fill => context.l10n.d(
              'Vult elk paneel en snijdt de randen bij; ‘Afbeelding aanpassen’ kiest het focuspunt',
            ),
          }, style: TextStyle(fontSize: 11, color: AppTheme.slate500)),
        ),
        if (_viewMode != _TwoImageViewMode.equalHeight) ...[
          const SizedBox(height: 12),
          const SectionLabel('Verdeling (links / rechts)'),
          ImageZoomControl(
            value: widget.slide.imageSize > 0 ? widget.slide.imageSize : 50,
            onChanged: (v) =>
                widget.onUpdate(widget.slide.copyWith(imageSize: v)),
            step: 5,
            minValue: 20,
            maxValue: 80,
          ),
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              'Links ${widget.slide.imageSize > 0 ? widget.slide.imageSize : 50}% — '
              'Rechts ${100 - (widget.slide.imageSize > 0 ? widget.slide.imageSize : 50)}%',
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ),
        ],
      ],
    );
  }
}
