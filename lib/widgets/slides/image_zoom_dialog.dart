import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/project_path.dart';

/// Opens a full-screen, pan-and-zoomable view of [imagePath] (resolved against
/// [projectPath]). Used by question slides so the audience can inspect a photo
/// in detail. Esc, the close button, or a tap on the dark backdrop dismisses it.
Future<void> showImageZoomDialog(
  BuildContext context, {
  required String imagePath,
  String? projectPath,
  String caption = '',
}) {
  final resolved = resolveSlideAssetPath(imagePath, projectPath);
  if (resolved == null) return Future<void>.value();
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ImageZoomView(file: File(resolved), caption: caption),
  );
}

class _ImageZoomView extends StatelessWidget {
  final File file;
  final String caption;

  const _ImageZoomView({required this.file, required this.caption});

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(context).maybePop(),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            // Tap the backdrop to close.
            Positioned.fill(
              child: GestureDetector(
                onTap: () => Navigator.of(context).maybePop(),
                behavior: HitTestBehavior.opaque,
              ),
            ),
            Positioned.fill(
              child: InteractiveViewer(
                minScale: 0.8,
                maxScale: 6,
                child: Center(
                  child: Image.file(
                    file,
                    fit: BoxFit.contain,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 64,
                    ),
                  ),
                ),
              ),
            ),
            if (caption.trim().isNotEmpty)
              Positioned(
                left: 0,
                right: 0,
                bottom: 24,
                child: IgnorePointer(
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        caption.trim(),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            Positioned(
              top: 16,
              right: 16,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
