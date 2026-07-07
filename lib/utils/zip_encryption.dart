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
