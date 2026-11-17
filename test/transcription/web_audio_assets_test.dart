@TestOn('browser')
library;

import 'dart:js_interop';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/file_capture_source_web.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/web_asset_store.dart';

@JS('eval')
external JSAny? evaluate(JSString code);

void main() {
  late void Function() unregister;
  const requestConsent = RecordingConsent(participantNoticeAcknowledged: true);

  setUp(() {
    WebAssetStore.clear();
    unregister = WebAssetStore.registerRoots(() => {});
    evaluate(
      'globalThis.savedAudioAssetBridge = globalThis.ocideckWhisper'.toJS,
    );
  });
  tearDown(() {
    unregister();
    WebAssetStore.clear();
    evaluate('globalThis.ocideckWhisper = savedAudioAssetBridge'.toJS);
  });

  CaptureRequest request(String path) => CaptureRequest(
    kinds: const {CaptureSourceKind.file},
    consent: requestConsent,
    sourcePath: path,
  );

  test(
    'WAV-bron overleeft sweep tussen voorbeschouwing en engine-invoer',
    () async {
      final path = WebAssetStore.put(
        encodePcmWav(Float32List(1600)),
        name: 'bron.wav',
      );
      final preview = WebAssetStore.lease([path]);
      const source = WebFileCaptureSource();
      expect((await source.describe(path)).engineReadsDirectly, isTrue);
      WebAssetStore.retain({});
      final session = await source.start(request(path));
      final audio = await session.stop();
      preview.release();
      WebAssetStore.retain({});
      expect(WebAssetStore.bytesFor(audio.durablePath), isNotNull);
      audio.releaseAssets();
      expect(WebAssetStore.totalBytes, 0);
    },
  );

  test('bron en gedecodeerde WAV blijven tot de taak klaar is', () async {
    evaluate(
      'globalThis.ocideckWhisper = {decodeAudio: async () => new Float32Array(1600)}'
          .toJS,
    );
    final path = WebAssetStore.put(
      Uint8List.fromList([79, 103, 103, 83, 1]),
      name: 'bron.ogg',
    );
    final preview = WebAssetStore.lease([path]);
    final session = await const WebFileCaptureSource().start(request(path));
    final audio = await session.stop();
    expect(audio.durablePath, isNot(path));
    preview.release();
    WebAssetStore.retain({});
    expect(WebAssetStore.bytesFor(path), isNotNull);
    final wav = WebAssetStore.bytesFor(audio.durablePath)!;
    expect(
      parseWavHeader(wav, wav.length)!.duration,
      const Duration(milliseconds: 100),
    );
    audio.releaseAssets();
    expect(WebAssetStore.totalBytes, 0);
  });

  test(
    'cancel tijdens decode houdt bron vast tot de niet-annuleerbare read eindigt',
    () async {
      evaluate(
        '''
      globalThis.ocideckWhisper = {decodeAudio: () => new Promise(resolve => {
        globalThis.finishAssetDecode = () => resolve(new Float32Array(1600));
      })};
    '''
            .toJS,
      );
      final path = WebAssetStore.put(
        Uint8List.fromList([79, 103, 103, 83, 2]),
        name: 'bron.ogg',
      );
      final preview = WebAssetStore.lease([path]);
      final session = await const WebFileCaptureSource().start(request(path));
      final pending = session.stop();
      final check = expectLater(pending, throwsA(isA<Cancelled>()));
      session.cancel();
      preview.release();
      WebAssetStore.retain({});
      expect(WebAssetStore.bytesFor(path), isNotNull);
      evaluate('finishAssetDecode()'.toJS);
      await check;
      expect(WebAssetStore.totalBytes, 0);
    },
  );

  test(
    'decodefout ruimt de eigen bron op en laat andere documenten staan',
    () async {
      final image = WebAssetStore.put(
        Uint8List.fromList([8, 9]),
        name: 'bestaand.png',
      );
      final documentRoots = WebAssetStore.registerRoots(() => {image});
      addTearDown(documentRoots);
      evaluate(
        'globalThis.ocideckWhisper = {decodeAudio: async () => {throw new Error("decoder");}}'
            .toJS,
      );
      final path = WebAssetStore.put(
        Uint8List.fromList([79, 103, 103, 83, 3]),
        name: 'bron.ogg',
      );
      final preview = WebAssetStore.lease([path]);
      final session = await const WebFileCaptureSource().start(request(path));
      preview.release();
      await expectLater(session.stop(), throwsA(isA<DecodeFailed>()));
      expect(WebAssetStore.bytesFor(path), isNull);
      expect(WebAssetStore.bytesFor(image), [8, 9]);
    },
  );

  test(
    'twee taken en een document mogen dezelfde gededupliceerde audio delen',
    () async {
      final path = WebAssetStore.put(
        encodePcmWav(Float32List(1600)),
        name: 'gedeeld.wav',
      );
      final document = <String>{};
      addTearDown(WebAssetStore.registerRoots(() => document));
      final a = await const WebFileCaptureSource().start(request(path));
      final b = await const WebFileCaptureSource().start(request(path));
      final first = await a.stop();
      final second = await b.stop();
      first.releaseAssets();
      expect(WebAssetStore.bytesFor(path), isNotNull);
      document.add(path);
      second.releaseAssets();
      expect(WebAssetStore.bytesFor(path), isNotNull);
      document.clear();
      WebAssetStore.collectGarbage();
      expect(WebAssetStore.totalBytes, 0);
    },
  );
}
