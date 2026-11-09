import 'package:material_ui/material_ui.dart';
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
    _quote = newController(widget.slide.quote, _emit, searchFieldId: 'quote');
    _author = newController(
      widget.slide.quoteAuthor,
      _emit,
      searchFieldId: 'quoteAuthor',
    );
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(quote: _quote.text, quoteAuthor: _author.text),
    );
  }

  Widget _strengthSlider(AppLocalizations l10n) => Row(
    children: [
      Expanded(
        child: Semantics(
          label: l10n.d('Grijze waas over afbeelding'),
          child: Slider(
            value: widget.slide.marpStyle.effectiveImageOverlayStrength
                .toDouble(),
            min: 0,
            max: 100,
            divisions: 100,
            label: '${widget.slide.marpStyle.effectiveImageOverlayStrength}%',
            semanticFormatterCallback: (v) => '${v.round()}%',
            onChanged: widget.slide.titleImageOverlay
                ? (v) => widget.onUpdate(
                    widget.slide.copyWith(
                      marpStyle: widget.slide.marpStyle.copyWith(
                        imageOverlayStrength: v.round(),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
      SizedBox(
        width: 44,
        child: Text('${widget.slide.marpStyle.effectiveImageOverlayStrength}%'),
      ),
    ],
  );

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
            value: widget.slide.titleImageOverlay,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(titleImageOverlay: value ?? true),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: Text(l10n.d('Grijze waas over afbeelding')),
            subtitle: Text(
              l10n.d(
                'De afbeelding wordt schermvullend als achtergrond getoond met verminderde opaciteit zodat de tekst leesbaar blijft.',
              ),
              style: TextStyle(fontSize: 11, color: AppTheme.slate500),
            ),
          ),
          const SizedBox(height: 12),
          _strengthSlider(l10n),
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
