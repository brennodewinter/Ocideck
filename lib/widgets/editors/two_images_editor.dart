import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
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

  const TwoImagesEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  ConsumerState<TwoImagesEditor> createState() => _TwoImagesEditorState();
}

class _TwoImagesEditorState extends ConsumerState<TwoImagesEditor> {
  late final EditorTextController _title;

  @override
  void initState() {
    super.initState();
    _title = EditorTextController(text: widget.slide.title);
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
      frameAspect: fraction * 16 / 9,
      imageSize: widget.slide.imageZoom,
      focalX: isSecond ? widget.slide.imageFocalX2 : widget.slide.imageFocalX,
      focalY: isSecond ? widget.slide.imageFocalY2 : widget.slide.imageFocalY,
      enableZoom: true,
    );
    if (result == null) return;
    widget.onUpdate(
      widget.slide.copyWith(
        imageFocalX: isSecond ? null : result.focalX,
        imageFocalY: isSecond ? null : result.focalY,
        imageFocalX2: isSecond ? result.focalX : null,
        imageFocalY2: isSecond ? result.focalY : null,
        imageZoom: result.imageSize,
      ),
    );
  }

  Widget _cropButton(bool isSecond) {
    final path = isSecond ? widget.slide.imagePath2 : widget.slide.imagePath;
    if (!imageIsCroppable(path)) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton.icon(
          icon: const Icon(Icons.crop, size: 18),
          label: Text(context.l10n.d('Afbeelding aanpassen')),
          onPressed: () => _openCrop(isSecond),
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
    );
  }
}
