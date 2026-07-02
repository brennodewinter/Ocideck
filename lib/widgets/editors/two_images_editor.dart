import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '_editor_field.dart';

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
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emitTitle);
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
        ),
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
        ),
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
            '${context.l10n.d('Links')} ${widget.slide.imageSize > 0 ? widget.slide.imageSize : 50}% — '
            '${context.l10n.d('Rechts')} ${100 - (widget.slide.imageSize > 0 ? widget.slide.imageSize : 50)}%',
            style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
        ),
      ],
    );
  }
}
