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
import 'package:ocideck/services/transcription/bundled_audio_helper_io.dart';
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

Uint8List wavBytes({
  int seconds = 2,
  int rate = 16000,
  int channels = 1,
  int bits = 16,
}) {
  final align = channels * bits ~/ 8;
  final dataLen = seconds * rate * align;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(36 + dataLen),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ..._le32(16),
    ..._le16(1),
    ..._le16(channels),
    ..._le32(rate),
    ..._le32(rate * align),
    ..._le16(align),
    ..._le16(bits),
    ...'data'.codeUnits,
    ..._le32(dataLen),
    ...List.filled(dataLen, 0),
  ]);
}

/// De WAV zoals afconvert hem schrijft: een FLLR-paginavulling van
/// enkele kB tussen `fmt ` en `data` (#2933). Geldig, maar `data` ligt
/// buiten elke vaste kopgrens.
Uint8List wavBytesFllr({int seconds = 2, int filler = 4044}) {
  const rate = 16000;
  final dataLen = seconds * rate * 2;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(4 + (8 + 16) + (8 + filler) + (8 + dataLen)),
    ...'WAVE'.codeUnits,
    ...'fmt '.codeUnits,
    ..._le32(16),
    ..._le16(1),
    ..._le16(1),
    ..._le32(rate),
    ..._le32(rate * 2),
    ..._le16(2),
    ..._le16(16),
    ...'FLLR'.codeUnits,
    ..._le32(filler),
    ...List.filled(filler, 0),
    ...'data'.codeUnits,
    ..._le32(dataLen),
    ...List.filled(dataLen, 0),
  ]);
}

/// Een geldige WAV-header met een `data`-chunk van nul bytes.
Uint8List wavBytesZeroData() {
  const rate = 16000;
  return Uint8List.fromList([
    ...'RIFF'.codeUnits,
    ..._le32(36),
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
    ..._le32(0),
  ]);
}

/// ISO-BMFF-magie — genoeg voor de sniffer, niet een echte film.
Uint8List mp4MagicBytes() => Uint8List.fromList([
  ..._le32(24),
  ...'ftyp'.codeUnits,
  ...'isom'.codeUnits,
  ...List.filled(64, 0),
]);

