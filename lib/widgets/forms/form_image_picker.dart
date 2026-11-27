// De bestandskiezer en de map van het document, samengebracht tot wat de
// invulpagina voor foto's nodig heeft ([FormImageSupport]).

import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/painting.dart' show MemoryImage;

import '../../services/form/form_image_service.dart';
import '../../utils/image_limits.dart';
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
///
/// [pick] is de bestandskiezer; een test geeft een eigen keuze mee. [presets]
/// zijn klaargezette bronnen per veld, zoals de stijllogo's voor het
/// logo-veld van een PE-bewijs.
FormImageSupport? formImageSupportFor({
  required String? projectPath,
  required String dialogTitle,
  Future<List<FormImagePick>> Function(String dialogTitle)? pick,
  Map<String, List<FormImagePreset>> presets = const {},
  FormSessionImages? sessionImages,
}) {
  if (sessionImages != null) {
    return FormImageSupport(
      add: (fieldId, taken) async {
        final files = await (pick ?? _pickPhotos)(dialogTitle);
        if (files.isEmpty) return null;
        return sessionImages.add(fieldId, taken, [
          for (final file in files) file.read,
        ]);
      },
      addReaders: sessionImages.add,
      probe: sessionImages.probe,
      preview: (path) {
        final bytes = sessionImages.read(path);
        return bytes == null ? null : MemoryImage(bytes);
      },
    );
  }
  if (projectPath == null || kIsWeb) return null;
  return FormImageSupport(
    add: (fieldId, taken) async {
      final files = await (pick ?? _pickPhotos)(dialogTitle);
      if (files.isEmpty) return null;
      return addFormImages(
        projectPath: projectPath,
        fieldId: fieldId,
        taken: taken,
        readers: [for (final file in files) file.read],
      );
    },
    // Dezelfde verwerking als de kiezer, maar dan voor bytes die al binnen
    // zijn: het klembord, een getekende handtekening, een stijllogo.
    addReaders: (fieldId, taken, readers) => addFormImages(
      projectPath: projectPath,
      fieldId: fieldId,
      taken: taken,
      readers: readers,
    ),
    presets: presets,
    probe: (paths) => probeFormImages(paths, projectPath: projectPath),
    preview: (path) {
      final absolute = resolveSlideAssetPath(path, projectPath);
      return absolute == null
          ? null
          : cappedFileImage(File(absolute), projectPath: projectPath);
    },
  );
}

/// Een gekozen bestand: wat het systeem teruggeeft, teruggebracht tot wat we ervan
/// nodig hebben. De naam wordt niet gebruikt — een foto krijgt zijn eigen naam —
/// maar staat er voor de log en de test.
typedef FormImagePick = ({String name, Future<Uint8List> Function() read});

Future<List<FormImagePick>> _pickPhotos(String dialogTitle) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: kIsWeb
        ? const ['jpg', 'jpeg', 'png', 'webp']
        : kFormImageExtensions,
  );
  return [for (final file in files) (name: file.name, read: file.readAsBytes)];
}
