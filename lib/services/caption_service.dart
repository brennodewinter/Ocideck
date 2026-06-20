import 'dart:convert';
import 'dart:io';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;

import '../utils/log.dart';
import '../utils/project_path.dart';

/// Slaat afbeeldingscaptions op als JSON-sidecar in de map van de afbeelding.
/// Bestandsnaam: .ocideck_captions.json
class CaptionService {
  static const _sidecar = '.ocideck_captions.json';

  Future<String?> getCaption(String imagePath, {String? basePath}) async {
    final resolvedPath = _resolvePath(imagePath, basePath);
    if (resolvedPath == null) return null;
    final file = _sidecarFile(resolvedPath);
    if (!file.existsSync()) return null;
    try {
      final data = jsonDecode(await file.readAsString()) as Map;
      final caption = data[p.basename(resolvedPath)];
      return caption is String ? caption : null;
    } catch (e) {
      logWarning('CaptionService.getCaption: read caption sidecar', e);
      return null;
    }
  }

  Future<void> saveCaption(
    String imagePath,
    String caption, {
    String? basePath,
  }) async {
    final resolvedPath = _resolvePath(imagePath, basePath);
    if (resolvedPath == null) return;
    final file = _sidecarFile(resolvedPath);
    Map<String, dynamic> data = {};
    if (file.existsSync()) {
      try {
        data = Map<String, dynamic>.from(
          jsonDecode(await file.readAsString()) as Map,
        );
      } catch (e, s) {
        logError('CaptionService.saveCaption: parse existing sidecar', e, s);
      }
    }
    final key = p.basename(resolvedPath);
    if (caption.trim().isEmpty) {
      data.remove(key);
    } else {
      data[key] = caption.trim();
    }
    if (data.isEmpty) {
      if (file.existsSync()) await file.delete();
    } else {
      await file.writeAsString(
        const JsonEncoder.withIndent('  ').convert(data),
      );
    }
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

  File _sidecarFile(String imagePath) {
    return File(p.join(p.dirname(imagePath), _sidecar));
  }
}

final captionServiceProvider = Provider<CaptionService>(
  (_) => CaptionService(),
);
