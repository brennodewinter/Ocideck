// Het ASR-serverprofiel (#2524): round-trip, defaults en de helpers die
// de UI (#2514) gebruikt. En de weigerende helften + de io-audiolezer —
// alles wat op de VM écht kan draaien.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_audio_source.dart' as facade;
import 'package:ocideck/services/transcription/asr_audio_source_io.dart' as io;
import 'package:ocideck/services/transcription/asr_audio_source_stub.dart'
    as stub;
import 'package:ocideck/services/transcription/asr_audio_source_web.dart'
    as web;
import 'package:ocideck/services/transcription/asr_transport_stub.dart'
    as t_stub;
import 'package:ocideck/services/transcription/transcription_errors.dart';
import 'package:ocideck/services/transcription/asr_transport.dart'
    show AiResolveStrategy;
import 'package:ocideck/services/web_asset_store.dart';

void main() {
  group('profiel', () {
    test('round-trip bewaart alle velden', () {
      const p = AsrServerProfile(
        enabled: true,
        mode: AsrServerMode.cloud,
        baseUrl: 'https://asr.example.nl',
        name: 'werkasr',
        trustedInternal: true,
        cloudConfirmed: true,
        liveUrl: 'wss://asr.example.nl/live',
      );
      final back = AsrServerProfile.fromJson(p.toJson());
      expect(back, p);
    });

    test('een profiel van vóór #2525 leest liveUrl als leeg', () {
      final p = AsrServerProfile.fromJson({
        'enabled': true,
        'mode': 'loopback',
        'baseUrl': 'http://127.0.0.1:8080',
      });
      expect(p.liveUrl, '');
      expect(p.hasLiveEndpoint, isFalse);
      expect(p.liveHost, '');
    });

    test('liveHost en hasLiveEndpoint lezen het live-endpoint', () {
      const p = AsrServerProfile(
        mode: AsrServerMode.loopback,
        baseUrl: 'http://127.0.0.1:8080',
        liveUrl: 'ws://127.0.0.1:2700',
      );
      expect(p.hasLiveEndpoint, isTrue);
      expect(p.liveHost, '127.0.0.1');
    });

    test('defaults zijn uit, geen modus, geen bevestigingen', () {
      const p = AsrServerProfile();
      expect(p.enabled, isFalse);
      expect(p.mode, AsrServerMode.none);
      expect(p.isConfigured, isFalse);
      expect(p.hasEndpoint, isFalse);
    });

    test('een kapotte of verouderde mode-naam valt terug op none', () {
      final p = AsrServerProfile.fromJson({
        'enabled': true,
        'mode': 'geheim',
        'baseUrl': 'https://x.nl',
      });
      expect(p.mode, AsrServerMode.none);
      expect(p.isConfigured, isFalse);
    });

    test('uitgeschakeld maar wel ingevuld blijft zichtbaar', () {
      const p = AsrServerProfile(
        mode: AsrServerMode.cloud,
        baseUrl: 'https://asr.example.nl',
      );
      expect(p.hasEndpoint, isTrue);
      expect(p.isConfigured, isFalse);
      expect(p.host, 'asr.example.nl');
      expect(p.provenanceName, 'asr.example.nl');
    });

    test('de eigen naam wint in de provenance, anders de host', () {
      const p = AsrServerProfile(
        mode: AsrServerMode.loopback,
        baseUrl: 'http://127.0.0.1:8080',
        name: 'studio-pc',
      );
      expect(p.provenanceName, 'studio-pc');
    });
  });

  group('io-audiolezer', () {
    test('leest een echt bestandspad', () async {
      final f = File(
        '${Directory.systemTemp.path}/asr-src-${DateTime.now().microsecondsSinceEpoch}.wav',
      );
      await f.writeAsBytes(Uint8List.fromList([1, 2, 3, 4]));
      try {
        expect(await io.readAsrAudio(f.path), [1, 2, 3, 4]);
      } finally {
        await f.delete();
      }
    });

    test('een weggevallen bestand is SourceUnavailable', () {
      expect(
        io.readAsrAudio('/definitief/niet/daar.wav'),
        throwsA(isA<SourceUnavailable>()),
      );
    });

    test('een mem-sleutel leest uit de assetstore', () async {
      final stored = WebAssetStore.put(
        Uint8List.fromList([9, 9]),
        name: 't.wav',
      );
      expect(await io.readAsrAudio(stored), [9, 9]);
      // Ook via de facade: op de VM resolveert die naar de io-helft.
      expect(await facade.readAsrAudio(stored), [9, 9]);
      expect(
        io.readAsrAudio('mem:definitief-weg'),
        throwsA(isA<SourceUnavailable>()),
      );
    });
  });

  group('web-audiolezer', () {
    test('kent alleen mem: en weigert paden', () async {
      // De webhelft gebruikt geen js_interop — de mem:/pad-logica loopt
      // dus óók op de VM en hoort hier gedekt.
      expect(
        () => web.readAsrAudio('/tmp/mag-niet.wav'),
        throwsA(isA<UnsupportedSource>()),
      );
      expect(
        web.readAsrAudio('mem:definitief-weg'),
        throwsA(isA<SourceUnavailable>()),
      );
      final stored = WebAssetStore.put(Uint8List.fromList([7]), name: 'w.wav');
      expect(await web.readAsrAudio(stored), [7]);
    });
  });

  group('weigerende helften', () {
    test('stub-lezer en -transport weigeren getypeerd', () {
      expect(() => stub.readAsrAudio('x'), throwsA(isA<UnsupportedSource>()));
      final h = const t_stub.StubAsrTransport().send(
        method: 'POST',
        url: Uri.parse('http://127.0.0.1:1'),
        strategy: AiResolveStrategy.loopbackDirect,
        body: null,
      );
      expect(h.done, throwsA(isA<UnsupportedSource>()));
      h.cancel();
    });
  });
}
