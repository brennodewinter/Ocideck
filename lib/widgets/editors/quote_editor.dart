import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '_editor_field.dart';

class QuoteEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;

  const QuoteEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
  });

  @override
  ConsumerState<QuoteEditor> createState() => _QuoteEditorState();
}

class _QuoteEditorState extends ConsumerState<QuoteEditor> {
  late final TextEditingController _quote;
  late final TextEditingController _author;

  @override
  void initState() {
    super.initState();
    _quote = TextEditingController(text: widget.slide.quote);
    _author = TextEditingController(text: widget.slide.quoteAuthor);
    _quote.addListener(_emit);
    _author.addListener(_emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(quote: _quote.text, quoteAuthor: _author.text),
    );
  }

  Future<void> _pasteBgImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await imgService.pasteImage();
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  Future<void> _pickBgImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await imgService.pickImage();
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  void _clearBgImage() {
    widget.onUpdate(widget.slide.copyWith(imagePath: '', imageCaption: ''));
  }

  @override
  void dispose() {
    _quote.dispose();
    _author.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = widget.slide.imagePath;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EditorField(
          label: 'Citaat',
          controller: _quote,
          hint: 'Citaat tekst...',
          maxLines: 5,
        ),
        const SizedBox(height: 16),
        EditorField(
          label: 'Auteur',
          controller: _author,
          hint: 'Naam van de auteur',
          maxLines: 1,
        ),
        const SizedBox(height: 20),

        // ── Background image ──────────────────────────────────────────────
        const SectionLabel('Achtergrondafbeelding (optioneel)'),
        const SizedBox(height: 4),
        const Text(
          'De afbeelding wordt schermvullend als achtergrond getoond '
          'met verminderde opaciteit zodat de tekst leesbaar blijft.',
          style: TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
          onBrowse: _pickBgImage,
          onPaste: _pasteBgImage,
          onClear: imagePath.isNotEmpty ? _clearBgImage : null,
          onCaptionChanged: (caption) =>
              widget.onUpdate(widget.slide.copyWith(imageCaption: caption)),
          label: 'Geen achtergrondafbeelding',
        ),
        if (imagePath.isNotEmpty) ...[
          const SizedBox(height: 12),
          const SectionLabel('Zoom achtergrond'),
          ImageZoomControl(
            value: widget.slide.imageSize,
            onChanged: (v) =>
                widget.onUpdate(widget.slide.copyWith(imageSize: v)),
          ),
        ],
      ],
    );
  }
}
