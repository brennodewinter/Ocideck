@TestOn('browser')
library;

import 'dart:convert';
import 'dart:js_interop';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/web_media_browser_web.dart';

@JS('eval')
external JSAny? evaluate(JSString code);

void install({bool failRead = false, bool omitStop = false}) {
  evaluate(
    '''
    globalThis.mediaTrackStops = 0;
    globalThis.mediaStopCalls = 0;
    globalThis.mediaTrack = {stop() {mediaTrackStops++;}, onended: null};
    globalThis.mediaStream = new MediaStream();
    mediaStream.getTracks = () => [mediaTrack];
    mediaStream.getAudioTracks = () => [mediaTrack];
    Object.defineProperty(navigator.mediaDevices, 'getUserMedia', {
      configurable: true, writable: true, value: async () => mediaStream
    });
    globalThis.MediaRecorder = class {
      static isTypeSupported() { return true; }
      constructor() {
        globalThis.mediaRecorder = this;
        this.state = 'inactive';
        this.mimeType = 'audio/webm';
      }
      start() { this.state = 'recording'; }
      stop() {
        mediaStopCalls++;
        this.state = 'inactive';
        if ($omitStop) return;
        this.finish();
      }
      finish() {
        this.state = 'inactive';
        [[1, 2], [3], [4, 5]].forEach((bytes, i) => {
          const blob = new Blob([new Uint8Array(bytes)]);
          blob.arrayBuffer = () => $failRead ? Promise.reject(new Error('read failed')) :
            new Promise(resolve => setTimeout(() => resolve(new Uint8Array(bytes).buffer), [30, 0, 10][i]));
          this.ondataavailable(new BlobEvent('dataavailable', {data: blob}));
        });
        this.onstop(new Event('stop'));
      }
    };
  '''
        .toJS,
  );
}

int count(String expression) =>
    (evaluate(expression.toJS) as JSNumber).toDartInt;

