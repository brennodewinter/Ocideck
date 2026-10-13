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
  final declaredEntries = readZipEntryCount(
    bytes,
    stopAfter: budget.maxArchiveEntries + 1,
  );
  if (declaredEntries == null) {
    throw const FormatException(
      'Not a readable ZIP archive: central directory is missing or malformed.',
    );
  }
  if (declaredEntries > budget.maxArchiveEntries) {
    throw ImportBudgetException('${budget.maxArchiveEntries} onderdelen');
  }
  if (zipContainsSymlinkMetadata(bytes)) {
    throw const FormatException(
      'ZIP archive contains symbolic-link metadata and cannot be imported.',
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

/// True when the central directory marks an entry as a Unix symbolic link.
///
/// `ZipDecoder` reads the link target while decoding the central directory,
/// before callers can apply their output budget. Rejecting this metadata here
/// keeps an attacker-controlled link target from bypassing that budget.
bool zipContainsSymlinkMetadata(List<int> bytes) {
  const eocdSignature = 0x06054b50;
  const centralSignature = 0x02014b50;
  const zip64LocatorSignature = 0x07064b50;
  const zip64EndSignature = 0x06064b50;
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (!_rangeWithin(i, 22, bytes.length) || _u32(bytes, i) != eocdSignature) {
      continue;
    }
    final commentLength = _u16(bytes, i + 20);
    if (i + 22 + commentLength > bytes.length) continue;
    int centralSize;
    int centralOffset;
    final centralSize16 = _u32(bytes, i + 12);
    final centralOffset16 = _u32(bytes, i + 16);
    if (centralSize16 != 0xFFFFFFFF && centralOffset16 != 0xFFFFFFFF) {
      centralSize = centralSize16;
      centralOffset = centralOffset16;
    } else {
      final locator = i - 20;
      if (!_rangeWithin(locator, 20, bytes.length) ||
          _u32(bytes, locator) != zip64LocatorSignature) {
        continue;
      }
      final zip64Offset = _u64(bytes, locator + 8);
      if (!_rangeWithin(zip64Offset, 56, bytes.length) ||
          _u32(bytes, zip64Offset.toInt()) != zip64EndSignature) {
        continue;
      }
      final zip64 = zip64Offset.toInt();
      centralSize = _u64(bytes, zip64 + 40).toInt();
      centralOffset = _u64(bytes, zip64 + 48).toInt();
    }
    if (!_rangeWithin(centralOffset, centralSize, i)) continue;
    final end = centralOffset + centralSize;
    var position = centralOffset;
    while (position < end) {
      if (!_rangeWithin(position, 46, end) ||
          _u32(bytes, position) != centralSignature) {
        break;
      }
      final headerLength =
          46 +
          _u16(bytes, position + 28) +
          _u16(bytes, position + 30) +
          _u16(bytes, position + 32);
      if (!_rangeWithin(position, headerLength, end)) break;
      final creatorSystem = bytes[position + 5];
      final externalAttributes = _u32(bytes, position + 38);
      if (creatorSystem == 3 &&
          ((externalAttributes >> 16) & 0xF000) == 0xA000) {
        return true;
      }
      position += headerLength;
    }
    return false;
  }
  return false;
}

/// Count the central-directory records without decoding the archive. A null
/// result means the archive has no parseable EOCD or central directory;
/// [ZipDecoder] remains responsible for reporting that malformed input.
int? readZipEntryCount(List<int> bytes, {int? stopAfter}) {
  const eocdSignature = 0x06054b50;
  const zip64LocatorSignature = 0x07064b50;
  const zip64EndSignature = 0x06064b50;
  for (var i = bytes.length - 22; i >= 0; i--) {
    if (!_rangeWithin(i, 22, bytes.length) || _u32(bytes, i) != eocdSignature) {
      continue;
    }
    final commentLength = _u16(bytes, i + 20);
    if (i + 22 + commentLength > bytes.length) continue;
    final centralSize16 = _u32(bytes, i + 12);
    final centralOffset16 = _u32(bytes, i + 16);
    if (centralSize16 != 0xFFFFFFFF &&
        centralOffset16 != 0xFFFFFFFF &&
        _rangeWithin(centralOffset16, centralSize16, i)) {
      return _countCentralDirectoryEntries(
        bytes,
        centralOffset16,
        centralSize16,
        stopAfter: stopAfter,
      );
    }

    final locator = i - 20;
    if (!_rangeWithin(locator, 20, bytes.length) ||
        _u32(bytes, locator) != zip64LocatorSignature) {
      return null;
    }
    final zip64Offset = _u64(bytes, locator + 8);
    if (!_rangeWithin(zip64Offset, 56, bytes.length)) return null;
    final zip64 = zip64Offset.toInt();
    if (_u32(bytes, zip64) != zip64EndSignature) return null;
    final centralSize = _u64(bytes, zip64 + 40);
    final centralOffset = _u64(bytes, zip64 + 48);
    if (!_rangeWithin(centralOffset, centralSize, zip64Offset)) return null;
    return _countCentralDirectoryEntries(
      bytes,
      centralOffset,
      centralSize,
      stopAfter: stopAfter,
    );
  }
  return null;
}

int? _countCentralDirectoryEntries(
  List<int> bytes,
  int offset,
  int size, {
  int? stopAfter,
}) {
  if (!_rangeWithin(offset, size, bytes.length)) return null;
  final end = offset + size;
  var count = 0;
  var position = offset;
  while (position < end) {
    if (!_rangeWithin(position, 46, end) ||
        _u32(bytes, position) != 0x02014b50) {
      return null;
    }
    final nameLength = _u16(bytes, position + 28);
    final extraLength = _u16(bytes, position + 30);
    final commentLength = _u16(bytes, position + 32);
    final headerLength = 46 + nameLength + extraLength + commentLength;
    if (!_rangeWithin(position, headerLength, end)) return null;
    count++;
    if (stopAfter != null && count >= stopAfter) return count;
    position += headerLength;
  }
  return count;
}

bool _rangeWithin(int offset, int size, int limit) =>
    offset >= 0 && size >= 0 && offset <= limit && size <= limit - offset;

int _u16(List<int> bytes, int offset) =>
    bytes[offset] | (bytes[offset + 1] << 8);

int _u32(List<int> bytes, int offset) =>
    _u16(bytes, offset) | (_u16(bytes, offset + 2) << 16);

int _u64(List<int> bytes, int offset) {
  var value = 0;
  for (var i = 0; i < 8; i++) {
    value |= bytes[offset + i] << (i * 8);
  }
  return value;
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
