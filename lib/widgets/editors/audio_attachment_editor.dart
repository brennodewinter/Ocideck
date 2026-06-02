import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '_editor_field.dart';

class AudioAttachmentEditor extends StatelessWidget {
  final Slide slide;
  final ImageService imageService;
  final ValueChanged<Slide> onUpdate;

  const AudioAttachmentEditor({
    super.key,
    required this.slide,
    required this.imageService,
    required this.onUpdate,
  });

  Future<void> _pickAudio() async {
    final path = await imageService.pickAudio();
    if (path != null) onUpdate(slide.copyWith(audioPath: path));
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Audio bij deze slide'),
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  border: Border.all(color: const Color(0xFFCBD5E1)),
                  borderRadius: BorderRadius.circular(6),
                  color: Colors.white,
                ),
                child: Text(
                  slide.audioPath.isEmpty
                      ? 'Geen audiobestand gekozen'
                      : slide.audioPath,
                  style: TextStyle(
                    fontSize: 12,
                    color: slide.audioPath.isEmpty
                        ? const Color(0xFF94A3B8)
                        : const Color(0xFF334155),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            ElevatedButton.icon(
              onPressed: _pickAudio,
              icon: const Icon(Icons.audio_file_outlined, size: 16),
              label: const Text('Kiezen'),
            ),
            if (slide.audioPath.isNotEmpty)
              IconButton(
                onPressed: () => onUpdate(
                  slide.copyWith(audioPath: '', audioAutoplay: false),
                ),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: 'Audio verwijderen',
              ),
          ],
        ),
        Material(
          color: Colors.transparent,
          child: CheckboxListTile(
            value: slide.audioAutoplay,
            onChanged: slide.audioPath.isEmpty
                ? null
                : (value) =>
                      onUpdate(slide.copyWith(audioAutoplay: value ?? false)),
            title: const Text('Audio automatisch afspelen'),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}
