// Desktophelft van de bestandsbron (#2515): PCM-WAV direct door, elke
// andere container via een gepinde platformdecoder naar een WAV in de
// sessie-staging.
//
// Decoderkeuze, bewust smal:
//  * macOS — `/usr/bin/afconvert`: bij het OS geleverd, vast absoluut pad
//    (geen PATH-raadsel), dekt WAV/AIFF/CAF/AAC/MP3/M4A en de audiotrack
//    van QuickTime/MP4-video;
//  * Linux/Windows — `ffmpeg` (`ffmpeg.exe`) als die op PATH staat:
//    aanwezigheid is opstelafhankelijk (§5.1 noot 4), dus `describe`
//    zegt eerlijk "alleen WAV" wanneer hij er niet is.
//
// Het bronbestand wordt nooit aangeraakt — de decoder leest, de staging
// vangt de uitvoer, en de bewaarkeuze bij Opslaan beslist pas over een
// kopie in `media/` (§3.2).
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../../utils/log.dart';
import 'capture_source.dart';
import 'file_capture_source.dart';
import 'media_sniff.dart';
import 'transcription_errors.dart';

class IoFileCaptureSource extends FileCaptureSource {
  IoFileCaptureSource({this.decoderOverride, this.decoderRunner = _runDecoder});

  /// Testinvoer: een vast decoderpad (of naam) dat de PATH-zoektocht
  /// vervangt, en een vervangbare processtarter.
  final String? decoderOverride;
  final DecoderRunner decoderRunner;

  @override
  CaptureSourceKind get kind => CaptureSourceKind.file;

  @override
  Future<CaptureAvailability> probe() async => CaptureAvailability.available;

  /// De gepinde decoder voor dit platform, of null als er geen staat.
  /// Alleen zoeken, nooit uitvoeren — `probe()`/`describe()` blijven
  /// passief (§4.1).
  Future<String?> findDecoder() async {
    if (decoderOverride != null) return decoderOverride;
    if (Platform.isMacOS) {
      const afconvert = '/usr/bin/afconvert';
      if (await File(afconvert).exists()) return afconvert;
      return null;
    }
    // ffmpeg via PATH — bewust geen uitvoering: alleen bestaanstoets.
    final pathVar = Platform.environment['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    for (final dir in pathVar.split(sep)) {
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, name);
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }

  @override
  Future<FileSourceInfo> describe(String sourcePath) async {
    final file = File(sourcePath);
    final FileStat stat;
    try {
      stat = await file.stat();
    } on Object catch (e) {
      throw IoFailed('bronbestand is niet leesbaar: $e');
    }
    if (stat.type == FileSystemEntityType.notFound) {
      throw const IoFailed('het gekozen bestand bestaat niet (meer)');
    }
    if (stat.size > maxFileSourceBytes) {
      throw const CapacityExceeded(
        'het bestand overschrijdt de invoergrens van 2 GiB',
      );
    }
    final Uint8List head;
    try {
      final ra = await file.open();
      try {
        head = Uint8List.fromList(await ra.read(sniffHeadBytes));
      } finally {
        await ra.close();
      }
    } on Object catch (e) {
      throw IoFailed('bronbestand is niet leesbaar: $e');
    }

    final container = sniffContainer(head, extension: p.extension(sourcePath));
    if (stat.size == 0) {
      throw const DecodeFailed('het bestand is leeg');
    }
    if (container == MediaContainer.wav) {
      final info = parseWavHeader(head, stat.size);
      if (info == null) {
        throw const DecodeFailed('WAV-header is beschadigd of onleesbaar');
      }
      return FileSourceInfo(
        path: sourcePath,
        sizeBytes: stat.size,
        container: container,
        duration: info.duration,
        engineReadsDirectly: true,
        decodable: true,
      );
    }
    final decoder = await findDecoder();
    return FileSourceInfo(
      path: sourcePath,
      sizeBytes: stat.size,
      container: container,
      engineReadsDirectly: false,
      decodable: decoder != null,
      decodeNote: decoder == null
          ? Platform.isMacOS
                ? 'geen decoder op dit systeem (afconvert ontbreekt) — alleen PCM-WAV kan direct'
                : 'geen decoder op dit systeem (ffmpeg ontbreekt) — alleen PCM-WAV kan direct'
          : null,
    );
  }

