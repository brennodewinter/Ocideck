// De lopende vergadering, als toestand van de app (T6).
//
// **Wortelgeschikt, niet per tabblad.** Een gesprek is geen eigenschap van een
// presentatie: wie tijdens een vergadering een ander deck opent, hoort niet uit
// de vergadering te vallen. Deze provider hoort daarom in de
// `ProviderScope` van `main.dart` thuis en staat bewust níet in de
// `overrides` van `AppShell._tabScope`; `meeting_provider_scope_test.dart`
// bewaakt dat.
//
// **De link, het toegangsbewijs en de vernieuwingssleutel staan hier niet in.**
// `MeetingState` is inspecteerbaar — via een diagnosevenster, een foutrapport,
// de devtools — en dat is precies waarom T5 en §8.1 verbieden ze daarin te
// bewaren. De uitnodiging leeft in het privéveld [_link] van deze notifier en
// wordt bij het verlaten gewist.
//
// **Opdrachten lopen in de rij, en dubbele klikken vallen samen.** §8.2: een
// tweede klik op dempen terwijl de eerste nog loopt, mag geen twee gelijktijdige
// SDK-aanroepen worden. De rij hieronder voert er één uit, met de láátst
// gewenste waarde — zo springt de knop niet terug en raakt de stand niet uit de
// pas met de dienst.
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../meetings/meeting_event.dart';
import '../meetings/meeting_failure.dart';
import '../meetings/meeting_link.dart';
import '../meetings/meeting_models.dart';
import '../meetings/meeting_provider.dart';
import '../meetings/meeting_registry.dart';
import '../meetings/meeting_state.dart';
import '../utils/log.dart';

/// De toestand van het lopende gesprek.
final meetingSessionProvider =
    NotifierProvider<MeetingSessionNotifier, MeetingState>(
      MeetingSessionNotifier.new,
    );

/// Of er iets loopt waar de gebruiker nog bij moet kunnen — het tweede been van
/// de modulepoort (T13).
final meetingSessionActiveProvider = Provider<bool>((ref) {
  return ref.watch(meetingSessionProvider.select((s) => s.isActive));
});

class MeetingSessionNotifier extends Notifier<MeetingState> {
  MeetingSession? _session;
  StreamSubscription<MeetingEvent>? _events;

  /// De herkende uitnodiging. Privé, en weg zodra het gesprek voorbij is.
  MeetingLinkMatch? _link;

  /// De opdrachtenrij. Elke nieuwe opdracht hangt achter de vorige, zodat er
  /// nooit twee tegelijk bij de adapter zijn.
  Future<void> _queue = Future<void>.value();

  /// De laatst gewenste stand van microfoon en camera, zolang de bijbehorende
  /// opdracht nog wacht. `null` betekent: er wacht er geen.
  bool? _wantedMicrophone;
  bool? _wantedCamera;

  @override
  MeetingState build() {
    ref.onDispose(_teardown);
    return MeetingState.idle;
  }

  /// De adapter van het lopende gesprek, voor een test of een diagnosevenster.
  /// `null` wanneer er niets loopt.
  MeetingSession? get session => _session;

  /// Herken een geplakte uitnodiging.
  ///
  /// Zet de fase op `validating` en, bij een afwijzing, op `failed` met de
  /// reden. Bij herkenning onthoudt de notifier de uitnodiging en blijft de
  /// fase staan: de volgende stap is die van de gebruiker (§6.2).
  MeetingLinkResolution resolveLink(String raw) {
    _apply(const MeetingPhaseChanged(MeetingPhase.validating));
    final resolution = meetingLinkResolver.resolve(raw);
    switch (resolution) {
      case MeetingLinkRecognised(:final match):
        _link = match;
      case MeetingLinkRejected(:final failure):
        _fail(failure);
      case MeetingLinkUnrecognised():
        _fail(MeetingFailure(MeetingFailureKind.unknownProvider));
    }
    return resolution;
  }

  /// De browser is om toestemming voor microfoon/camera gevraagd (§6.2 stap 5).
  void requestDevicePermission() =>
      _apply(const MeetingPhaseChanged(MeetingPhase.permissionPrompt));

  /// Toestemming rond en apparaten gekozen; de gebruiker ziet zijn eigen beeld
  /// (§6.2 stap 6–7).
  void devicesReady() =>
      _apply(const MeetingPhaseChanged(MeetingPhase.preview));

  /// Vraag de adapter wat er met de herkende uitnodiging mogelijk is.
  ///
  /// Pas ná een handeling van de gebruiker (T8). Geeft `null` wanneer er nog
  /// geen uitnodiging herkend is of de adapter niet bestaat.
  Future<MeetingPreflight?> preflight() async {
    final link = _link;
    if (link == null) return null;
    final provider = meetingProviderById(link.provider);
    if (provider == null) return null;
    return provider.preflight(link);
  }

