// De opnamegrens uit #2510 (docs/design/TRANSCRIPTION.md §2.3, §3.2, §4.4).
//
// Eén plek die bezit wat "een opname loopt" betekent: hij start alleen na
// een bewuste `start()` met een [RecordingConsent] erin, hij is zichtbaar
// via [RecordingManager.active] vanaf de eerste seconde, en hij stopt
// aantoonbaar bij elke reden — Stop, module uit, toestemming weg, bron weg,
// app sluit. Omdat álle eindwegen door dezelfde [RecordingManager.stop]
// lopen, is "de track stopt" één bewijs in plaats van vijf losse beloftes.
import 'dart:async';

import '../../utils/log.dart';
import 'capture_source.dart';
import 'recording_staging.dart';
import 'transcription_errors.dart';

/// Waarom een opname eindigde. Elke waarde is een testbaar eindscenario
/// uit de acceptatie van #2510.
enum RecordingEndReason {
  /// De gebruiker drukte op Stop.
  userStop,

  /// De module werd uitgezet terwijl de opname liep.
  moduleDisabled,

  /// Het platform trok de toestemming in tijdens de opname.
  permissionLost,

  /// De bron viel weg: apparaat los, gedeelde tab dicht, sessie om.
  sourceLost,

  /// De app sloot. De staging blijft bestaan voor de herstelperiode (§3.2).
  appQuit,
}

/// Waar een lopende opname in zijn leven staat.
enum RecordingPhase {
  /// `start()` loopt — toestemming kan net worden gevraagd.
  starting,

  /// De capture schrijft.
  recording,

  /// `stop()` is onderweg; de duurzame file wordt afgerond.
  stopping,

  /// Netjes geëindigd; [RecordingHandle.result] staat klaar.
  ended,

  /// Iets faalde; [RecordingHandle.error] vertelt wat.
  failed,
}

/// Eén overgang in het leven van een opname — wat de indicator en de
/// toekomstige opslagflow opvolgen.
class RecordingEvent {
  const RecordingEvent({required this.phase, this.reason, this.error});

  final RecordingPhase phase;

  /// Bij `ended`/`failed`: waarom hij eindigde.
  final RecordingEndReason? reason;

  /// Bij `failed`: de getypte fout.
  final Object? error;
}

/// Het publieke gezicht van een lopende opname, zoals de indicator en de
/// provider hem zien. Alleen [RecordingManager] maakt hem; de buitenwereld
/// leest hem en roept [stop].
class RecordingHandle {
  RecordingHandle._(
    this._manager,
    this._capture,
    this.kinds,
    this.startedAt,
    this.stagingDir,
  );

  final RecordingManager _manager;
  final CaptureSession _capture;

  /// Welke bronnen deze opname voeden — de indicator toont ze.
  final Set<CaptureSourceKind> kinds;

  final DateTime startedAt;

  /// De stagingmap van deze sessie, of null op web (`mem:`-opslag).
  final String? stagingDir;

  final _events = StreamController<RecordingEvent>.broadcast();
  Stream<RecordingEvent> get events => _events.stream;

  RecordingPhase _phase = RecordingPhase.recording;
  RecordingPhase get phase => _phase;

  RecordedAudio? _result;

  /// Het duurzame resultaat na [RecordingPhase.ended]; anders null.
  RecordedAudio? get result => _result;

  Object? _error;

  /// De getypte fout na [RecordingPhase.failed]; anders null.
  Object? get error => _error;

  /// Looptijd voor de indicator: telt tijdens `recording`, bevriest bij
  /// `ended` op de duur die de capture rapporteerde.
  Duration get elapsed =>
      _result?.duration ?? DateTime.now().difference(startedAt);

  /// Stagingpad dat de capture wegschrijft (`mem:`-sleutel op web).
  String get durablePath => _capture.durablePath;

  /// Stop — dezelfde weg als elke andere reden, met [userStop] als
  /// toedracht. Idempotent net als [CaptureSession.stop].
  Future<void> stop() => _manager.stop(RecordingEndReason.userStop);

  void _emit(RecordingEvent e) => _events.add(e);
  void _close() => unawaited(_events.close());
}

