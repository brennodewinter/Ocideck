// Desktop-microfoon achter [CaptureSource] (#2516, TRANSCRIPTION.md §4.1).
//
// De platformbinding levert bytes; dit bestand beslist wat een opname is:
// toestemming pas bij start, één houder van de microfoon, 16 kHz mono PCM
// in de stagingmap, stop bij bronverlies of een volle schijf. Dezelfde
// bytes gaan ook als live-blokken naar buiten; of daar tekst uit komt
// beslist de engine (#2522), niet deze bron.
import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'mic_session_gate.dart';
import 'pcm_resample.dart';
import 'transcription_errors.dart';
import 'wav_sink.dart';
import 'wav_sink_stub.dart' if (dart.library.io) 'wav_sink_io.dart' as wav_file;

/// Minimaal vrije ruimte vóór de microfoon open gaat. Minder dan dit en
/// we starten niet — een opname die meteen vastloopt is geen opname.
const minFreeBytesForRecording = 32 * 1024 * 1024;

typedef FreeBytes = Future<int?> Function(String directory);

class DesktopMicrophoneSource extends CaptureSource {
  DesktopMicrophoneSource({
    required this._port,
    required this._gate,
    required this._freeBytes,
    this.onLevel,
    this.minFreeBytes = minFreeBytesForRecording,
    this.maxRecordingBytes = maxRecordingWavBytes,
  }) : kind = CaptureSourceKind.microphone;

  /// Systeem- of appgeluid (#2518–#2520). Zelfde schrijfweg als de
  /// microfoon, zonder de microfoonpoort: dit is geen tweede mic-greep.
  DesktopMicrophoneSource.system({
    required this._port,
    required this._freeBytes,
    this.minFreeBytes = minFreeBytesForRecording,
    this.maxRecordingBytes = maxRecordingWavBytes,
  }) : _gate = null,
       onLevel = null,
       kind = CaptureSourceKind.systemAudio;

  final MicCapturePort _port;
  final MicSessionGate? _gate;
  final FreeBytes _freeBytes;
  final void Function(double level)? onLevel;
  final int minFreeBytes;
  final int maxRecordingBytes;

  @override
  final CaptureSourceKind kind;

  @override
  Future<CaptureAvailability> probe() async {
    final facts = await _port.describe();
    return facts.availability;
  }

  /// Dezelfde feiten als [probe], plus de apparaatlijst voor de kiezer.
  Future<MicPlatformFacts> describe() => _port.describe();

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    if (request.kinds.length != 1 || !request.kinds.contains(kind)) {
      throw UnsupportedSource(
        kind == CaptureSourceKind.microphone
            ? 'deze route neemt alleen de microfoon op, geen systeemgeluid'
            : 'deze route neemt alleen systeemgeluid op, niet de microfoon',
      );
    }
    final stagingDir = request.stagingDir;
    if (request.persistFile && (stagingDir == null || stagingDir.isEmpty)) {
      throw const IoFailed('geen stagingmap voor de opname');
    }
    final gate = _gate;
    if (gate != null && !gate.tryAcquire(MicHolder.recording)) {
      throw const SourceUnavailable(micHeldByMonitorMessage);
    }
    MicCaptureLive? live;
    try {
      if (request.persistFile && stagingDir != null) {
        final free = await _freeBytes(stagingDir);
        if (free != null && free < minFreeBytes) {
          throw const CapacityExceeded(
            'te weinig vrije schijfruimte om een opname te starten',
          );
        }
      }
      live = await _port.open(deviceId: request.inputDeviceId);
      wav_file.IncrementalWav? wav;
      if (request.persistFile && stagingDir != null) {
        wav = wav_file.IncrementalWav(
          p.join(stagingDir, recordingWavName),
          maxBytes: maxRecordingBytes,
        );
        await wav.open();
      }
      final session = _DesktopMicSession(
        live: live,
        wav: wav,
        gate: gate,
        onLevel: onLevel,
        kinds: {kind},
      );
      live = null;
      return session;
    } on TranscriptionError {
      await live?.stop();
      gate?.release(MicHolder.recording);
      rethrow;
    } on Object {
      await live?.stop();
      gate?.release(MicHolder.recording);
      throw const IoFailed('de opname kon niet worden gestart');
    }
  }
}

