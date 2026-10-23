// Microfoon én systeemgeluid in één bestand (#2516-vervolg, §2.2).
//
// De twee bronnen openen elk hun eigen apparaat. Deze bron schrijft het
// bestand: links de microfoon, rechts het systeemgeluid, 16 kHz. Een
// kindbron krijgt `persistFile: false`, anders zouden er drie bestanden
// ontstaan. De microfoonpoort blijft bij het kind — geen tweede greep.
import 'dart:async';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import 'capture_source.dart';
import 'transcription_errors.dart';
import 'wav_sink.dart';
import 'wav_sink_stub.dart' if (dart.library.io) 'wav_sink_io.dart' as wav_file;

class CombinationSource extends CaptureSource {
  CombinationSource({required this._microphone, required this._systemAudio});

  final CaptureSource _microphone;
  final CaptureSource _systemAudio;

  @override
  CaptureSourceKind get kind => CaptureSourceKind.combination;

  @override
  Future<CaptureAvailability> probe() async {
    final mic = await _microphone.probe();
    final system = await _systemAudio.probe();
    if (mic == CaptureAvailability.unavailable ||
        system == CaptureAvailability.unavailable) {
      return CaptureAvailability.unavailable;
    }
    if (mic == CaptureAvailability.untested ||
        system == CaptureAvailability.untested) {
      return CaptureAvailability.untested;
    }
    if (mic == CaptureAvailability.tryAfterPermission ||
        system == CaptureAvailability.tryAfterPermission) {
      return CaptureAvailability.tryAfterPermission;
    }
    return CaptureAvailability.available;
  }

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    const expected = {
      CaptureSourceKind.microphone,
      CaptureSourceKind.systemAudio,
    };
    if (request.kinds.length != expected.length ||
        !request.kinds.containsAll(expected)) {
      throw const UnsupportedSource(
        'een combinatie neemt microfoon en systeemgeluid samen op',
      );
    }
    final stagingDir = request.stagingDir;
    if (stagingDir == null || stagingDir.isEmpty) {
      throw const IoFailed('geen stagingmap voor de opname');
    }
    final mic = await _microphone.start(
      CaptureRequest(
        kinds: const {CaptureSourceKind.microphone},
        consent: request.consent,
        stagingDir: stagingDir,
        inputDeviceId: request.inputDeviceId,
        persistFile: false,
      ),
    );
    final CaptureSession system;
    try {
      system = await _systemAudio.start(
        CaptureRequest(
          kinds: const {CaptureSourceKind.systemAudio},
          consent: request.consent,
          stagingDir: stagingDir,
          persistFile: false,
        ),
      );
    } on Object {
      await mic.stop();
      rethrow;
    }
    if (mic.liveChunks == null || system.liveChunks == null) {
      await mic.stop();
      await system.stop();
      throw const SourceUnavailable('deze bronnen leveren geen losse kanalen');
    }
    final wav = wav_file.IncrementalWav(
      p.join(stagingDir, recordingWavName),
      channels: 2,
    );
    await wav.open();
    return _CombinationSession(mic: mic, system: system, wav: wav);
  }
}

class _CombinationSession implements CaptureSession {
  _CombinationSession({
    required CaptureSession mic,
    required CaptureSession system,
    required wav_file.IncrementalWav wav,
  }) : _mic = mic,
       _system = system,
       _wav = wav,
       durablePath = wav.path {
    _micSub = mic.liveChunks!.listen((chunk) {
      _left.addAllBytes(chunk);
      unawaited(_pump());
    });
    _systemSub = system.liveChunks!.listen((chunk) {
      _right.addAllBytes(chunk);
      unawaited(_pump());
    });
    _micEnded = mic.ended?.listen((cause) {
      _micDone = cause;
      unawaited(_pump());
    });
    _systemEnded = system.ended?.listen((cause) {
      _systemDone = cause;
      unawaited(_pump());
    });
  }

  final CaptureSession _mic;
  final CaptureSession _system;
  final wav_file.IncrementalWav _wav;
  final _left = _PcmBuffer();
  final _right = _PcmBuffer();
  final _ended = StreamController<CaptureEndCause>.broadcast();
  final _liveOut = StreamController<AudioChunk>.broadcast();
  late final StreamSubscription<AudioChunk> _micSub;
  late final StreamSubscription<AudioChunk> _systemSub;
  StreamSubscription<CaptureEndCause>? _micEnded;
  StreamSubscription<CaptureEndCause>? _systemEnded;
  CaptureEndCause? _micDone;
  CaptureEndCause? _systemDone;
  var _pumping = false;
  var _stopping = false;
  Future<RecordedAudio>? _stopFuture;