  /// Doe mee met de herkende uitnodiging.
  ///
  /// Het teruggeven van deze future betekent niet dat de gebruiker binnen is —
  /// alleen dat de adapter het overneemt. Wat er daarna gebeurt komt langs de
  /// gebeurtenissen (§13.1).
  Future<void> join({
    required String displayName,
    bool startMuted = true,
    bool startWithVideo = false,
  }) async {
    final link = _link;
    if (link == null || _session != null) return;
    // Buiten de volgorde van §6.2 gebeurt er niets. De fasetabel is de enige
    // plek waar die volgorde staat; hem hier nog eens overschrijven zou twee
    // waarheden opleveren die uiteen kunnen lopen. Zonder deze poort zou een
    // vroege `join()` wél een sessie opzetten terwijl de fase stil op
    // `validating` blijft staan — een gesprek dat volgens de toestand niet
    // bestaat.
    if (!state.phase.canTransitionTo(MeetingPhase.provisioning)) return;
    final provider = meetingProviderById(link.provider);
    if (provider == null) {
      _fail(MeetingFailure(MeetingFailureKind.unknownProvider));
      return;
    }
    _apply(const MeetingPhaseChanged(MeetingPhase.provisioning));
    final request = MeetingJoinRequest(
      link: link,
      displayName: displayName,
      startMuted: startMuted,
      startWithVideo: startWithVideo,
    );
    if (!request.isComplete) {
      _fail(MeetingFailure(MeetingFailureKind.invalidLink, provider: provider.id));
      return;
    }
    try {
      final session = await provider.join(request);
      _session = session;
      state = state.copyWith(provider: session.provider);
      _events = session.events.listen(_apply, onDone: _onSessionDone);
    } on Exception catch (e, s) {
      // Een adapter die struikelt levert een getypeerde afloop op, geen
      // uitzondering die ergens bovenaan de boom uitkomt (T11). De uitzondering
      // zelf gaat naar het logboek en niet naar de toestand: zijn tekst kan de
      // link bevatten.
      logError('MeetingSessionNotifier.join: adapter faalde', e, s);
      _fail(MeetingFailure(MeetingFailureKind.unknown, provider: provider.id));
    }
  }

  /// Zet de microfoon aan of uit. Snel achter elkaar aanroepen levert één
  /// opdracht op, met de laatste waarde.
  Future<void> setMicrophone(bool enabled) {
    final alreadyQueued = _wantedMicrophone != null;
    _wantedMicrophone = enabled;
    if (alreadyQueued) return _queue;
    return _serialize(() async {
      final wanted = _wantedMicrophone;
      _wantedMicrophone = null;
      if (wanted != null) await _session?.setMicrophone(wanted);
    });
  }

  /// Idem voor de camera.
  Future<void> setCamera(bool enabled) {
    final alreadyQueued = _wantedCamera != null;
    _wantedCamera = enabled;
    if (alreadyQueued) return _queue;
    return _serialize(() async {
      final wanted = _wantedCamera;
      _wantedCamera = null;
      if (wanted != null) await _session?.setCamera(wanted);
    });
  }

  Future<void> setScreenShare(bool sharing) => _serialize(() async {
    final session = _session;
    if (session == null) return;
    await (sharing ? session.startScreenShare() : session.stopScreenShare());
  });

  /// Antwoord op een gevraagde uitdrukkelijke toestemming (§15).
  Future<void> submitRecordingConsent(bool consent) =>
      _serialize(() async => _session?.submitRecordingConsent(consent));

  /// Ga weg. Idempotent: het sluiten van een venster, een klik en een verbroken
  /// verbinding mogen elkaar kruisen (§6.5).
  Future<void> leave() => _serialize(() async {
    final session = _session;
    // De fasen worden hier gezet en niet uit de adapter afgewacht. Dat is geen
    // wantrouwen maar timing: de gebeurtenissen van een stroom komen in een
    // volgende microtask aan, en het abonnement gaat er in [_teardown] meteen
    // daarna af — wie op die gebeurtenissen wacht, verliest ze. De adapter mag
    // hetzelfde nog eens melden; vanuit een terminale fase landt dat niet meer.
    _apply(const MeetingPhaseChanged(MeetingPhase.leaving));
    await session?.leave();
    _apply(const MeetingPhaseChanged(MeetingPhase.ended));
    await _teardown();
  });

  /// Wis de afloop van een afgelopen of mislukt gesprek.
  ///
  /// Pas hierna verdwijnt de module weer wanneer hij uit staat (T13) — de
  /// gebruiker heeft de reden dan gezien.
  void reset() {
    _link = null;
    state = MeetingState.idle;
  }

  /// De adapter sloot zijn stroom zonder afscheid. Dat is geen fout, maar het
  /// gesprek is er wel mee voorbij.
  void _onSessionDone() {
    if (state.isActive && state.phase != MeetingPhase.ended) {
      _apply(const MeetingPhaseChanged(MeetingPhase.ended));
    }
  }

  void _apply(MeetingEvent event) => state = state.apply(event);

  void _fail(MeetingFailure failure) =>
      _apply(MeetingPhaseChanged(MeetingPhase.failed, failure: failure));

  /// Hang [operation] achter de wachtende opdrachten.
  ///
  /// De rij loopt door na een mislukte opdracht: één adapter die niet antwoordt
  /// mag niet betekenen dat `Verlaten` daarna nooit meer aan de beurt komt.
  Future<void> _serialize(Future<void> Function() operation) {
    final next = _queue.then((_) => operation());
    _queue = next.catchError((Object e, StackTrace s) {
      logError('MeetingSessionNotifier: opdracht mislukt', e, s);
    });
    return next;
  }

  /// Alles los: abonnement eruit, adapter opgeruimd, uitnodiging gewist.
  Future<void> _teardown() async {
    final events = _events;
    final session = _session;
    _events = null;
    _session = null;
    _link = null;
    await events?.cancel();
    await session?.dispose();
  }
}
