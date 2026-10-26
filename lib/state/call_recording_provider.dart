// De root-scoped opnamefase van een OciDeck-call (#2528). Hij overleeft
// een tab- of presentatiewissel, net als de vergadering zelf: de strook
// boven de werkruimte leest hem, niet de widget die toevallig openstaat.
//
// Starten kan alleen vanuit [start], en alleen in de fase `klaar`. De
// module-schakelaars hangen hier aan de stop-kant: aanzetten doet niets,
// uitzetten tijdens een opname stopt hem. De call zelf blijft staan.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../meetings/call_audio_capture_source.dart';
import '../meetings/call_recording.dart';
import '../meetings/meeting_event.dart';
import '../meetings/meeting_provider.dart';
import '../services/transcription/capture_source.dart';
import '../services/transcription/recording_session.dart';
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
  StreamSubscription<AudioChunk>? _audio;
  StreamSubscription<RecordingEvent>? _recordingEvents;
  var _starting = false;

  @override
  CallRecordingState build() {
    ref.listen(transcriptionEnabledProvider, (prev, next) {
      if (prev == true && !next) {
        unawaited(stop(reason: RecordingEndReason.moduleDisabled));
      }
    });
    ref.listen(videoCallsEnabledProvider, (prev, next) {
      if (prev == true && !next) {
        unawaited(stop(reason: RecordingEndReason.sourceLost));
      }
    });
    ref.listen(meetingSessionProvider, (prev, next) {
      if (next == null) unawaited(stop(callEnded: true));
    });
    ref.onDispose(() {
      unawaited(_events?.cancel());
      unawaited(_audio?.cancel());
      unawaited(_recordingEvents?.cancel());
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
    try {
      // Dezelfde duurzame, begrensde pipeline als de microfoonopname
      // (#2529): staging, schijfcontrole, crashherstel en de live-route
      // komen mee; hieronder tellen we alleen wat er écht binnenkomt.
      final handle = await ref
          .read(recordingSessionProvider.notifier)
          .start(
            CallAudioCaptureSource(session: session),
            kinds: {CaptureSourceKind.callAudio},
            consent: RecordingConsent(
              participantNoticeAcknowledged: state.noticeAcknowledged,
            ),
          );
      _audio = handle.liveChunks?.listen(_onLiveTick, onError: _onAudioError);
      _recordingEvents = handle.events.listen(_onRecordingEvent);
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

  Future<void> stop({
    bool callEnded = false,
    RecordingEndReason? reason,
  }) async {
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
    final events = _recordingEvents;
    _recordingEvents = null;
    if (events != null) unawaited(events.cancel());
    // De duurzame file wordt netjes afgerond — ook als de call eindigt:
    // "wat er stond is bewaard" is het eerlijke eindbeeld (sourceLost),
    // niet een stil afgekapte staart.
    await ref
        .read(recordingSessionProvider.notifier)
        .stopAll(
          reason ??
              (callEnded
                  ? RecordingEndReason.sourceLost
                  : RecordingEndReason.userStop),
        );
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

  /// Eén event per mix-tick (20 ms, zie `CallAudioCaptureSource`). De
  /// bytes zijn al duurzaam weggeschreven; hier telt alleen wat de
  /// gebruiker mag volgen.
  void _onLiveTick(AudioChunk tick) {
    if (!ref.mounted) return;
    final session = _session;
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

  void _onRecordingEvent(RecordingEvent event) {
    if (!ref.mounted) return;
    switch (event.phase) {
      case RecordingPhase.failed:
        logWarning('callRecording.failed', event.error);
        if (state.phase == CallRecordingPhase.bezig ||
            state.phase == CallRecordingPhase.stoppen) {
          state = state.copyWith(phase: CallRecordingPhase.fout);
        }
      case RecordingPhase.ended:
        // Viel de bron spontaan weg (sourceLost), dan bereikte onze
        // stop() de fase niet meer — toch eerlijk terug naar rust.
        if (state.phase == CallRecordingPhase.bezig) _applyResting();
      case RecordingPhase.starting ||
          RecordingPhase.recording ||
          RecordingPhase.stopping:
        break;
    }
  }

  void _onAudioError(Object error) {
    logWarning('callRecording.audio', error);
    if (!ref.mounted) return;
    state = state.copyWith(phase: CallRecordingPhase.fout);
  }

  void _applyResting() {
    if (!ref.mounted) return;
    final session = _session;
    final connected = session != null && _connected(session);
    if (!connected) {
      if (state.phase == CallRecordingPhase.bezig) {
        unawaited(stop(reason: RecordingEndReason.sourceLost));
      }
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
