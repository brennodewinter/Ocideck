/// Aflevering van een export in de browser: één export, één download.
///
/// Op web is elke uitgang een download — er is geen map om in te schrijven.
/// Browsers laten de eerste automatische download door en zetten een poort voor
/// de tweede en verdere: Chrome vraagt of de site meerdere bestanden mag
/// downloaden en levert bij weigering stilzwijgend niets. Een export die uit
/// meer dan één bestand bestaat verloor daar zijn tweede en derde bestand —
/// een geredigeerd rapport vertrok zonder zijn manifest en sleutels, en de app
/// meldde "geëxporteerd" (#1902). Daarom gaat zo'n export hier als één ZIP.
///
/// Wat deze laag niet kan: zien of het bestand werkelijk in de downloadmap
/// aankwam. Een download-anker meldt niets terug. Het enige eerlijke signaal is
/// of het *aanbieden* lukte, en dat is wat [deliverAsDownload] teruggeeft. De
/// aanroeper mag niet meer beweren dan dat — vandaar de aparte bewoording in de
/// schil ("aangeboden als download", niet "geëxporteerd naar").
library;

import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import '../utils/file_download.dart';

/// Eén af te leveren bestand: de naam die de gebruiker ziet, en de bytes.
typedef DownloadFile = ({String name, Uint8List bytes});

/// De laag waar bytes de pagina verlaten. Geeft `true` als het aanbieden lukte.
typedef DownloadSink =
    bool Function(String fileName, Uint8List bytes, String mimeType);

/// Test-seam: vervangt de echte browserdownload.
///
/// Zonder deze haak is er niets te meten. `downloadBytesToBrowser` bestaat
/// alleen op web, en de suite draait op de VM: een test kon niet zien hoevéél
/// downloads een export afvuurde, en dus ook niet dat een geredigeerde export
/// er stilletjes drie deed (#1902). Een test zet hem in `setUp` en herstelt hem
/// in `tearDown`.
@visibleForTesting
DownloadSink? debugDownloadSink;

/// Test-seam voor de platformtak: dwingt [deliversByDownload] af.
///
/// De exportpaden vertakken op "levert dit als download of als bestand op
/// schijf", en die vraag was op de VM niet te stellen — `kIsWeb` is daar altijd
/// `false`, dus de hele webtak lag buiten bereik van de suite.
@visibleForTesting
bool? debugDeliversByDownload;

/// True wanneer een export bij de gebruiker aankomt als browserdownload in
/// plaats van als bestand op schijf.
bool get deliversByDownload => debugDeliversByDownload ?? kIsWeb;

/// Levert [files] af als **één** download en geeft de naam terug die de
/// gebruiker in zijn downloadmap ziet, of `null` als het aanbieden mislukte.
///
/// Eén bestand gaat als zichzelf; meer dan één gaat als ZIP onder
/// [bundleName], met de bestanden op hun eigen naam erin. Bewust geen tweede
/// `saveFile`-aanroep erachteraan: dat is precies de download die de browser
/// stil tegenhoudt.
String? deliverAsDownload(
  List<DownloadFile> files, {
  required String bundleName,
}) {
  if (files.isEmpty) return null;
  final sink = debugDownloadSink ?? downloadBytesToBrowser;
  if (files.length == 1) {
    final only = files.single;
    return sink(only.name, only.bytes, _mimeTypeFor(only.name))
        ? only.name
        : null;
  }
  final archive = Archive();
  for (final f in files) {
    archive.add(ArchiveFile(f.name, f.bytes.length, f.bytes));
  }
  final zip = ZipEncoder().encodeBytes(archive);
  return sink(bundleName, zip, _mimeTypeFor(bundleName)) ? bundleName : null;
}

/// [deliverAsDownload] voor tekst: codeert als UTF-8 en levert één bestand af.
String? deliverTextAsDownload(String fileName, String content) =>
    deliverAsDownload([
      (name: fileName, bytes: Uint8List.fromList(utf8.encode(content))),
    ], bundleName: fileName);

/// De ZIP-naam voor een export die uit meer dan één bestand bestaat.
///
/// De volledige naam van het hoofdbestand plus `.zip`, dus niet de kale
/// basisnaam: een PDF- en een HTML-export van hetzelfde deck zouden anders
/// dezelfde ZIP-naam krijgen, en in een downloadmap is "deck.zip" en
/// "deck (1).zip" niet meer uit elkaar te houden.
String bundleNameFor(String primaryFileName) => '$primaryFileName.zip';

/// Het MIME-type bij een bestandsnaam. Het `download`-attribuut bepaalt dat de
/// browser opslaat in plaats van toont, dus dit is beleefdheid en geen
/// beveiliging; onbekend valt bewust terug op octet-stream.
String _mimeTypeFor(String fileName) {
  switch (p.extension(fileName).toLowerCase()) {
    case '.md':
      return 'text/markdown;charset=utf-8';
    case '.json':
      return 'application/json;charset=utf-8';
    case '.html':
      return 'text/html;charset=utf-8';
    case '.tex':
      return 'text/x-tex;charset=utf-8';
    case '.txt':
      return 'text/plain;charset=utf-8';
    case '.pdf':
      return 'application/pdf';
    case '.zip':
    case '.ocideck':
      return 'application/zip';
    case '.pptx':
      return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
    case '.odp':
      return 'application/vnd.oasis.opendocument.presentation';
    case '.odt':
      return 'application/vnd.oasis.opendocument.text';
    case '.epub':
      return 'application/epub+zip';
    default:
      return 'application/octet-stream';
  }
}
