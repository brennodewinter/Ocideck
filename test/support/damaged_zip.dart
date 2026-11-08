import 'dart:typed_data';

import 'package:archive/archive.dart';

/// Beschadigde zips voor de strikte lezers: de centrale map is intact, alleen
/// één lid klopt niet. Precies het geval waarover archive 4.6 zonder
/// `verify`/`throwOnError` zwijgt — een afgekapt of omgevallen archief geeft
/// dan halve of verkeerde bytes terug in plaats van een fout.

/// Een zip van [members], allemaal *opgeslagen*: hun inhoud staat letterlijk in
/// het bestand, zodat [flipByteIn] hem kan raken.
Uint8List storedZip(Map<String, List<int>> members) {
  final archive = Archive();
  members.forEach((name, bytes) {
    archive.add(
      ArchiveFile.bytes(name, bytes)..compression = CompressionType.none,
    );
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Draait één byte om midden in het eerste voorkomen van [needle] in [zip].
/// Grootte en map blijven kloppen; alleen de CRC-32 van dat lid niet meer.
Uint8List flipByteIn(Uint8List zip, List<int> needle) {
  final damaged = Uint8List.fromList(zip);
  damaged[_indexOf(zip, needle) + needle.length ~/ 2] ^= 0xFF;
  return damaged;
}

/// Een zip van [members] (gedeflate) waarvan de gecomprimeerde stroom van lid
/// [name] halverwege ophoudt: lokale kop én centrale map noemen de ingekorte
/// lengte, dus alleen het lid zelf is afgekapt, niet het archief.
Uint8List zipWithCutEntry(Map<String, List<int>> members, String name) {
  final archive = Archive();
  members.forEach((n, bytes) => archive.add(ArchiveFile.bytes(n, bytes)));
  final zip = Uint8List.fromList(ZipEncoder().encode(archive));
  final view = ByteData.sublistView(zip);
  void halve(int at) =>
      view.setUint32(at, view.getUint32(at, Endian.little) ~/ 2, Endian.little);
  final nameBytes = name.codeUnits;
  for (var i = 0; i + 46 <= zip.length; i++) {
    final signature = view.getUint32(i, Endian.little);
    if (signature == 0x04034b50 &&
        _nameAt(
          zip,
          i + 30,
          view.getUint16(i + 26, Endian.little),
          nameBytes,
        )) {
      halve(i + 18);
    } else if (signature == 0x02014b50 &&
        _nameAt(
          zip,
          i + 46,
          view.getUint16(i + 28, Endian.little),
          nameBytes,
        )) {
      halve(i + 20);
    }
  }
  return zip;
}

/// Inhoud die deflate nauwelijks kleiner krijgt en die maar één keer in een zip
/// voorkomt: een afgekapte stroom mist dan echt zijn slot, en [flipByteIn]
/// raakt het bedoelde lid.
List<int> incompressible(int length, {int seed = 1}) => [
  for (var i = 0, x = seed; i < length; i++)
    (x = (x * 1103515245 + 12345) & 0x7fffffff) >> 16 & 0xff,
];

bool _nameAt(Uint8List zip, int at, int length, List<int> name) {
  if (length != name.length || at + length > zip.length) return false;
  for (var i = 0; i < length; i++) {
    if (zip[at + i] != name[i]) return false;
  }
  return true;
}

int _indexOf(Uint8List haystack, List<int> needle) {
  outer:
  for (var i = 0; i + needle.length <= haystack.length; i++) {
    for (var j = 0; j < needle.length; j++) {
      if (haystack[i + j] != needle[j]) continue outer;
    }
    return i;
  }
  throw StateError('inhoud niet letterlijk in de zip gevonden');
}
