/// Detecteer of een ZIP (`.ocideck`-pakket) versleuteld is, zónder het
/// wachtwoord te kennen.
///
/// De `archive`-library exposet de encryptie-status niet publiek op
/// `ArchiveFile`, en `ZipDecoder().decodeBytes()` gooit of levert lege inhoud op
/// een versleuteld archief zonder wachtwoord. Daarom lezen we de ZIP-header zelf:
/// het *general purpose bit flag*-veld (bit 0) markeert of een lid versleuteld
/// is — dat geldt voor zowel klassieke ZipCrypto als WinZip-AES.
///
/// OciDeck versleutelt een pakket altijd als geheel (álle leden of geen enkel),
/// dus het eerste lokale bestandshoofd bij offset 0 is representatief. Voor de
/// zekerheid lopen we ook de central directory na als die goedkoop te vinden is.
library;

import 'dart:typed_data';

/// Little-endian handtekening van een lokaal ZIP-bestandshoofd (`PK\x03\x04`).
const int _localFileHeaderSig = 0x04034b50;

/// Little-endian handtekening van een central-directory-hoofd (`PK\x01\x02`).
const int _centralDirHeaderSig = 0x02014b50;

/// Little-endian handtekening van de End Of Central Directory (`PK\x05\x06`).
const int _eocdSig = 0x06054b50;

/// Het enige pakketprofiel dat OciServe voor tijdelijke lessen mag leveren.
///
/// Gewone, door auteurs uitgewisselde pakketten blijven AE-1 gebruiken. Deze
/// naam is een netwerkprotocolversie: een onbekende waarde wordt niet geraden.
const String ociServeAesPackageProfile = 'ocideck-winzip-aes256-ae2-v1';

const int _aesExtraFieldId = 0x9901;
const int _aesCompressionMethod = 99;
const int _aesVendorVersionAe2 = 2;
const int _aesStrength256 = 3;
const int _utf8FlagBit = 0x0800;
const int _dataDescriptorFlagBit = 0x0008;

/// Bit 0 van de *general purpose bit flag*: het lid is versleuteld.
const int _encryptedFlagBit = 0x0001;

/// True als [bytes] een ZIP is waarvan (minstens) het eerste lid versleuteld is.
///
/// Onbekende/niet-ZIP-inhoud levert `false` op: de gewone decode-fout-afhandeling
/// verderop verzorgt dan de melding. Puur byte-inspectie — geen `RegExp`, geen
/// decompressie.
bool isEncryptedZip(List<int> bytes) {
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  // Snelle en gebruikelijke weg: het eerste lokale bestandshoofd staat bij
  // offset 0. Flag-veld staat 6 bytes na de handtekening (2 bytes, LE).
  if (data.length >= 8 && _readUint32LE(data, 0) == _localFileHeaderSig) {
    final flags = _readUint16LE(data, 6);
    if (flags & _encryptedFlagBit != 0) return true;
  }
  // Robuuste terugval: loop de central directory na (die bevat per lid dezelfde
  // flag op offset +8). Nodig als het eerste lokale hoofd niet op offset 0 stond.
  return _centralDirectoryHasEncryptedEntry(data);
}

/// Controleert het complete OciServe-ZIP-profiel zonder iets te ontcijferen.
///
/// Elk lid moet in zowel de lokale als centrale header WinZip AES-256 AE-2
/// verklaren. Een gemengd archief, ZipCrypto, een afgezwakte sleutel of
/// strijdige headers faalt. Dit staat bewust vóór `ZipDecoder`: een decoder die
/// een onbekende variant toevallig accepteert mag het servercontract niet
/// verruimen.
bool hasExactOciServeAesPackageProfile(
  List<int> bytes, {
  required String profile,
}) {
  if (profile != ociServeAesPackageProfile) return false;
  final data = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final eocd = _findEocd(data);
  if (eocd < 0 || eocd + 22 > data.length) return false;
  if (_readUint16LE(data, eocd + 4) != 0 ||
      _readUint16LE(data, eocd + 6) != 0 ||
      eocd + 22 + _readUint16LE(data, eocd + 20) != data.length) {
    return false;
  }
  final diskEntryCount = _readUint16LE(data, eocd + 8);
  final entryCount = _readUint16LE(data, eocd + 10);
  final centralSize = _readUint32LE(data, eocd + 12);
  final centralOffset = _readUint32LE(data, eocd + 16);
  if (entryCount == 0 ||
      diskEntryCount != entryCount ||
      entryCount == 0xffff ||
      centralSize == 0xffffffff ||
      centralOffset == 0xffffffff ||
      centralOffset + centralSize != eocd ||
      centralOffset < 0 ||
      centralOffset > data.length) {
    return false;
  }

  var offset = centralOffset;
  for (var index = 0; index < entryCount; index++) {
    if (offset + 46 > eocd ||
        _readUint32LE(data, offset) != _centralDirHeaderSig) {
      return false;
    }
    final flags = _readUint16LE(data, offset + 8);
    final method = _readUint16LE(data, offset + 10);
    final crc32 = _readUint32LE(data, offset + 16);
    final compressedSize = _readUint32LE(data, offset + 20);
    final uncompressedSize = _readUint32LE(data, offset + 24);
    final nameLength = _readUint16LE(data, offset + 28);
    final extraLength = _readUint16LE(data, offset + 30);
    final commentLength = _readUint16LE(data, offset + 32);
    final localOffset = _readUint32LE(data, offset + 42);
    final end = offset + 46 + nameLength + extraLength + commentLength;
    if (!_hasAllowedAesFlags(flags) ||
        method != _aesCompressionMethod ||
        crc32 != 0 ||
        end > eocd) {
      return false;
    }
    final centralExtra = _readExactAesExtra(
      data,
      offset + 46 + nameLength,
      extraLength,
    );
    if (centralExtra == null ||
        !_matchingLocalAesHeader(
          data,
          localOffset: localOffset,
          centralNameOffset: offset + 46,
          nameLength: nameLength,
          flags: flags,
          compressedSize: compressedSize,
          uncompressedSize: uncompressedSize,
          centralExtra: centralExtra,
          centralDirectoryOffset: centralOffset,
        )) {
      return false;
    }
    offset = end;
  }
  return offset == eocd;
}