  @override
  Future<FileCaptureSession> start(CaptureRequest request) async {
    if (request.kinds.length != 1 ||
        request.kinds.single != CaptureSourceKind.file) {
      throw const UnsupportedSource(
        'de bestandsbron kent alleen {file} als invoer',
      );
    }
    final sourcePath = request.sourcePath;
    if (sourcePath == null || sourcePath.isEmpty) {
      throw const IoFailed('geen bronbestand meegegeven');
    }
    final info = await describe(sourcePath);
    if (!info.engineReadsDirectly && !info.decodable) {
      throw UnsupportedSource(
        info.decodeNote ?? 'geen decoder voor dit formaat',
      );
    }
    final stagingDir =
        request.stagingDir ??
        (await Directory.systemTemp.createTemp('ocideck_file_')).path;
    return IoFileCaptureSession._(
      info: info,
      stagingDir: stagingDir,
      decoderOverride: decoderOverride,
      runner: decoderRunner,
    );
  }
}

/// Uitkomst van één decoderrun — spiegel van `WhisperResult`.
class DecodeResult {
  const DecodeResult({
    required this.exitCode,
    required this.stderr,
    this.timedOut = false,
    this.killed = false,
  });

  final int exitCode;
  final String stderr;
  final bool timedOut;
  final bool killed;
}

/// De vervangbare processtarter voor tests — zelfde vorm als
/// `WhisperRunner` in local_whisper_engine_io.
typedef DecoderRunner =
    DecodeRun Function(
      String executable,
      List<String> arguments, {
      Map<String, String>? environment,
      required Duration timeout,
    });

class DecodeRun {
  const DecodeRun({required this.done, required this.kill});

  final Future<DecodeResult> done;
  final void Function() kill;
}

class IoFileCaptureSession extends FileCaptureSession {
  IoFileCaptureSession._({
    required FileSourceInfo info,
    required String stagingDir,
    required this.decoderOverride,
    required this._runner,
  }) : _info = info,
       _stagingDir = stagingDir {
    durablePath = info.engineReadsDirectly
        ? info.path
        : p.join(stagingDir, 'input.wav');
  }

  final FileSourceInfo _info;
  final String _stagingDir;
  final String? decoderOverride;
  final DecoderRunner _runner;

  DecodeRun? _decode;
  Future<RecordedAudio>? _stopping;
  var _cancelled = false;

  /// Decode is maximaal tien minuten — ruim voor wat afconvert/ffmpeg aan
  /// uren audio doen, krap genoeg om een vastloper af te schieten.
  static const _decodeTimeout = Duration(minutes: 10);

  static const _maxStderrBytes = 64 * 1024;

  @override
  late final String durablePath;

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => null;

  /// Breekt de lopende decode af — het proces krijgt `SIGKILL` en
  /// [stop] eindigt in [Cancelled].
  @override
  void cancel() {
    _cancelled = true;
    _decode?.kill();
  }

  @override
  Future<RecordedAudio> stop() {
    // Idempotent: een tweede stop() krijgt dezelfde toekomst, nooit een
    // tweede decode.
    return _stopping ??= _run();
  }

  Future<RecordedAudio> _run() async {
    return _info.engineReadsDirectly ? _passthrough() : await _decodeToWav();
  }

  /// WAV refereert, kopieert niet — het origineel blijft waar hij ligt.
  RecordedAudio _passthrough() {
    if (_cancelled) throw const Cancelled('de taak is afgebroken');
    return RecordedAudio(
      durablePath: _info.path,
      duration: _info.duration ?? Duration.zero,
      kinds: const {CaptureSourceKind.file},
    );
  }

