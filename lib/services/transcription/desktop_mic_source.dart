// Desktop-microfoon achter [CaptureSource] (#2516, TRANSCRIPTION.md §4.1).
//
// De platformbinding levert bytes; dit bestand beslist wat een opname is:
// toestemming pas bij start, één houder van de microfoon, 16 kHz mono PCM
// in de stagingmap, stop bij bronverlies of een volle schijf. Dezelfde
// bytes gaan ook als live-blokken naar buiten; of daar tekst uit komt
// beslist de engine (#2522), niet deze bron.
import 'dart:async';
import 'dart:collection';
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

/// Harde grens aan ontvangen PCM die op de schrijver wacht (geen stil verlies).
const maxQueuedRecordingBytes = 8 * 1024 * 1024;

typedef FreeBytes = Future<int?> Function(String directory);

class DesktopMicrophoneSource extends CaptureSource {
  DesktopMicrophoneSource({
    required this._port,
    required this._gate,
    required this._freeBytes,
    this.onLevel,
    this.minFreeBytes = minFreeBytesForRecording,
    this.maxRecordingBytes = maxRecordingWavBytes,
    this.maxQueuedBytes = maxQueuedRecordingBytes,
  }) : kind = CaptureSourceKind.microphone;

  /// Systeem- of appgeluid (#2518–#2520). Zelfde schrijfweg als de
  /// microfoon, zonder de microfoonpoort: dit is geen tweede mic-greep.
  DesktopMicrophoneSource.system({
    required this._port,
    required this._freeBytes,
    this.minFreeBytes = minFreeBytesForRecording,
    this.maxRecordingBytes = maxRecordingWavBytes,
    this.maxQueuedBytes = maxQueuedRecordingBytes,
  }) : _gate = null,
       onLevel = null,
       kind = CaptureSourceKind.systemAudio;

  final MicCapturePort _port;
  final MicSessionGate? _gate;
  final FreeBytes _freeBytes;
  final void Function(double level)? onLevel;
  final int minFreeBytes;
  final int maxRecordingBytes;
  final int maxQueuedBytes;

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
        maxQueuedBytes: maxQueuedBytes,
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
    required this.maxQueuedBytes,
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
        if (_stopping || _overflow != null) return;
        if (frame.pcm.length > maxQueuedBytes - _queuedBytes) {
          _overflow = const CapacityExceeded('opnamebuffer vol');
          _emit(CaptureEndCause.storageFailed);
          return;
        }
        _queue.add(frame);
        _queuedBytes += frame.pcm.length;
        // Toewijzen vóór de drain start, ook als die zonder file synchroon loopt.
        _drainFuture ??= Future<void>.microtask(_drain);
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
  final _queue = Queue<MicPcmFrame>();
  final int maxQueuedBytes;
  var _queuedBytes = 0;
  Future<void>? _drainFuture;
  CapacityExceeded? _overflow;
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
    try {
      while (_queue.isNotEmpty) {
        final frame = _queue.removeFirst();
        _queuedBytes -= frame.pcm.length;
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
          _queuedBytes = 0;
          if (!_stopping) _emit(CaptureEndCause.storageFailed);
          return;
        }
      }
    } finally {
      _drainFuture = null;
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
    await _framesSub.cancel();
    await _endedSub.cancel();
    // Geen nieuwe invoer; schrijf alle reeds geaccepteerde frames af vóór close.
    await _drainFuture;
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
    final overflow = _overflow;
    if (overflow != null) throw overflow;
    final duration = wav?.duration ?? _emitted;
    return RecordedAudio(
      durablePath: durablePath,
      duration: duration,
      kinds: _kinds,
    );
  }
}
