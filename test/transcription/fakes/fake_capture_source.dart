// Een scriptbare fake achter het capture-contract uit
// docs/design/TRANSCRIPTION.md §4.1 — dezelfde rol als FakeMeetingProvider
// voor de vergadergrens. Hiermee kan de sessiegrens uit #2510 elke eindweg
// bewijzen (Stop, bronverlies, ingetrokken toestemming) zonder één echt
// apparaat, één toestemmingsprompt of één byte audio.
//
// Hij woont onder test/ bewust: een test-double, geen geleverde bron —
// er kan dus nooit "per ongeluk" een nepopname in productie starten.
import 'dart:async';

import 'package:ocideck/services/transcription/capture_source.dart';

/// Een [CaptureSource] die zijn [probe]-antwoord vasthoudt en zijn
/// [start] gedraagt zoals de test voorschrijft.
class FakeCaptureSource implements CaptureSource {
  FakeCaptureSource({
    this.kind = CaptureSourceKind.microphone,
    this.availability = CaptureAvailability.available,
  });

  /// Gooi een getypte fout uit `start()` (bijv. [PermissionDenied]).
  Object? startError;

  /// Wat de laatste `start()` meekreeg — de toets van het
  /// staging/consent-contract.
  CaptureRequest? lastRequest;

  /// De laatst gestarte sessie, om `loseSource()`/`revokePermission()` op
  /// te sturen.
  FakeCaptureSession? lastSession;

  @override
  final CaptureSourceKind kind;

  /// Wat [probe] teruggeeft.
  CaptureAvailability availability;

  int startCalls = 0;

  @override
  Future<CaptureAvailability> probe() async => availability;

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    startCalls++;
    lastRequest = request;
    final error = startError;
    if (error != null) throw error;
    return lastSession = FakeCaptureSession(request);
  }
}

/// Een lopende fake-capture. `stop()` telt zijn aanroepen — "de track
/// stopt precies eenmaal" is zo aantoonbaar.
class FakeCaptureSession implements CaptureSession {
  FakeCaptureSession(this._request);

  final CaptureRequest _request;
  final _ended = StreamController<CaptureEndCause>.broadcast();
  final _live = StreamController<AudioChunk>.broadcast();

  bool stopped = false;
  int stopCalls = 0;

  /// Gooi een fout uit [stop] — het `failed`-pad van de sessiegrens.
  Object? stopError;

  /// Of deze sessie een `ended`-stroom heeft (een bestand kent er geen).
  bool emitsEnded = true;

  /// De duur die [stop] rapporteert; testbaar zonder echt te wachten.
  Duration recordedDuration = const Duration(seconds: 3);

  @override
  String get durablePath => '${_request.stagingDir ?? 'mem'}/opname.wav';

  @override
  Stream<AudioChunk>? get liveChunks => _live.stream;

  @override
  Stream<CaptureEndCause>? get ended => emitsEnded ? _ended.stream : null;

  @override
  Future<RecordedAudio> stop() async {
    stopCalls++;
    if (stopped) {
      // Idempotent zoals het contract eist: dezelfde uitslag, geen tweede
      // afbraak van dezelfde track.
      return _result();
    }
    stopped = true;
    await _live.close();
    await _ended.close();
    final error = stopError;
    if (error != null) throw error;
    return _result();
  }

  RecordedAudio _result() => RecordedAudio(
    durablePath: durablePath,
    duration: recordedDuration,
    kinds: _request.kinds,
  );

  // ── test helpers ──────────────────────────────────────────────────────

  /// De bron verdwijnt van buitenaf (apparaat weg, tab dicht).
  void loseSource() => _ended.add(CaptureEndCause.sourceLost);

  /// Het platform trekt de toestemming in terwijl de opname loopt.
  void revokePermission() => _ended.add(CaptureEndCause.permissionRevoked);

  /// De schijf hield verdere audio tegen.
  void failStorage() => _ended.add(CaptureEndCause.storageFailed);
}
