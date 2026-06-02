import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/deck.dart';
import '../../models/settings.dart';
import '../../models/slide.dart';
import '../../state/slide_clipboard_provider.dart';
import '../../theme/app_theme.dart';
import 'slide_preview.dart';

class SlideThumbnail extends ConsumerWidget {
  final Slide slide;
  final int index;
  final bool isSelected;

  /// De actieve slide binnen een meervoudige selectie (de slide die in de
  /// editor wordt getoond). Krijgt een iets sterkere markering.
  final bool isPrimary;
  final String? projectPath;
  final ThemeProfile themeProfile;
  final int slideCount;
  final TlpLevel tlp;
  final VoidCallback onTap;
  final VoidCallback onDuplicate;
  final VoidCallback onDelete;
  final VoidCallback onToggleSkip;
  final VoidCallback onCopyImage;

  const SlideThumbnail({
    super.key,
    required this.slide,
    required this.index,
    required this.isSelected,
    required this.onTap,
    required this.onDuplicate,
    required this.onDelete,
    required this.onToggleSkip,
    required this.onCopyImage,
    this.isPrimary = true,
    this.projectPath,
    this.themeProfile = const ThemeProfile(),
    this.slideCount = 1,
    this.tlp = TlpLevel.none,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skipped = slide.skipped;
    final borderColor = isSelected
        ? AppTheme.accent
        : skipped
        ? const Color(0xFF8A6D3B)
        : const Color(0xFF3A3F4B);
    // Actieve slide krijgt een dikkere rand dan de overige geselecteerde.
    final borderWidth = isSelected ? (isPrimary ? 2.5 : 1.6) : 1.0;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: borderWidth),
          color: isSelected ? const Color(0xFF2A2F3B) : const Color(0xFF252830),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Mini slide preview
            ClipRRect(
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(5),
              ),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Overgeslagen slides worden gedimd weergegeven.
                    Opacity(
                      opacity: skipped ? 0.32 : 1,
                      child: SlidePreviewWidget(
                        slide: slide,
                        projectPath: projectPath,
                        themeProfile: themeProfile,
                        slideNumber: index + 1,
                        slideCount: slideCount,
                        tlp: tlp,
                      ),
                    ),
                    if (skipped)
                      Positioned(
                        top: 4,
                        left: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xCC8A6D3B),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.visibility_off_outlined,
                                size: 10,
                                color: Colors.white,
                              ),
                              SizedBox(width: 3),
                              Text(
                                'Overgeslagen',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // Footer: slide number, type label, action buttons
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                children: [
                  Container(
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? AppTheme.accent
                          : const Color(0xFF4A4F5B),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: Center(
                      child: Text(
                        '${index + 1}',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      slide.type.label,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontSize: 9,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  // Drag handle
                  ReorderableDragStartListener(
                    index: index,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 2),
                      child: Icon(
                        Icons.drag_handle,
                        size: 14,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                  // Snelle overslaan-toggle
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      iconSize: 14,
                      splashRadius: 12,
                      tooltip: skipped
                          ? 'Weer tonen bij presenteren/exporteren'
                          : 'Overslaan bij presenteren/exporteren',
                      icon: Icon(
                        skipped
                            ? Icons.visibility_off
                            : Icons.visibility_outlined,
                        color: skipped
                            ? const Color(0xFFD4A24E)
                            : const Color(0xFF64748B),
                      ),
                      onPressed: onToggleSkip,
                    ),
                  ),
                  // Context menu
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: PopupMenuButton<String>(
                      icon: const Icon(
                        Icons.more_vert,
                        color: Color(0xFF64748B),
                        size: 14,
                      ),
                      padding: EdgeInsets.zero,
                      itemBuilder: (_) => [
                        const PopupMenuItem(
                          value: 'copy',
                          child: Text('Kopiëren'),
                        ),
                        const PopupMenuItem(
                          value: 'copy_image',
                          child: Text('Kopieer als afbeelding'),
                        ),
                        const PopupMenuItem(
                          value: 'duplicate',
                          child: Text('Dupliceren'),
                        ),
                        PopupMenuItem(
                          value: 'skip',
                          child: Text(
                            skipped ? 'Niet meer overslaan' : 'Overslaan',
                          ),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text(
                            'Verwijderen',
                            style: TextStyle(color: Colors.red),
                          ),
                        ),
                      ],
                      onSelected: (v) {
                        if (v == 'copy') {
                          ref.read(slideClipboardProvider.notifier).state =
                              slide;
                        }
                        if (v == 'copy_image') onCopyImage();
                        if (v == 'duplicate') onDuplicate();
                        if (v == 'skip') onToggleSkip();
                        if (v == 'delete') onDelete();
                      },
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
