// De bediening van opnemen vanuit een OciDeck-call (#2528). Puur, zodat
// een test de statussen kan bewijzen zonder een widget of een microfoon.
//
// Twee feiten blijven uit elkaar: de capability uit #2527 (is er een
// audiobron van de hele call) en de fase van déze bediening (heeft de
// gebruiker bewust gestart). Een track-id, een unmute, een join of het
// opname-lampje van de provider verandert die fase niet. Het lampje is
// een melding van de vergadering, geen toestemming en geen lokale opname.

import 'call_audio_source.dart';

/// `uit / toestemming nodig / klaar / bezig / stoppen / fout`.
enum CallRecordingPhase { uit, toestemmingNodig, klaar, bezig, stoppen, fout }

/// Welke zin de paneelregel toont. De widget vertaalt hem; deze laag
/// kent geen teksten, zodat een statuswissel geen vertaalkey verzint.
enum CallRecordingMessage {
  none,
  noPerSourceTap,
  remoteMissing,
  providerForbids,
  consentNeeded,
  ready,
  recording,
  stopping,
  failed,
}

class CallRecordingOffer {
  const CallRecordingOffer({
    required this.showSection,
    required this.showStart,
    required this.showStop,
    required this.showRetry,
    required this.showNotice,
    required this.showAsrConsent,
    required this.forwardToServer,
    required this.message,
  });

  const CallRecordingOffer.hidden()
    : showSection = false,
      showStart = false,
      showStop = false,
      showRetry = false,
      showNotice = false,
      showAsrConsent = false,
      forwardToServer = false,
      message = CallRecordingMessage.none;

  final bool showSection;
  final bool showStart;
  final bool showStop;
  final bool showRetry;
  final bool showNotice;
  final bool showAsrConsent;

  /// Alleen waar als er een gekozen server is én een aparte upload-
  /// toestemming. Intrekken maakt dit direct onwaar; de call blijft.
  final bool forwardToServer;
  final CallRecordingMessage message;
}

/// De rustfase zolang er niet opgenomen wordt. Een whole-call-bron zonder
/// bevestiging blijft op toestemming; zonder die bron is de fase uit en
/// is er geen startknop.
CallRecordingPhase restingCallRecordingPhase({
  required bool connected,
  required CallAudioCaptureFact audio,
  required bool noticeAcknowledged,
}) {
  if (!connected || !audio.wholeCall) return CallRecordingPhase.uit;
  if (!noticeAcknowledged) return CallRecordingPhase.toestemmingNodig;
  return CallRecordingPhase.klaar;
}

/// Een tweede start terwijl het al loopt verandert niets. Alleen `klaar`
/// gaat naar `bezig`.
CallRecordingPhase phaseAfterCallRecordingStart(CallRecordingPhase phase) {
  if (phase != CallRecordingPhase.klaar) return phase;
  return CallRecordingPhase.bezig;
}

CallRecordingOffer offerCallRecording({
  required bool connected,
  required CallAudioCaptureFact audio,
  required bool noticeAcknowledged,
  required bool asrServerChosen,
  required bool asrUploadAllowed,
  required bool providerIndicatesRecording,
  required CallRecordingPhase phase,
}) {
  if (!connected) return const CallRecordingOffer.hidden();
  final blocked = !audio.wholeCall;
  final live =
      phase == CallRecordingPhase.bezig ||
      phase == CallRecordingPhase.stoppen ||
      phase == CallRecordingPhase.fout;
  return CallRecordingOffer(
    showSection:
        blocked || audio.wholeCall || providerIndicatesRecording || live,
    showStart:
        audio.wholeCall &&
        noticeAcknowledged &&
        phase == CallRecordingPhase.klaar,
    showStop:
        phase == CallRecordingPhase.bezig ||
        phase == CallRecordingPhase.stoppen,
    showRetry: phase == CallRecordingPhase.fout,
    showNotice:
        audio.wholeCall &&
        (phase == CallRecordingPhase.toestemmingNodig ||
            phase == CallRecordingPhase.klaar),
    showAsrConsent: audio.wholeCall && asrServerChosen && !blocked,
    forwardToServer: mayForwardCallAudioToServer(
      phase: phase,
      asrServerChosen: asrServerChosen,
      asrUploadAllowed: asrUploadAllowed,
      wholeCall: audio.wholeCall,
    ),
    message: _message(
      audio: audio,
      noticeAcknowledged: noticeAcknowledged,
      phase: phase,
    ),
  );
}

/// Bytes mogen de gekozen server pas op als de opname loopt, de server
/// gekozen is en de uploadtoestemming er apart bij staat. Zonder die
/// toestemming blijft de teller op nul; de call wordt niet verlaten.
bool mayForwardCallAudioToServer({
  required CallRecordingPhase phase,
  required bool asrServerChosen,
  required bool asrUploadAllowed,
  required bool wholeCall,
}) {
  return phase == CallRecordingPhase.bezig &&
      asrServerChosen &&
      asrUploadAllowed &&
      wholeCall;
}

CallRecordingMessage _message({
  required CallAudioCaptureFact audio,
  required bool noticeAcknowledged,
  required CallRecordingPhase phase,
}) {
  if (phase == CallRecordingPhase.fout) return CallRecordingMessage.failed;
  if (phase == CallRecordingPhase.stoppen) {
    return CallRecordingMessage.stopping;
  }
  if (phase == CallRecordingPhase.bezig) return CallRecordingMessage.recording;
  if (!audio.wholeCall) return _blocked(audio);
  if (!noticeAcknowledged) return CallRecordingMessage.consentNeeded;
  return CallRecordingMessage.ready;
}

CallRecordingMessage _blocked(CallAudioCaptureFact audio) {
  // De benoemde reden wint. `remote == false` zonder reden is de
  // microfoon-alleen-zin; de huidige binding noemt wél een reden
  // (`noPerSourceTap`) en die moet de zin zijn, niet de microfoon.
  return switch (audio.denial) {
    CallAudioDenial.providerForbids => CallRecordingMessage.providerForbids,
    CallAudioDenial.remoteMissing => CallRecordingMessage.remoteMissing,
    CallAudioDenial.noPerSourceTap => CallRecordingMessage.noPerSourceTap,
    null =>
      audio.remote
          ? CallRecordingMessage.noPerSourceTap
          : CallRecordingMessage.remoteMissing,
  };
}
