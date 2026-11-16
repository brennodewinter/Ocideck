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
import 'dart:convert';
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

/// De velden van een `fmt `-chunk — de enige chunk die iets over de
/// audio zelf zegt.
class WavFmt {
  const WavFmt({
    required this.formatTag,
    required this.channels,
    required this.sampleRate,
    required this.byteRate,
    required this.bitsPerSample,
  });

  /// RIFF-formatcode: 1 is PCM. Float (3), extensible (0xFFFE) en
  /// gecomprimeerde varianten zijn géén PCM — de engine spreekt alleen
  /// PCM, de rest gaat via de decoder.
  final int formatTag;
  final int channels;
  final int sampleRate;
  final int byteRate;
  final int bitsPerSample;

  bool get isPcm => formatTag == 1;
}

/// Wat de kop van een WAV zegt — genoeg voor duur en "is dit echt PCM".
class WavInfo {
  const WavInfo({
    required this.duration,
    required this.channels,
    required this.sampleRate,
    required this.bitsPerSample,
    required this.formatTag,
    required this.dataOffset,
    required this.dataBytes,
  });

  final Duration duration;
  final int channels;
  final int sampleRate;
  final int bitsPerSample;

  /// De `fmt `-formatcode — [WavFmt.isPcm] zegt of de engine hem direct
  /// leest.
  final int formatTag;

  /// Byte-offset van de `data`-payload in het bestand.
  final int dataOffset;

  /// Werkelijke payloadgrootte: de kleinste van de chunkclaim en wat er
  /// nog in het bestand staat. Nul is een legitieme uitslag — een
  /// geldige header zonder audio, te onderscheiden van een kapotte kop
  /// (die null oplevert).
  final int dataBytes;
}

/// Zoveel kopbytes als de sniffer leest. WAV-headers met een `data`-chunk
/// die niet direct volgt (LIST/metadata ertussen) vragen zelden meer —
/// voor alles groters seekt `readWavInfo` er doorheen (#2933).
const sniffHeadBytes = 256;

/// Extensies die een audio- of videobestand kunnen dragen — de snelle
/// aanwijzing van de openroute (#2932). Dezelfde namen als de
/// extensietabel hieronder, plus de varianten die decoders aankunnen;
/// of er écht media in zit beslissen de magische bytes.
const mediaFileExtensions = {
  'wav',
  'wave',
  'mp3',
  'm4a',
  'aac',
  'flac',
  'ogg',
  'oga',
  'opus',
  'mp4',
  'm4v',
  'mov',
  '3gp',
  'webm',
  'mkv',
  'mk3d',
  'avi',
};

/// Wat de openroute met een bestand doet (#2932): media krijgt de
/// transcriptievoorbeschouwing, de rest loopt de bestaande
/// tekst-/pakket-/importroutes.
enum OpenTarget {
  /// Audio/video — de transcriptievoorbeschouwing is de openactie.
  media,

  /// Geen media aangetoond — de gewone openroutes bepalen verder.
  other,
}

/// De centrale classificatie van de openroute, vóór elke tekstlezing:
/// de magische bytes geven de doorslag (een `.mp3`-naam op MP4-inhoud,
/// maar óók media-magic onder een tekstnaam), de extensie is de reserve
/// voor containers zonder herkenbare kop — behalve als de kop gewoon
/// leesbare tekst blijkt.
OpenTarget classifyOpenTarget(Uint8List head, {String? extension}) {
  if (sniffContainer(head) != MediaContainer.unknown) {
    return OpenTarget.media;
  }
  final ext = (extension ?? '').toLowerCase().replaceFirst('.', '');
  if (!mediaFileExtensions.contains(ext)) return OpenTarget.other;
  return _looksLikeUtf8Text(head) ? OpenTarget.other : OpenTarget.media;
}

/// Mag dit de tekstroute in, ondanks een media-naam? Een `.mp3`-naam op
/// een tekstbestand mag geen decodefout opleveren — en andersom hoort
/// een medianaam op binaire inhoud níet de kans tekst te zijn.
bool _looksLikeUtf8Text(Uint8List head) {
  final end = head.length < 512 ? head.length : 512;
  if (end == 0) return false;
  // NUL-bytes zijn geen tekst meer.
  for (var i = 0; i < end; i++) {
    if (head[i] == 0) return false;
  }
  try {
    utf8.decode(head.sublist(0, end));
    return true;
  } on Object {
    return false;
  }
}

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

