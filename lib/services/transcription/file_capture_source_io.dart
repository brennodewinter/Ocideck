// Desktophelft van de bestandsbron (#2515): PCM-WAV direct door, elke
// andere container via een gepinde platformdecoder naar een WAV in de
// sessie-staging.
//
// Decoderkeuze, bewust smal:
//  * macOS — `/usr/bin/afconvert`: bij het OS geleverd, vast absoluut pad
//    (geen PATH-raadsel), dekt WAV/AIFF/CAF/AAC/MP3/M4A en de audiotrack
//    van QuickTime/MP4-video;
//  * Linux/Windows — bundled ocideck-audio (GStreamer/Media Foundation);
//    optional legacy fallback: `ffmpeg` (`ffmpeg.exe`) on PATH:
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
import 'bundled_audio_helper_io.dart';
import 'file_capture_source.dart';
import 'media_sniff.dart';
import 'transcription_errors.dart';
import 'wav_reader_io.dart';

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
    final bundled = bundledAudioHelper();
    if (bundled != null) return bundled;
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

    final extension = p.extension(sourcePath);
    final container = sniffContainer(head, extension: extension);
    if (stat.size == 0) {
      throw const DecodeFailed('het bestand is leeg');
    }
    WavInfo? wav;
    if (container == MediaContainer.wav) {
      // De begrensde chunklezer seekt over metadata/FLLR-vulling heen —
      // de 256-kop van de sniffer is voor afconvert-uitvoer te kort
      // (#2933).
      final ra = await file.open();
      try {
        wav = await readWavInfo(ra, stat.size);
      } finally {
        await ra.close();
      }
      if (wav == null) {
        throw const DecodeFailed('WAV-header is beschadigd of onleesbaar');
      }
      if (wav.dataBytes == 0) {
        throw const DecodeFailed('het bestand bevat geen audiodata');
      }
      if (wav.formatTag == 1) {
        return FileSourceInfo(
          path: sourcePath,
          sizeBytes: stat.size,
          container: container,
          duration: wav.duration,
          engineReadsDirectly: true,
          decodable: true,
        );
      }
      // Geen PCM-WAV (float, extensible, gecomprimeerd): de engine
      // leest alleen PCM — via de decoder kan hij alsnog.
    }
    final decoder = await findDecoder();
    return FileSourceInfo(
      path: sourcePath,
      sizeBytes: stat.size,
      container: container,
      duration: wav?.duration,
      engineReadsDirectly: false,
      decodable: decoder != null,
      decodeNote: _describeNote(
        decoder: decoder,
        container: container,
        extension: extension,
        wav: wav,
      ),
    );
  }

  /// Diagnose voor de voorbeschouwing: welke naam/inhoud-botsing en
  /// welke onzekerheid er zit, niet gelokaliseerd.
  String? _describeNote({
    required String? decoder,
    required MediaContainer container,
    required String extension,
    required WavInfo? wav,
  }) {
    final parts = <String>[
      if (wav != null && wav.formatTag != 1)
        'de WAV is geen 16-bit PCM — decode nodig',
      if (_extensionContradicts(container, extension))
        'de bestandsnaam wijkt af van de gedetecteerde inhoud',
      if (decoder == null)
        Platform.isMacOS
            ? 'geen decoder op dit systeem (afconvert ontbreekt) — alleen PCM-WAV kan direct'
            : 'geen decoder op dit systeem (ffmpeg ontbreekt) — alleen PCM-WAV kan direct',
    ];
    return parts.isEmpty ? null : parts.join('; ');
  }

  /// Zegt de extensie iets anders dan de magische bytes? Dan is de naam
  /// geen betrouwbare gids — afconvert struikelt daar bijvoorbeeld over
  /// (#2934).
  static bool _extensionContradicts(
    MediaContainer container,
    String extension,
  ) {
    final implied = sniffContainer(Uint8List(0), extension: extension);
    return implied != MediaContainer.unknown && implied != container;
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
  ///
  /// `--no-filler` voorkomt dat afconvert een FLLR-paginavulling van
  /// enkele kB vóór de `data`-chunk zet (#2933); zonder die vlag schijnt
  /// de werkelijke audio buiten elke vaste kopleesgrens.
  List<String> _decoderArgs(String decoder, String inputPath, String outPath) {
    final base = p.basename(decoder).toLowerCase();
    if (base == 'ocideck-audio' || base == 'ocideck-audio.exe') {
      return ['--decode', inputPath, outPath];
    }
    if (base == 'afconvert') {
      return [
        '-f',
        'WAVE',
        '-d',
        'LEI16@16000',
        '-c',
        '1',
        '--no-filler',
        inputPath,
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
      inputPath,
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
  Map<String, String> _decoderEnv(String decoder) {
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
      if (Platform.isLinux)
        'LD_LIBRARY_PATH': p.join(p.dirname(decoder), 'lib'),
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

  /// afconvert kijkt mee naar de extensie: MP4-inhoud met een
  /// `.mp3`-naam faalt met de generieke open-fout `dta?`, terwijl
  /// dezelfde bytes als `.mp4` gewoon decoderen (#2934). Levert de
  /// canonieke extensie als naam en gesnuffelde inhoud botsen —
  /// anders null, dan is een kopie ook niet nodig.
  String? _afconvertCanonicalExt(String decoder) {
    if (p.basename(decoder).toLowerCase() != 'afconvert') return null;
    final canonical = switch (_info.container) {
      MediaContainer.mpeg4 => '.mp4',
      MediaContainer.mp3 => '.mp3',
      MediaContainer.flac => '.flac',
      MediaContainer.ogg => '.ogg',
      MediaContainer.wav => '.wav',
      MediaContainer.avi => '.avi',
      // ebml/unknown: geen afconvert-formaat waar een naam bij helpt.
      _ => null,
    };
    if (canonical == null) return null;
    final implied = sniffContainer(
      Uint8List(0),
      extension: p.extension(_info.path),
    );
    if (implied == _info.container) return null;
    return canonical;
  }

  /// Kopieert de bron onder een naam die wél bij de inhoud past naar
  /// de stagingmap. Gestreamd, zodat ook een 2 GiB-bron niet het
  /// geheugen in hoeft; het origineel blijft onaangeraakt.
  Future<String> _stageInputAs(String ext) async {
    final dst = p.join(_stagingDir, 'input$ext');
    try {
      await File(_info.path).openRead().pipe(File(dst).openWrite());
    } on Object catch (e) {
      try {
        await File(dst).delete();
      } on Object {
        // De halve kopie hoeft geen tweede fout op te leveren.
      }
      throw IoFailed(
        'de bron kon niet naar de stagingmap worden gekopieerd: $e',
      );
    }
    return dst;
  }

  Future<RecordedAudio> _decodeToWav() async {
    final decoder = decoderOverride ?? await _findDecoderForRun();
    if (decoder == null) {
      throw const UnsupportedSource(
        'geen decoder op dit systeem — alleen PCM-WAV kan direct',
      );
    }
    String? staged;
    try {
      var inputPath = _info.path;
      final canonicalExt = _afconvertCanonicalExt(decoder);
      if (canonicalExt != null) {
        staged = await _stageInputAs(canonicalExt);
        inputPath = staged;
      }
      final run = _runner(
        decoder,
        _decoderArgs(decoder, inputPath, durablePath),
        environment: _decoderEnv(decoder),
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
        if (result.exitCode == 3 &&
            p.basename(decoder).toLowerCase().startsWith('ocideck-audio')) {
          throw const DecodeFailed('de container bevat geen audiotrack');
        }
        throw _decodeError(decoder, result.stderr, stagedInput: staged);
      }
      return await _readResult();
    } finally {
      // De gerenommeerde invoer is wegwerpwerk — opruimen bij succes,
      // fout én annulering; het origineel blijft hoe dan ook staan.
      if (staged != null) await _deleteQuiet(staged);
    }
  }

  /// De uitkomst van een niet-nul-exit naar de juiste getypte fout —
  /// "geen audiotrack" is een andere uitspraak dan "corrupt", en de
  /// dialoog vertaalt ze verschillend (§4.4).
  TranscriptionError _decodeError(
    String decoder,
    String stderr, {
    String? stagedInput,
  }) {
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
    // afconvert geeft geen onderscheidende fout: `Couldn't open input
    // file ('dta?')` geldt evengoed voor een ontbrekende audiotrack als
    // voor een onleesbare container — "geen audiotrack" claimen is dan
    // een gok, dus blijft het bij een eerlijke decodeermelding plus een
    // geschoonde stderr-hint (#2934).
    final hint = _stderrHint(stderr, stagedInput);
    if (mayBeVideo(_info.container)) {
      return DecodeFailed(
        'de decoder kon geen audio uit deze container halen — '
        'er zit mogelijk geen audiotrack in, of de container is '
        'onleesbaar$hint',
      );
    }
    return DecodeFailed('de decoder kon het bestand niet lezen$hint');
  }

  /// stderr als compacte diagnose: één regel, begrensd, en zonder de
  /// paden van gebruiker of staging mee te nemen in een melding.
  String _stderrHint(String stderr, String? stagedInput) {
    var t = stderr.replaceAll(_info.path, '<bron>');
    if (stagedInput != null) t = t.replaceAll(stagedInput, '<invoer>');
    t = t
        .replaceAll(RegExp(r'(/[\w.\-]+){2,}/?'), '<pad>')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (t.isEmpty) return '';
    if (t.length > 140) t = '${t.substring(0, 140)}…';
    return ' ($t)';
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
    final WavInfo? wav;
    try {
      // Dezelfde begrensde chunklezer als describe: FLLR-vulling of
      // metadata vóór `data` is geen lege decode (#2933).
      wav = await readWavInfo(ra, size);
    } finally {
      await ra.close();
    }
    if (wav == null) {
      await _deletePartial();
      throw const DecodeFailed('de decoder schreef geen leesbare WAV-header');
    }
    if (wav.dataBytes <= 0) {
      await _deletePartial();
      throw const DecodeFailed('de decode leverde lege audio op');
    }
    if (wav.formatTag != 1) {
      await _deletePartial();
      throw const DecodeFailed('de decoder schreef geen PCM-WAV');
    }
    return RecordedAudio(
      durablePath: durablePath,
      duration: wav.duration,
      kinds: const {CaptureSourceKind.file},
    );
  }

  Future<void> _deletePartial() async => _deleteQuiet(durablePath);

  static Future<void> _deleteQuiet(String path) async {
    try {
      final f = File(path);
      if (await f.exists()) await f.delete();
    } on Object catch (e) {
      logWarning('FileCaptureSession: halve decode opruimen', e);
    }
  }

  /// Losse zoektocht voor `stop()` — `describe` zocht al, maar de bron
  /// mag niet vertrouwen op wat een eerdere stap zag.
  Future<String?> _findDecoderForRun() => IoFileCaptureSource().findDecoder();
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
