// Begrensde RIFF-chunklezer voor echte bestanden (#2933): de kop van
// twaalf bytes, dan per chunk een header van acht — vreemde chunks
// (FLLR, LIST, metadata) worden via hun lengteveld overgeslagen tot
// `fmt ` en `data` gevonden zijn.
//
// Waarom dit naast `parseWavHeader` bestaat: afconvert schrijft een
// FLLR-vulling van enkele kB vóór `data`, en de sniffkop van 256 bytes
// is daar te kort voor — de bufferparser ziet "geen data" en meldt een
// onleesbare header op een prima WAV. Deze lezer seekt in plaats van te
// lezen: onbeperkt de hele WAV in het geheugen trekken is geen optie,
// maar een chunklengte overslaan kost niets.
import 'dart:io';
import 'dart:typed_data';

import 'media_sniff.dart';

/// Zoveel niet-audio bytes vóór `data` de scanner hooguit doorloopt.
/// De afconvert-vulling is ~4 kB; embedded metadata kan groter zijn —
/// 64 MiB is royaal maar begrensd, daarna is "onleesbare header" de
/// eerlijke uitslag.
const wavHeaderScanLimitBytes = 64 * 1024 * 1024;

/// `fmt ` is in de praktijk ≤ 40 bytes; een grotere claim is verdacht
/// en wordt niet meegelezen.
const _maxFmtChunkBytes = 4096;

/// Leest de WAV-feiten van een geopend bestand. Null betekent altijd
/// "header niet gevonden of ongeldig" — een geldige header met nul
/// audiobytes levert een [WavInfo] met `dataBytes == 0`, zodat de
/// caller "beschadigd" en "echt leeg" uit elkaar kan houden.
Future<WavInfo?> readWavInfo(RandomAccessFile ra, int fileSize) async {
  try {
    if (fileSize < 44) return null;
    await ra.setPosition(0);
    final head = Uint8List.fromList(await ra.read(12));
    if (sniffContainer(head) != MediaContainer.wav) return null;

    var off = 12;
    var scanned = 0;
    WavFmt? fmt;
    while (off + 8 <= fileSize && scanned <= wavHeaderScanLimitBytes) {
      await ra.setPosition(off);
      final hdr = Uint8List.fromList(await ra.read(8));
      if (hdr.length < 8) return null;
      final id = hdr[0] | (hdr[1] << 8) | (hdr[2] << 16) | (hdr[3] << 24);
      final size = hdr[4] | (hdr[5] << 8) | (hdr[6] << 16) | (hdr[7] << 24);
      if (id == 0x20746D66 /* 'fmt ' */ ) {
        if (size < 16 || size > _maxFmtChunkBytes) return null;
        if (off + 8 + size > fileSize) return null;
        final fmtBytes = Uint8List.fromList(await ra.read(size));
        if (fmtBytes.length < size) return null;
        fmt = parseWavFmt(fmtBytes);
        if (fmt == null) return null;
      } else if (id == 0x61746164 /* 'data' */ ) {
        if (fmt == null) return null;
        final avail = fileSize - off - 8;
        if (avail < 0) return null;
        return wavInfoFromFields(
          fmt,
          dataBytes: size <= avail ? size : avail,
          dataOffset: off + 8,
        );
      }
      final next = off + 8 + size + (size & 1);
      if (next <= off) return null; // corrupte lengte — niet doorpogen
      scanned += next - off;
      off = next;
    }
    return null;
  } on Object {
    // Een I/O-fout halverwege scannen is óók "onleesbaar", geen crash.
    return null;
  }
}
