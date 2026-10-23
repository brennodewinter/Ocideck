// Herkenning van mediabestanden voor de bestandstranscriptie (#2515).
//
// Puur bytes in, feiten uit — geen dart:io, geen netwerk. De detectie
// kijkt naar de magische bytes van de container (de bestandsnaam liegt
// even makkelijk als hij klopt) en de extensie is alleen een zwakke
// reserve voor containers zonder herkenbare kop.
//
// Twee dingen beslist dit bestand voor de flow:
//  * wat de container is, zodat de dialoog "MP4 met audio" eerlijk kan
//    noemen in plaats van "een bestand";
//  * voor PCM-WAV meteen de duur en of de engine hem direct leest — de
//    enige container die géén decoder nodig heeft (§5.1 noot 1).
import 'dart:typed_data';

/// De herkende container van een mediabestand.
enum MediaContainer {
  /// RIFF/WAVE — met PCM-data de basiscarrier die elke route leest.
  wav,

  /// ISO-BMFF (`ftyp`): `.mp4`, `.m4a`, `.mov` — audio óf video; of er een
  /// audiotrack in zit bewijst alleen de decoder.
  mpeg4,

  /// OggS — `.ogg`/`.opus`/`.oga`.
  ogg,

  /// `fLaC` — ongecomprimeerd-hijzig maar verliesloos, eigen codec.
  flac,

  /// MPEG audio (`ID3` of sync-frame) — `.mp3` e.d.
  mp3,

  /// EBML — `.webm`/`.mkv`; audio óf video.
  ebml,

  /// RIFF/AVI — oudere videocontainer.
  avi,

  /// Niets herkend: de extensie mag een poging rechtvaardigen, de
  /// decoderuitslag is dan de waarheid.
  unknown,
}

/// Wat de kop van een WAV zegt — genoeg voor duur en "is dit echt PCM".
class WavInfo {
  const WavInfo({
    required this.duration,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
  });

  final Duration duration;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;
}

/// Zoveel kopbytes als de sniffer leest. WAV-headers met een `data`-chunk
/// die niet direct volgt (LIST/metadata ertussen) vragen zelden meer.
const sniffHeadBytes = 256;

bool _eq(Uint8List head, int off, List<int> magic) {
  if (head.length < off + magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (head[off + i] != magic[i]) return false;
  }
  return true;
}

/// Herkent de container op magische bytes. [extension] (met of zonder
/// punt) deunt alleen mee als de kop niets zegt — bij tegenstrijdigheid
/// wint de inhoud.
MediaContainer sniffContainer(Uint8List head, {String? extension}) {
  if (_eq(head, 0, [0x52, 0x49, 0x46, 0x46])) {
    // 'RIFF' — de vier bytes op 8 bepalen welke RIFF-variant.
    if (_eq(head, 8, [0x57, 0x41, 0x56, 0x45])) return MediaContainer.wav;
    if (_eq(head, 8, [0x41, 0x56, 0x49, 0x20])) return MediaContainer.avi;
    return MediaContainer.unknown;
  }
  // ISO-BMFF: 'ftyp' op offset 4.
  if (_eq(head, 4, [0x66, 0x74, 0x79, 0x70])) return MediaContainer.mpeg4;
  if (_eq(head, 0, [0x4F, 0x67, 0x67, 0x53])) return MediaContainer.ogg;
  if (_eq(head, 0, [0x66, 0x4C, 0x61, 0x43])) return MediaContainer.flac;
  // EBML-magic dekt webm én matroska.
  if (_eq(head, 0, [0x1A, 0x45, 0xDF, 0xA3])) return MediaContainer.ebml;
  // MP3: ID3v2-tag, of een MPEG-audioframe-sync aan het begin.
  if (_eq(head, 0, [0x49, 0x44, 0x33])) return MediaContainer.mp3;
  if (head.length >= 2 &&
      head[0] == 0xFF &&
      head[1] & 0xE0 == 0xE0 &&
      head[1] & 0x18 != 0x08) {
    return MediaContainer.mp3;
  }
  // Geen magic — de extensie is de zwakke reserve: ze rechtvaardigt een
  // decodepoging maar bewijst niets.
  final ext = (extension ?? '').toLowerCase().replaceFirst('.', '');
  return switch (ext) {
    'wav' || 'wave' => MediaContainer.wav,
    'mp3' => MediaContainer.mp3,
    'flac' => MediaContainer.flac,
    'ogg' || 'oga' || 'opus' => MediaContainer.ogg,
    'm4a' || 'aac' || 'mp4' || 'mov' || 'm4v' || '3gp' => MediaContainer.mpeg4,
    'webm' || 'mkv' || 'mk3d' => MediaContainer.ebml,
    'avi' => MediaContainer.avi,
    _ => MediaContainer.unknown,
  };
}

