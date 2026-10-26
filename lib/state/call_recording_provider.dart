// De root-scoped opnamefase van een OciDeck-call (#2528). Hij overleeft
// een tab- of presentatiewissel, net als de vergadering zelf: de strook
// boven de werkruimte leest hem, niet de widget die toevallig openstaat.
//
// Starten kan alleen vanuit [start], en alleen in de fase `klaar`. De
// module-schakelaars hangen hier aan de stop-kant: aanzetten doet niets,
// uitzetten tijdens een opname stopt hem. De call zelf blijft staan.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../meetings/call_audio_source.dart';
import '../meetings/call_recording.dart';
import '../meetings/meeting_event.dart';
import '../meetings/meeting_provider.dart';
import '../utils/log.dart';
import 'meeting_session_provider.dart';
import 'transcription_provider.dart';

final callRecordingProvider =
    NotifierProvider<CallRecordingNotifier, CallRecordingState>(
      CallRecordingNotifier.new,
    );

class CallRecordingState {
  const CallRecordingState({
    this.phase = CallRecordingPhase.uit,
    this.noticeAcknowledged = false,
    this.asrUploadAllowed = false,
    this.providerIndicatesRecording = false,
    this.capturedChunks = 0,
    this.forwardedChunks = 0,
  });

  final CallRecordingPhase phase;
  final bool noticeAcknowledged;
  final bool asrUploadAllowed;
  final bool providerIndicatesRecording;

  /// Brokken die de tap leverde ná een bewuste start. Niet bewaard: de
  /// bytes zelf gaan nergens heen. De teller bewijst alleen dát de tap
  /// liep.
  final int capturedChunks;

  /// Brokken die naar een gekozen transcriptieserver móchten. Blijft 0
  /// zolang de aparte uploadtoestemming ontbreekt.
  final int forwardedChunks;

  CallRecordingState copyWith({
    CallRecordingPhase? phase,
    bool? noticeAcknowledged,
    bool? asrUploadAllowed,
    bool? providerIndicatesRecording,
    int? capturedChunks,
    int? forwardedChunks,
  }) {
    return CallRecordingState(
      phase: phase ?? this.phase,
      noticeAcknowledged: noticeAcknowledged ?? this.noticeAcknowledged,
      asrUploadAllowed: asrUploadAllowed ?? this.asrUploadAllowed,
      providerIndicatesRecording:
          providerIndicatesRecording ?? this.providerIndicatesRecording,
      capturedChunks: capturedChunks ?? this.capturedChunks,
      forwardedChunks: forwardedChunks ?? this.forwardedChunks,
    );
  }
}

class CallRecordingNotifier extends Notifier<CallRecordingState> {
  MeetingSession? _session;
  StreamSubscription<MeetingEvent>? _events;
  StreamSubscription<CallAudioChunk>? _audio;
  CallAudioGate? _gate;
  var _starting = false;

