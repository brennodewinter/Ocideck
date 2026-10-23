import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show Abi;
import 'dart:io';
import 'dart:typed_data' show ByteData, BytesBuilder, Endian;

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../../utils/log.dart';
import 'capture_source.dart' show AudioChunk;
import 'local_whisper_engine.dart';
import 'model_store.dart';
import 'transcription_engine.dart';
import 'transcription_errors.dart';
import 'whisper_model.dart';

/// Eén gestart helper-proces: zijn uitkomst plus de knop waarmee `cancel()`
/// hem kan afbreken. Vervangbaar in tests zodat argv, omgeving en
/// foutmapping te controleren zijn zonder echt te starten.
class WhisperRun {
  const WhisperRun({required this.done, required this.kill});

  /// Voltooit met de procesuitkomst (of een fout die het starten zelf was).
  final Future<WhisperResult> done;

  /// Beëindigt het proces direct. Idempotent; doet niets als het al klaar was.
  final void Function() kill;
}

class WhisperResult {
  const WhisperResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    this.timedOut = false,
    this.killed = false,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final bool timedOut;

  /// Door `cancel()` afgeschoten — onderscheid van een eigen crash.
  final bool killed;
}

typedef WhisperRunner =
    WhisperRun Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      required Duration timeout,

      /// Complete stderr-regels terwijl ze binnenkomen — `-pp` print
      /// `progress = N%` per verwerkt segment (#2515).
      void Function(String line)? onStderrLine,
    });

/// De lokale whisper.cpp-engine op desktop (§4.4). Regels van §10.2 passen
/// we hier opnieuw toe: argv-array zonder shell, een uitgeklede omgeving,
/// begrensde uitvoer en een tijdslimiet die een vastloper afschiet.
class IoLocalWhisperEngine implements LocalWhisperEngine {
  IoLocalWhisperEngine({
    TranscriptionModelStore? store,
    WhisperRunner? runner,
    this.executable,
    WhisperModel? model,
    Directory? workDir,
  }) : _store = store ?? createModelStore(),
       _runner = runner ?? _spawn,
       _model = model ?? whisperModelCatalog.first,
       _workDirOverride = workDir;

  final TranscriptionModelStore _store;
  final WhisperRunner _runner;

  /// Expliciete helper-locatie (tests, ongewone bundels); null = zoeken.
  final String? executable;

  final Directory? _workDirOverride;

  final WhisperModel _model;
  @override
  WhisperModel? get model => _model;

  WhisperRun? _current;

  /// De hash is getoetst vóór een model aan het proces gaat (#2512); de
  /// sleutel (pad+grootte+mtime) voorkomt dat een 1,5 GB-model bij élke
  /// run opnieuw volledig gelezen wordt zonder aan de eis iets af te dingen.
  String? _verifiedKey;

  /// Begrenst uitvoer per kanaal; een losgeslagen helper mag het geheugen
  /// niet vullen (zelfde cap als de git-uitvoerder).
  static const _maxOutputBytes = 4 * 1024 * 1024;

  /// Grace na einde van het proces vóór we een opengehouden pijp loslaten
  /// — zie git_cli_io._spawn voor de kleinkind-klem die dit afdekt.
  static const _drainGrace = Duration(seconds: 2);

  /// Whisper ondersteunt `auto` plus de talen van het model; de lijst is
  /// bewust niet limitatief geknipt — `languages` meldt alleen dat meertalig
  /// en auto-detect bestaan, de catalogus bepaalt verder niets over taal.
  static const _languages = {'auto', 'nl', 'en', 'de', 'fr', 'es'};

  /// De architecturen waarvoor de buildketen `whisper-cli` levert
  /// (§7: gebouwd en getoetst; andere architecturen vallen eerlijk af).
  static const _supportedAbis = {
    Abi.macosArm64,
    Abi.macosX64,
    Abi.windowsX64,
    Abi.linuxX64,
  };