  @override
  final String durablePath;

  @override
  Stream<AudioChunk>? get liveChunks => _liveOut.stream;

  @override
  Stream<CaptureEndCause>? get ended => _ended.stream;

  Future<void> _pump() async {
    if (_pumping || _stopping) return;
    _pumping = true;
    try {
      while (!_stopping) {
        final frames = _pairFrames();
        if (frames == 0) break;
        final stereo = _interleave(frames);
        final offset = _wav.duration;
        try {
          await _wav.add(stereo);
        } on IoFailed {
          if (!_ended.isClosed) _ended.add(CaptureEndCause.storageFailed);
          return;
        }
        if (!_liveOut.isClosed) {
          _liveOut.add(AudioChunk(bytes: _mixdown(stereo), offset: offset));
        }
      }
      if (_micDone != null && _systemDone != null && !_stopping) {
        if (!_ended.isClosed) {
          _ended.add(
            _micDone == CaptureEndCause.storageFailed
                ? _micDone!
                : _systemDone!,
          );
        }
      }
    } finally {
      _pumping = false;
      // Alleen opnieuw als er écht een paar te schrijven is. Eén kant
      // met data en de andere nog niet is geen werk — anders roept
      // `_pump` zichzelf synchroon aan tot de stapel vol is.
      if (!_stopping && _canPair) unawaited(_pump());
    }
  }

  bool get _canPair =>
      (_left.frames > 0 && _right.frames > 0) ||
      (_micDone != null && _right.frames > 0) ||
      (_systemDone != null && _left.frames > 0);

  int _pairFrames() {
    final ready = _left.frames < _right.frames ? _left.frames : _right.frames;
    if (ready > 0) return ready;
    if (_micDone != null && _right.frames > 0) {
      _left.pad(_right.frames);
      return _right.frames;
    }
    if (_systemDone != null && _left.frames > 0) {
      _right.pad(_left.frames);
      return _left.frames;
    }
    return 0;
  }

  Uint8List _interleave(int frames) {
    final out = Uint8List(frames * 4);
    final view = ByteData.sublistView(out);
    for (var i = 0; i < frames; i++) {
      view.setInt16(i * 4, _left.take(), Endian.little);
      view.setInt16(i * 4 + 2, _right.take(), Endian.little);
    }
    return out;
  }

  Uint8List _mixdown(Uint8List stereo) {
    final src = ByteData.sublistView(stereo);
    final frames = stereo.length ~/ 4;
    final out = Uint8List(frames * 2);
    final dst = ByteData.sublistView(out);
    for (var i = 0; i < frames; i++) {
      final left = src.getInt16(i * 4, Endian.little);
      final right = src.getInt16(i * 4 + 2, Endian.little);
      dst.setInt16(i * 2, (left + right) ~/ 2, Endian.little);
    }
    return out;
  }

  @override
  Future<RecordedAudio> stop() => _stopFuture ??= _stop();

  Future<RecordedAudio> _stop() async {
    _stopping = true;
    await _micSub.cancel();
    await _systemSub.cancel();
    await _micEnded?.cancel();
    await _systemEnded?.cancel();
    while (_pumping) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
    await _mic.stop();
    await _system.stop();
    try {
      await _wav.close();
    } on IoFailed {
      await wav_file.repairWavHeader(durablePath);
    }
    if (!_ended.isClosed) await _ended.close();
    if (!_liveOut.isClosed) await _liveOut.close();
    return RecordedAudio(
      durablePath: durablePath,
      duration: _wav.duration,
      kinds: const {
        CaptureSourceKind.microphone,
        CaptureSourceKind.systemAudio,
      },
    );
  }
}

class _PcmBuffer {
  final _bytes = <int>[];
  var _read = 0;

  int get frames => (_bytes.length - _read) ~/ 2;

  void addAllBytes(AudioChunk chunk) {
    if (_read > 4096 && _read * 2 > _bytes.length) {
      _bytes.removeRange(0, _read);
      _read = 0;
    }
    _bytes.addAll(chunk.bytes);
  }

  void pad(int frames) {
    final missing = frames - this.frames;
    if (missing <= 0) return;
    _bytes.addAll(List<int>.filled(missing * 2, 0));
  }

  int take() {
    final lo = _bytes[_read];
    final hi = _bytes[_read + 1];
    _read += 2;
    final value = lo | (hi << 8);
    return value >= 0x8000 ? value - 0x10000 : value;
  }
}
