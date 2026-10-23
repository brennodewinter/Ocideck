// Provisionele tekst naast de duurzame opname (#2522).
//
// De engine beslist of er een live-route is. `transcribeLive` null — de
// lokale whisper-cli en de batch-server doen dat — betekent dat deze
// pass niets opent en niets veinst. Blokken worden gekopieerd, nooit
// weggegooid: loopt de engine achter, dan blijven ze in de wachtrij en
// de opname zelf gaat door.
import 'dart:async';
import 'dart:typed_data';

import 'capture_source.dart';
import 'transcription_engine.dart';

/// Na dit aantal wachtende blokken noemen we de tekst achterlopend.
const livePassLagAfter = 8;

class LivePass {
  var lagging = false;
  StreamSubscription<AudioChunk>? _incoming;
  StreamController<AudioChunk>? _outgoing;

  /// Null als [chunks] of [TranscriptionEngine.transcribeLive] null is.
  Stream<PartialTranscript>? attach({
    required TranscriptionEngine engine,
    required Stream<AudioChunk>? chunks,
    void Function(bool lagging)? onLag,
    int lagAfter = livePassLagAfter,
  }) {
    final input = chunks;
    if (input == null) return null;
    final outgoing = StreamController<AudioChunk>();
    _outgoing = outgoing;
    final partials = engine.transcribeLive(outgoing.stream);
    if (partials == null) {
      // Sluiten zonder luisteraar voltooit nooit. Er is niets te leveren.
      _outgoing = null;
      return null;
    }
    final waiting = <AudioChunk>[];
    void noteLag() {
      final next = waiting.length > lagAfter;
      if (next == lagging) return;
      lagging = next;
      onLag?.call(next);
    }

    void flush() {
      while (waiting.isNotEmpty && !outgoing.isPaused && !outgoing.isClosed) {
        outgoing.add(waiting.removeAt(0));
      }
      noteLag();
    }

    outgoing.onResume = flush;
    _incoming = input.listen((chunk) {
      waiting.add(
        AudioChunk(
          bytes: Uint8List.fromList(chunk.bytes),
          offset: chunk.offset,
        ),
      );
      flush();
    });
    return partials;
  }

  Future<void> close() async {
    await _incoming?.cancel();
    _incoming = null;
    final outgoing = _outgoing;
    _outgoing = null;
    if (outgoing != null && !outgoing.isClosed) await outgoing.close();
  }
}