  /// Argv voor de gepinde decoder: vaste vlaggen, uitvoer 16 kHz mono
  /// 16-bit-WAV — precies wat elke engine-route spreekt (§5.1 noot 1).
  List<String> _decoderArgs(String decoder, String outPath) {
    final base = p.basename(decoder).toLowerCase();
    if (base == 'afconvert') {
      return [
        '-f',
        'WAVE',
        '-d',
        'LEI16@16000',
        '-c',
        '1',
        _info.path,
        outPath,
      ];
    }
    // ffmpeg: alleen de eerste audiotrack; mist die, dan eindigt hij op
    // "matches no streams" — dé uitspraak "video zonder audio".
    return [
      '-nostdin',
      '-v',
      'error',
      '-y',
      '-i',
      _info.path,
      '-map',
      '0:a:0',
      '-vn',
      '-ac',
      '1',
      '-ar',
      '16000',
      '-f',
      'wav',
      outPath,
    ];
  }

  /// Dezelfde toelatingslijst als de whisper-helper: alleen wat een
  /// decoder legitiem nodig heeft (tijdelijke map, op Windows de
  /// systeemvariabelen voor DLL-lading) — geen erfenis.
  Map<String, String> _decoderEnv() {
    const carriedWindows = {
      'PATHEXT',
      'SystemRoot',
      'SYSTEMROOT',
      'SystemDrive',
      'COMSPEC',
      'windir',
    };
    final env = <String, String>{
      'LC_ALL': 'C',
      'HOME': _stagingDir,
      if (!Platform.isWindows) 'TMPDIR': _stagingDir,
      if (Platform.isWindows) ...{
        'USERPROFILE': _stagingDir,
        'TEMP': _stagingDir,
        'TMP': _stagingDir,
      },
    };
    if (Platform.isWindows) {
      for (final e in Platform.environment.entries) {
        if (carriedWindows.contains(e.key)) env[e.key] = e.value;
      }
    }
    return env;
  }

  Future<RecordedAudio> _decodeToWav() async {
    final decoder = decoderOverride ?? await _findDecoderForRun();
    if (decoder == null) {
      throw const UnsupportedSource(
        'geen decoder op dit systeem — alleen PCM-WAV kan direct',
      );
    }
    final run = _runner(
      decoder,
      _decoderArgs(decoder, durablePath),
      environment: _decoderEnv(),
      timeout: _decodeTimeout,
    );
    _decode = run;
    DecodeResult result;
    try {
      result = await run.done;
    } finally {
      _decode = null;
    }

    if (result.killed || _cancelled) {
      await _deletePartial();
      throw const Cancelled('de decode is afgebroken');
    }
    if (result.timedOut) {
      await _deletePartial();
      throw const EngineUnavailable('de decoder overschreed de tijdslimiet');
    }
    if (result.exitCode != 0) {
      await _deletePartial();
      throw _decodeError(decoder, result.stderr);
    }
    return _readResult();
  }

  /// De uitkomst van een niet-nul-exit naar de juiste getypte fout —
  /// "geen audiotrack" is een andere uitspraak dan "corrupt", en de
  /// dialoog vertaalt ze verschillend (§4.4).
  TranscriptionError _decodeError(String decoder, String stderr) {
    final text = stderr.toLowerCase();
    final ffmpeg = p.basename(decoder).toLowerCase().startsWith('ffmpeg');
    if (ffmpeg && text.contains('matches no streams')) {
      return const DecodeFailed('de container bevat geen audiotrack');
    }
    if (ffmpeg &&
        (text.contains('invalid data') ||
            text.contains('moov atom not found') ||
            text.contains('end of file'))) {
      return const DecodeFailed('het bestand is beschadigd of afgebroken');
    }
    // afconvert meldt "no audio" en corruptie niet met vaste strings;
    // de container mag video zijn — dan is een mislukte decode de
    // eerlijkste uitspraak "geen bruikbare audiotrack".
    if (mayBeVideo(_info.container)) {
      return const DecodeFailed(
        'geen decodeerbare audiotrack in deze container',
      );
    }
    return DecodeFailed('de decoder kon het bestand niet lezen');
  }

