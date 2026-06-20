import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';
import 'audio_attachment_editor.dart';

class VideoSlideEditor extends StatefulWidget {
  final Slide slide;
  final ValueChanged<Slide> onUpdate;
  final ImageService imageService;

  const VideoSlideEditor({
    super.key,
    required this.slide,
    required this.onUpdate,
    required this.imageService,
  });

  @override
  State<VideoSlideEditor> createState() => _VideoSlideEditorState();
}

class _VideoSlideEditorState extends State<VideoSlideEditor> {
  late final TextEditingController _title;

  @override
  void initState() {
    super.initState();
    _title = TextEditingController(text: widget.slide.title);
    _title.addListener(_emit);
  }

  void _emit() {
    widget.onUpdate(widget.slide.copyWith(title: _title.text));
  }

  Future<void> _pickVideo() async {
    final path = await widget.imageService.pickVideo();
    if (path != null) widget.onUpdate(widget.slide.copyWith(videoPath: path));
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        EditorField(
          label: 'Titel (optioneel)',
          controller: _title,
          hint: 'Titel boven de video',
          maxLines: 2,
          qualityField: 'title',
        ),
        const SizedBox(height: 16),
        const SectionLabel('Video'),
        Row(
          children: [
            Expanded(child: _PathBox(path: widget.slide.videoPath)),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickVideo,
              icon: const Icon(Icons.movie_outlined, size: 16),
              label: Text(l10n.d('Kiezen')),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            value: widget.slide.videoAutoplay,
            onChanged: (value) => widget.onUpdate(
              widget.slide.copyWith(videoAutoplay: value ?? false),
            ),
            title: Text(l10n.d('Video automatisch afspelen')),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
        const SizedBox(height: 16),
        AudioAttachmentEditor(
          slide: widget.slide,
          imageService: widget.imageService,
          onUpdate: widget.onUpdate,
        ),
      ],
    );
  }
}

class _PathBox extends StatelessWidget {
  final String path;

  const _PathBox({required this.path});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        border: Border.all(color: const Color(0xFFCBD5E1)),
        borderRadius: BorderRadius.circular(6),
        color: Colors.white,
      ),
      child: Text(
        path.isEmpty ? l10n.d('Geen video gekozen') : path,
        style: TextStyle(
          fontSize: 12,
          color: path.isEmpty
              ? const Color(0xFF64748B)
              : const Color(0xFF334155),
        ),
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