/// Of deze container een video kan zijn — alleen dan is "geen
/// audiotrack" een zinnige uitslag om expliciet te melden.
bool mayBeVideo(MediaContainer container) => switch (container) {
  MediaContainer.mpeg4 || MediaContainer.ebml || MediaContainer.avi => true,
  _ => false,
};

/// Schrijft 16 kHz mono 16-bit-PCM als WAV — het duurzame bestand dat de
/// web-decode (`decodeAudioData` → Float32) achterlaat. Puur, zodat de
/// VM-test hem rond kan rijden.
Uint8List encodePcmWav(Float32List pcm, {int sampleRate = 16000}) {
  final dataBytes = pcm.length * 2;
  final out = Uint8List(44 + dataBytes);
  final view = ByteData.view(out.buffer);
  void str(int off, String s) {
    for (var i = 0; i < s.length; i++) {
      out[off + i] = s.codeUnitAt(i);
    }
  }

  str(0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, Endian.little);
  str(8, 'WAVE');
  str(12, 'fmt ');
  view.setUint32(16, 16, Endian.little);
  view.setUint16(20, 1, Endian.little); // PCM
  view.setUint16(22, 1, Endian.little); // mono
  view.setUint32(24, sampleRate, Endian.little);
  view.setUint32(28, sampleRate * 2, Endian.little);
  view.setUint16(32, 2, Endian.little);
  view.setUint16(34, 16, Endian.little);
  str(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  for (var i = 0; i < pcm.length; i++) {
    final s = pcm[i].clamp(-1.0, 1.0);
    view.setInt16(44 + i * 2, (s * 32767).round(), Endian.little);
  }
  return out;
}

/// Leest een WAV-header: RIFF-kop, `fmt `-chunk, `data`-chunk. Levert
/// null bij een kapotte of vreemde kop — de caller meldt dat als
/// ondecodeerbaar, niet als "duur onbekend".
///
/// [fileSize] is de echte lengte van waar de kop uit komt: de `data`-
/// chunk kan groter claimen dan de meegelezen bytes (we lazen alleen de
/// kop), dus de duur rekent op `fileSize`, niet op `head.length`.
WavInfo? parseWavHeader(Uint8List head, int fileSize) {
  if (head.length < 44) return null;
  if (!_eq(head, 0, [0x52, 0x49, 0x46, 0x46]) ||
      !_eq(head, 8, [0x57, 0x41, 0x56, 0x45])) {
    return null;
  }
  int u16(int off) => head[off] | (head[off + 1] << 8);
  int u32(int off) =>
      head[off] |
      (head[off + 1] << 8) |
      (head[off + 2] << 16) |
      (head[off + 3] << 24);

  var off = 12;
  int? channels;
  int? sampleRate;
  int? bitsPerSample;
  int? byteRate;
  int? dataSize;
  // Chunks lopen achter elkaar; `fmt` en `data` zijn de twee die tellen.
  // Alles vreemds ertussen (LIST, fact, cue) wordt overgeslagen op zijn
  // eigen lengteveld.
  while (off + 8 <= head.length) {
    final id = u32(off);
    final size = u32(off + 4);
    if (id == 0x20746D66 /* 'fmt ', little-endian gelezen */ &&
        off + 16 <= head.length) {
      channels = u16(off + 10);
      sampleRate = u32(off + 12);
      byteRate = u32(off + 16);
      bitsPerSample = u16(off + 22);
    } else if (id == 0x61746164 /* 'data ', little-endian gelezen */ ) {
      // De chunk kan meer claimen dan er werkelijk in het bestand staat;
      // de kleinste van beide is de waarheid.
      dataSize = size > 0 && off + 8 + size > fileSize
          ? fileSize - off - 8
          : size;
      break;
    }
    // Chunk-lengtes zijn even-afgerond (pad-byte).
    final next = off + 8 + size + (size & 1);
    if (next <= off) return null; // corrupte lengte — niet doorpogen
    off = next;
  }
  if (sampleRate == null ||
      sampleRate <= 0 ||
      byteRate == null ||
      byteRate <= 0 ||
      dataSize == null ||
      dataSize < 0) {
    return null;
  }
  final micros = ((dataSize / byteRate) * 1000000).round();
  return WavInfo(
    duration: Duration(microseconds: micros),
    channels: channels ?? 0,
    sampleRate: sampleRate,
    bitsPerSample: bitsPerSample ?? 0,
  );
}