bool _hasAllowedAesFlags(int flags) {
  if (flags & _encryptedFlagBit == 0) return false;
  // Alleen encryptie, data-descriptor en UTF-8 hebben betekenis in dit
  // profiel. Onbekende vlaggen worden niet stil naar de decoder doorgeschoven.
  const allowed = _encryptedFlagBit | _dataDescriptorFlagBit | _utf8FlagBit;
  return flags & ~allowed == 0;
}

({int actualMethod})? _readExactAesExtra(
  Uint8List data,
  int start,
  int length,
) {
  final end = start + length;
  if (start < 0 || end > data.length) return null;
  ({int actualMethod})? aes;
  var offset = start;
  while (offset + 4 <= end) {
    final id = _readUint16LE(data, offset);
    final size = _readUint16LE(data, offset + 2);
    offset += 4;
    if (offset + size > end) return null;
    if (id == _aesExtraFieldId) {
      if (aes != null || size != 7) return null;
      final vendorVersion = _readUint16LE(data, offset);
      final vendorA = data[offset + 2];
      final vendorE = data[offset + 3];
      final strength = data[offset + 4];
      final actualMethod = _readUint16LE(data, offset + 5);
      if (vendorVersion != _aesVendorVersionAe2 ||
          vendorA != 0x41 ||
          vendorE != 0x45 ||
          strength != _aesStrength256 ||
          (actualMethod != 0 && actualMethod != 8)) {
        return null;
      }
      aes = (actualMethod: actualMethod);
    }
    offset += size;
  }
  return offset == end ? aes : null;
}

bool _matchingLocalAesHeader(
  Uint8List data, {
  required int localOffset,
  required int centralNameOffset,
  required int nameLength,
  required int flags,
  required int compressedSize,
  required int uncompressedSize,
  required ({int actualMethod}) centralExtra,
  required int centralDirectoryOffset,
}) {
  if (localOffset < 0 ||
      localOffset + 30 > centralDirectoryOffset ||
      _readUint32LE(data, localOffset) != _localFileHeaderSig ||
      _readUint16LE(data, localOffset + 6) != flags ||
      _readUint16LE(data, localOffset + 8) != _aesCompressionMethod ||
      _readUint32LE(data, localOffset + 14) != 0) {
    return false;
  }
  final localNameLength = _readUint16LE(data, localOffset + 26);
  final localExtraLength = _readUint16LE(data, localOffset + 28);
  final localCompressedSize = _readUint32LE(data, localOffset + 18);
  final localUncompressedSize = _readUint32LE(data, localOffset + 22);
  final dataOffset = localOffset + 30 + localNameLength + localExtraLength;
  if (localNameLength != nameLength ||
      !_matchingLocalSize(flags, localCompressedSize, compressedSize) ||
      !_matchingLocalSize(flags, localUncompressedSize, uncompressedSize) ||
      dataOffset > centralDirectoryOffset ||
      compressedSize > centralDirectoryOffset - dataOffset) {
    return false;
  }
  for (var i = 0; i < nameLength; i++) {
    if (data[localOffset + 30 + i] != data[centralNameOffset + i]) return false;
  }
  final localExtra = _readExactAesExtra(
    data,
    localOffset + 30 + localNameLength,
    localExtraLength,
  );
  return localExtra != null &&
      localExtra.actualMethod == centralExtra.actualMethod;
}

bool _matchingLocalSize(int flags, int local, int central) =>
    flags & _dataDescriptorFlagBit == 0
    ? local == central
    : local == 0 || local == central;

/// Zoek de central directory via de EOCD en test de flag van elk lid.
bool _centralDirectoryHasEncryptedEntry(Uint8List data) {
  final eocd = _findEocd(data);
  if (eocd < 0) return false;
  // EOCD: central-directory-offset staat op +16 (4 bytes, LE).
  if (eocd + 20 > data.length) return false;
  var offset = _readUint32LE(data, eocd + 16);
  while (offset + 46 <= data.length &&
      _readUint32LE(data, offset) == _centralDirHeaderSig) {
    final flags = _readUint16LE(data, offset + 8);
    if (flags & _encryptedFlagBit != 0) return true;
    final nameLen = _readUint16LE(data, offset + 28);
    final extraLen = _readUint16LE(data, offset + 30);
    final commentLen = _readUint16LE(data, offset + 32);
    offset += 46 + nameLen + extraLen + commentLen;
  }
  return false;
}

/// Vind de offset van de EOCD-handtekening door van achteren te zoeken (het
/// EOCD-blok ligt aan het einde, met een optioneel commentaar van ≤64 KiB).
int _findEocd(Uint8List data) {
  if (data.length < 22) return -1;
  final earliest = data.length - 22 - 0xffff;
  final start = earliest < 0 ? 0 : earliest;
  for (var i = data.length - 22; i >= start; i--) {
    if (_readUint32LE(data, i) == _eocdSig) return i;
  }
  return -1;
}

int _readUint16LE(Uint8List d, int o) => d[o] | (d[o + 1] << 8);

int _readUint32LE(Uint8List d, int o) =>
    d[o] | (d[o + 1] << 8) | (d[o + 2] << 16) | (d[o + 3] << 24);
