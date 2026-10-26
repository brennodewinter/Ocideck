// De provisionele pass (#2522). Een engine zonder streaming levert null.
// Een engine die pauzeert laat blokken wachten; er gaat er geen verloren
// en de achterstand wordt benoemd.
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/live_pass.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';

class _Engine implements TranscriptionEngine {
  _Engine({required this.streaming});

  final bool streaming;
  final received = <AudioChunk>[];
  StreamSubscription<AudioChunk>? sub;
  var pauseOnListen = false;
  TranscriptionOptions? seenOptions;

  @override
  EngineKind get kind => EngineKind.local;

  @override
  Future<EngineCapabilities> capabilities() async =>
      EngineCapabilities(streaming: streaming);

  @override
  Future<TranscriptResult> transcribe(
    AudioRef audio,
    TranscriptionOptions options,
  ) => throw UnimplementedError();

  @override
  void cancel() {}

  @override
  Stream<PartialTranscript>? transcribeLive(
    Stream<AudioChunk> chunks, {
    TranscriptionOptions? options,
  }) {
    seenOptions = options;
    if (!streaming) return null;
    final out = StreamController<PartialTranscript>();
    late StreamSubscription<AudioChunk> subscription;
    subscription = chunks.listen((chunk) {
      received.add(chunk);
      out.add(
        PartialTranscript(text: 't${received.length}', offset: chunk.offset),
      );
    });
    sub = subscription;
    if (pauseOnListen) subscription.pause();
    return out.stream;
  }
}

void main() {
  test('zonder streaming-engine is er geen live-route', () async {
    final pass = LivePass();
    final partials = pass.attach(
      engine: _Engine(streaming: false),
      chunks: const Stream<AudioChunk>.empty(),
    );
    expect(partials, isNull);
    expect(pass.lagging, isFalse);
    await pass.close();
  });

  test('opties gaan ongemoeid door naar de engine', () async {
    final engine = _Engine(streaming: true);
    final pass = LivePass();
    const options = TranscriptionOptions(
      serverConsent: ServerConsent.liveSession('127.0.0.1'),
    );
    final partials = pass.attach(
      engine: engine,
      chunks: const Stream<AudioChunk>.empty(),
      options: options,
    );
    expect(partials, isNotNull);
    expect(engine.seenOptions, same(options));
    await pass.close();
  });

  test(
    'een pauzerende engine laat niets vallen en noemt de achterstand',
    () async {
      final engine = _Engine(streaming: true)..pauseOnListen = true;
      final pass = LivePass();
      final input = StreamController<AudioChunk>();
      final lags = <bool>[];
      final partials = pass.attach(
        engine: engine,
        chunks: input.stream,
        onLag: lags.add,
        lagAfter: 2,
      );
      final texts = <String>[];
      partials!.listen((part) => texts.add(part.text));
      for (var i = 0; i < 6; i++) {
        input.add(
          AudioChunk(
            bytes: Uint8List.fromList([i]),
            offset: Duration(milliseconds: i),
          ),
        );
      }
      await Future<void>.delayed(Duration.zero);
      expect(engine.received, isEmpty);
      expect(pass.lagging, isTrue);
      expect(lags, contains(true));
      engine.sub!.resume();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(engine.received, hasLength(6));
      expect(texts, hasLength(6));
      expect(pass.lagging, isFalse);
      await input.close();
      await pass.close();
    },
  );
}
