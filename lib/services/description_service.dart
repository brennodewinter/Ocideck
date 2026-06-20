import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../utils/log.dart';

/// Stores short, searchable image descriptions as a JSON sidecar in the image's
/// own directory. File name: .ocideck_descriptions.json, keyed by base name.
///
/// Kept separate from captions (which are source/credit lines): a description
/// is free-text used to find images by the words in it.
class DescriptionService {
  static const _sidecar = '.ocideck_descriptions.json';

  Future<String?> getDescription(String imagePath) async {
    final resolvedPath = _resolveSidecarImagePath(imagePath);
    if (resolvedPath == null) return null;
    final file = _sidecarFile(resolvedPath);
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map;
      final value = data[p.basename(resolvedPath)];
      return value is String ? value : null;
    } catch (e) {
      logWarning(
        'DescriptionService.getDescription: read description sidecar',
        e,
      );
      return null;
    }
  }

  Future<void> saveDescription(String imagePath, String description) async {
    final resolvedPath = _resolveSidecarImagePath(imagePath);
    if (resolvedPath == null) return;
    final file = _sidecarFile(resolvedPath);
    Map<String, dynamic> data = {};
    if (file.existsSync()) {
      try {
        data = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      } catch (e, s) {
        logError(
          'DescriptionService.saveDescription: parse existing sidecar',
          e,
          s,
        );
      }
    }
    final key = p.basename(resolvedPath);
    if (description.trim().isEmpty) {
      data.remove(key);
    } else {
      data[key] = description.trim();
    }
    if (data.isEmpty) {
      if (file.existsSync()) await file.delete();
    } else {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    }
  }

  /// Remove the description entry for [imagePath] (used when an image is
  /// deleted). Safe to call when no entry exists.
  Future<void> removeDescription(String imagePath) =>
      saveDescription(imagePath, '');

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
      final file = File(p.join(dir, _sidecar));
      if (!file.existsSync()) continue;
      try {
        final data = jsonDecode(await file.readAsString()) as Map;
        for (final entry in data.entries) {
          if (entry.value is String) {
            result[p.join(dir, entry.key as String)] = entry.value as String;
          }
        }
      } catch (e) {
        logWarning('DescriptionService.loadFor: read description sidecar', e);
      }
    }
    return result;
  }

  /// Normalize and reject paths that escape via `../` after normalization.
  String? _resolveSidecarImagePath(String imagePath) {
    if (imagePath.trim().isEmpty || !p.isAbsolute(imagePath)) return null;
    final normalized = p.normalize(imagePath);
    if (normalized.contains('..${p.separator}') ||
        normalized.endsWith('..')) {
      return null;
    }
    return normalized;
  }

  File _sidecarFile(String imagePath) {
    return File(p.join(p.dirname(imagePath), _sidecar));
  }
}

final descriptionServiceProvider = Provider<DescriptionService>(
  (_) => DescriptionService(),
);
