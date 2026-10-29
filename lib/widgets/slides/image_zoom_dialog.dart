import 'dart:io';

import 'package:material_ui/material_ui.dart';

export '../theme_profile_logo.dart' show ThemeProfileLogo;
export 'slide_preview.dart' show SlidePreviewWidget;
import 'package:flutter/services.dart';

import '../../services/web_asset_store.dart';
import '../../utils/image_limits.dart';
import '../../utils/project_path.dart';
import '../safe_svg_image.dart';

/// Opens a full-screen, pan-and-zoomable view of [imagePath] (resolved against
/// [projectPath]). Used by question slides so the audience can inspect a photo
/// in detail. Esc, the close button, or a tap on the dark backdrop dismisses it.
Future<void> showImageZoomDialog(
  BuildContext context, {
  required String imagePath,
  String? projectPath,
  String caption = '',
}) {
  // `mem:`-pad (webversie): bytes uit de WebAssetStore i.p.v. een bestand.
  final memBytes = WebAssetStore.isMemPath(imagePath)
      ? WebAssetStore.bytesFor(imagePath)
      : null;
  if (isSvgImagePath(imagePath)) {
    final Widget vector;
    if (memBytes != null) {
      vector = SafeSvgImage.memory(
        memBytes,
        fit: BoxFit.contain,
        errorBuilder: (_) => const _ZoomImageError(),
      );
    } else {
      final resolved = resolveContainedRealPath(imagePath, projectPath);
      if (resolved == null) return Future<void>.value();
      vector = SafeSvgImage.file(
        resolved,
        fit: BoxFit.contain,
        errorBuilder: (_) => const _ZoomImageError(),
      );
    }
    return showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.92),
      builder: (_) => _ImageZoomView.vector(vector, caption: caption),
    );
  }
  final ImageProvider provider;
  if (memBytes != null) {
    provider = cappedMemoryImage(memBytes);
  } else {
    final resolved = resolveSlideAssetPath(imagePath, projectPath);
    if (resolved == null) return Future<void>.value();
    // De symlink-containment zit in de byte-lezing van de provider (#2624).
    provider = cappedFileImage(File(resolved), projectPath: projectPath);
  }
  return showImageProviderZoomDialog(
    context,
    image: provider,
    caption: caption,
  );
}

/// Same viewer for an [ImageProvider] that is already resolved — bundled assets
/// (`AssetImage`) carry no project-relative path to resolve, so they enter here.
Future<void> showImageProviderZoomDialog(
  BuildContext context, {
  required ImageProvider image,
  String caption = '',
}) {
  return showDialog<void>(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.92),
    builder: (_) => _ImageZoomView.raster(image, caption: caption),
  );
}

class _ImageZoomView extends StatelessWidget {
  final ImageProvider? image;
  final Widget? vector;
  final String caption;

  const _ImageZoomView.raster(this.image, {required this.caption})
    : vector = null;

  const _ImageZoomView.vector(this.vector, {required this.caption})
    : image = null;

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
                  child:
                      vector ??
                      Image(
                        image: image!,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => const _ZoomImageError(),
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

class _ZoomImageError extends StatelessWidget {
  const _ZoomImageError();

  @override
  Widget build(BuildContext context) =>
      const Icon(Icons.broken_image_outlined, color: Colors.white54, size: 64);
}
