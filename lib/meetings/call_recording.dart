// De bediening van opnemen vanuit een OciDeck-call (#2528). Puur, zodat
// een test de statussen kan bewijzen zonder een widget of een microfoon.
//
// Twee feiten blijven uit elkaar: de capability uit #2527 (is er een
// audiobron van de hele call) en de fase van déze bediening (heeft de
// gebruiker bewust gestart). Een track-id, een unmute, een join of het
// opname-lampje van de provider verandert die fase niet. Het lampje is
// een melding van de vergadering, geen toestemming en geen lokale opname.

import 'call_audio_source.dart';

/// Het aantal bronnen dat stilte bijdroeg in een callopname én hoeveel —
/// uit `sources.json` van de sessie (#2530). `silenceTicks` is in
/// 20 ms-ticks (de mix-tick); de UI maakt er seconden van. Null als er
/// geen manifest is, de vorm vreemd is, of niets ontbrak: een gat dat we
/// niet kunnen onderbouwen claimen we niet.
(int sources, Duration silence)? missingCallAudio(
  Map<String, Object?>? manifest,
) {
  final list = manifest?['sources'];
  if (list is! List) return null;
  var silenced = 0;
  var ticks = 0;
  for (final entry in list) {
    if (entry is! Map) continue;
    final n = entry['silenceTicks'];
    if (n is! int || n <= 0) continue;
    silenced++;
    ticks += n;
  }
  if (ticks == 0) return null;
  return (silenced, Duration(milliseconds: ticks * 20));
}

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
    required this.message,
  });

  const CallRecordingOffer.hidden()
    : showSection = false,
      showStart = false,
      showStop = false,
      showRetry = false,
      showNotice = false,
      message = CallRecordingMessage.none;

  final bool showSection;
  final bool showStart;
  final bool showStop;
  final bool showRetry;
  final bool showNotice;
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
    message: _message(
      audio: audio,
      noticeAcknowledged: noticeAcknowledged,
      phase: phase,
    ),
  );
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
