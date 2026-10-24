// Lineaire hermonstering naar 16 kHz mono s16le (#2516).
//
// De platformbinding levert het formaat dat het apparaat echt spreekt
// (vaak 48 kHz stereo). De duurzame file is altijd dezelfde klok en
// dezelfde codec — 16 kHz, één kanaal, 16-bit little-endian PCM — zodat
// de engine en elke standaardspeler het bestand zonder onderhandeling
// lezen. Een Bluetooth-wissel verandert die klok niet: de sessie stopt
// in plaats van stil op een ander apparaat over te stappen.
import 'dart:math' as math;
import 'dart:typed_data';

import 'wav_sink.dart';

class Mono16kResampler {
  Mono16kResampler({required this.sampleRate, required this.channels});

  final int sampleRate;
  final int channels;

  final List<double> _mono = [];
  double _pos = 0;
  final BytesBuilder _tail = BytesBuilder(copy: true);

  /// Voegt interleaved s16le toe en geeft de 16 kHz-mono-PCM terug die
  /// daaruit volgt. Leeg als er nog geen heel uitvoersample in zit.
  /// Een afgekapt frame aan het eind van een blok wacht op het volgende.
  Uint8List add(Uint8List interleaved) {
    if (sampleRate <= 0 || channels <= 0) return Uint8List(0);
    final frameBytes = channels * 2;
    if (_tail.isNotEmpty) {
      _tail.add(interleaved);
      interleaved = _tail.toBytes();
      _tail.clear();
    }
    final frames = interleaved.length ~/ frameBytes;
    final leftover = interleaved.length - frames * frameBytes;
    if (leftover > 0) {
      _tail.add(interleaved.sublist(frames * frameBytes));
    }
    if (frames == 0) return Uint8List(0);

    if (sampleRate == recordingSampleRate && channels == 1) {
      final n = frames * 2;
      return Uint8List.fromList(interleaved.sublist(0, n));
    }

    final view = ByteData.sublistView(interleaved);
    for (var f = 0; f < frames; f++) {
      var sum = 0.0;
      for (var c = 0; c < channels; c++) {
        sum += view.getInt16((f * channels + c) * 2, Endian.little);
      }
      _mono.add(sum / channels);
    }

    final step = sampleRate / recordingSampleRate;
    final out = BytesBuilder(copy: true);
    final sample = ByteData(2);
    while (_pos + 1 < _mono.length) {
      final i = _pos.floor();
      final frac = _pos - i;
      final mixed = _mono[i] * (1 - frac) + _mono[i + 1] * frac;
      sample.setInt16(0, mixed.round().clamp(-32768, 32767), Endian.little);
      out.add(sample.buffer.asUint8List());
      _pos += step;
    }
    final drop = _pos.floor();
    if (drop > 0) {
      _mono.removeRange(0, drop);
      _pos -= drop;
    }
    return out.toBytes();
  }
}

/// Wortel van het gemiddelde kwadraat, 0..1, over mono s16le. De
/// niveaumeter toont dit — een echt signaal van deze capture, geen animatie.
double pcmRms(Uint8List monoS16le) {
  final n = monoS16le.length ~/ 2;
  if (n == 0) return 0;
  final view = ByteData.sublistView(monoS16le);
  var acc = 0.0;
  for (var i = 0; i < n; i++) {
    final s = view.getInt16(i * 2, Endian.little) / 32768.0;
    acc += s * s;
  }
  return math.sqrt(acc / n).clamp(0.0, 1.0);
}
