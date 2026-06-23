import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/slide.dart';
import '../../state/deck_provider.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';

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

class _TitleEditorState extends ConsumerState<TitleEditor> {
  late final TextEditingController _title;
  late final TextEditingController _subtitle;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _subtitle = TextEditingController(text: widget.slide.subtitle);
    _title.addListener(_emit);
    _subtitle.addListener(_emit);
  }

  void _emit() {
    widget.onUpdate(
      widget.slide.copyWith(title: _title.text, subtitle: _subtitle.text),
    );
  }

  Future<void> _pasteBgImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await imgService.pasteImage(
      projectPath: widget.captionBasePath,
    );
    if (path != null) {
      widget.onUpdate(widget.slide.copyWith(imagePath: path, imageCaption: ''));
    }
  }

  Future<void> _pickBgImage() async {
    final imgService = ref.read(imageServiceProvider);
    final path = await imgService.pickImage(
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
    _title.dispose();
    _subtitle.dispose();
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

        // ── Background image ─────────────────────────────────────────────
        const SectionLabel('Achtergrondafbeelding (optioneel)'),
        const SizedBox(height: 4),
        Text(
          l10n.d(
            'De afbeelding wordt schermvullend als achtergrond getoond. Gebruik de waas als de titel meer rust of contrast nodig heeft.',
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
          // imageSize == 0 renders the image with BoxFit.cover: it fills the
          // whole slide and crops whatever falls outside. Any other value
          // switches to the zoom/contain control below.
          CheckboxListTile(
            value: widget.slide.imageSize == 0,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(imageSize: (value ?? false) ? 0 : 100),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Afbeelding vult hele slide'),
            subtitle: const Text(
              'Vult de hele slide; wat buiten beeld valt wordt bijgesneden.',
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
          const SizedBox(height: 12),
          CheckboxListTile(
            value: widget.slide.titleImageOverlay,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(titleImageOverlay: value ?? true),
            ),
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            title: const Text('Grijze waas over afbeelding'),
            subtitle: const Text(
              'Maakt de achtergrond rustiger achter titel en subtitel.',
            ),
          ),
        ],
      ],
    );
  }
}
