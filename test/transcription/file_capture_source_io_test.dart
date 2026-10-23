// Tests voor de desktophelft van de bestandsbron (#2515): describe op
// echte bestanden, decode via een scriptbare DecoderRunner, en de
// cancel/timeout/foutmapping van IoFileCaptureSession. De decoder zelf
// is een fake — wat getoetst wordt is het gedrag van de bron, niet of
// afconvert/ffmpeg werkt.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source_io.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:path/path.dart' as p;

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];

Uint8List wavBytes({int seconds = 2}) {
  const rate = 16000;
  final dataLen = seconds * rate * 2;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(36 + dataLen),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ..._le32(16),
    ..._le16(1),
    ..._le16(1),
    ..._le32(rate),
    ..._le32(rate * 2),
    ..._le16(2),
    ..._le16(16),
    ...'data'.codeUnits,
    ..._le32(dataLen),
    ...List.filled(dataLen, 0),
  ]);
}

void main() {
  late Directory tmp;
  late Directory staging;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('filesource_test_');
    staging = await Directory(
      p.join(tmp.path, 'staging'),
    ).create(recursive: true);
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  File writeWav({String name = 'clip.wav', int seconds = 2}) =>
      File(p.join(tmp.path, name))
        ..writeAsBytesSync(wavBytes(seconds: seconds));

  CaptureRequest request(String path) => CaptureRequest(
    kinds: const {CaptureSourceKind.file},
    consent: const RecordingConsent(participantNoticeAcknowledged: true),
    stagingDir: staging.path,
    sourcePath: path,
  );

  group('describe', () {
    test('PCM-WAV gaat direct door, met duur uit de header', () async {
      final wav = writeWav(seconds: 3);
      final info = await IoFileCaptureSource().describe(wav.path);
      expect(info.container, MediaContainer.wav);
      expect(info.engineReadsDirectly, isTrue);
      expect(info.duration, const Duration(seconds: 3));
      expect(info.sizeBytes, wav.lengthSync());
    });

    test('andere container met decoder is decodeerbaar', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final info = await IoFileCaptureSource(
        decoderOverride: '/usr/bin/true',
      ).describe(mp3.path);
      expect(info.container, MediaContainer.mp3);
      expect(info.engineReadsDirectly, isFalse);
      expect(info.decodable, isTrue);
    });

    test('een onleesbare of afwezige bron is IoFailed', () async {
      expect(
        () => IoFileCaptureSource().describe(p.join(tmp.path, 'weg.wav')),
        throwsA(isA<IoFailed>()),
      );
    });

    test('een leeg bestand is DecodeFailed, geen stille transcriptie', () {
      final leeg = File(p.join(tmp.path, 'leeg.wav'))..writeAsBytesSync([]);
      expect(
        () => IoFileCaptureSource().describe(leeg.path),
        throwsA(isA<DecodeFailed>()),
      );
    });

    test('onbekende inhoud met onbekende extensie blijft unknown', () async {
      final vreemd = File(p.join(tmp.path, 'data.bin'))
        ..writeAsBytesSync(Uint8List.fromList('geen media'.codeUnits));
      final info = await IoFileCaptureSource(
        decoderOverride: '/usr/bin/true',
      ).describe(vreemd.path);
      expect(info.container, MediaContainer.unknown);
      // De decoderuitslag is dan de waarheid — decodable zegt alleen
      // "er staat een decoder", niet "dit gaat lukken".
      expect(info.decodable, isTrue);
    });
  });

  group('start', () {
    test('weigert elke bronvraag die niet {file} is', () {
      expect(
        () => IoFileCaptureSource().start(
          const CaptureRequest(
            kinds: {CaptureSourceKind.microphone},
            consent: RecordingConsent(participantNoticeAcknowledged: true),
          ),
        ),
        throwsA(isA<UnsupportedSource>()),
      );
    });

    test('weigert een vraag zonder bronpad', () {
      expect(
        () => IoFileCaptureSource().start(
          CaptureRequest(
            kinds: const {CaptureSourceKind.file},
            consent: const RecordingConsent(
              participantNoticeAcknowledged: true,
            ),
            stagingDir: staging.path,
          ),
        ),
        throwsA(isA<IoFailed>()),
      );
    });
  });

  group('sessie', () {
    test('WAV-sessie refereert het origineel — nooit een kopie', () async {
      final wav = writeWav(seconds: 2);
      final session = await IoFileCaptureSource().start(request(wav.path));
      final audio = await session.stop();
      expect(audio.durablePath, wav.path);
      expect(audio.duration, const Duration(seconds: 2));
      // Het origineel staat er nog, onaangeraakt.
      expect(wav.readAsBytesSync().length, wavBytes(seconds: 2).length);
    });

    test('decode schrijft WAV in de staging via de gepinde decoder', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final argvs = <List<String>>[];
      final envs = <Map<String, String>?>[];
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: (exe, argv, {environment, required timeout}) {
          argvs.add(argv);
          envs.add(environment);
          // De fake doet wat afconvert zou doen: uitvoer op de laatste
          // argv-plek schrijven.
          File(argv.last).writeAsBytesSync(wavBytes(seconds: 5));
          return DecodeRun(
            done: Future.value(const DecodeResult(exitCode: 0, stderr: '')),
            kill: () {},
          );
        },
      ).start(request(mp3.path));

      final audio = await session.stop();
      expect(audio.durablePath, p.join(staging.path, 'input.wav'));
      expect(audio.duration, const Duration(seconds: 5));

      // De afconvert-vorm: genormaliseerd naar 16 kHz mono WAV.
      final argv = argvs.single;
      expect(argv, containsAllInOrder(['-f', 'WAVE', '-d', 'LEI16@16000']));

      // De omgeving is uitgekleed: geen erfenis-variabelen mee.
      expect(envs.single!.keys, isNot(contains('PATH')));
      expect(envs.single!['HOME'], staging.path);
    });

    test('ffmpeg-argv mapt alleen de eerste audiotrack', () async {
      final mp4 = File(p.join(tmp.path, 'film.mp4'))
        ..writeAsBytesSync(
          Uint8List.fromList([
            ..._le32(24),
            ...'ftyp'.codeUnits,
            ...'isom'.codeUnits,
            ...List.filled(32, 0),
          ]),
        );
      final argvs = <List<String>>[];
      final session = await IoFileCaptureSource(
        decoderOverride: 'ffmpeg',
        decoderRunner: (exe, argv, {environment, required timeout}) {
          argvs.add(argv);
          File(argv.last).writeAsBytesSync(wavBytes());
          return DecodeRun(
            done: Future.value(const DecodeResult(exitCode: 0, stderr: '')),
            kill: () {},
          );
        },
      ).start(request(mp4.path));

      await session.stop();
      final argv = argvs.single;
      expect(argv, containsAllInOrder(['-map', '0:a:0']));
      expect(argv, containsAllInOrder(['-ar', '16000']));
      expect(argv, containsAllInOrder(['-ac', '1']));
    });

    test('"matches no streams" is DecodeFailed: geen audiotrack', () {
      expect(
        () async {
          final mp4 = File(p.join(tmp.path, 'stille-film.mp4'))
            ..writeAsBytesSync(
              Uint8List.fromList([
                ..._le32(24),
                ...'ftyp'.codeUnits,
                ...'isom'.codeUnits,
                ...List.filled(32, 0),
              ]),
            );
          final session = await IoFileCaptureSource(
            decoderOverride: 'ffmpeg',
            decoderRunner: (exe, argv, {environment, required timeout}) =>
                DecodeRun(
                  done: Future.value(
                    const DecodeResult(
                      exitCode: 1,
                      stderr: 'Stream map matches no streams',
                    ),
                  ),
                  kill: () {},
                ),
          ).start(request(mp4.path));
          await session.stop();
        }(),
        throwsA(
          isA<DecodeFailed>().having(
            (e) => e.message,
            'melding',
            contains('audiotrack'),
          ),
        ),
      );
    });

    test('decoder zonder uitvoer is DecodeFailed, geen lege audio', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: (exe, argv, {environment, required timeout}) =>
            DecodeRun(
              done: Future.value(const DecodeResult(exitCode: 0, stderr: '')),
              kill: () {},
            ),
      ).start(request(mp3.path));
      expect(() => session.stop(), throwsA(isA<DecodeFailed>()));
    });

    test('cancel() tijdens de decode eindigt in Cancelled', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      DecodeRun? theRun;
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: (exe, argv, {environment, required timeout}) {
          final completer = Completer<DecodeResult>();
          final run = DecodeRun(
            done: completer.future,
            kill: () => completer.complete(
              const DecodeResult(exitCode: -9, stderr: '', killed: true),
            ),
          );
          theRun = run;
          return run;
        },
      ).start(request(mp3.path));

      final stopping = session.stop();
      // cancel() vuurt kill op de lopende decode.
      session.cancel();
      await expectLater(stopping, throwsA(isA<Cancelled>()));
      expect(theRun, isNotNull);
      // De halve decode is opgeruimd.
      expect(File(p.join(staging.path, 'input.wav')).existsSync(), isFalse);
    });

    test(
      'cancel() vóór de start van de decode eindigt ook in Cancelled',
      () async {
        final wav = writeWav();
        final session = await IoFileCaptureSource().start(request(wav.path));
        session.cancel();
        await expectLater(session.stop(), throwsA(isA<Cancelled>()));
      },
    );

    test('een decoder-timeout is EngineUnavailable, geen hang', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: (exe, argv, {environment, required timeout}) =>
            DecodeRun(
              done: Future.value(
                const DecodeResult(exitCode: -9, stderr: '', timedOut: true),
              ),
              kill: () {},
            ),
      ).start(request(mp3.path));
      await expectLater(session.stop(), throwsA(isA<EngineUnavailable>()));
    });

    test('een tweede stop() krijgt dezelfde toekomst', () async {
      final wav = writeWav();
      final session = await IoFileCaptureSource().start(request(wav.path));
      final first = session.stop();
      final second = session.stop();
      expect(identical(first, second), isTrue);
      await first;
    });
  });
}
