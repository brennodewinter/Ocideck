import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';
import 'markdown_editor_field.dart';
import '../../theme/app_theme.dart';

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

class _QuoteEditorState extends ConsumerState<QuoteEditor>
    with EditorTextControllers, BgImageHandlers {
  late final TextEditingController _quote;
  late final TextEditingController _author;

  @override
  Slide get editorSlide => widget.slide;
  @override
  ValueChanged<Slide> get onSlideUpdate => widget.onUpdate;
  @override
  String? get bgImageBasePath => widget.captionBasePath;

  @override
  void initState() {
    super.initState();
    _quote = newController(widget.slide.quote, _emit);
    _author = newController(widget.slide.quoteAuthor, _emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(quote: _quote.text, quoteAuthor: _author.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final imagePath = widget.slide.imagePath;

    return editorScrollList(
      nestedInScrollView: widget.nestedInScrollView,
      children: [
        MarkdownEditorField(
          label: 'Citaat',
          controller: _quote,
          hint: 'Citaat tekst...',
          minLines: 3,
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