/// Leest de velden van een `fmt `-payload. Null bij een afgekapte chunk
/// of ongeldige kernwaarden — bounds worden gevalideerd vóór er een
/// veld wordt gelezen, dus nooit een RangeError op corruptie.
WavFmt? parseWavFmt(Uint8List fmt) {
  if (fmt.length < 16) return null;
  int u16(int off) => fmt[off] | (fmt[off + 1] << 8);
  int u32(int off) =>
      fmt[off] |
      (fmt[off + 1] << 8) |
      (fmt[off + 2] << 16) |
      (fmt[off + 3] << 24);
  final out = WavFmt(
    formatTag: u16(0),
    channels: u16(2),
    sampleRate: u32(4),
    byteRate: u32(8),
    bitsPerSample: u16(14),
  );
  if (out.channels <= 0 || out.sampleRate <= 0 || out.byteRate <= 0) {
    return null;
  }
  return out;
}

/// Bouwt de uitkomst op uit fmt-velden en de gevonden `data`-grootte.
/// [dataBytes] is al afgekapt op wat werkelijk in het bestand staat.
WavInfo wavInfoFromFields(
  WavFmt fmt, {
  required int dataBytes,
  required int dataOffset,
}) {
  final micros = ((dataBytes / fmt.byteRate) * 1000000).round();
  return WavInfo(
    duration: Duration(microseconds: micros < 0 ? 0 : micros),
    channels: fmt.channels,
    sampleRate: fmt.sampleRate,
    bitsPerSample: fmt.bitsPerSample,
    formatTag: fmt.formatTag,
    dataOffset: dataOffset,
    dataBytes: dataBytes,
  );
}

/// Leest een WAV-header uit een bytebuffer: RIFF-kop, `fmt `-chunk,
/// `data`-chunk. Levert null bij een kapotte of vreemde kop — de caller
/// meldt dat als ondecodeerbaar, niet als "duur onbekend". Een geldige
/// kop met nul audiobytes geeft een [WavInfo] met `dataBytes == 0`.
///
/// [fileSize] is de echte lengte van waar de kop uit komt: de `data`-
/// chunk kan groter claimen dan de meegelezen bytes (we lazen alleen de
/// kop), dus de duur rekent op `fileSize`, niet op `head.length`. Zit
/// `data` pas ná de meegelezen kop, dan is dit niet aantoonbaar —
/// `readWavInfo` (wav_reader_io) leest daar dan wél door met seeks.
WavInfo? parseWavHeader(Uint8List head, int fileSize) {
  if (head.length < 44) return null;
  if (!_eq(head, 0, [0x52, 0x49, 0x46, 0x46]) ||
      !_eq(head, 8, [0x57, 0x41, 0x56, 0x45])) {
    return null;
  }
  int u32(int off) =>
      head[off] |
      (head[off + 1] << 8) |
      (head[off + 2] << 16) |
      (head[off + 3] << 24);

  var off = 12;
  WavFmt? fmt;
  // Chunks lopen achter elkaar; `fmt` en `data` zijn de twee die tellen.
  // Alles vreemds ertussen (LIST, FLLR, fact, cue) wordt overgeslagen
  // op zijn eigen lengteveld.
  while (off + 8 <= head.length) {
    final id = u32(off);
    final size = u32(off + 4);
    if (id == 0x20746D66 /* 'fmt ', little-endian gelezen */ ) {
      if (size < 16 || off + 8 + size > head.length) return null;
      fmt = parseWavFmt(Uint8List.sublistView(head, off + 8, off + 8 + size));
      if (fmt == null) return null;
    } else if (id == 0x61746164 /* 'data' */ ) {
      if (fmt == null) return null;
      // De chunk kan meer claimen dan er werkelijk in het bestand staat;
      // de kleinste van beide is de waarheid.
      final avail = fileSize - off - 8;
      if (avail < 0) return null;
      return wavInfoFromFields(
        fmt,
        dataBytes: size <= avail ? size : avail,
        dataOffset: off + 8,
      );
    }
    // Chunk-lengtes zijn even-afgerond (pad-byte).
    final next = off + 8 + size + (size & 1);
    if (next <= off) return null; // corrupte lengte — niet doorpogen
    off = next;
  }
  return null;
}
