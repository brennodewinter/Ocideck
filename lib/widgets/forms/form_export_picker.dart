// De bestandskiezer, het opslagvenster en de map van het document, samengebracht tot
// wat de invulpagina voor het opslaan van de inzending nodig heeft
// ([FormExportSupport]).

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:ocideck_form_core/ocideck_form_core.dart'
    show FormBundlePins, FormSpec;
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/download_delivery.dart';
import '../../services/export_metadata.dart' show kOciDeckVersion;
import '../../services/file_service.dart' show pickDocumentExportDestination;
import '../../services/form/form_image_service.dart';
import '../../utils/atomic_file.dart';
import 'form_export_support.dart';
import 'form_text_helpers.dart' show formTextOf;

/// De gepubliceerde formulieren die in deze sessie zijn gezien, per formulier en
/// versie. Het geheugen van de ondersteuning; een nieuwe sessie begint leeg, en dan
/// vraagt de pagina om het bestand.
final Map<String, String> _publishedForms = {};

/// De bundel en de vingerafdruk die bij een formulier in deze sessie tot een verzegelde
/// inzending leidden, per formulier en versie: een tweede inzending vraagt er niet opnieuw om.
final Map<String, ({String bundle, String fingerprint})> _sealMemory = {};

/// Waar de pins staan: per formulier en organisator het hoogste volgnummer dat de invuller zag
/// (FORM_INTAKE.md §5.1). Blijft over sessies bestaan, anders beschermt het tegen niets.
const String kFormBundlePinsKey = 'form_bundle_pins';

/// Leegt het geheugen van [formExportSupportFor], voor een test.
@visibleForTesting
void debugClearPublishedForms() {
  _publishedForms.clear();
  _sealMemory.clear();
}

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
  String? bundleTitle,
  Future<String?> Function(String dialogTitle)? pick,
  Future<String?> Function(String dialogTitle)? pickBundle,
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
    // Verzegelen gebruikt de age-bibliotheek, en die draait in de webbouw nog niet (dart2js):
    // daar is er alleen de gewone zip.
    seal: kIsWeb || bundleTitle == null
        ? null
        : FormSealSupport(
            pickBundle: () => (pickBundle ?? _pickBundle)(bundleTitle),
            readPins: _readPins,
            writePins: _writePins,
            recall: (spec) => _sealMemory[key(spec)],
            remember: (spec, bundle, fingerprint) => _sealMemory[key(spec)] = (
              bundle: bundle,
              fingerprint: fingerprint,
            ),
            forget: (spec) => _sealMemory.remove(key(spec)),
          ),
  );
}

Future<String?> _pickBundle(String dialogTitle) async {
  final files = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: FileType.custom,
    allowedExtensions: const ['json'],
  );
  if (files.isEmpty) return null;
  return formTextOf(await files.first.readAsBytes());
}

/// De pins uit de voorkeuren. Wat er niet staat of niet te lezen is, is een lege lijst: de
/// invuller geloofde nog geen bundel — het is niet te weten of hij er wel een zag.
Future<FormBundlePins> _readPins() async {
  final prefs = await SharedPreferences.getInstance();
  final text = prefs.getString(kFormBundlePinsKey);
  if (text == null) return const FormBundlePins();
  try {
    return FormBundlePins.fromJson(jsonDecode(text));
  } on FormatException {
    return const FormBundlePins();
  }
}

Future<void> _writePins(FormBundlePins pins) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kFormBundlePinsKey, jsonEncode(pins.toJson()));
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