  @override
  CallRecordingState build() {
    ref.listen(transcriptionEnabledProvider, (prev, next) {
      if (prev == true && !next) unawaited(stop());
    });
    ref.listen(videoCallsEnabledProvider, (prev, next) {
      if (prev == true && !next) unawaited(stop());
    });
    ref.listen(meetingSessionProvider, (prev, next) {
      if (next == null) unawaited(stop(callEnded: true));
    });
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_audio?.cancel());
    });
    return const CallRecordingState();
  }

  /// Volg [session]. Een tweede keer met dezelfde sessie doet niets, zodat
  /// een herbouw van het paneel de lopende opname niet opnieuw bindt.
  void bind(MeetingSession session) {
    if (identical(_session, session)) return;
    unawaited(_events?.cancel());
    _session = session;
    _events = session.events.listen(_onEvent);
    _applyResting();
  }

  void setNotice(bool acknowledged) {
    state = state.copyWith(noticeAcknowledged: acknowledged);
    _applyResting();
  }

  /// De uploadtoestemming intrekken stopt de telling en laat de call
  /// met rust. Een lopende opname wordt daar niet door verlaten, en de
  /// bytes gaan nog steeds nergens heen.
  void setAsrUploadAllowed(bool allowed) {
    state = state.copyWith(asrUploadAllowed: allowed);
  }

  Future<void> start() async {
    final session = _session;
    if (session == null || _starting) return;
    final next = phaseAfterCallRecordingStart(state.phase);
    if (next == state.phase) return;
    _starting = true;
    state = state.copyWith(phase: next);
    _gate = CallAudioGate(session.capabilities.callAudio);
    try {
      final stream = session.startCallAudioCapture();
      _audio = stream.listen(
        _onChunk,
        onError: _onAudioError,
        onDone: _onAudioDone,
      );
    } catch (e) {
      logWarning('callRecording.start', e);
      if (ref.mounted) state = state.copyWith(phase: CallRecordingPhase.fout);
    } finally {
      _starting = false;
    }
  }

  Future<void> retry() async {
    if (state.phase != CallRecordingPhase.fout) return;
    await _audio?.cancel();
    _audio = null;
    if (!ref.mounted) return;
    // `fout` blokkeert de rustfase. Eerst eraf, dan opnieuw kijken of
    // starten weer mag.
    state = state.copyWith(phase: CallRecordingPhase.uit);
    _applyResting();
  }

  Future<void> stop({bool callEnded = false}) async {
    final live =
        state.phase == CallRecordingPhase.bezig ||
        state.phase == CallRecordingPhase.stoppen ||
        state.phase == CallRecordingPhase.fout;
    if (!live && !callEnded) return;
    if (live && ref.mounted) {
      state = state.copyWith(phase: CallRecordingPhase.stoppen);
    }
    // cancel() niet afwachten: die future kan blijven hangen terwijl de
    // provider-update nog loopt, en dan komt de sessie-stop nooit.
    final audio = _audio;
    _audio = null;
    if (audio != null) unawaited(audio.cancel());
    final session = _session;
    if (session != null) {
      try {
        await session.stopCallAudioCapture();
      } catch (e) {
        logWarning('callRecording.stop', e);
      }
    }
    if (!ref.mounted) return;
    if (callEnded || session == null) {
      if (callEnded) _session = null;
      state = const CallRecordingState();
      return;
    }
    if (!_connected(session)) {
      state = state.copyWith(phase: CallRecordingPhase.uit);
      return;
    }
    state = state.copyWith(
      phase: restingCallRecordingPhase(
        connected: true,
        audio: session.capabilities.callAudio,
        noticeAcknowledged: state.noticeAcknowledged,
      ),
    );
  }

  void _onEvent(MeetingEvent event) {
    if (!ref.mounted) return;
    if (event is RecordingIndicatorChanged) {
      state = state.copyWith(providerIndicatesRecording: event.active);
      return;
    }
    if (event is ConnectionStateChanged || event is CapabilitiesChanged) {
      _applyResting();
    }
  }

  void _onChunk(CallAudioChunk chunk) {
    if (!ref.mounted) return;
    final session = _session;
    // Gemute lokale mic levert ná mute geen opname — dat is het on-wire-
    // contract van #2527, geen filter op stilte (stilte is een geldige
    // opname).
    final localMuted =
        session?.participants.any((p) => p.isLocal && p.micMuted) ?? false;
    final kept = _gate?.consider(chunk, localMuted: localMuted);
    if (kept == null) return;
    final forward = mayForwardCallAudioToServer(
      phase: state.phase,
      asrServerChosen: _asrChosen(),
      asrUploadAllowed: state.asrUploadAllowed,
      wholeCall: session?.capabilities.callAudio.wholeCall ?? false,
    );
    // De bytes worden hier losgelaten, mét of zonder uploadtoestemming.
    // [forwardedChunks] is alleen het hek: zonder toestemming telt een
    // brok niet mee, en er wordt niets weggeschreven of verstuurd.
    state = state.copyWith(
      capturedChunks: state.capturedChunks + 1,
      forwardedChunks: state.forwardedChunks + (forward ? 1 : 0),
    );
  }

  void _onAudioError(Object error) {
    logWarning('callRecording.audio', error);
    if (!ref.mounted) return;
    state = state.copyWith(phase: CallRecordingPhase.fout);
  }

  /// Een tap die tijdens `bezig` stopt is geen nette afronding maar een
  /// weggevallen bron — de opnameclaim moet dan eerlijk op fout, anders
  /// blijft de teller op een dode stroom staan.
  void _onAudioDone() {
    if (!ref.mounted || state.phase != CallRecordingPhase.bezig) return;
    state = state.copyWith(phase: CallRecordingPhase.fout);
  }

  void _applyResting() {
    if (!ref.mounted) return;
    final session = _session;
    final connected = session != null && _connected(session);
    if (!connected) {
      if (state.phase == CallRecordingPhase.bezig) unawaited(stop());
      return;
    }
    final phase = state.phase;
    if (phase == CallRecordingPhase.bezig ||
        phase == CallRecordingPhase.stoppen ||
        phase == CallRecordingPhase.fout) {
      return;
    }
    state = state.copyWith(
      phase: restingCallRecordingPhase(
        connected: true,
        audio: session.capabilities.callAudio,
        noticeAcknowledged: state.noticeAcknowledged,
      ),
    );
  }

  bool _connected(MeetingSession session) =>
      session.connectionState == MeetingConnectionState.connected;

  bool _asrChosen() => ref.read(asrServerProfileProvider).isConfigured;
}
