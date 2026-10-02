// De bestandskiezer, het opslagvenster en de map van het document, samengebracht tot
// wat de invulpagina voor het opslaan van de inzending nodig heeft
// ([FormExportSupport]).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:ocideck_form_core/ocideck_form_core.dart' show FormSpec;
import 'package:path/path.dart' as p;

import '../../services/download_delivery.dart';
import '../../services/export_metadata.dart' show kOciDeckVersion;
import '../../services/file_service.dart' show pickDocumentExportDestination;
import '../../services/form/form_image_service.dart';
import '../../utils/atomic_file.dart';
import 'form_export_support.dart';

/// De gepubliceerde formulieren die in deze sessie zijn gezien, per formulier en
/// versie. Het geheugen van de ondersteuning; een nieuwe sessie begint leeg, en dan
/// vraagt de pagina om het bestand.
final Map<String, String> _publishedForms = {};

/// Leegt het geheugen van [formExportSupportFor], voor een test.
@visibleForTesting
void debugClearPublishedForms() => _publishedForms.clear();

/// Waar het opslagvenster naartoe schrijft: een pad, of `null` als de invuller
/// annuleert. Dezelfde vorm als [pickDocumentExportDestination].
typedef FormExportDestination =
    Future<String?> Function({
      required String dialogTitle,
      required String fileName,
      String? initialDirectory,
    });

/// De ondersteuning voor het opslaan van een inzending van een document in
/// [projectPath] (`null`: nog nergens opgeslagen, of het web — dan zijn er geen foto's
/// te lezen, en de tekst gaat gewoon mee).
///
/// [pick] en [destination] zijn de bestandskiezer en het opslagvenster; een test
/// geeft eigen keuzes mee.
FormExportSupport formExportSupportFor({
  required String? projectPath,
  required String frontMatter,
  required String pickTitle,
  required String saveTitle,
  Future<String?> Function(String dialogTitle)? pick,
  FormExportDestination? destination,
}) {
  String key(FormSpec spec) => '${spec.id}@${spec.version}';
  return FormExportSupport(
    frontMatter: frontMatter,
    clientVersion: kOciDeckVersion,
    readImage: (path) async => projectPath == null || kIsWeb
        ? null
        : readFormImage(path, projectPath: projectPath),
    pickPublished: () => (pick ?? _pickForm)(pickTitle),
    save: (fileName, bytes) => _save(
      fileName,
      bytes,
      saveTitle: saveTitle,
      projectPath: projectPath,
      destination: destination ?? pickDocumentExportDestination,
    ),
    recall: (spec) => _publishedForms[key(spec)],
    remember: (spec, published) => _publishedForms[key(spec)] = published,
  );
}

Future<String?> _save(
  String fileName,
  Uint8List bytes, {
  required String saveTitle,
  required String? projectPath,
  required FormExportDestination destination,
}) async {
  if (deliversByDownload) {
    return deliverAsDownload([
      (name: fileName, bytes: bytes),
    ], bundleName: fileName);
  }
  final path = await destination(
    dialogTitle: saveTitle,
    fileName: fileName,
    initialDirectory: projectPath,
  );
  if (path == null) return null;
  await writeBytesAtomic(File(path), bytes);
  return p.basename(path);
}

Future<String?> _pickForm(String dialogTitle) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: const ['md', 'markdown'],
  );
  if (files.isEmpty) return null;
  return formTextOf(await files.first.readAsBytes());
}

/// De tekst van een gekozen formulierbestand, of `null` als het geen UTF-8 is: een
/// formulier is Markdown, en wat niet te lezen valt kan ook niet het gepubliceerde
/// formulier zijn.
@visibleForTesting
String? formTextOf(Uint8List bytes) {
  try {
    return const Utf8Decoder().convert(bytes);
  } on FormatException {
    return null;
  }
}
