// De bestandskiezer en de map van het document, samengebracht tot wat de
// invulpagina voor foto's nodig heeft ([FormImageSupport]).

import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show FileImage;

import '../../services/form/form_image_service.dart';
import '../../utils/project_path.dart';
import 'form_image_support.dart';

/// De extensies die de kiezer toont. De echte controle is de inhoud van het bestand
/// (`cleanImage`); dit is alleen wat de kiezer aanbiedt.
const List<String> kFormImageExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'heic',
  'heif',
];

/// De ondersteuning voor foto's van een document in [projectPath], of `null` als
/// die er niet kan zijn: het document staat nog nergens, of het draait op het web
/// (waar foto's in het geheugen leven en niet in een map).
FormImageSupport? formImageSupportFor({
  required String? projectPath,
  required String dialogTitle,
}) {
  if (projectPath == null || kIsWeb) return null;
  return FormImageSupport(
    add: (fieldId, taken) async {
      final files = await FilePicker.pickFiles(
        dialogTitle: dialogTitle,
        type: FileType.custom,
        allowedExtensions: kFormImageExtensions,
      );
      if (files.isEmpty) return null;
      return addFormImages(
        projectPath: projectPath,
        fieldId: fieldId,
        taken: taken,
        readers: [for (final file in files) file.readAsBytes],
      );
    },
    probe: (paths) => probeFormImages(paths, projectPath: projectPath),
    preview: (path) {
      final absolute = resolveSlideAssetPath(path, projectPath);
      return absolute == null ? null : FileImage(File(absolute));
    },
  );
}
