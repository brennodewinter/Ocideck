// De providerneutrale audiobron van een OciDeck-call (#2527). Opname en
// transcriptie moeten lokale uitgaande audio ná mute en remote audio ná
// decodering apart kunnen lezen, met een tijdstempel en een bron. Een
// [MeetingTrack] blijft een opaak id: dat id is geen tap, en het lampje
// waarmee een provider "er wordt opgenomen" toont is evenmin byte-toegang.
//
// De binding (eigen flutter_webrtc-fork, `audioTrackFrames`) levert per
// track een stroom gedecodeerde PCM: remote via het RTCAudioRenderer-
// protocol (decode-pad), lokaal via de APM-renderer van LocalAudioTrack
// (capture-pad), op web via Web Audio. Dat is wat een INPUT/OUTPUT-
// bestandsmix nooit kan: aparte samples per bron. Dit bestand spreekt
// alleen over het CONTRACT; de stroom zelf maakt de adapter aan.

import 'dart:async';

import 'package:flutter/foundation.dart';

/// Waarom een hele-call-tap er niet is. De UI (#2528) toont de reden en
/// biedt de knop niet aan.
enum CallAudioDenial {
  /// De binding levert geen gedecodeerde samples per bron.
  noPerSourceTap,

  /// Remote audio ontbreekt. Alleen de microfoon is geen hele call.
  remoteMissing,

  /// Het vergaderbeleid verbiedt opnemen. De knop blijft weg.
  providerForbids,
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

/// Het eerlijke feit voor een binding zonder per-bron-tap.
const unavailableCallAudio = CallAudioCaptureFact(
  localOutbound: false,
  remote: false,
  denial: CallAudioDenial.noPerSourceTap,
);

/// De binding van nu. Eén plek, zodat de sessie en de media-core hetzelfde
/// zeggen en een test die uitspraak kan vastzetten.
///
/// Bewezen: macOS (darwin-sink) en web (Web Audio op het jsTrack-object).
/// Windows en Linux hebben dezelfde C++-route in de binding maar zijn
/// nóóit in een echte call getest — geen claim. iOS/Android: niet bewezen.
CallAudioCaptureFact callAudioCaptureOfCurrentBinding() {
  if (kIsWeb || defaultTargetPlatform == TargetPlatform.macOS) {
    return const CallAudioCaptureFact(localOutbound: true, remote: true);
  }
  return unavailableCallAudio;
}

enum CallAudioRole { localOutbound, remote }

/// Eén brok PCM zoals één track hem levert: s16le, mono na downmix.
class CallPcmFrame {
  const CallPcmFrame({required this.pcm, required this.sampleRateHz});

  final Uint8List pcm;
  final int sampleRateHz;
}

/// Eén opengegaande tap op één audiotrack van de call. [participantId] mag
/// '' zijn als de binding de eigenaar niet kent — de sessie stempelt hem
/// dan via de roster. [frames] is wat de binding écht levert.
class CallAudioTrackTap {
  const CallAudioTrackTap({
    required this.trackId,
    required this.role,
    this.participantId = '',
    required this.frames,
  });

  final String trackId;
  final String participantId;
  final CallAudioRole role;
  final Stream<CallPcmFrame> frames;
}

/// Resampled interleaved s16le naar mono 16 kHz — de rate die de
/// opname- en ASR-pijplijn spreekt. `channels` > 1 wordt gemiddeld
/// (downmix). Lineaire interpolatie is voldoende voor spraak; het is
/// bewust geen polyfase — bronnen zijn bandbeperkte telefoonaudio.
CallPcmFrame callPcmFrame16k(Uint8List pcm, int sampleRateHz, int channels) {
  if (channels <= 0 || pcm.isEmpty) {
    return CallPcmFrame(pcm: Uint8List(0), sampleRateHz: 16000);
  }
  final src = ByteData.sublistView(pcm);
  final srcFrames = pcm.lengthInBytes ~/ (2 * channels);
  final mono = Int32List(srcFrames);
  for (var i = 0; i < srcFrames; i++) {
    var acc = 0;
    for (var c = 0; c < channels; c++) {
      acc += src.getInt16((i * channels + c) * 2, Endian.little);
    }
    mono[i] = acc ~/ channels;
  }
  final outLen = sampleRateHz == 16000
      ? srcFrames
      : (srcFrames * 16000 / sampleRateHz).round();
  final out = Uint8List(outLen * 2);
  final od = out.buffer.asByteData();
  for (var i = 0; i < outLen; i++) {
    final pos = i * (srcFrames - 1) / (outLen > 1 ? outLen - 1 : 1);
    final lo = pos.floor();
    final hi = lo + 1 < srcFrames ? lo + 1 : lo;
    final frac = pos - lo;
    final v = (mono[lo] * (1 - frac) + mono[hi] * frac).round();
    od.setInt16(i * 2, v.clamp(-32768, 32767), Endian.little);
  }
  return CallPcmFrame(pcm: out, sampleRateHz: 16000);
}

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

/// Opent de tap: per aangeboden [CallAudioTrackTap] worden diens frames
/// chunks met een tijdstip. De stroom van taps mag oneindig open blijven —
/// een remote track die ná het begin van de opname join tapt gewoon mee.
/// Een niet-beschikbare capability geeft een lege stroom.
Stream<CallAudioChunk> openCallAudioCapture(
  CallAudioCaptureFact fact,
  Stream<CallAudioTrackTap> taps,
) {
  if (!fact.wholeCall) return const Stream.empty();
  // Geen asyncExpand: die pauzeert de taps-bron zolang een tap-framestroom
  // loopt, en die loopt hier bewust eindeloos — een tweede tap (remote)
  // zou dan nooit openen. Eigen merge: iedere tap krijgt een eigen
  // subscription die chunks doorzet; cancel ruimt ze allemaal op.
  late final StreamController<CallAudioChunk> out;
  StreamSubscription<CallAudioTrackTap>? tapsSub;
  final frameSubs = <StreamSubscription<CallAudioChunk>>{};
  var tapsDone = false;

  void maybeClose() {
    if (tapsDone && frameSubs.isEmpty) unawaited(out.close());
  }

  out = StreamController<CallAudioChunk>(
    onListen: () {
      tapsSub = taps.listen(
        (tap) {
          late StreamSubscription<CallAudioChunk> frameSub;
          frameSub = tap.frames
              .map(
                (f) => CallAudioChunk(
                  participantId: tap.participantId,
                  role: tap.role,
                  trackId: tap.trackId,
                  at: DateTime.now(),
                  pcm: f.pcm,
                  sampleRateHz: f.sampleRateHz,
                ),
              )
              .listen(
                out.add,
                onError: out.addError,
                onDone: () {
                  frameSubs.remove(frameSub);
                  maybeClose();
                },
              );
          frameSubs.add(frameSub);
        },
        onError: out.addError,
        onDone: () {
          tapsDone = true;
          maybeClose();
        },
      );
    },
    onCancel: () async {
      await tapsSub?.cancel();
      for (final s in frameSubs.toList()) {
        await s.cancel();
      }
      frameSubs.clear();
    },
  );
  return out.stream;
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