  /// Controle na de decode: het WAV-resultaat bestaat, blijft onder de
  /// duurgrens en draagt een leesbare header.
  Future<RecordedAudio> _readResult() async {
    final out = File(durablePath);
    if (!await out.exists()) {
      throw const DecodeFailed('de decoder liet geen uitvoer achter');
    }
    final size = await out.length();
    if (size > maxDecodedWavBytes) {
      await _deletePartial();
      throw const CapacityExceeded(
        'de gedecodeerde audio overschrijdt de duurgrens',
      );
    }
    final ra = await out.open();
    final Uint8List head;
    try {
      head = Uint8List.fromList(await ra.read(sniffHeadBytes));
    } finally {
      await ra.close();
    }
    final wav = parseWavHeader(head, size);
    if (wav == null || wav.duration <= Duration.zero) {
      await _deletePartial();
      throw const DecodeFailed('de decode leverde lege audio op');
    }
    return RecordedAudio(
      durablePath: durablePath,
      duration: wav.duration,
      kinds: const {CaptureSourceKind.file},
    );
  }

  Future<void> _deletePartial() async {
    try {
      final out = File(durablePath);
      if (await out.exists()) await out.delete();
    } on Object catch (e) {
      logWarning('FileCaptureSession: halve decode opruimen', e);
    }
  }

  /// Losse zoektocht voor `stop()` — `describe` zocht al, maar de bron
  /// mag niet vertrouwen op wat een eerdere stap zag.
  Future<String?> _findDecoderForRun() async {
    if (Platform.isMacOS) {
      const afconvert = '/usr/bin/afconvert';
      if (await File(afconvert).exists()) return afconvert;
      return null;
    }
    final pathVar = Platform.environment['PATH'] ?? '';
    final sep = Platform.isWindows ? ';' : ':';
    final name = Platform.isWindows ? 'ffmpeg.exe' : 'ffmpeg';
    for (final dir in pathVar.split(sep)) {
      if (dir.isEmpty) continue;
      final candidate = p.join(dir, name);
      if (await File(candidate).exists()) return candidate;
    }
    return null;
  }
}

/// De echte start van de decoder — hetzelfde patroon als
/// local_whisper_engine_io._spawn: argv-array, geen shell, uitgeklede
/// omgeving, begrensde stderr en een `SIGKILL`-tijdslimiet.
DecodeRun _runDecoder(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
  required Duration timeout,
}) {
  Process? process;
  var killed = false;

  Future<DecodeResult> run() async {
    final proc = process = await Process.start(
      executable,
      arguments,
      environment: environment,
      includeParentEnvironment: false,
      runInShell: false,
    );
    if (killed) proc.kill(ProcessSignal.sigkill);
    final err = BytesBuilder(copy: false);
    var errDropped = false;
    final errSub = proc.stderr.listen((chunk) {
      if (errDropped) return;
      err.add(chunk);
      if (err.length > IoFileCaptureSession._maxStderrBytes) {
        errDropped = true;
      }
    });
    // stdout mag geen vastloper worden: afzuigen en weggooien.
    final outSub = proc.stdout.listen((_) {});
    final drained = Future.wait([
      errSub.asFuture<void>().catchError((Object _) {}),
      outSub.asFuture<void>().catchError((Object _) {}),
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
        .timeout(const Duration(seconds: 2), onTimeout: () => true)) {
      unawaited(errSub.cancel());
      unawaited(outSub.cancel());
    }
    return DecodeResult(
      exitCode: exitCode,
      stderr: utf8.decode(err.toBytes(), allowMalformed: true),
      timedOut: timedOut,
      killed: killed,
    );
  }

  return DecodeRun(
    done: run(),
    kill: () {
      killed = true;
      process?.kill(ProcessSignal.sigkill);
    },
  );
}

FileCaptureSource createFileCaptureSource() => IoFileCaptureSource();
