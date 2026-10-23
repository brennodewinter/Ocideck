// De serverengine (#2524) met een fake transport: de echte bewijsvoering
// is wat er verstuurd wordt (multipart-body, headers) en wat er terugkomt
// (parsen van verbose_json), zonder dat een test het netwerk raakt.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/capture_source.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

/// Vangt één verzoek en antwoordt met wat de test instelde.
class FakeTransport implements AsrTransport {
  AsrResponse? respondWith;
  Object? throwWith;
  bool cancelled = false;
  String? method;
  Uri? url;
  Map<String, String>? headers;
  Uint8List? body;

  /// Als gezet, hangt `done` tot de test hem zelf completeert — voor de
  /// annuleerbaarheidsproef.
  Completer<AsrResponse>? gate;

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    this.method = method;
    this.url = url;
    this.headers = headers;
    this.body = body;
    Future<AsrResponse> done;
    if (gate != null) {
      done = gate!.future;
    } else if (throwWith != null) {
      done = Future.error(throwWith!);
    } else {
      done = Future.value(respondWith ?? const AsrResponse(200, '{"text":""}'));
    }
    return AsrSendHandle(done: done, cancel: () => cancelled = true);
  }
}

Uint8List fakeAudio([int size = 512]) => Uint8List(size);

void main() {
  const profile = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.loopback,
    baseUrl: 'http://127.0.0.1:8080',
    name: 'testserver',
  );
  const ref = AudioRef('mem:a1');
  const consent = ServerConsent(host: '127.0.0.1', audioPath: 'mem:a1');
  const options = TranscriptionOptions(serverConsent: consent);

  AsrServerEngine engine(FakeTransport transport) => AsrServerEngine(
    profile: profile,
    transport: transport,
    audioReader: (path) async => path == 'mem:a1' ? fakeAudio() : fakeAudio(16),
    apiKeyReader: () async => 's3cr3t',
  );

  group('toestemming en poort', () {
    test('zonder ServerConsent vertrekt er niets', () {
      final t = FakeTransport();
      expect(
        engine(t).transcribe(ref, const TranscriptionOptions()),
        throwsA(isA<ConsentRequired>()),
      );
      expect(t.url, isNull, reason: 'er mag geen verzoek gestuurd zijn');
    });

    test('consent voor een andere host dekt deze taak niet', () {
      final t = FakeTransport();
      expect(
        engine(t).transcribe(
          ref,
          const TranscriptionOptions(
            serverConsent: ServerConsent(
              host: 'asr.example.nl',
              audioPath: 'mem:a1',
            ),
          ),
        ),
        throwsA(isA<ConsentRequired>()),
      );
      expect(t.url, isNull);
    });

    test('consent voor een andere audio dekt deze taak niet', () {
      final t = FakeTransport();
      expect(
        engine(t).transcribe(
          ref,
          const TranscriptionOptions(
            serverConsent: ServerConsent(
              host: '127.0.0.1',
              audioPath: 'mem:anders',
            ),
          ),
        ),
        throwsA(isA<ConsentRequired>()),
      );
      expect(t.url, isNull);
    });

    test('een niet-bruikbaar profiel faalt vóór de consentvraag', () {
      final e = AsrServerEngine(
        profile: const AsrServerProfile(),
        transport: FakeTransport(),
        audioReader: (p) async => fakeAudio(),
      );
      expect(e.transcribe(ref, options), throwsA(isA<EngineUnavailable>()));
    });
  });

  group('verzoekvorm', () {
    test('POST naar /inference met multipart body en verbose_json', () async {
      final t = FakeTransport()
        ..respondWith = const AsrResponse(200, '{"text":"hallo"}');
      final result = await engine(t).transcribe(ref, options);
      expect(result.text, 'hallo');
      expect(t.method, 'POST');
      expect(t.url.toString(), 'http://127.0.0.1:8080/inference');
      final contentType = t.headers!['content-type']!;
      expect(contentType, contains('multipart/form-data'));
      final boundary = contentType.split('boundary=').last;
      final bodyText = utf8.decode(t.body!, allowMalformed: true);
      expect(bodyText, contains('--$boundary'));
      expect(
        bodyText,
        contains('Content-Disposition: form-data; name="response_format"'),
      );
      expect(bodyText, contains('verbose_json'));
      expect(bodyText, contains('name="file"'));
      expect(bodyText, contains('filename="audio.wav"'));
      expect(t.body!.length, greaterThan(512));
    });

    test('taal gaat mee als veld', () async {
      final t = FakeTransport();
      await engine(t).transcribe(
        ref,
        const TranscriptionOptions(language: 'nl', serverConsent: consent),
      );
      expect(
        utf8.decode(t.body!, allowMalformed: true),
        contains('\r\nnl\r\n'),
      );
    });

    test(
      'de API-sleutel komt in de Authorization-header en nergens anders',
      () async {
        final t = FakeTransport();
        await engine(t).transcribe(ref, options);
        expect(t.headers!['authorization'], 'Bearer s3cr3t');
        expect(t.url.toString(), isNot(contains('s3cr3t')));
        expect(
          utf8.decode(t.body!, allowMalformed: true),
          isNot(contains('s3cr3t')),
        );
      },
    );

    test('zonder sleutel is er geen Authorization-header', () async {
      final t = FakeTransport();
      await AsrServerEngine(
        profile: profile,
        transport: t,
        audioReader: (p) async => fakeAudio(),
      ).transcribe(ref, options);
      expect(t.headers!.keys, isNot(contains('authorization')));
    });
  });

  group('antwoord en fouten', () {
    test('verbose_json-segmenten leveren tijdstempels', () async {
      final t = FakeTransport()
        ..respondWith = const AsrResponse(
          200,
          '{"task":"transcribe","segments":[{"id":0,"text":" dag","start":0.5,"end":1.2},{"id":1,"text":" meneer","start":1.2,"end":2.0}]}',
        );
      final r = await engine(t).transcribe(ref, options);
      expect(r.segments, hasLength(2));
      expect(r.segments[0].text, ' dag');
      expect(r.segments[0].start, const Duration(milliseconds: 500));
      expect(r.text, ' dag meneer');
    });

    test('kapotte JSON en ontbrekende velden zijn ServerRefused', () {
      final t = FakeTransport()
        ..respondWith = const AsrResponse(200, 'geen json');
      expect(engine(t).transcribe(ref, options), throwsA(isA<ServerRefused>()));
      t.respondWith = const AsrResponse(200, '{"iets":1}');
      expect(engine(t).transcribe(ref, options), throwsA(isA<ServerRefused>()));
    });

    test('HTTP-fout is ServerRefused, nooit stil', () {
      final t = FakeTransport()..respondWith = const AsrResponse(500, 'x');
      expect(engine(t).transcribe(ref, options), throwsA(isA<ServerRefused>()));
    });

    test('netwerkfout van de transport is ServerRefused', () {
      final t = FakeTransport()
        ..throwWith = const AsrRequestException('netwerk');
      expect(engine(t).transcribe(ref, options), throwsA(isA<ServerRefused>()));
    });

    test('afgebroken verzoek is Cancelled, geen fout', () {
      final t = FakeTransport()
        ..throwWith = const AsrRequestException('afgebroken');
      expect(engine(t).transcribe(ref, options), throwsA(isA<Cancelled>()));
    });

    test('te grote audio is CapacityExceeded vóór het netwerk', () async {
      final t = FakeTransport();
      final e = AsrServerEngine(
        profile: profile,
        transport: t,
        audioReader: (p) async => Uint8List(AsrServerEngine.maxUploadBytes + 1),
      );
      expect(e.transcribe(ref, options), throwsA(isA<CapacityExceeded>()));
      expect(t.url, isNull);
    });
  });

  group('annuleren en probe', () {
    test('cancel() roept de afbreekknop van het lopende verzoek', () async {
      final t = FakeTransport()..gate = Completer<AsrResponse>();
      final e = engine(t);
      final future = e.transcribe(ref, options);
      await Future<void>.delayed(Duration.zero);
      e.cancel();
      expect(t.cancelled, isTrue);
      t.gate!.completeError(const AsrRequestException('afgebroken'));
      expect(future, throwsA(isA<Cancelled>()));
    });

    test('probe() verstuurt geen audio en toetst bereikbaarheid', () async {
      final t = FakeTransport()..respondWith = const AsrResponse(200, '<html>');
      final probe = await engine(t).probe();
      expect(probe.status, AsrProbeStatus.reachable);
      expect(t.method, 'GET');
      expect(t.body, isNull);
      expect(t.url.toString(), 'http://127.0.0.1:8080');
    });

    test('probe() meldt auth-eis en onbereikbaarheid als feit', () async {
      final t = FakeTransport()..respondWith = const AsrResponse(401, '');
      expect((await engine(t).probe()).status, AsrProbeStatus.authRequired);
      t.throwWith = const AsrRequestException('netwerk');
      t.respondWith = null;
      expect((await engine(t).probe()).status, AsrProbeStatus.unreachable);
    });

    test('probe() op een geweigerd profiel meldt de poortreden', () async {
      final probe = await AsrServerEngine(
        profile: const AsrServerProfile(),
        transport: FakeTransport(),
        audioReader: (p) async => fakeAudio(),
      ).probe();
      expect(probe.status, AsrProbeStatus.refused);
      expect(probe.detail, 'disabled');
    });
  });

  test('de batchserver heeft geen live-route', () async {
    final caps = await engine(FakeTransport()).capabilities();
    expect(caps.streaming, isFalse);
    expect(
      engine(FakeTransport()).transcribeLive(const Stream<AudioChunk>.empty()),
      isNull,
    );
  });
}
