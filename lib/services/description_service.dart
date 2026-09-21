import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import 'image_dedup_service.dart';
import 'image_sidecar_store.dart';

/// Stores short, searchable image descriptions as a JSON sidecar in the image's
/// own directory. File name: .ocideck_descriptions.json, keyed by base name.
///
/// Kept separate from captions (which are source/credit lines): a description
/// is free-text used to find images by the words in it.
class DescriptionService {
  static const _store = ImageSidecarStore(
    sidecarName: '.ocideck_descriptions.json',
    logLabel: 'DescriptionService',
  );

  Future<String?> getDescription(String imagePath) async {
    final resolvedPath = _resolveSidecarImagePath(imagePath);
    if (resolvedPath == null) return null;
    return _store.read(resolvedPath);
  }

  Future<void> saveDescription(String imagePath, String description) async {
    final resolvedPath = _resolveSidecarImagePath(imagePath);
    if (resolvedPath == null) return;
    await _store.write(resolvedPath, description);
  }

  /// Remove the description entry for [imagePath] (used when an image is
  /// deleted). Safe to call when no entry exists.
  Future<void> removeDescription(String imagePath) =>
      saveDescription(imagePath, '');

  /// Neem de beschrijving (de zoekbare tags) van [sourceImagePath] mee naar
  /// [destinationImagePath] — de sidecar-tak van het kopiëren van het bestand
  /// zelf. Zonder dit verhuist de kopieerslag alleen de bytes en is de kopie in
  /// de doelmap ongetagd (#2147).
  ///
  /// Draagt de bestemming al een eigen beschrijving (een hergebruikt,
  /// byte-identiek bestand, of een handmatige tag), dan wint die: de brontekst
  /// wordt er met een komma achter gezet in plaats van hem te overschrijven.
  Future<void> copyDescription(
    String sourceImagePath,
    String destinationImagePath,
  ) async {
    final description = await getDescription(sourceImagePath);
    if (description == null || description.trim().isEmpty) return;
    final existing = await getDescription(destinationImagePath);
    final merged = ImageDedupService().mergeMetadata([
      existing,
      description,
    ], separator: ', ');
    await saveDescription(destinationImagePath, merged);
  }

  /// Load every description stored in the directories that contain [imagePaths].
  /// Returns a map of absolute image path → description. Each sidecar is read
  /// once, so this stays cheap even for thousands of images.
  Future<Map<String, String>> loadFor(Iterable<String> imagePaths) async {
    final dirs = <String>{};
    for (final path in imagePaths) {
      final resolved = _resolveSidecarImagePath(path);
      if (resolved != null) dirs.add(p.dirname(resolved));
    }
    final result = <String, String>{};
    for (final dir in dirs) {
      final entries = await _store.readDir(dir);
      for (final entry in entries.entries) {
        result[p.join(dir, entry.key)] = entry.value;
      }
    }
    return result;
  }

  /// Normalize and reject paths that escape via `../` after normalization.
  String? _resolveSidecarImagePath(String imagePath) {
    if (imagePath.trim().isEmpty || !p.isAbsolute(imagePath)) return null;
    final normalized = p.normalize(imagePath);
    if (normalized.contains('..${p.separator}') || normalized.endsWith('..')) {
      return null;
    }
    return normalized;
  }
}

final descriptionServiceProvider = Provider<DescriptionService>(
  (_) => DescriptionService(),
);
