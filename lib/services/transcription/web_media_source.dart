// Webopname achter een browsergrens die tests kunnen vervangen (#2517,
// #2521). `probe` roept nooit `getUserMedia` of `getDisplayMedia` aan.
// Alleen `open` mag de browser om toestemming vragen.
//
// Firefox negeert audio bij schermdelen en Safari levert het niet. Die
// route blijft daar afwezig in plaats van een video zonder geluid.
import 'dart:async';
import 'dart:typed_data';

import '../web_asset_store.dart';
import 'capture_source.dart';
import 'mic_capture_port.dart';
import 'mic_session_gate.dart';
import 'transcription_errors.dart';

/// Diagnose wanneer een tabdeling geen audiospoor meegaf. De dialoog
/// vertaalt deze zin; ze verschijnt niet zelf in de interface.
const webDisplaySilentMessage = 'het tabblad deelde geen geluid';

/// Of een microfoon op deze pagina überhaupt gevraagd kan worden.
/// Geen aanroep naar de browser — de webhelft vult de vlaggen.
CaptureAvailability microphoneAvailability({
  required bool secure,
  required bool hasRecorder,
  required bool hasUserMedia,
}) {
  if (!secure || !hasRecorder || !hasUserMedia) {
    return CaptureAvailability.unavailable;
  }
  return CaptureAvailability.tryAfterPermission;
}

/// Tab- of schermgeluid. Chromium levert het; Firefox en Safari niet.
CaptureAvailability displayAvailability({
  required bool secure,
  required bool hasRecorder,
  required bool hasDisplayMedia,
  required String userAgent,
}) {
  if (!secure || !hasRecorder || !hasDisplayMedia) {
    return CaptureAvailability.unavailable;
  }
  if (userAgent.contains('Firefox')) return CaptureAvailability.unavailable;
  final safari =
      userAgent.contains('Safari') &&
      !userAgent.contains('Chrome') &&
      !userAgent.contains('Chromium') &&
      !userAgent.contains('Edg');
  if (safari) return CaptureAvailability.unavailable;
  return CaptureAvailability.tryAfterPermission;
}

/// Wat de pagina kan, zonder een apparaat te openen.
abstract class WebMediaBrowser {
  Future<CaptureAvailability> probeMicrophone();
  Future<CaptureAvailability> probeDisplay();
  Future<WebMediaLive> openMicrophone();
  Future<WebMediaLive> openDisplay();
}

class WebMediaLive {
  const WebMediaLive({
    required this.chunks,
    required this.mime,
    required this.stop,
  });

  final Stream<Uint8List> chunks;
  final String mime;
  final Future<void> Function() stop;
}

class WebMediaSource extends CaptureSource {
  WebMediaSource.microphone({required this._browser, this._gate})
    : _display = false,
      kind = CaptureSourceKind.microphone;

  WebMediaSource.display({required this._browser})
    : _gate = null,
      _display = true,
      kind = CaptureSourceKind.systemAudio;

  final WebMediaBrowser _browser;
  final MicSessionGate? _gate;
  final bool _display;

  @override
  final CaptureSourceKind kind;

  @override
  Future<CaptureAvailability> probe() =>
      _display ? _browser.probeDisplay() : _browser.probeMicrophone();

  @override
  Future<CaptureSession> start(CaptureRequest request) async {
    if (request.kinds.length != 1 || !request.kinds.contains(kind)) {
      throw UnsupportedSource(
        _display
            ? 'deze route neemt alleen tab- of schermgeluid op'
            : 'deze route neemt alleen de microfoon op',
      );
    }
    final gate = _gate;
    if (gate != null && !gate.tryAcquire(MicHolder.recording)) {
      throw const SourceUnavailable(micHeldByMonitorMessage);
    }
    try {
      final live = _display
          ? await _browser.openDisplay()
          : await _browser.openMicrophone();
      return _WebMediaSession(
        live: live,
        gate: gate,
        display: _display,
        kinds: {kind},
      );
    } on TranscriptionError {
      gate?.release(MicHolder.recording);
      rethrow;
    } on Object {
      gate?.release(MicHolder.recording);
      throw const SourceUnavailable('de browseropname kon niet starten');
    }
  }
}

class _WebMediaSession implements CaptureSession {
  _WebMediaSession({
    required WebMediaLive live,
    required this._gate,
    required this._display,
    required this._kinds,
  }) : _live = live,
       _started = DateTime.now() {
    _sub = live.chunks.listen(_chunks.add);
  }

  final WebMediaLive _live;
  final MicSessionGate? _gate;
  final bool _display;
  final Set<CaptureSourceKind> _kinds;
  final DateTime _started;
  final _chunks = <Uint8List>[];
  late final StreamSubscription<Uint8List> _sub;
  Future<RecordedAudio>? _stopFuture;

  @override
  String get durablePath => _storedPath ?? '';

  String? _storedPath;

  @override
  Stream<AudioChunk>? get liveChunks => null;

  @override
  Stream<CaptureEndCause>? get ended => null;

  @override
  Future<RecordedAudio> stop() => _stopFuture ??= _finish();

  Future<RecordedAudio> _finish() async {
    await _live.stop();
    await _sub.cancel();
    final bytes = _concat(_chunks);
    _gate?.release(MicHolder.recording);
    if (bytes.isEmpty) {
      throw SourceUnavailable(
        _display ? webDisplaySilentMessage : 'lege opname',
      );
    }
    final name = 'opname.${_extension(_live.mime)}';
    try {
      _storedPath = WebAssetStore.put(bytes, name: name);
    } on WebAssetBudgetExceeded {
      throw const CapacityExceeded(
        'de opname past niet in het browsergeheugen',
      );
    }
    return RecordedAudio(
      durablePath: _storedPath!,
      duration: DateTime.now().difference(_started),
      kinds: _kinds,
    );
  }
}

Uint8List _concat(List<Uint8List> parts) {
  var total = 0;
  for (final part in parts) {
    total += part.length;
  }
  final out = Uint8List(total);
  var offset = 0;
  for (final part in parts) {
    out.setRange(offset, offset + part.length, part);
    offset += part.length;
  }
  return out;
}

String _extension(String mime) {
  if (mime.contains('mp4')) return 'm4a';
  if (mime.contains('ogg')) return 'ogg';
  return 'webm';
}

/// Beschrijving voor de kiezer. `open` bestaat hier niet: de bron opent.
class WebMicPort extends MicCapturePort {
  const WebMicPort(this._browser);

  final WebMediaBrowser _browser;

  @override
  Future<MicPlatformFacts> describe() async {
    final availability = await _browser.probeMicrophone();
    return MicPlatformFacts(
      availability: availability,
      reason: availability == CaptureAvailability.unavailable
          ? 'geen bruikbare microfoon in deze browser'
          : null,
    );
  }

  @override
  Future<MicCaptureLive> open({String? deviceId}) {
    throw UnsupportedError('web opent de microfoon via de opnamebron');
  }
}
