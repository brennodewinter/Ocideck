/// Zip archive helpers with hardening against zip-bom and oversized payloads.
library;

import 'package:archive/archive.dart';

import 'import_budget.dart';

/// Decode a zip buffer within the [budget]: input size, entry count, per-entry
/// uncompressed size and total uncompressed size.
///
/// The [ArchiveFile.size] values come from the central directory, so the size
/// checks happen before any entry is decompressed. This prevents a small
/// compressed file that claims a huge uncompressed size from causing an
/// out-of-memory crash. The entry-count check bounds the decode loop itself: an
/// archive with a million tiny entries is as harmful as one huge entry.
///
/// Elke overschrijding gooit een [ImportBudgetException] met een leesbare
/// grensbeschrijving; de importer vertaalt die naar een
/// `ImportFailureReason.tooLarge`-melding. Een niet-zip of beschadigd archief
/// gooit nog steeds een gewone [FormatException] — dat is een ander soort fout
/// (kapot, niet te-groot) en de gebruiker verdient het onderscheid.
///
/// Het budget is een parameter met [ImportBudget.standard] als standaard. Niet
/// omdat een aanroeper hem in productie wil verzetten — dat doet niemand — maar
/// omdat de zip-bom-beveiliging anders onbeproefbaar is: een echte 2 GiB-invoer
/// maken om één `if` te raken kan geen test. Met [ImportBudget.forTest] is elk
/// pad in twee regels te toetsen.
Archive safeDecodeZip(
  List<int> bytes, {
  ImportBudget budget = ImportBudget.standard,
}) {
  if (bytes.length > budget.maxSourceBytes) {
    throw ImportBudgetException(humanBytes(budget.maxSourceBytes));
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
  if (archive.length > budget.maxArchiveEntries) {
    throw ImportBudgetException('${budget.maxArchiveEntries} onderdelen');
  }
  var total = 0;
  for (final file in archive) {
    if (file.size > budget.maxUncompressedEntry) {
      throw ImportBudgetException(
        '${humanBytes(budget.maxUncompressedEntry)} per onderdeel',
      );
    }
    total += file.size;
    if (total > budget.maxUncompressedTotal) {
      throw ImportBudgetException(
        '${humanBytes(budget.maxUncompressedTotal)} uitgepakt',
      );
    }
  }
  return archive;
}

/// A byte count as a short human string for the grens-beschrijving: MiB for the
/// production budget (whole MiB throughout), KiB or bytes for the tiny values a
/// test uses. Rounds down.
String humanBytes(int bytes) {
  const mib = 1024 * 1024;
  const kib = 1024;
  if (bytes >= mib) return '${bytes ~/ mib} MiB';
  if (bytes >= kib) return '${bytes ~/ kib} KiB';
  return '$bytes bytes';
}
