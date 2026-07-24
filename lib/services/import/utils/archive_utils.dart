/// Zip archive helpers with hardening against zip-bom and oversized payloads.
library;

import 'package:archive/archive.dart';

/// Maximum presentation file size we are willing to read into memory.
const maxArchiveInputSize = 2 * 1024 * 1024 * 1024; // 2 GiB

/// Maximum total uncompressed size of all entries in a zip.
const maxArchiveUncompressedTotal = 4 * 1024 * 1024 * 1024; // 4 GiB

/// Maximum uncompressed size of a single zip entry.
const maxArchiveUncompressedFile = 2 * 1024 * 1024 * 1024; // 2 GiB

/// Decode a zip buffer after checking for oversized input and zip-bom
/// declarations.
///
/// The [ArchiveFile.size] values come from the central directory, so the check
/// happens before any entry is decompressed. This prevents a small compressed
/// file that claims a huge uncompressed size from causing an out-of-memory
/// crash.
///
/// De drie grenzen zijn parameters met de constanten als standaard. Niet omdat
/// een aanroeper ze wil verzetten — dat doet niemand — maar omdat de
/// zip-bom-beveiliging anders onbeproefbaar is: een echte 2 GiB-invoer maken om
/// één `if` te raken kan geen test. Met een kleine grens is elk pad in twee
/// regels te toetsen.
Archive safeDecodeZip(
  List<int> bytes, {
  int maxInput = maxArchiveInputSize,
  int maxFile = maxArchiveUncompressedFile,
  int maxTotal = maxArchiveUncompressedTotal,
}) {
  if (bytes.length > maxInput) {
    throw FormatException(
      'ZIP input is ${bytes.length} bytes, which exceeds the '
      '$maxInput byte limit.',
    );
  }
  // De local-file-header-magie, vóór het decoderen. Dit hoort hier en niet in
  // elke importer, want `archive` 4.x geeft op rommel géén fout meer maar een
  // *leeg* archief — waar 3.x nog gooide. Zonder deze controle leest een
  // beschadigd bestand als een presentatie zonder dia's, en kreeg de gebruiker
  // "geen dia's gevonden" te zien terwijl het bestand kapot was. Eén plek,
  // alle drie de formaten.
  if (bytes.length < 4 ||
      bytes[0] != 0x50 ||
      bytes[1] != 0x4B ||
      bytes[2] != 0x03 ||
      bytes[3] != 0x04) {
    throw const FormatException(
      'Not a ZIP archive: the local file header magic (PK\u0003\u0004) is '
      'missing, so the file is not a readable pptx/odp/key.',
    );
  }
  final archive = ZipDecoder().decodeBytes(bytes);
  var total = 0;
  for (final file in archive) {
    if (file.size > maxFile) {
      throw FormatException(
        'ZIP entry ${file.name} declares an uncompressed size of '
        '${file.size} bytes, which exceeds the $maxFile byte limit.',
      );
    }
    total += file.size;
    if (total > maxTotal) {
      throw FormatException(
        'ZIP total uncompressed size exceeds the $maxTotal byte limit.',
      );
    }
  }
  return archive;
}
