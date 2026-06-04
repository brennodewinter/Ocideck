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

  const TitleEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    this.searchPaths = const [],
    this.captionBasePath,
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
    _title.dispose();
    _subtitle.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final imagePath = widget.slide.imagePath;

    return ListView(
      padding: const EdgeInsets.all(16),
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
            'De afbeelding wordt schermvullend als achtergrond getoond met verminderde opaciteit zodat de tekst leesbaar blijft.',
          ),
          style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
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
