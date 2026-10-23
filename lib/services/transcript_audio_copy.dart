// De bewaarkeuze die bij Opslaan landt (#2515, contract §3.2): kopieert
// het door de gebruiker gekozen bronbestand naar `media/` naast het
// document en levert het projectrelatieve pad dat in de marker hoort.
//
// Het bronpad is een door de gebruiker gekozen bestand — géén
// projectcontainment nodig (hij koos het expliciet), wél dezelfde
// mediacap en botsingsveilige naamgeving als elke andere asset.
// Gelezen en geschreven via streams: een uur WAV is ~115 MB, die hoeft
// nooit in zijn geheel in het geheugen.
import 'dart:io';

import 'package:path/path.dart' as p;

import '../utils/asset_destination.dart';
import '../utils/log.dart';
import 'image_service.dart' show ImageService;

/// De grens die `media/` ook voor dia-audio en -video hanteert.
const maxTranscriptAudioBytes = ImageService.maxMediaBytes;

/// Kopieert [sourcePath] naar `<documentDir>/media/` en levert het
/// `media/<naam>`-pad voor de `audio=`-verwijzing — of null wanneer de
/// kopie niet eerlijk kan: bron weg, boven de cap, doelmap niet
/// schrijfbaar. De aanroeper schrijft bij null gewoon géén `audio=` —
/// liever geen link dan een leugen (§3.2).
Future<String?> copyTranscriptAudioToMedia(
  String sourcePath,
  String documentDir,
) async {
  try {
    final src = File(sourcePath);
    if (!await src.exists()) return null;
    final size = await src.length();
    if (size <= 0 || size > maxTranscriptAudioBytes) {
      return null;
    }
    final mediaDir = Directory(p.join(documentDir, 'media'));
    if (!await mediaDir.exists()) {
      await mediaDir.create(recursive: true);
    }
    final dest = await resolveAssetDestination(
      mediaDir,
      p.basename(sourcePath),
      src,
    );
    if (dest == null) return null;
    if (!dest.alreadyPresent) {
      // Stream, niet readAsBytes: een uur audio moet niet tweemaal in
      // het geheugen staan.
      final out = dest.file.openWrite();
      try {
        await src.openRead().pipe(out);
      } finally {
        await out.close();
      }
    }
    return 'media/${p.basename(dest.file.path)}';
  } on Object catch (e) {
    logWarning('copyTranscriptAudioToMedia: kopie mislukt', e);
    return null;
  }
}