  @override
  EngineKind get kind => EngineKind.local;

  @override
  Future<LocalEngineStatus> status() async {
    if (!_supportedAbis.contains(Abi.current())) {
      return LocalEngineStatus(
        LocalEngineSupport.unsupportedArchitecture,
        Abi.current().toString(),
      );
    }
    final exe = resolveExecutable();

    if (exe == null || !await File(exe).exists()) {
      return const LocalEngineStatus(
        LocalEngineSupport.missingHelper,
        'whisper-cli ontbreekt in dit artefact',
      );
    }
    return const LocalEngineStatus(LocalEngineSupport.ready, '');
  }

  @override
  Future<EngineCapabilities> capabilities() async => EngineCapabilities(
    languages: _languages,
    timestamps: true,
    diarization: false,
    streaming: false,
    requiresModel: _model.id,
  );

  @override
  Stream<PartialTranscript>? transcribeLive(Stream<AudioChunk> chunks) => null; // whisper-cli is batch; live is een aparte route (§4.2)

  /// Breekt de lopende run af; het `done`-antwoord vertaalt dat naar
  /// [Cancelled], zodat de aanroeper geen "crash" te zien krijgt.
  @override
  void cancel() => _current?.kill();

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) async {
    final status = await this.status();
    if (status.support != LocalEngineSupport.ready) {
      throw EngineUnavailable(status.detail);
    }

    final wav = File(audio.path);
    if (!await wav.exists()) {
      throw const IoFailed('het audiobestand bestaat niet (meer)');
    }
    if (!wav.path.toLowerCase().endsWith('.wav')) {
      // §5.1 noot 1: WAV/PCM is de eenduidige basis; de bestandsbron
      // decodeert elke andere container vóór de engine (#2515) — komt er
      // toch iets anders binnen, dan is dit het eerlijke antwoord.
      throw const DecodeFailed('de lokale engine leest alleen PCM-WAV');
    }

    final modelPath = await _verifiedModelPath();

    // De uitvoer gaat naar een eigen map onder de app-support-staging, niet
    // naast de audio (die mag schrijfbeveiligd of van iemand anders zijn)
    // en niet in `/tmp` onder een radbare naam.
    final workDir = await _workDir();
    final outBase = p.join(
      workDir.path,
      'run-${DateTime.now().millisecondsSinceEpoch}',
    );

    final seconds = await _wavDurationSeconds(wav);
    final timeout = Duration(seconds: 90 + (seconds * 2).ceil());

    final run = _runner(
      resolveExecutable()!,
      [
        '-m',
        modelPath,
        '-l',
        options.language ?? 'auto',
        '-f',
        wav.path,
        '-oj',
        '-of',
        outBase,
        // Voortgang per verwerkt segment naar stderr (#2515) — de flow
        // toont hem; zonder callback kost de vlag niets.
        '-pp',
      ],
      environment: _hardenedEnv(workDir.path),
      timeout: timeout,
      onStderrLine: options.onProgress == null
          ? null
          : (line) {
              final m = _progressPattern.firstMatch(line);
              if (m != null) {
                options.onProgress!(int.parse(m.group(1)!) / 100);
              }
            },
    );
    _current = run;
    WhisperResult result;
    try {
      result = await run.done;
    } finally {
      _current = null;
    }

    if (result.killed) {
      await _cleanup(outBase);
      throw const Cancelled('de transcriptie is afgebroken');
    }
    if (result.timedOut) {
      await _cleanup(outBase);
      throw const EngineUnavailable('de helper overschreed de tijdslimiet');
    }
    if (result.exitCode != 0) {
      await _cleanup(outBase);
      final err = _cap(result.stderr, 800);
      if (err.contains('failed to allocate') || err.contains('out of memory')) {
        throw CapacityExceeded('het model past niet in het geheugen: $err');
      }
      throw EngineUnavailable('whisper-cli eindigde met een fout: $err');
    }

    final outFile = File('$outBase.json');
    if (!await outFile.exists()) {
      await _cleanup(outBase);
      throw const EngineUnavailable(
        'de helper eindigde netjes maar liet geen resultaat achter',
      );
    }
    final parsed = await _parseJson(await outFile.readAsString());
    await _cleanup(outBase);
    return parsed;
  }

  /// De vertrouwde plek van het model: containment via de store, daarna
  /// de hash — per sessie sleutel gecachet, maar elk bestand dat intussen
  /// veranderde wordt opnieuw volledig getoetst.
  Future<String> _verifiedModelPath() async {
    final path = (await _store.modelPath(_model)).path;
    if (await _store.stateOf(_model) == ModelInstallState.absent) {
      throw EngineUnavailable(
        'model ${_model.id} is niet geïnstalleerd — haal het binnen via '
        'Instellingen → Transcriptie',
      );
    }
    final file = File(path);
    final stat = await file.stat();
    final key = '$path:${stat.size}:${stat.modified.microsecondsSinceEpoch}';
    if (_verifiedKey != key) {
      if (!await _store.verify(_model)) {
        throw EngineUnavailable(
          'de SHA-256 van model ${_model.id} klopt niet met de catalogus — '
          'verwijder het model en haal het opnieuw binnen',
        );
      }
      _verifiedKey = key;
    }
    return path;
  }

  /// De werkmap voor uitvoer: app-support (privé) of een
  /// `mkdtemp`-terugval met onradelijke naam.
  Future<Directory> _workDir() async {
    if (_workDirOverride != null) {
      await _workDirOverride.create(recursive: true);
      return _workDirOverride;
    }
    try {
      final support = await getApplicationSupportDirectory();
      final dir = Directory(p.join(support.path, 'transcription', 'runs'));
      await dir.create(recursive: true);
      return dir;
    } on Object catch (e) {
      logWarning(
        'LocalWhisperEngine: geen app-support-map; tijdelijke runmap',
        e,
      );
      return Directory.systemTemp.createTemp('ocideck_whisper_');
    }
  }

  /// Waar `whisper-cli` zou moeten staan: `OCIDECK_WHISPER_CLI` voor
  /// dev/tests, anders naast het hoofdproces zoals de bundel hem plaatst.
  String? resolveExecutable() {
    final override = executable ?? Platform.environment['OCIDECK_WHISPER_CLI'];
    if (override != null && override.isNotEmpty) return override;
    final exeDir = File(Platform.resolvedExecutable).parent.path;
    if (Platform.isMacOS) {
      // <app>/Contents/MacOS/OciDeck → <app>/Contents/Helpers/whisper-cli
      return p.normalize(p.join(exeDir, '..', 'Helpers', 'whisper-cli'));
    }
    final name = Platform.isWindows ? 'whisper-cli.exe' : 'whisper-cli';
    return p.join(exeDir, name);
  }

  /// De omgeving waarin de helper draait — toelatingslijst, geen erfenis.
  /// whisper heeft alleen een tijdelijke map nodig (uitvoerbestanden) en op
  /// Windows de systeemvariabelen zonder welke het laden van DLL's faalt.
  Map<String, String> _hardenedEnv(String workDir) {
    const carriedPosix = {'TMPDIR'};
    const carriedWindows = {
      'PATHEXT',
      'SystemRoot',
      'SYSTEMROOT',
      'SystemDrive',
      'COMSPEC',
      'windir',
      'TEMP',
      'TMP',
    };
    final carried = Platform.isWindows ? carriedWindows : carriedPosix;
    return {
      for (final e in Platform.environment.entries)
        if (carried.contains(e.key)) e.key: e.value,
      // Parseerbare uitvoer: de meldingen en --help van de helper zijn
      // in C-locale voorspelbaar.
      'LC_ALL': 'C',
      // Een HOME die de helper nooit zou moeten gebruiken — maar schrijft
      // hij toch ergens naartoe, dan is het de werkmap en niet het huis
      // van de gebruiker.
      'HOME': workDir,
      if (Platform.isWindows) 'USERPROFILE': workDir,
    };
  }

  /// De WAV-header vertelt hoe lang de audio is — de tijdslimiet hangt
  /// eraan (RTF-metingen §7, met royale marge voor CPU-terugval).
  /// Leest alleen de eerste chunks; bij een onparseerbare header is de
  /// schatting op bestandsgrootte (16 kHz mono 16-bit ≈ 32 kB/s).
  static Future<double> _wavDurationSeconds(File wav) async {
    try {
      final header = await wav
          .openRead(0, 64 * 1024)
          .fold<BytesBuilder>(BytesBuilder(), (b, c) => b..add(c));
      final bytes = header.toBytes();
      if (bytes.length < 44 ||
          utf8.decode(bytes.sublist(0, 4)) != 'RIFF' ||
          utf8.decode(bytes.sublist(8, 12)) != 'WAVE') {
        return wav.lengthSync() / 32000;
      }
      var byteRate = 0;
      var dataBytes = 0;
      var off = 12;
      while (off + 8 <= bytes.length) {
        final id = utf8.decode(bytes.sublist(off, off + 4));
        final size = ByteData.sublistView(
          bytes,
          off + 4,
          off + 8,
        ).getUint32(0, Endian.little);
        if (id == 'fmt ' && size >= 16) {
          byteRate = ByteData.sublistView(
            bytes,
            off + 8 + 8,
            off + 8 + 12,
          ).getUint32(0, Endian.little);
        }
        if (id == 'data') {
          dataBytes = size;
          break;
        }
        off += 8 + size + (size.isOdd ? 1 : 0);
      }
      if (byteRate <= 0 || dataBytes <= 0) {
        return wav.lengthSync() / 32000;
      }
      return dataBytes / byteRate;
    } on Object {
      return wav.lengthSync() / 32000;
    }
  }

  /// De JSON die `-oj` schrijft: `transcription[]` met `offsets.from` (ms)
  /// en `text`. Onverwachte vorm is `EngineUnavailable` — nooit gokken.
  static Future<TranscriptResult> _parseJson(String source) async {
    try {
      final doc = jsonDecode(source);
      final list = (doc as Map<String, dynamic>)['transcription'];
      if (list is! List) throw const FormatException('geen transcription');
      final segments = <TranscriptSegment>[];
      for (final raw in list) {
        final map = raw as Map<String, dynamic>;
        final offsets = map['offsets'] as Map<String, dynamic>?;
        // whisper begint elk segment met een spatie — die draagt de
        // woordafstand naar het vorige segment en mag daarom niet weg.
        // Alleen de allereerste trimmen we: een lopende koptekst begint
        // niet met een spatie.
        final text = map['text'] as String? ?? '';
        segments.add(
          TranscriptSegment(
            text: segments.isEmpty ? text.trimLeft() : text,
            start: offsets?['from'] is num
                ? Duration(milliseconds: (offsets!['from'] as num).toInt())
                : null,
          ),
        );
      }
      return TranscriptResult(segments: segments);
    } on Object {
      throw const EngineUnavailable(
        'de uitvoer van de helper is niet te lezen',
      );
    }
  }

  /// Ruimt alleen de uitvoer van díe run op — `runs/` is een gedeelde map
  /// en een `rm -rf` daarop zou een naastliggende run meenemen.
  static Future<void> _cleanup(String outBase) async {
    try {
      final out = File('$outBase.json');
      if (await out.exists()) await out.delete();
    } on Object {
      // Opruimen mag een foutmelding nooit overschrijven.
    }
  }

  static String _cap(String s, int max) =>
      s.length <= max ? s : '${s.substring(0, max)}…';

  /// `progress = NN%` op stderr (whisper.cpp cli, `-pp` — één regel per
  /// verwerkt segment).
  static final _progressPattern = RegExp(r'progress =\s*(\d+)%');

  /// De echte start: één proces, argv-array, geen shell, begrensde pijpen
  /// en een `SIGKILL`-tijdslimiet — het patroon van git_cli_io._spawn.
  static WhisperRun _spawn(
    String executable,
    List<String> arguments, {
    Map<String, String>? environment,
    required Duration timeout,
    void Function(String line)? onStderrLine,
  }) {
    Process? process;
    var killed = false;

    Future<WhisperResult> run() async {
      final proc = process = await Process.start(
        executable,
        arguments,
        environment: environment,
        includeParentEnvironment: false,
        runInShell: false,
      );
      // Een `cancel()` die landde terwijl `Process.start` nog bezig was:
      // de vlag staat, het proces is er nu — alsnog afbreken.
      if (killed) proc.kill(ProcessSignal.sigkill);
      final out = _CappedCollector(_maxOutputBytes);
      final err = _CappedCollector(_maxOutputBytes);
      final outSub = proc.stdout.listen(out.add);
      // stderr doet dubbel werk: begrensd verzamelen voor foutdiagnose,
      // én regel-voor-regel doorleveren voor `-pp`-voortgang.
      var errCarry = '';
      final errSub = proc.stderr.listen((chunk) {
        err.add(chunk);
        if (onStderrLine != null) {
          errCarry += utf8.decode(chunk, allowMalformed: true);
          var idx = errCarry.indexOf('\n');
          while (idx >= 0) {
            onStderrLine(errCarry.substring(0, idx));
            errCarry = errCarry.substring(idx + 1);
            idx = errCarry.indexOf('\n');
          }
        }
      });
      final drained = Future.wait([
        outSub.asFuture<void>().catchError((Object _) {}),
        errSub.asFuture<void>().catchError((Object _) {}),
      ]);

      var timedOut = false;
      final killer = Timer(timeout, () {
        timedOut = true;
        proc.kill(ProcessSignal.sigkill);
      });

      final exitCode = await proc.exitCode;
      killer.cancel();
      if (await drained
          .then((_) => false)
          .timeout(_drainGrace, onTimeout: () => true)) {
        logWarning(
          'LocalWhisperEngine: uitvoer-pijp bleef open na einde helper',
        );
        unawaited(outSub.cancel());
        unawaited(errSub.cancel());
      }

      return WhisperResult(
        exitCode: exitCode,
        stdout: out.text,
        stderr: err.text,
        timedOut: timedOut,
        killed: killed,
      );
    }

    return WhisperRun(
      done: run(),
      kill: () {
        killed = true;
        // Het proces hoeft nog niet gestart te zijn; `Process.kill` op null
        // slaat dan niets en de run eindigt op zichzelf. `killed` staat in
        // beide gevallen — de aanroeper ziet Cancelled, geen crash.
        process?.kill(ProcessSignal.sigkill);
      },
    );
  }
}

/// Verzamelt bytes tot een cap; daarna telt hij door zonder te bewaren —
/// hetzelfde patroon als git_cli_io._CappedCollector.
class _CappedCollector {
  _CappedCollector(this.maxBytes);
  final int maxBytes;
  final BytesBuilder _builder = BytesBuilder(copy: false);
  var _dropped = false;

  void add(List<int> chunk) {
    if (_dropped) return;
    if (_builder.length + chunk.length > maxBytes) {
      _builder.add(chunk.sublist(0, maxBytes - _builder.length));
      _dropped = true;
    } else {
      _builder.add(chunk);
    }
  }

  String get text => utf8.decode(_builder.toBytes(), allowMalformed: true);
}

LocalWhisperEngine createLocalWhisperEngine({WhisperModel? model}) =>
    IoLocalWhisperEngine(model: model);
