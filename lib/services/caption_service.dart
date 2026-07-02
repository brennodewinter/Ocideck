import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../utils/project_path.dart';
import 'image_sidecar_store.dart';

/// Slaat afbeeldingscaptions op als JSON-sidecar in de map van de afbeelding.
/// Bestandsnaam: .ocideck_captions.json
class CaptionService {
  static const _store = ImageSidecarStore(
    sidecarName: '.ocideck_captions.json',
    logLabel: 'CaptionService',
  );

  Future<String?> getCaption(String imagePath, {String? basePath}) async {
    final resolvedPath = _resolvePath(imagePath, basePath);
    if (resolvedPath == null) return null;
    return _store.read(resolvedPath);
  }

  Future<void> saveCaption(
    String imagePath,
    String caption, {
    String? basePath,
  }) async {
    final resolvedPath = _resolvePath(imagePath, basePath);
    if (resolvedPath == null) return;
    await _store.write(resolvedPath, caption);
  }

  Future<void> copyCaption(
    String sourceImagePath,
    String destinationImagePath, {
    String? sourceBasePath,
    String? destinationBasePath,
  }) async {
    final caption = await getCaption(sourceImagePath, basePath: sourceBasePath);
    if (caption == null || caption.trim().isEmpty) return;
    await saveCaption(
      destinationImagePath,
      caption,
      basePath: destinationBasePath,
    );
  }

  String? _resolvePath(String imagePath, String? basePath) {
    if (imagePath.trim().isEmpty) return null;
    if (basePath == null || basePath.isEmpty) {
      return p.isAbsolute(imagePath) ? p.normalize(imagePath) : null;
    }
    if (p.isAbsolute(imagePath)) {
      return resolveProjectAbsolute(basePath, imagePath);
    }
    return resolveProjectRelative(basePath, imagePath);
  }
}

final captionServiceProvider = Provider<CaptionService>(
  (_) => CaptionService(),
);
