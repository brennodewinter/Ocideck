import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '_editor_field.dart';

class ImageSlideEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;
  final List<String> searchPaths;
  final String? captionBasePath;

  const ImageSlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
    this.searchPaths = const [],
    this.captionBasePath,
  });

  @override
  State<ImageSlideEditor> createState() => _ImageSlideEditorState();
}

class _ImageSlideEditorState extends State<ImageSlideEditor> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
  }

  void _emit() => widget.onUpdate(widget.slide.copyWith(title: _title.text));

  Future<void> _pasteImage() async {
    final path = await widget.imageService.pasteImage();
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  Future<void> _pickImage() async {
    final path = await widget.imageService.pickImage();
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const SectionLabel('Achtergrondafbeelding'),
        ImagePickerBar(
          imagePath: widget.slide.imagePath,
          imageCaption: widget.slide.imageCaption,
          searchPaths: widget.searchPaths,
          captionBasePath: widget.captionBasePath,
          onPicked: (path, caption) => widget.onUpdate(
            widget.slide.copyWith(imagePath: path, imageCaption: caption),
          ),
          onBrowse: _pickImage,
          onPaste: _pasteImage,
          onClear: widget.slide.imagePath.isNotEmpty
              ? () => widget.onUpdate(
                  widget.slide.copyWith(imagePath: '', imageCaption: ''),
                )
              : null,
          onCaptionChanged: (caption) =>
              widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
        ),
        const SizedBox(height: 16),
        const SectionLabel('Zoom afbeelding'),
        ImageZoomControl(
          value: widget.slide.imageSize,
          onChanged: (v) =>
              widget.onUpdate(widget.slide.copyWith(imageSize: v)),
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