/// Bezit de enige lopende opname van de app (er is er nooit meer dan één —
/// één indicator, één set tracks, één duurzaam bestand) en elke weg waarop
/// die eindigt.
class RecordingManager {
  RecordingManager({RecordingStaging? staging})
    : _staging = staging ?? createRecordingStaging();

  final RecordingStaging _staging;

  RecordingHandle? _active;
  StreamSubscription<CaptureEndCause>? _endedSub;

  /// De lopende opname, of null. De indicator bestaat precies zo lang als
  /// dit object bestaat — zichtbaarheid is dus geen vlag om te vergeten
  /// maar een gevolg van de staat zelf (§2.3).
  RecordingHandle? get active => _active;

  /// Start een opname. Faalt vóór er iets draait als de toestemming voor
  /// deze bronnen niet klopt, of als er al een opname loopt.
  Future<RecordingHandle> start(
    CaptureSource source, {
    required Set<CaptureSourceKind> kinds,
    required RecordingConsent consent,
    String? sourcePath,
  }) async {
    if (_active != null) {
      throw StateError('Er loopt al een opname');
    }
    // §2.3: bronnen die per constructie andermans stemmen vastleggen mogen
    // alleen starten als de melding getoond én bevestigd is. Bij microfoon
    // en bestand beslist de dialoog zelf of de regel relevant was.
    const othersVoices = {
      CaptureSourceKind.systemAudio,
      CaptureSourceKind.combination,
    };
    if (kinds.any(othersVoices.contains) &&
        !consent.participantNoticeAcknowledged) {
      throw const ConsentRequired(
        'deelnemersmelding niet bevestigd voor deze bron',
      );
    }
    final stagingDir = await _staging.createSessionDir();
    final request = CaptureRequest(
      kinds: kinds,
      consent: consent,
      stagingDir: stagingDir,
      sourcePath: sourcePath,
    );
    final CaptureSession capture;
    try {
      capture = await source.start(request);
    } on Object {
      // De stagingmap die we net maakten is van ons — weg ermee, anders
      // blijft er bij elke mislukte start een leeg spoor achter. `Object`
      // bewust: een bron die zijn eigen contract overtreedt en iets
      // ongetypts gooit laat alsnog geen weesmap achter.
      await _staging.discardDir(stagingDir);
      rethrow;
    }
    final handle = RecordingHandle._(
      this,
      capture,
      kinds,
      DateTime.now(),
      stagingDir,
    );
    _active = handle;
    _endedSub = capture.ended?.listen((cause) {
      unawaited(
        stop(
          cause == CaptureEndCause.permissionRevoked
              ? RecordingEndReason.permissionLost
              : RecordingEndReason.sourceLost,
        ),
      );
    });
    return handle;
  }

  /// Stop de lopende opname, om welke reden dan ook. De enige plek waar
  /// tracks worden afgebroken: `ended`/`failed` bereik je nergens anders
  /// dan hier — daardoor geldt één bewijs voor alle eindwegen.
  Future<void> stop(RecordingEndReason reason) async {
    final handle = _active;
    if (handle == null || handle._phase != RecordingPhase.recording) return;
    handle._phase = RecordingPhase.stopping;
    // De `ended`-subscription loslaten zonder erop te wachten: de afbraak
    // van de echte capture mag niet wachten op de gebeurtenisplumbing, en
    // een laat binnenkomend `ended` strandt toch op de faseguard hierboven.
    final sub = _endedSub;
    _endedSub = null;
    if (sub != null) unawaited(sub.cancel());
    try {
      final audio = await handle._capture.stop();
      handle._result = audio;
      handle._phase = RecordingPhase.ended;
      handle._emit(RecordingEvent(phase: RecordingPhase.ended, reason: reason));
    } catch (e, s) {
      logError('RecordingManager.stop', e, s);
      handle._error = e;
      handle._phase = RecordingPhase.failed;
      handle._emit(
        RecordingEvent(phase: RecordingPhase.failed, reason: reason, error: e),
      );
    } finally {
      if (identical(_active, handle)) _active = null;
      handle._close();
    }
  }
}