/// Vangt argv van de fake decoder én schrijft een WAV als uitvoer.
DecoderRunner wavWritingDecoder(
  List<List<String>> argvs, {
  Uint8List Function()? wav,
  DecodeResult result = const DecodeResult(exitCode: 0, stderr: ''),
}) {
  return (exe, argv, {environment, required timeout}) {
    argvs.add(argv);
    if (result.exitCode == 0) {
      File(argv.last).writeAsBytesSync((wav ?? wavBytesFllr)());
    }
    return DecodeRun(done: Future.value(result), kill: () {});
  };
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

  test(
    'macOS decoder lookup uses the exact bundle helper, never a sibling/PATH',
    () async {
      final executable = p.join(
        tmp.path,
        'OciDeck ü.app',
        'Contents',
        'MacOS',
        'ocideck',
      );
      final helper = File(
        p.join(p.dirname(executable), '..', 'Helpers', 'ffmpeg'),
      );
      expect(
        bundledMacMediaDecoder(executable: executable, macOS: true),
        isNull,
      );
      await helper.parent.create(recursive: true);
      await helper.writeAsString('test helper');
      expect(
        bundledMacMediaDecoder(executable: executable, macOS: true),
        p.normalize(helper.path),
      );
      expect(
        bundledMacMediaDecoder(executable: executable, macOS: false),
        isNull,
      );
    },
  );

  for (final format in [(48000, 2, 16), (44100, 1, 24), (16000, 2, 16)]) {
    test(
      'WAV $format is normalized before being offered to an engine',
      () async {
        final original = wavBytes(
          rate: format.$1,
          channels: format.$2,
          bits: format.$3,
        );
        final input = File(p.join(tmp.path, 'variant.wav'))
          ..writeAsBytesSync(original);
        var runs = 0;
        final source = IoFileCaptureSource(
          decoderOverride: 'ffmpeg',
          decoderRunner: (exe, argv, {environment, required timeout}) {
            runs++;
            File(argv.last).writeAsBytesSync(wavBytes());
            return DecodeRun(
              done: Future.value(const DecodeResult(exitCode: 0, stderr: '')),
              kill: () {},
            );
          },
        );
        final info = await source.describe(input.path);
        expect(info.engineReadsDirectly, isFalse);
        final session = await source.start(request(input.path));
        final audio = await session.stop();
        expect(runs, 1);
        expect(audio.durablePath, isNot(input.path));
        expect(audio.duration, const Duration(seconds: 2));
        expect(input.readAsBytesSync(), original);
      },
    );
  }

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

  group('WAV met vulling/metadata vóór data (#2933)', () {
    test('describe leest de duur ook met FLLR tussen fmt en data', () async {
      final wav = File(p.join(tmp.path, 'fllr.wav'))
        ..writeAsBytesSync(wavBytesFllr(seconds: 3));
      final info = await IoFileCaptureSource().describe(wav.path);
      expect(info.container, MediaContainer.wav);
      expect(info.engineReadsDirectly, isTrue);
      expect(info.duration, const Duration(seconds: 3));
    });

    test('metadata groter dan 4096 bytes blokkeert de header niet', () async {
      final wav = File(p.join(tmp.path, 'groot-metadata.wav'))
        ..writeAsBytesSync(wavBytesFllr(seconds: 2, filler: 70000));
      final info = await IoFileCaptureSource().describe(wav.path);
      expect(info.duration, const Duration(seconds: 2));
    });

    test('afconvert-uitvoer met FLLR is geen "lege audio" meer', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: wavWritingDecoder([]),
      ).start(request(mp3.path));
      final audio = await session.stop();
      expect(audio.duration, const Duration(seconds: 2));
    });

    test('afconvert-argv bevat --no-filler tegen de vulling zelf', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final argvs = <List<String>>[];
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: wavWritingDecoder(argvs),
      ).start(request(mp3.path));
      await session.stop();
      expect(argvs.single, contains('--no-filler'));
    });

    test(
      'een decoder met niet-genormaliseerde uitvoer wordt geweigerd',
      () async {
        final mp3 = File(p.join(tmp.path, 'clip.mp3'))
          ..writeAsBytesSync(
            Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
          );
        final session = await IoFileCaptureSource(
          decoderOverride: 'afconvert',
          decoderRunner: wavWritingDecoder(
            [],
            wav: () => wavBytes(rate: 48000, channels: 2),
          ),
        ).start(request(mp3.path));
        await expectLater(
          session.stop(),
          throwsA(
            isA<DecodeFailed>().having(
              (e) => e.message,
              'melding',
              contains('16 kHz mono PCM16'),
            ),
          ),
        );
        expect(await File(session.durablePath).exists(), isFalse);
        expect(await mp3.exists(), isTrue);
      },
    );

    test('een geldige header met nul audiobytes is wél "lege audio"', () async {
      final mp3 = File(p.join(tmp.path, 'clip.mp3'))
        ..writeAsBytesSync(
          Uint8List.fromList([0x49, 0x44, 0x33, ...List.filled(40, 0)]),
        );
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: wavWritingDecoder([], wav: wavBytesZeroData),
      ).start(request(mp3.path));
      expect(
        () => session.stop(),
        throwsA(
          isA<DecodeFailed>().having(
            (e) => e.message,
            'melding',
            contains('lege audio'),
          ),
        ),
      );
    });

    test('direct openen van een nul-data-WAV meldt geen audiodata', () {
      final wav = File(p.join(tmp.path, 'leeg-maar-valide.wav'))
        ..writeAsBytesSync(wavBytesZeroData());
      expect(
        () => IoFileCaptureSource().describe(wav.path),
        throwsA(
          isA<DecodeFailed>().having(
            (e) => e.message,
            'melding',
            contains('audiodata'),
          ),
        ),
      );
    });

    test(
      'afgekapt fmt-blok of chunk buiten bestand: geweigerd, geen crash',
      () {
        // fmt claimt 16 bytes maar er staan er maar 8.
        final afgekapt = File(p.join(tmp.path, 'afgekapt.wav'))
          ..writeAsBytesSync(
            Uint8List.fromList([
              ...'RIFF'.codeUnits,
              ..._le32(20),
              ...'WAVE'.codeUnits,
              ...'fmt '.codeUnits,
              ..._le32(16),
              ..._le16(1),
              ..._le16(1),
              ..._le32(16000),
            ]),
          );
        expect(
          () => IoFileCaptureSource().describe(afgekapt.path),
          throwsA(isA<DecodeFailed>()),
        );
        // Een chunk die voorbij het bestand claimt.
        final buiten = File(p.join(tmp.path, 'buiten.wav'))
          ..writeAsBytesSync(
            Uint8List.fromList([
              ...'RIFF'.codeUnits,
              ..._le32(40),
              ...'WAVE'.codeUnits,
              ...'FLLR'.codeUnits,
              ..._le32(0x7FFFFFFF),
              ...List.filled(16, 0),
            ]),
          );
        expect(
          () => IoFileCaptureSource().describe(buiten.path),
          throwsA(isA<DecodeFailed>()),
        );
      },
    );

    test('een niet-PCM-WAV gaat via de decoder, niet direct door', () async {
      final floatWav = Uint8List.fromList([
        ...'RIFF'.codeUnits,
        ..._le32(36 + 32000),
        ...'WAVE'.codeUnits,
        ...'fmt '.codeUnits,
        ..._le32(16),
        ..._le16(3), // IEEE float — geen PCM
        ..._le16(1),
        ..._le32(16000),
        ..._le32(64000),
        ..._le16(4),
        ..._le16(32),
        ...'data'.codeUnits,
        ..._le32(32000),
        ...List.filled(32000, 0),
      ]);
      final wav = File(p.join(tmp.path, 'float.wav'))
        ..writeAsBytesSync(floatWav);
      final info = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
      ).describe(wav.path);
      expect(info.container, MediaContainer.wav);
      expect(info.engineReadsDirectly, isFalse);
      expect(info.decodable, isTrue);
      expect(info.decodeNote, contains('16 kHz mono PCM16'));
    });
  });

  group('verkeerd benoemde invoer (#2934)', () {
    test(
      'MP4-inhoud met .mp3-naam krijgt een hernoemde staginginvoer',
      () async {
        final bron = File(p.join(tmp.path, 'verkeerd.mp3'))
          ..writeAsBytesSync(mp4MagicBytes());
        final argvs = <List<String>>[];
        final session = await IoFileCaptureSource(
          decoderOverride: 'afconvert',
          decoderRunner: wavWritingDecoder(argvs),
        ).start(request(bron.path));

        // De voorbeschouwing zegt eerlijk MP4, niet MP3.
        final session2 = IoFileCaptureSource(decoderOverride: 'afconvert');
        final info = await session2.describe(bron.path);
        expect(info.container, MediaContainer.mpeg4);
        expect(info.decodeNote, contains('bestandsnaam'));

        await session.stop();
        final argv = argvs.single;
        // De decoder kreeg geen .mp3-naam maar een .mp4-stagingkopie.
        final input = argv[argv.length - 2];
        expect(p.extension(input), '.mp4');
        expect(p.dirname(input), staging.path);
        // De kopie is wegwerpwerk — na de sessie weg.
        expect(File(input).existsSync(), isFalse);
        // En het origineel staat er onaangeraakt.
        expect(bron.readAsBytesSync(), mp4MagicBytes());
      },
    );

    test('een juiste .mp4-naam krijgt geen stagingkopie', () async {
      final bron = File(p.join(tmp.path, 'film.mp4'))
        ..writeAsBytesSync(mp4MagicBytes());
      final argvs = <List<String>>[];
      final session = await IoFileCaptureSource(
        decoderOverride: 'afconvert',
        decoderRunner: wavWritingDecoder(argvs),
      ).start(request(bron.path));
      await session.stop();
      expect(argvs.single[argvs.single.length - 2], bron.path);
      // Alleen de decode-uitvoer staat in de staging — geen kopie.
      expect(
        Directory(
          staging.path,
        ).listSync().where((e) => p.extension(e.path) == '.mp4'),
        isEmpty,
      );
    });

    test('ffmpeg krijgt de originele naam — inhoud telt daar', () async {
      final bron = File(p.join(tmp.path, 'verkeerd.mp3'))
        ..writeAsBytesSync(mp4MagicBytes());
      final argvs = <List<String>>[];
      final session = await IoFileCaptureSource(
        decoderOverride: 'ffmpeg',
        decoderRunner: wavWritingDecoder(argvs),
      ).start(request(bron.path));
      await session.stop();
      expect(argvs.single, contains(bron.path));
    });

    test(
      'afconvert-fout op een videocontainer claimt geen ontbrekende track',
      () async {
        final bron = File(p.join(tmp.path, 'video.mp4'))
          ..writeAsBytesSync(mp4MagicBytes());
        final session = await IoFileCaptureSource(
          decoderOverride: 'afconvert',
          decoderRunner: (exe, argv, {environment, required timeout}) =>
              DecodeRun(
                done: Future.value(
                  const DecodeResult(
                    exitCode: 1,
                    stderr: "Error: Couldn't open input file ('dta?')",
                  ),
                ),
                kill: () {},
              ),
        ).start(request(bron.path));
        await expectLater(
          session.stop(),
          throwsA(
            isA<DecodeFailed>().having(
              (e) => e.message,
              'melding',
              allOf(contains('mogelijk geen audiotrack'), contains('dta?')),
            ),
          ),
        );
      },
    );
  });
}
