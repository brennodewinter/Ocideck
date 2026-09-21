// Wat een op het venster gesleept bestand is, en hoe je er bytes uit krijgt.
//
// Waarom dit náást de shell staat en niet erin: onder `flutter test` is
// `kIsWeb` altijd `false`, dus de web-tak van de drop-afhandeling wordt door
// geen enkele widgettest aangeraakt — precies de blinde vlek waarin het
// stil-falen van de web-drop jarenlang kon zitten. Alles wat hier staat is
// platformloos en gewoon aanroepbaar, zodat het wél getoetst kan worden.
import 'dart:typed_data';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;

import '../../utils/log.dart';
import 'presentation_import_action.dart' show isImportablePresentationName;

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
