// Wat een op het venster gesleept bestand is, en hoe je er bytes uit krijgt.
//
// Waarom dit náást de shell staat en niet erin: onder `flutter test` is
// `kIsWeb` altijd `false`, dus de web-tak van de drop-afhandeling wordt door
// geen enkele widgettest aangeraakt — precies de blinde vlek waarin het
// stil-falen van de web-drop jarenlang kon zitten. Alles wat hier staat is
// platformloos en gewoon aanroepbaar, zodat het wél getoetst kan worden.
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' show BuildContext;
import 'package:path/path.dart' as p;

import '../../services/import/document_import_service.dart'
    show isImportableDocumentName;
import '../../utils/log.dart';
import 'document_import_action.dart' show importDroppedDocuments;
import 'presentation_import_action.dart';

/// De extensies die een gesleept bestand als afbeelding laten tellen.
///
/// Niet meer dan een eerste zeef: of het écht een afbeelding is, bepaalt
/// `ImageService` daarna op de magic bytes — een extensie is een bewering van
/// degene die het bestand aanlevert.
const droppedImageExtensions = {
  '.jpg',
  '.jpeg',
  '.png',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.tiff',
  '.tif',
};

/// Wat de drop met een bestand doet.
enum DroppedKind {
  /// Een deck of pakket: opent in een tabblad.
  deck,

  /// Een presentatie van elders (.pptx/.odp/.key): gaat de import in.
  presentation,

  /// Een document of spreadsheet van elders (.docx/.odt/.xlsx/.ods/.csv):
  /// gaat de documentimport in.
  document,

  /// Een afbeelding: wordt slide-inhoud.
  image,
}

/// De afhandeling die [name] krijgt, of `null` als de drop dit bestand negeert.
///
/// Bepaald op de náám, vóór er één byte gelezen wordt: een type dat we toch
/// laten liggen mag geen megabytes door het geheugen trekken.
DroppedKind? droppedKind(String name) {
  final ext = p.extension(name.toLowerCase());
  if (ext == '.md' || ext == '.ocideck' || ext == '.zip') {
    return DroppedKind.deck;
  }
  if (isImportablePresentationName(name)) return DroppedKind.presentation;
  if (isImportableDocumentName(name)) return DroppedKind.document;
  if (droppedImageExtensions.contains(ext)) return DroppedKind.image;
  return null;
}

/// De bytes van een gesleept bestand, of `null` als ze niet te lezen waren.
///
/// Op web is een gesleept bestand een blob-URL en haalt `readAsBytes` die met
/// een XHR terug — een netwerkhandeling in de ogen van de Content-Security-
/// Policy, en dus iets dat kán weigeren. Dat gebeurde ook: zolang `connect-src`
/// geen `blob:` toestond, gooide elke lezing en nam die fout de hele
/// drop-afhandeling mee. De aanroep hangt aan `onDragDone` zonder `await`, dus
/// er was geen aanroeper die hem opving en de gebruiker zag letterlijk niets
/// gebeuren.
///
/// De CSP is inmiddels gerepareerd, maar de vangst blijft: een ingetrokken blob
/// of een leesfout mag één bestand kosten, niet de andere en niet de melding.
Future<Uint8List?> readDroppedBytes(DropItem file) async {
  try {
    return await file.readAsBytes();
  } catch (e, s) {
    logError('drop: bytes lezen mislukt voor ${file.name}', e, s);
    return null;
  }
}

/// De importkant van een drop, gedeeld door de desktop- en webhandler: splitst
/// [files] op naam en stuurt presentaties via de wachtrijroute (met
/// modulepoort) en documenten/spreadsheets elk in een eigen tabblad — zie
/// [importDroppedDocuments]. Een lege lijst is een no-op; [context] wordt pas
/// aangeraakt als er werk is.
Future<void> importDroppedFiles(
  BuildContext context,
  WidgetRef ref,
  List<PickedPresentation> files,
) async {
  if (files.isEmpty || !context.mounted) return;
  final presentations = <PickedPresentation>[];
  final documents = <PickedPresentation>[];
  for (final file in files) {
    (isImportableDocumentName(file.name) ? documents : presentations).add(file);
  }
  if (presentations.isNotEmpty) {
    await importDroppedPresentations(context, ref, presentations);
  }
  if (!context.mounted) return;
  await importDroppedDocuments(context, documents);
}
