import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';

class QuoteEditor extends ConsumerStatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final List<String> searchPaths;
  final String? captionBasePath;
  final bool nestedInScrollView;

  const QuoteEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
    this.nestedInScrollView = false,
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
    final path = await pasteImageWithFeedback(
      context,
      imgService,
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  Future<void> _pickBgImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await pickImageWithFeedback(
      context,
      imgService,
      projectPath: widget.captionBasePath,
    );
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
    final l10n = context.l10n;
    final imagePath = widget.slide.imagePath;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        EditorField(
          label: 'Citaat',
          controller: _quote,
          hint: 'Citaat tekst...',
          maxLines: 5,
          qualityField: 'quote',
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
        Text(
          l10n.d(
            'De afbeelding wordt schermvullend als achtergrond getoond met verminderde opaciteit zodat de tekst leesbaar blijft.',
          ),
          style: const TextStyle(fontSize: 11, color: Color(0xFF64748B)),
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
