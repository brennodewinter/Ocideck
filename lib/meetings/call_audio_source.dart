// De providerneutrale audiobron van een OciDeck-call (#2527). Opname en
// transcriptie moeten lokale uitgaande audio ná mute en remote audio ná
// decodering apart kunnen lezen, met een tijdstempel en een bron. Een
// [MeetingTrack] blijft een opaak id: dat id is geen tap, en het lampje
// waarmee een provider "er wordt opgenomen" toont is evenmin byte-toegang.
//
// flutter_webrtc 1.6 kan dit niet leveren. `MediaRecorder` schrijft een
// bestand van het INPUT- of OUTPUT-kanaal — een mix, geen samples per
// deelnemer na de mute. Zolang die tap er niet is, is een hele-call-opname
// niet beschikbaar. Een microfoon alleen mag die naam niet dragen.

import 'dart:typed_data';

/// Waarom een hele-call-tap er niet is. De UI (#2528) toont de reden en
/// biedt de knop niet aan.
enum CallAudioDenial {
  /// De binding levert geen gedecodeerde samples per bron.
  noPerSourceTap,

  /// Remote audio ontbreekt. Alleen de microfoon is geen hele call.
  remoteMissing,
}

/// Wat een adapter echt kan leveren. [wholeCall] is alleen waar als zowel
/// de lokale uitgaande bron ná mute als de remote bron ná decodering
/// beschikbaar is, en er geen [denial] op zit.
class CallAudioCaptureFact {
  const CallAudioCaptureFact({
    required this.localOutbound,
    required this.remote,
    this.denial,
  });

  final bool localOutbound;
  final bool remote;
  final CallAudioDenial? denial;

  bool get wholeCall => localOutbound && remote && denial == null;
}

/// Het eerlijke feit voor de huidige `flutter_webrtc`-binding (#2527).
const unavailableCallAudio = CallAudioCaptureFact(
  localOutbound: false,
  remote: false,
  denial: CallAudioDenial.noPerSourceTap,
);

/// De binding van nu. Eén plek, zodat de sessie en de media-core hetzelfde
/// zeggen en een test die uitspraak kan vastzetten.
CallAudioCaptureFact callAudioCaptureOfCurrentBinding() => unavailableCallAudio;

enum CallAudioRole { localOutbound, remote }

/// Eén brok gedecodeerde audio van precies één bron. PCM is 16-bit
/// little-endian, mono. Lege bytes zijn stilte en horen niet in de opname.
class CallAudioChunk {
  const CallAudioChunk({
    required this.participantId,
    required this.role,
    required this.trackId,
    required this.at,
    required this.pcm,
    required this.sampleRateHz,
  });

  final String participantId;
  final CallAudioRole role;
  final String trackId;
  final DateTime at;
  final Uint8List pcm;
  final int sampleRateHz;
}

/// Opent de tap. Een niet-beschikbare capability geeft een lege stroom —
/// er wordt niets opgenomen. Een capability die wél whole-call claimt
/// terwijl er geen tap is, faalt hard: stil niets teruggeven zou de leugen
/// verbergen.
Stream<CallAudioChunk> openCallAudioCapture(CallAudioCaptureFact fact) {
  if (!fact.wholeCall) return const Stream.empty();
  throw StateError('call-audiotap ontbreekt terwijl wholeCall waar is');
}

/// Filtert een aangeboden brok. Niet-beschikbaar, gemute lokaal, lege
/// samples of een tijdstip dat niet ná het vorige van dezelfde bron ligt
/// vallen af. Twee deelnemers op hetzelfde moment tellen allebei; dezelfde
/// bron twee keer op hetzelfde moment niet.
class CallAudioGate {
  CallAudioGate(this.fact);

  final CallAudioCaptureFact fact;
  final _lastAt = <String, DateTime>{};

  CallAudioChunk? consider(CallAudioChunk chunk, {required bool localMuted}) {
    if (!fact.wholeCall) return null;
    if (chunk.role == CallAudioRole.localOutbound && localMuted) return null;
    if (chunk.pcm.isEmpty) return null;
    final key = '${chunk.participantId}|${chunk.role.name}|${chunk.trackId}';
    final prev = _lastAt[key];
    if (prev != null && !chunk.at.isAfter(prev)) return null;
    _lastAt[key] = chunk.at;
    return chunk;
  }
}
