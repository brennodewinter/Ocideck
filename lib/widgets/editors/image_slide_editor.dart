import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../slides/image_crop_dialog.dart';
import '_editor_field.dart';

class ImageSlideEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const ImageSlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
  });

  @override
  State<ImageSlideEditor> createState() => _ImageSlideEditorState();
}

class _ImageSlideEditorState extends State<ImageSlideEditor>
    with EditorTextControllers {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = newController(widget.slide.title, _emit);
  }

  void _emit() => widget.onUpdate(widget.slide.copyWith(title: _title.text));

  void _setImage(String path, {String caption = ''}) {
    widget.onUpdate(
      widget.slide.copyWith(
        imagePath: path,
        imageCaption: caption,
        // A full-slide image should start at the largest uncropped size.
        imageSize: 100,
      ),
    );
  }

  Future<void> _pasteImage() async {
    final path = await pasteImageWithFeedback(
      context,
      widget.imageService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      _setImage(path);
    }
  }

  Future<void> _pickImage() async {
    final path = await pickImageWithFeedback(
      context,
      widget.imageService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      _setImage(path);
    }
  }

  Future<void> _openCrop() async {
    // The image slide is full-bleed (16:9); crop adjusts both the zoom and the
    // focal point so the author picks which part stays in view.
    final result = await showImageCropDialog(
      context,
      imagePath: widget.slide.imagePath,
      projectPath: widget.captionBasePath,
      frameAspect: 16 / 9,
      imageSize: widget.slide.imageSize,
      focalX: widget.slide.imageFocalX,
      focalY: widget.slide.imageFocalY,
      enableZoom: true,
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
    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        const SectionLabel('Achtergrondafbeelding'),
        ImagePickerBar(
          imagePath: widget.slide.imagePath,
          imageCaption: widget.slide.imageCaption,
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => _setImage(path, caption: caption),
          onBrowse: _pickImage,
          onPaste: _pasteImage,
          onClear: widget.slide.imagePath.isNotEmpty
              ? () => widget.onUpdate(
                  widget.slide.copyWith(imagePath: '', imageCaption: ''),
                )
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
        const SizedBox(height: 8),
        // Slide-filling = cover mode (imageSize 0): the image fills the whole
        // slide and the overflow is cropped. Off = the image is shown in full
        // (contain) and the zoom control below applies.
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(context.l10n.d('Afbeelding slidevullend')),
          subtitle: Text(
            context.l10n.d('Vult de hele slide en snijdt de randen bij'),
          ),
          value: widget.slide.imageSize == 0,
          onChanged: widget.slide.imagePath.isEmpty
              ? null
              : (checked) => widget.onUpdate(
                  widget.slide.copyWith(imageSize: checked == true ? 0 : 100),
                ),
        ),
        if (widget.slide.imageSize != 0) ...[
          const SizedBox(height: 12),
          const SectionLabel('Zoom afbeelding'),
          ImageZoomControl(
            value: widget.slide.imageSize,
            onChanged: (v) =>
                widget.onUpdate(widget.slide.copyWith(imageSize: v)),
          ),
        ],
        if (imageIsCroppable(widget.slide.imagePath)) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: OutlinedButton.icon(
              icon: const Icon(Icons.crop, size: 18),
              label: Text(context.l10n.d('Bijsnijden')),
              onPressed: _openCrop,
            ),
          ),
        ],
        const SizedBox(height: 16),
        CheckboxListTile(
          contentPadding: EdgeInsets.zero,
          controlAffinity: ListTileControlAffinity.leading,
          dense: true,
          title: Text(context.l10n.d('Titel boven afbeelding')),
          subtitle: Text(
            context.l10n.d(
              'Toont de titel boven de afbeelding in plaats van eroverheen',
            ),
          ),
          value: widget.slide.imageTitleAbove,
          onChanged: widget.slide.imagePath.isEmpty
              ? null
              : (checked) => widget.onUpdate(
                  widget.slide.copyWith(imageTitleAbove: checked ?? false),
                ),
        ),
        const SizedBox(height: 16),
        EditorField(
          label: 'Titel overlay (optioneel)',
          controller: _title,
          hint: 'Titel over de afbeelding',
          maxLines: 2,
        ),
      ],
    );
  }
}