class _DesktopMicSession implements CaptureSession {
  _DesktopMicSession({
    required MicCaptureLive live,
    required wav_file.IncrementalWav? wav,
    required this._gate,
    required this._onLevel,
    required this._kinds,
  }) : _live = live,
       _wav = wav,
       durablePath = wav?.path ?? '',
       _liveOut = wav == null
           ? StreamController<AudioChunk>()
           : StreamController<AudioChunk>.broadcast() {
    _resampler = Mono16kResampler(
      sampleRate: live.format.sampleRate,
      channels: live.format.channels,
    );
    // Eén schrijver: frames komen sneller binnen dan de schijf ze wegzet,
    // en twee `add`s tegelijk zouden de header en de PCM door elkaar halen.
    _framesSub = live.frames.listen(
      (frame) {
        _queue.add(frame);
        if (!_draining) unawaited(_drain());
      },
      onError: (_) {
        if (!_stopping) _emit(CaptureEndCause.sourceLost);
      },
    );
    _endedSub = live.ended.listen((cause) {
      if (!_stopping) _emit(cause);
    });
  }

  final MicCaptureLive _live;
  final wav_file.IncrementalWav? _wav;
  final MicSessionGate? _gate;
  final void Function(double level)? _onLevel;
  final Set<CaptureSourceKind> _kinds;
  late final Mono16kResampler _resampler;
  late final StreamSubscription<MicPcmFrame> _framesSub;
  late final StreamSubscription<CaptureEndCause> _endedSub;

  final _ended = StreamController<CaptureEndCause>.broadcast();
  final StreamController<AudioChunk> _liveOut;
  var _emitted = Duration.zero;
  final _queue = <MicPcmFrame>[];
  var _draining = false;
  var _stopping = false;
  Future<RecordedAudio>? _stopFuture;
  var _lastLevel = Duration.zero;
  final _started = DateTime.now();

  @override
  final String durablePath;

  @override
  Stream<AudioChunk>? get liveChunks => _liveOut.stream;

  @override
  Stream<CaptureEndCause>? get ended => _ended.stream;

  void _emit(CaptureEndCause cause) {
    if (!_ended.isClosed) _ended.add(cause);
  }

  Future<void> _drain() async {
    _draining = true;
    try {
      while (_queue.isNotEmpty && !_stopping) {
        final frame = _queue.removeAt(0);
        final pcm = _resampler.add(frame.pcm);
        if (pcm.isEmpty) continue;
        _publishLevel(pcm);
        final offset = _wav?.duration ?? _emitted;
        try {
          final wav = _wav;
          if (wav != null) {
            await wav.add(pcm);
          } else {
            _emitted += Duration(
              microseconds: ((pcm.length ~/ 2) * 1000000 / recordingSampleRate)
                  .round(),
            );
          }
          if (!_liveOut.isClosed) {
            _liveOut.add(
              AudioChunk(bytes: Uint8List.fromList(pcm), offset: offset),
            );
          }
        } on IoFailed {
          _queue.clear();
          if (!_stopping) _emit(CaptureEndCause.storageFailed);
          return;
        }
      }
    } finally {
      _draining = false;
    }
  }

  void _publishLevel(Uint8List pcm) {
    final now = DateTime.now().difference(_started);
    if (now - _lastLevel < const Duration(milliseconds: 100)) return;
    _lastLevel = now;
    _onLevel?.call(pcmRms(pcm));
  }

  @override
  Future<RecordedAudio> stop() => _stopFuture ??= _stop();

  Future<RecordedAudio> _stop() async {
    _stopping = true;
    _queue.clear();
    await _framesSub.cancel();
    await _endedSub.cancel();
    // Wacht tot een lopende schrijfbeurt klaar is, anders sluiten we de
    // file onder een `add` die nog bezig is.
    while (_draining) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    try {
      await _live.stop();
    } on Object {
      // Het apparaat is al weg. De file telt, de uitzondering niet.
    }
    final wav = _wav;
    if (wav != null) {
      try {
        await wav.close();
      } on IoFailed {
        await wav_file.repairWavHeader(durablePath);
      }
    }
    _onLevel?.call(0);
    _gate?.release(MicHolder.recording);
    if (!_ended.isClosed) await _ended.close();
    if (!_liveOut.isClosed) await _liveOut.close();
    final duration = wav?.duration ?? _emitted;
    return RecordedAudio(
      durablePath: durablePath,
      duration: duration,
      kinds: _kinds,
    );
  }
}