void main() {
  setUp(() {
    evaluate(
      '''
      globalThis.savedMediaRecorder = globalThis.MediaRecorder;
      globalThis.savedGetUserMedia = navigator.mediaDevices.getUserMedia;
    '''
          .toJS,
    );
  });
  tearDown(() {
    evaluate(
      '''
      globalThis.MediaRecorder = savedMediaRecorder;
      Object.defineProperty(navigator.mediaDevices, 'getUserMedia', {
        configurable: true, writable: true, value: savedGetUserMedia
      });
    '''
          .toJS,
    );
  });

  test('Stop wacht op alle Blob-reads en bewaart de eventvolgorde', () async {
    install();
    final live = await WebMediaBrowserImpl().openMicrophone();
    final bytes = <int>[];
    live.chunks.listen(bytes.addAll);
    final first = live.stop();
    final second = live.stop();
    expect(identical(first, second), isTrue);
    await first;
    await second;
    expect(bytes, [1, 2, 3, 4, 5]);
    expect(count('mediaStopCalls'), 1);
    expect(count('mediaTrackStops'), 1);
  });

  test(
    'inactief vóór onstop sluit de laatste data niet voortijdig af',
    () async {
      install();
      final live = await WebMediaBrowserImpl().openMicrophone();
      final bytes = <int>[];
      live.chunks.listen(bytes.addAll);
      evaluate(
        '''
      mediaRecorder.state = 'inactive';
      setTimeout(() => mediaRecorder.finish(), 20);
    '''
            .toJS,
      );
      await live.stop();
      expect(bytes, [1, 2, 3, 4, 5]);
      expect(count('mediaStopCalls'), 0);
      expect(count('mediaTrackStops'), 1);
    },
  );

  test(
    'spontane recorderstop meldt bronverlies en bewaart de staart',
    () async {
      install();
      final live = await WebMediaBrowserImpl().openMicrophone();
      final bytes = <int>[];
      live.chunks.listen(bytes.addAll);
      final ended = live.ended!.first;
      evaluate('mediaRecorder.finish()'.toJS);
      expect(await ended, CaptureEndCause.sourceLost);
      await live.stop();
      expect(bytes, [1, 2, 3, 4, 5]);
      expect(count('mediaTrackStops'), 1);
    },
  );

  for (final event in [
    'mediaTrack.onended(new Event("ended"))',
    'mediaRecorder.onerror(new Event("error"))',
  ]) {
    test('browser-eindevent wordt doorgegeven: $event', () async {
      install();
      final live = await WebMediaBrowserImpl().openMicrophone();
      live.chunks.listen((_) {});
      final ended = live.ended!.first;
      evaluate(event.toJS);
      expect(await ended, CaptureEndCause.sourceLost);
      await live.stop();
      expect(count('mediaTrackStops'), 1);
    });
  }

  test('mislukte Blob-read is getypeerd en geeft de tracks vrij', () async {
    install(failRead: true);
    final live = await WebMediaBrowserImpl().openMicrophone();
    live.chunks.listen((_) {});
    await expectLater(live.stop(), throwsA(isA<DecodeFailed>()));
    expect(count('mediaTrackStops'), 1);
  });

  test('ontbrekende onstop eindigt begrensd met een fout', () async {
    install(omitStop: true);
    final live = await WebMediaBrowserImpl(
      stopTimeout: const Duration(milliseconds: 30),
    ).openMicrophone();
    live.chunks.listen((_) {});
    await expectLater(live.stop(), throwsA(isA<IoFailed>()));
    expect(count('mediaTrackStops'), 1);
  });

  test(
    'echte korte MediaRecorder-opname bevat decodeerbare audio na Stop',
    () async {
      // Een synthetisch audiospoor: geen microfoon, geen gebruikersaudio.
      evaluate(
        '''
      globalThis.MediaRecorder = savedMediaRecorder;
      globalThis.generatedAudioTrack = new MediaStreamTrackGenerator({kind: 'audio'});
      globalThis.generatedAudioWriter = generatedAudioTrack.writable.getWriter();
      Object.defineProperty(navigator.mediaDevices, 'getUserMedia', {
        configurable: true, writable: true,
        value: async () => new MediaStream([generatedAudioTrack])
      });
    '''
            .toJS,
      );
      final live = await WebMediaBrowserImpl().openMicrophone();
      final bytes = <int>[];
      live.chunks.listen(bytes.addAll);
      await (evaluate(
                '''
      (async () => {
        for (let i = 0; i < 10; i++) {
          const samples = new Float32Array(960);
          for (let j = 0; j < samples.length; j++) {
            samples[j] = 0.1 * Math.sin(2 * Math.PI * 440 * (i * 960 + j) / 48000);
          }
          const data = new AudioData({format: 'f32', sampleRate: 48000,
            numberOfFrames: 960, numberOfChannels: 1, timestamp: i * 20000,
            data: samples});
          await generatedAudioWriter.write(data);
          data.close();
          await new Promise(resolve => setTimeout(resolve, 20));
        }
      })()
    '''
                    .toJS,
              )
              as JSPromise<JSAny?>)
          .toDart;
      await live.stop();
      expect(bytes, isNotEmpty);
      final duration =
          await (evaluate(
                    '''
      (async () => {
        const context = new AudioContext();
        try {
          const decoded = await context.decodeAudioData(new Uint8Array(${jsonEncode(bytes)}).buffer);
          return decoded.duration;
        } finally { await context.close(); }
      })()
    '''
                        .toJS,
                  )
                  as JSPromise<JSNumber>)
              .toDart;
      expect(duration.toDartDouble, greaterThan(0));
      expect(duration.toDartDouble, lessThan(1));
      expect(
        evaluate('generatedAudioTrack.readyState'.toJS).dartify(),
        'ended',
      );
    },
  );

  test('browserweigering blijft PermissionDenied', () async {
    install();
    evaluate(
      '''
      navigator.mediaDevices.getUserMedia = async () => {
        throw new DOMException('denied', 'NotAllowedError');
      };
    '''
          .toJS,
    );
    await expectLater(
      WebMediaBrowserImpl().openMicrophone(),
      throwsA(isA<PermissionDenied>()),
    );
  });
}
