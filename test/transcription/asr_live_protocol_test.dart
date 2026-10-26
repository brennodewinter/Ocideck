// Het draadcontract `vosk-ws-1` (#2525): wat wij sturen en wat wij van
// de server accepteren. De parser is defensief — elke vreemde vorm is
// `LiveUnknown`, nooit een crash, want de server is externe invoer.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/asr_live_protocol.dart';

void main() {
  group('uitgaande frames', () {
    test('config draagt samplerate en woordvraag', () {
      final frame =
          jsonDecode(buildLiveConfigFrame(sampleRate: 16000))
              as Map<String, Object?>;
      final config = frame['config'] as Map<String, Object?>;
      expect(config['sample_rate'], 16000);
      expect(config['words'], true);
    });

    test('eof is het protocol-eindmerk, géén audio', () {
      expect(jsonDecode(liveEofFrame), {'eof': 1});
    });
  });

  group('inkomende frames', () {
    test('partial is een overschrijfbare hypothese', () {
      final msg = parseLiveMessage('{"partial":"hal"}');
      expect(msg, isA<LivePartial>());
      expect((msg as LivePartial).text, 'hal');
    });

    test('result draagt tekst en woordtijden in seconden→duration', () {
      final msg = parseLiveMessage(
        '{"result":[{"word":"hal","start":1.25,"end":1.5}],"text":"hal"}',
      );
      expect(msg, isA<LiveResult>());
      final r = msg as LiveResult;
      expect(r.text, 'hal');
      expect(r.words.single.word, 'hal');
      expect(r.words.single.start, const Duration(milliseconds: 1250));
      expect(r.words.single.end, const Duration(milliseconds: 1500));
    });

    test('result zonder woordtijden telt ook', () {
      final msg = parseLiveMessage('{"text":"alleen tekst"}');
      expect(msg, isA<LiveResult>());
      expect((msg as LiveResult).words, isEmpty);
    });

    test('kaputte en onbekende invoer is LiveUnknown, nooit een fout', () {
      for (final raw in [
        'geen json',
        '[1,2]',
        '{}',
        '{"vreemd":true}',
        '{"result":"geen lijst"}',
        '42',
        'null',
      ]) {
        expect(parseLiveMessage(raw), isA<LiveUnknown>(), reason: raw);
      }
    });

    test('kapotte woorden in een result vallen weg, de rest blijft', () {
      final msg =
          parseLiveMessage(
                '{"result":[{"word":"a","start":0,"end":1},{"word":5},'
                '{"word":"b","start":"x","end":2}],"text":"a"}',
              )
              as LiveResult;
      expect(msg.words, hasLength(1));
      expect(msg.words.single.word, 'a');
    });
  });

  group('wavPcmData', () {
    Uint8List wav({int fmtSize = 16, int dataSize = 4}) {
      // Minimale RIFF: RIFF-header + fmt-chunk + data-chunk.
      final bytes = ByteData(12 + 8 + fmtSize + 8 + dataSize);
      void tag(int off, String t) {
        for (var i = 0; i < 4; i++) {
          bytes.setUint8(off + i, t.codeUnitAt(i));
        }
      }

      tag(0, 'RIFF');
      bytes.setUint32(4, bytes.lengthInBytes - 8, Endian.little);
      tag(8, 'WAVE');
      tag(12, 'fmt ');
      bytes.setUint32(16, fmtSize, Endian.little);
      tag(20 + fmtSize, 'data');
      bytes.setUint32(24 + fmtSize, dataSize, Endian.little);
      for (var i = 0; i < dataSize; i++) {
        bytes.setUint8(28 + fmtSize + i, 0xAB);
      }
      return bytes.buffer.asUint8List();
    }

    test('levert de data-chunk als view', () {
      final pcm = wavPcmData(wav(dataSize: 4));
      expect(pcm, isNotNull);
      expect(pcm, [0xAB, 0xAB, 0xAB, 0xAB]);
    });

    test('slaakt onbekende chunks over, ook met oneven lengte', () {
      // fmt gevolgd door een 3-byte LIST-chunk (oneven → 1 padbyte) en
      // pas dán data — RIFF schrijft padding voor.
      final base = wav(fmtSize: 16, dataSize: 2);
      final extra = <int>[
        0x4C, 0x49, 0x53, 0x54, // 'LIST'
        3, 0, 0, 0,
        1, 2, 3, 0, // payload + pad
      ];
      final merged = Uint8List(36 + extra.length + 10);
      merged.setRange(0, 36, base); // t/m fmt
      merged.setRange(36, 36 + extra.length, extra);
      merged.setRange(36 + extra.length, merged.length, base, 36);
      final pcm = wavPcmData(merged);
      expect(pcm, isNotNull);
      expect(pcm!.length, 2);
    });

    test('geen WAVE of geen data-chunk is null — de aanroeper beslist', () {
      expect(wavPcmData(Uint8List(0)), isNull);
      expect(wavPcmData(Uint8List.fromList('nope'.codeUnits)), isNull);
      // Een RIFF die ná de fmt-chunk eindigt — er is simpelweg geen
      // data-chunk om terug te geven.
      expect(wavPcmData(wav().sublist(0, 36)), isNull);
    });
  });
}
