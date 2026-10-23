// Tests voor media_sniff.dart — pure containerdetectie en de
// WAV-headerparser (#2515). Geen IO: alle gevallen zijn byte-fixtures in
// het geheugen, zodat de herkenning zelf getoetst wordt en niet de
// leesroute eromheen.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

List<int> _chunk(String id, List<int> body) => [
  ...id.codeUnits,
  ..._le32(body.length),
  ...body,
  if (body.length.isOdd) 0, // RIFF-chunks zijn even-uitgelijnd
];

Uint8List _wav({
  int seconds = 1,
  int sampleRate = 16000,
  int channels = 1,
  int bits = 16,
  bool withJunk = false,
}) {
  final bytesPerSample = bits ~/ 8;
  final dataLen = seconds * sampleRate * channels * bytesPerSample;
  final chunks = <List<int>>[
    if (withJunk) _chunk('JUNK', List.filled(17, 0)),
    _chunk('fmt ', [
      ..._le16(1), // PCM
      ..._le16(channels),
      ..._le32(sampleRate),
      ..._le32(sampleRate * channels * bytesPerSample),
      ..._le16(channels * bytesPerSample),
      ..._le16(bits),
    ]),
    _chunk('data', List.filled(dataLen, 0)),
  ];
  final payload = chunks.expand((c) => c).toList();
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(4 + payload.length),
    ...'WAVE'.codeUnits,
    ...payload,
  ]);
}

Uint8List _head(String magic, {int pad = 16}) =>
    Uint8List.fromList([...magic.codeUnits, ...List.filled(pad, 0)]);

void main() {
  group('sniffContainer', () {
    test('herkent de gedragen containers op hun magische bytes', () {
      expect(sniffContainer(_wav()), MediaContainer.wav);
      expect(sniffContainer(_head('OggS')), MediaContainer.ogg);
      expect(sniffContainer(_head('fLaC')), MediaContainer.flac);
      expect(
        sniffContainer(
          Uint8List.fromList([0x1A, 0x45, 0xDF, 0xA3, 0, 0, 0, 0]),
        ),
        MediaContainer.ebml,
        reason: 'EBML-magic dekt webm én matroska',
      );
      expect(sniffContainer(_head('ID3')), MediaContainer.mp3);
      expect(
        sniffContainer(Uint8List.fromList([0xff, 0xfb, 0, 0])),
        MediaContainer.mp3,
        reason: 'mp3-framesync zonder ID3',
      );
      expect(
        sniffContainer(
          Uint8List.fromList([
            ...'RIFF'.codeUnits,
            ..._le32(12),
            ...'AVI '.codeUnits,
            ...List.filled(8, 0),
          ]),
        ),
        MediaContainer.avi,
        reason: 'RIFF maar geen WAVE — avi',
      );
      expect(
        sniffContainer(
          Uint8List.fromList([
            ..._le32(24),
            ...'ftyp'.codeUnits,
            ...'isom'.codeUnits,
            ...List.filled(8, 0),
          ]),
        ),
        MediaContainer.mpeg4,
      );
    });

    test('onbekende en afgekapte invoer is `unknown`, nooit een gok', () {
      expect(sniffContainer(Uint8List(0)), MediaContainer.unknown);
      expect(sniffContainer(Uint8List(4)), MediaContainer.unknown);
      expect(
        sniffContainer(Uint8List.fromList('PDF-1.7 content'.codeUnits)),
        MediaContainer.unknown,
      );
      expect(
        sniffContainer(Uint8List.fromList('RIFF'.codeUnits)),
        MediaContainer.unknown,
        reason: 'RIFF zonder WAVE-vierlettercode valt niet in de wav-tak',
      );
    });

    test('de extensie is een zwakke reserve, inhoud wint', () {
      expect(
        sniffContainer(Uint8List(16), extension: '.mp3'),
        MediaContainer.mp3,
      );
      expect(
        sniffContainer(Uint8List(16), extension: 'MKV'),
        MediaContainer.ebml,
      );
      expect(
        sniffContainer(Uint8List(16), extension: '.wat'),
        MediaContainer.unknown,
      );
      expect(
        sniffContainer(_wav(), extension: '.mp3'),
        MediaContainer.wav,
        reason: 'een mp3-naam op wav-inhoud liegt — de bytes winnen',
      );
    });
  });

  group('mayBeVideo', () {
    test('alleen containers met een videospoor kunnen "geen audio" zijn', () {
      expect(mayBeVideo(MediaContainer.mpeg4), isTrue);
      expect(mayBeVideo(MediaContainer.ebml), isTrue);
      expect(mayBeVideo(MediaContainer.avi), isTrue);
      expect(mayBeVideo(MediaContainer.wav), isFalse);
      expect(mayBeVideo(MediaContainer.mp3), isFalse);
      expect(mayBeVideo(MediaContainer.ogg), isFalse);
      expect(mayBeVideo(MediaContainer.flac), isFalse);
      expect(mayBeVideo(MediaContainer.unknown), isFalse);
    });
  });

  group('parseWavHeader', () {
    test('leest duur, kanalen en samplerate uit een PCM-header', () {
      final bytes = _wav(seconds: 3, sampleRate: 44100);
      final info = parseWavHeader(bytes, bytes.length);
      expect(info, isNotNull);
      expect(info!.duration, const Duration(seconds: 3));
      expect(info.sampleRate, 44100);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
    });

    test('slaat vreemde chunks over en vindt fmt+data toch', () {
      final bytes = _wav(seconds: 2, withJunk: true);
      final info = parseWavHeader(bytes, bytes.length);
      expect(info?.duration, const Duration(seconds: 2));
    });

    test('data-claim groter dan het bestand rekent op het bestand', () {
      // De kop claimt 3 s data, het bestand bevat maar de helft — de
      // duur volgt de werkelijkheid, niet de claim.
      final full = _wav(seconds: 3);
      final half = Uint8List.sublistView(full, 0, full.length ~/ 2);
      final info = parseWavHeader(half, half.length);
      expect(info, isNotNull);
      expect(info!.duration.inMilliseconds, lessThan(3000));
    });

    test('weigert kapotte headers en niet-wav met null', () {
      expect(parseWavHeader(Uint8List.fromList('RIFF'.codeUnits), 4), isNull);
      expect(parseWavHeader(_head('OggS'), 20), isNull);
      // Corrupte chunklengte die nooit meer vooruitkomt.
      final corrupt = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        ..._le32(40),
        ...'WAVE'.codeUnits,
        ...'fmt '.codeUnits,
        ..._le32(0xFFFFFFF8),
        ...List.filled(8, 0),
      ]);
      expect(parseWavHeader(corrupt, corrupt.length), isNull);
    });
  });

  group('encodePcmWav', () {
    test('schrijft een header die de parser weer leest', () {
      final wav = encodePcmWav(
        Float32List(16000), // 1 s stilte aan 16 kHz
      );
      expect(sniffContainer(wav), MediaContainer.wav);
      final info = parseWavHeader(wav, wav.length);
      expect(info, isNotNull);
      expect(info!.duration, const Duration(seconds: 1));
      expect(info.sampleRate, 16000);
      expect(info.channels, 1);
      expect(info.bitsPerSample, 16);
    });
  });
}
