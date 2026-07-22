import 'package:flutter/material.dart';
import '../../models/slide.dart';
import '../../services/image_service.dart';
import '../../l10n/app_localizations.dart';
import '_editor_field.dart';
import '../../theme/app_theme.dart';
import '../../platform/platform_features.dart';

class AudioAttachmentEditor extends StatelessWidget {
  final Slide slide;
  final ImageService imageService;
  final ValueChanged<Slide> onUpdate;
  final String? projectPath;

  const AudioAttachmentEditor({
    super.key,
    required this.slide,
    required this.imageService,
    required this.onUpdate,
    this.projectPath,
  });

  Future<void> _pickAudio() async {
    final path = await imageService.pickAudio(projectPath: projectPath);
    if (path != null) onUpdate(slide.copyWith(audioPath: path));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
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
                  border: Border.all(color: AppTheme.slate300),
                  borderRadius: BorderRadius.circular(6),
                  color: AppTheme.paper,
                ),
                child: Text(
                  slide.audioPath.isEmpty
                      ? l10n.d('Geen audiobestand gekozen')
                      : slide.audioPath,
                  style: TextStyle(
                    fontSize: 12,
                    color: slide.audioPath.isEmpty
                        ? AppTheme.slate500
                        : AppTheme.slate700,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Zie video_slide_editor.dart: op web is er geen projectmap om
            // het bestand in te importeren, dus geen kiezer.
            if (supportsLocalProjectFolders)
              ElevatedButton.icon(
                onPressed: _pickAudio,
                icon: const Icon(Icons.audio_file_outlined, size: 16),
                label: Text(l10n.d('Kiezen')),
              ),
            if (slide.audioPath.isNotEmpty)
              IconButton(
                onPressed: () => onUpdate(
                  slide.copyWith(audioPath: '', audioAutoplay: false),
                ),
                icon: const Icon(Icons.clear, size: 18),
                tooltip: l10n.d('Audio verwijderen'),
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
            title: Text(l10n.d('Audio automatisch afspelen')),
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
          ),
        ),
      ],
    );
  }
}
