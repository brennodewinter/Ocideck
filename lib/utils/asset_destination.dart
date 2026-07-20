import 'dart:io';

import 'package:path/path.dart' as p;

/// Waar een geïmporteerde asset heen gaat, en of hij er al stond.
class AssetDestination {
  /// Het bestand waarnaar gekopieerd moet worden, of dat er al identiek staat.
  final File file;

  /// True als [file] er al staat met exact dezelfde inhoud; kopiëren is dan
  /// overbodig.
  final bool alreadyPresent;

  const AssetDestination(this.file, {required this.alreadyPresent});
}

/// Hoeveel achtervoegsels we proberen voordat we het opgeven. Een map met
/// duizend varianten van dezelfde naam is geen normaal gebruik meer; dan is
/// stoppen eerlijker dan eindeloos doorzoeken.
const _maxNameAttempts = 999;

/// Kies de bestemming voor [filename] in [destDir], gegeven bronbestand [src].
///
/// Botst de naam met een bestand dat er al staat, dan zijn er twee gevallen.
/// Is de inhoud identiek, dan is dit dezelfde afbeelding die al eerder is
/// geïmporteerd en wijzen we naar het bestaande bestand. Verschilt de inhoud,
/// dan zou hergebruiken de vórige afbeelding op de nieuwe slide zetten — twee
/// mensen noemen hun schermafdruk allebei `screenshot.png` — dus krijgt de
/// nieuwkomer een oplopend achtervoegsel: `screenshot_2.png`.
///
/// Geeft null terug als er na [_maxNameAttempts] pogingen geen vrije naam is.
Future<AssetDestination?> resolveAssetDestination(
  Directory destDir,
  String filename,
  File src,
) async {
  final ext = p.extension(filename);
  final stem = p.basenameWithoutExtension(filename);
  for (var n = 1; n <= _maxNameAttempts; n++) {
    final name = n == 1 ? filename : '${stem}_$n$ext';
    final candidate = File(p.join(destDir.path, name));
    if (!await candidate.exists()) {
      return AssetDestination(candidate, alreadyPresent: false);
    }
    if (await filesHaveSameContent(src, candidate)) {
      return AssetDestination(candidate, alreadyPresent: true);
    }
  }
  return null;
}

/// Zoals [resolveAssetDestination], maar voor materiaal dat alleen als [bytes]
/// bestaat en geen bronbestand heeft — bijvoorbeeld een in-geheugen
/// `mem:`-afbeelding uit een remote deck. Een naambotsing met identieke inhoud
/// hergebruikt het bestaande bestand; verschilt de inhoud, dan wijkt de kopie
/// uit naar een oplopend achtervoegsel, net als de bestandsvariant.
Future<AssetDestination?> resolveAssetDestinationForBytes(
  Directory destDir,
  String filename,
  List<int> bytes,
) async {
  final ext = p.extension(filename);
  final stem = p.basenameWithoutExtension(filename);
  for (var n = 1; n <= _maxNameAttempts; n++) {
    final name = n == 1 ? filename : '${stem}_$n$ext';
    final candidate = File(p.join(destDir.path, name));
    if (!await candidate.exists()) {
      return AssetDestination(candidate, alreadyPresent: false);
    }
    if (await _fileHasBytes(candidate, bytes)) {
      return AssetDestination(candidate, alreadyPresent: true);
    }
  }
  return null;
}

/// Vergelijk de inhoud van [file] met [bytes]. Een leesfout telt als "niet
/// gelijk" — dan volgt een nieuwe naam, wat erger is dan nodig maar nooit de
/// verkeerde afbeelding oplevert (zie [filesHaveSameContent]).
Future<bool> _fileHasBytes(File file, List<int> bytes) async {
  try {
    if (await file.length() != bytes.length) return false;
    final actual = await file.readAsBytes();
    for (var i = 0; i < actual.length; i++) {
      if (actual[i] != bytes[i]) return false;
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

/// Vergelijk twee bestanden byte voor byte, met een vroege uitstap.
///
/// De lengtevergelijking vooraf vangt het gros af; pas bij gelijke lengte wordt
/// er echt gelezen, zodat een naamsbotsing tussen twee grote video's niet
/// standaard een volledige lezing kost. Een leesfout telt als "niet gelijk":
/// dan volgt een nieuwe naam, wat erger is dan nodig maar nooit de verkeerde
/// afbeelding oplevert.
Future<bool> filesHaveSameContent(File a, File b) async {
  const chunkBytes = 64 * 1024;
  try {
    if (await a.length() != await b.length()) return false;
    final readerA = await a.open();
    try {
      final readerB = await b.open();
      try {
        while (true) {
          final chunkA = await readerA.read(chunkBytes);
          final chunkB = await readerB.read(chunkBytes);
          if (chunkA.length != chunkB.length) return false;
          if (chunkA.isEmpty) return true;
          for (var i = 0; i < chunkA.length; i++) {
            if (chunkA[i] != chunkB[i]) return false;
          }
        }
      } finally {
        await readerB.close();
      }
    } finally {
      await readerA.close();
    }
  } on FileSystemException {
    return false;
  }
}
