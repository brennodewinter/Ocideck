// De lokale whisper-engine (#2512): argv-opbouw, geharde omgeving,
// foutmapping, timeout/annulering en model-toetsing — alles met een
// vervangen procesrunner, dus nooit een echt subproces in tests.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/transcription/local_whisper_engine.dart';
import 'package:ocideck/services/transcription/local_whisper_engine_io.dart';
import 'package:ocideck/services/transcription/model_store_io.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/whisper_model.dart';

void main() {
  late Directory temp;
  late Directory storeRoot;
  late Directory workDir;
  late IoModelStore store;
  late File wav;

  /// Een 1-second 16 kHz mono PCM-WAV, geldig genoeg voor de header-pars.
  List<int> wavBytes({int seconds = 1}) {
    final byteRate = 16000 * 2;
    final dataLen = byteRate * seconds;
    final b = BytesBuilder()
      ..add('RIFF'.codeUnits)
      ..add(_le32(36 + dataLen))
      ..add('WAVE'.codeUnits)
      ..add('fmt '.codeUnits)
      ..add(_le32(16))
      ..add(_le16(1)) // PCM
      ..add(_le16(1)) // mono
      ..add(_le32(16000))
      ..add(_le32(byteRate))
      ..add(_le16(2))
      ..add(_le16(16))
      ..add('data'.codeUnits)
      ..add(_le32(dataLen))
      ..add(List.filled(dataLen, 0));
    return b.toBytes();
  }

  /// Schrijft het testmodel in de store zodat install-toetsen slagen.
  late WhisperModel model;
  late List<int> modelBytes;

  setUp(() async {
    temp = Directory.systemTemp.createTempSync('engine_test_');
    storeRoot = Directory('${temp.path}/models')..createSync();
    workDir = Directory('${temp.path}/work')..createSync();
    store = IoModelStore(root: storeRoot, candidateRoots: const []);
    modelBytes = [7, 7, 7, 7];
    model = WhisperModel(
      id: 'testmodel',
      fileName: 'ggml-test.bin',
      sha256: sha256.convert(modelBytes).toString(),
      downloadBytes: modelBytes.length,
      diskBytes: modelBytes.length,
      tier: 'light',
    );
    File('${storeRoot.path}/ggml-test.bin').writeAsBytesSync(modelBytes);
    wav = File('${temp.path}/clip.wav')
      ..writeAsBytesSync(wavBytes(seconds: 30));
  });

  tearDown(() {
    temp.deleteSync(recursive: true);
  });

  /// Een runner die doet alsof `-of <base>` werkte: schrijft `<base>.json`
  /// met twee segmenten en rapporteert geslaagd. Legt argv + env vast.
  ({
    WhisperRunner runner,
    List<List<String>> argvs,
    List<Map<String, String>?> envs,
  })
  runnerWriting(Object Function() body) {
    final argvs = <List<String>>[];
    final envs = <Map<String, String>?>[];
    return (
      argvs: argvs,
      envs: envs,
      runner:
          (
            String exe,
            List<String> argv, {
            Map<String, String>? environment,
            required Duration timeout,
            void Function(String line)? onStderrLine,
          }) {
            argvs.add(argv);
            envs.add(environment);
            final of = argv[argv.indexOf('-of') + 1];
            File('$of.json').writeAsStringSync(jsonEncode(body()));
            return WhisperRun(
              done: Future.value(
                const WhisperResult(exitCode: 0, stdout: '', stderr: ''),
              ),
              kill: () {},
            );
          },
    );
  }

  IoLocalWhisperEngine engine(WhisperRunner runner) => IoLocalWhisperEngine(
    store: store,
    runner: runner,
    executable: Platform.resolvedExecutable,
    model: model,
    workDir: workDir,
  );

  group('happy path', () {
    test(
      'start whisper-cli met de juiste argv en parseert de segmenten',
      () async {
        final r = runnerWriting(
          () => {
            'transcription': [
              {
                'offsets': {'from': 0, 'to': 1500},
                'text': ' Hallo wereld',
              },
              {
                'offsets': {'from': 1500, 'to': 3000},
                'text': ' en allemaal',
              },
            ],
          },
        );
        final e = engine(r.runner);
        final result = await e.transcribe(
          AudioRef(wav.path),
          const TranscriptionOptions(language: 'nl'),
        );
        expect(r.argvs.single, [
          '-m',
          p.join(storeRoot.path, 'ggml-test.bin'),
          '-l',
          'nl',
          '-f',
          wav.path,
          '-oj',
          '-of',
          anything,
          // Voortgang per segment naar stderr (#2515).
          '-pp',
        ]);
        expect(result.segments, hasLength(2));
        expect(result.segments.first.start, Duration.zero);
        expect(result.text, 'Hallo wereld en allemaal');
        // De run-uitvoer is opgeruimd; de (gedeelde) runmap niet.
        expect(workDir.existsSync(), isTrue);
        expect(workDir.listSync().isEmpty, isTrue);
      },
    );

    test('streamt `-pp`-voortgang naar options.onProgress', () async {
      final r = runnerWriting(() => {'transcription': <Map<String, Object>>[]});
      final base = r.runner;
      final progress = <double>[];
      final e = IoLocalWhisperEngine(
        store: store,
        runner: (exe, argv, {environment, required timeout, onStderrLine}) {
          // De fake speelt na: whisper-cli print deze regels per
          // verwerkt segment naar stderr.
          onStderrLine?.call('progress =   0%');
          onStderrLine?.call('progress =  37%');
          onStderrLine?.call('progress = 100%');
          onStderrLine?.call('geen voortgangsregel');
          return base(
            exe,
            argv,
            environment: environment,
            timeout: timeout,
            onStderrLine: onStderrLine,
          );
        },
        executable: Platform.resolvedExecutable,
        model: model,
        workDir: workDir,
      );
      await e.transcribe(
        AudioRef(wav.path),
        TranscriptionOptions(onProgress: progress.add),
      );
      expect(progress, [0.0, 0.37, 1.0]);
    });

    test('taal null valt terug op auto', () async {
      final r = runnerWriting(() => {'transcription': <Map<String, Object>>[]});
      await engine(
        r.runner,
      ).transcribe(AudioRef(wav.path), const TranscriptionOptions());
      expect(r.argvs.single[3], 'auto');
    });

    test('de omgeving is uitgekleed: geen erfenis-variabelen', () async {
      final r = runnerWriting(() => {'transcription': <Map<String, Object>>[]});
      await engine(
        r.runner,
      ).transcribe(AudioRef(wav.path), const TranscriptionOptions());
      final env = r.envs.single!;
      expect(env['LC_ALL'], 'C');
      expect(env['HOME'], workDir.path);
      // Geen PATH, geen tokens — toelatingslijst.
      expect(env.containsKey('PATH'), isFalse);
      expect(env.containsKey('GITHUB_TOKEN'), isFalse);
    });
  });

  group('foutmapping (§4.4)', () {
    test('niet-wav invoer is DecodeFailed, niet "silent failure"', () async {
      final other = File('${temp.path}/clip.ogg')..writeAsBytesSync([1, 2, 3]);
      final e = engine(runnerWriting(() => {}).runner);
      await expectLater(
        e.transcribe(AudioRef(other.path), const TranscriptionOptions()),
        throwsA(isA<DecodeFailed>()),
      );
    });

    test('ontbrekende invoer is IoFailed', () async {
      final e = engine(runnerWriting(() => {}).runner);
      await expectLater(
        e.transcribe(
          AudioRef('${temp.path}/bestaat-niet.wav'),
          const TranscriptionOptions(),
        ),
        throwsA(isA<IoFailed>()),
      );
    });

    test(
      'ontbrekend model is EngineUnavailable met benoemde vervolgstap',
      () async {
        File('${storeRoot.path}/ggml-test.bin').deleteSync();
        final e = engine(runnerWriting(() => {}).runner);
        await expectLater(
          e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
          throwsA(
            isA<EngineUnavailable>().having(
              (e) => e.message,
              'message',
              contains('niet geïnstalleerd'),
            ),
          ),
        );
      },
    );

    test('corrupt modelbestand (hash-mismatch) is EngineUnavailable', () async {
      File('${storeRoot.path}/ggml-test.bin').writeAsBytesSync([9, 9, 9, 9]);
      final e = engine(runnerWriting(() => {}).runner);
      await expectLater(
        e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
        throwsA(isA<EngineUnavailable>()),
      );
    });

    test('niet-nul exit is EngineUnavailable met stderr', () async {
      final e = engine(
        (exe, argv, {environment, required timeout, onStderrLine}) =>
            WhisperRun(
              done: Future.value(
                const WhisperResult(
                  exitCode: 1,
                  stdout: '',
                  stderr: 'bad model file',
                ),
              ),
              kill: () {},
            ),
      );
      await expectLater(
        e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
        throwsA(
          isA<EngineUnavailable>().having(
            (e) => e.message,
            'message',
            contains('bad model file'),
          ),
        ),
      );
    });

    test('out-of-memory in stderr is CapacityExceeded', () async {
      final e = engine(
        (exe, argv, {environment, required timeout, onStderrLine}) =>
            WhisperRun(
              done: Future.value(
                const WhisperResult(
                  exitCode: 1,
                  stdout: '',
                  stderr: 'ggml: failed to allocate memory',
                ),
              ),
              kill: () {},
            ),
      );
      await expectLater(
        e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
        throwsA(isA<CapacityExceeded>()),
      );
    });

    test(
      'timeout is EngineUnavailable — de run is weg, audio blijft',
      () async {
        final e = engine(
          (exe, argv, {environment, required timeout, onStderrLine}) =>
              WhisperRun(
                done: Future.value(
                  const WhisperResult(
                    exitCode: -9,
                    stdout: '',
                    stderr: '',
                    timedOut: true,
                  ),
                ),
                kill: () {},
              ),
        );
        await expectLater(
          e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
          throwsA(isA<EngineUnavailable>()),
        );
        // De opname zelf is nooit het slachtoffer van een enginefout.
        expect(wav.existsSync(), isTrue);
      },
    );

    test('cancel() leidt tot Cancelled, niet tot een "crash"', () async {
      final completer = Completer<WhisperResult>();
      final started = Completer<void>();
      final handle = WhisperRun(
        done: completer.future,
        kill: () {
          completer.complete(
            const WhisperResult(
              exitCode: -9,
              stdout: '',
              stderr: '',
              killed: true,
            ),
          );
        },
      );
      final e = engine((
        exe,
        argv, {
        environment,
        required timeout,
        onStderrLine,
      }) {
        started.complete();
        return handle;
      });
      final future = e.transcribe(
        AudioRef(wav.path),
        const TranscriptionOptions(),
      );
      // Wacht tot het proces echt staat — één tick is te weinig voor de
      // model- en bestandstoetsen die ervoor zitten.
      await started.future;
      e.cancel();
      await expectLater(future, throwsA(isA<Cancelled>()));
    });

    test('kapotte JSON-uitvoer is EngineUnavailable', () async {
      final e = engine((
        exe,
        argv, {
        environment,
        required timeout,
        onStderrLine,
      }) {
        final of = argv[argv.indexOf('-of') + 1];
        File('$of.json').writeAsStringSync('{"transcription": 42}');
        return WhisperRun(
          done: Future.value(
            const WhisperResult(exitCode: 0, stdout: '', stderr: ''),
          ),
          kill: () {},
        );
      });
      await expectLater(
        e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
        throwsA(isA<EngineUnavailable>()),
      );
    });

    test('exit 0 zonder uitvoerbestand is EngineUnavailable', () async {
      final e = engine(
        (exe, argv, {environment, required timeout, onStderrLine}) =>
            WhisperRun(
              done: Future.value(
                const WhisperResult(exitCode: 0, stdout: '', stderr: ''),
              ),
              kill: () {},
            ),
      );
      await expectLater(
        e.transcribe(AudioRef(wav.path), const TranscriptionOptions()),
        throwsA(isA<EngineUnavailable>()),
      );
    });
  });

  group('capaciteiten en status', () {
    test('capabilities meldt local, timestamps, geen streaming', () async {
      final e = engine(runnerWriting(() => {}).runner);
      expect(e.kind, EngineKind.local);
      final caps = await e.capabilities();
      expect(caps.timestamps, isTrue);
      expect(caps.streaming, isFalse);
      expect(caps.diarization, isFalse);
      expect(caps.requiresModel, 'testmodel');
    });

    test('status is ready met geldige helper, missingHelper zonder', () async {
      final ok = engine(runnerWriting(() => {}).runner);
      expect((await ok.status()).support, LocalEngineSupport.ready);
      final missing = IoLocalWhisperEngine(
        store: store,
        runner: runnerWriting(() => {}).runner,
        executable: '${temp.path}/geen-helper',
        model: model,
        workDir: workDir,
      );
      expect(
        (await missing.status()).support,
        LocalEngineSupport.missingHelper,
      );
    });

    test('transcribeLive is null — lokale batchroute heeft geen live', () {
      final e = engine(runnerWriting(() => {}).runner);
      expect(e.transcribeLive(const Stream.empty()), isNull);
    });
  });
}

List<int> _le16(int v) => [v & 0xff, (v >> 8) & 0xff];
List<int> _le32(int v) => [
  v & 0xff,
  (v >> 8) & 0xff,
  (v >> 16) & 0xff,
  (v >> 24) & 0xff,
];
