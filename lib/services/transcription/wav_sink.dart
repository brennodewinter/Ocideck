// Incrementele PCM-WAV voor een lopende microfoonopname (#2516,
// TRANSCRIPTION.md §3.2).
//
// De header wordt na elk blok bijgewerkt en geflusht. Een crash kost
// daardoor hooguit het blok dat nog niet geflusht was; `repairWavHeader`
// maakt een file waarvan de header achterloopt op de echte lengte weer
// afspeelbaar. De sink schrijft alleen zijn eigen pad — een volle schijf
// raakt eerder afgeronde opnames niet aan.
import 'dart:io';
import 'dart:typed_data';

import 'transcription_errors.dart';

/// 16 kHz mono 16-bit PCM. De sampleklok en de codec staan in de header;
/// er is geen onderhandeling.
const recordingSampleRate = 16000;
const recordingChannels = 1;
const recordingBitsPerSample = 16;

/// Bestandsnaam binnen de sessiemap. Herstel zoekt op deze naam.
const recordingWavName = 'recording.wav';

/// Bovengrens van één opname, gelijk aan de mediacap (§3.2). Een langere
/// opname stopt met een benoemde fout in plaats van de schijf leeg te eten.
const maxRecordingWavBytes = 1024 * 1024 * 1024;

class IncrementalWav {
  IncrementalWav(
    this.path, {
    this.channels = recordingChannels,
    this.maxBytes = maxRecordingWavBytes,
  });

  final String path;

  /// 1 voor de microfoon, 2 voor een combinatie (links mic, rechts systeem).
  final int channels;

  /// Testinjectie: kleiner dan de productgrens, zodat een toets de
  /// schijfvol-weg kan bewijzen zonder de schijf te vullen.
  final int maxBytes;

  RandomAccessFile? _file;
  int _dataBytes = 0;

  int get dataBytes => _dataBytes;

  Duration get duration => Duration(
    microseconds: _dataBytes <= 0
        ? 0
        : (_dataBytes / (2 * channels) / recordingSampleRate * 1000000).round(),
  );

  Future<void> open() async {
    final raf = await File(path).open(mode: FileMode.write);
    _file = raf;
    await raf.writeFrom(_header(0, channels));
    await raf.flush();
  }

  /// Voegt 16-bit-PCM toe in het kanaalaantal van deze sink. Gooit [IoFailed]
  /// als het blok niet meer
  /// past of de schijf het weigert; wat er al stond blijft staan.
  Future<void> add(Uint8List pcm) async {
    final raf = _file;
    if (raf == null) {
      throw const IoFailed('opnamebestand is niet open');
    }
    if (pcm.isEmpty) return;
    if (_dataBytes + pcm.length > maxBytes) {
      throw const IoFailed('de opname past niet meer op de schijf');
    }
    try {
      await raf.writeFrom(pcm);
      _dataBytes += pcm.length;
      await _writeSizes();
    } on IoFailed {
      rethrow;
    } on FileSystemException {
      throw const IoFailed('de opname kon niet worden weggeschreven');
    }
  }

  Future<void> close() async {
    final raf = _file;
    if (raf == null) return;
    try {
      await _writeSizes();
      await raf.close();
    } on FileSystemException {
      throw const IoFailed('de opname kon niet worden afgerond');
    } finally {
      _file = null;
    }
  }

  Future<void> _writeSizes() async {
    final raf = _file;
    if (raf == null) return;
    final end = await raf.position();
    final riff = ByteData(4)..setUint32(0, 36 + _dataBytes, Endian.little);
    final data = ByteData(4)..setUint32(0, _dataBytes, Endian.little);
    await raf.setPosition(4);
    await raf.writeFrom(riff.buffer.asUint8List());
    await raf.setPosition(40);
    await raf.writeFrom(data.buffer.asUint8List());
    await raf.setPosition(end);
    await raf.flush();
  }
}

Uint8List _header(int dataBytes, int channels) {
  final out = Uint8List(44);
  final view = ByteData.sublistView(out);
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
  view.setUint16(20, 1, Endian.little);
  view.setUint16(22, channels, Endian.little);
  view.setUint32(24, recordingSampleRate, Endian.little);
  final blockAlign = channels * 2;
  view.setUint32(28, recordingSampleRate * blockAlign, Endian.little);
  view.setUint16(32, blockAlign, Endian.little);
  view.setUint16(34, recordingBitsPerSample, Endian.little);
  str(36, 'data');
  view.setUint32(40, dataBytes, Endian.little);
  return out;
}

/// Zet de lengtevelden gelijk aan de bytes die echt op schijf staan.
/// Een crash tussen het audioblok en de headerupdate laat anders een
/// te korte `data`-claim achter, en spelers stoppen daar.
///
/// Geeft false terug als het geen canonical 44-byte-WAV van ons is.
Future<bool> repairWavHeader(String path) async {
  final file = File(path);
  if (!await file.exists()) return false;
  final length = await file.length();
  if (length < 44) return false;
  final head = await file
      .openRead(0, 44)
      .fold<List<int>>(<int>[], (a, b) => a..addAll(b));
  if (head.length < 44) return false;
  final riff = String.fromCharCodes(head.sublist(0, 4));
  final wave = String.fromCharCodes(head.sublist(8, 12));
  final data = String.fromCharCodes(head.sublist(36, 40));
  if (riff != 'RIFF' || wave != 'WAVE' || data != 'data') return false;
  final dataBytes = (length - 44) & ~1;
  final raf = await file.open(mode: FileMode.append);
  try {
    final riffSize = ByteData(4)..setUint32(0, 36 + dataBytes, Endian.little);
    final dataSize = ByteData(4)..setUint32(0, dataBytes, Endian.little);
    await raf.setPosition(4);
    await raf.writeFrom(riffSize.buffer.asUint8List());
    await raf.setPosition(40);
    await raf.writeFrom(dataSize.buffer.asUint8List());
    await raf.flush();
  } finally {
    await raf.close();
  }
  return true;
}
