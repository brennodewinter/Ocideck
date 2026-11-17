// De expliciete protocolgrens: geen capability, geen upload met diarisatie.
import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/transcription/asr_batch_protocol.dart';
import 'package:ocideck/services/transcription/asr_server_engine.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/transcript_document.dart';
import 'package:ocideck/services/transcription/transcription_engine.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

const _caps =
    '{"protocol":"ocideck-asr","version":1,"languages":["nl","en"],'
    '"features":{"timestamps":true,"diarization":true}}';

String _response(List<Map<String, Object?>> segments, {bool applied = true}) =>
    jsonEncode({
      'protocol': 'ocideck-asr',
      'version': 1,
      'diarization_applied': applied,
      'segments': segments,
    });

Map<String, Object?> _segment(
  String text,
  List<String> speakers, {
  double start = 0,
  double end = 1,
  bool uncertain = false,
}) => {
  'text': text,
  'start': start,
  'end': end,
  'speaker_ids': speakers,
  'speaker_uncertain': uncertain,
};

class _Transport implements AsrTransport {
  final methods = <String>[];
  final urls = <Uri>[];
  final bodies = <Uint8List?>[];
  String capabilities = _caps;
  String response = _response([
    _segment('Hallo', ['a']),
  ]);
  Completer<AsrResponse>? pending;
  bool cancelled = false;

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    required Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    methods.add(method);
    urls.add(url);
    bodies.add(body);
    return AsrSendHandle(
      done:
          pending?.future ??
          Future.value(
            AsrResponse(200, method == 'GET' ? capabilities : response),
          ),
      cancel: () {
        cancelled = true;
        if (pending case final value? when !value.isCompleted) {
          value.completeError(const AsrRequestException('afgebroken'));
        }
      },
    );
  }
}

void main() {
  const profile = AsrServerProfile(
    enabled: true,
    mode: AsrServerMode.loopback,
    baseUrl: 'http://127.0.0.1:8093/base',
    batchProtocol: AsrBatchProtocol.ocideckV1,
  );
  const options = TranscriptionOptions(
    diarize: true,
    language: 'nl',
    serverConsent: ServerConsent(host: '127.0.0.1', audioPath: 'local.wav'),
  );

  test('oude profielen blijven whisper; onbekende versies blijven dicht', () {
    expect(
      AsrServerProfile.fromJson({}).batchProtocol,
      AsrBatchProtocol.whisperCpp,
    );
    expect(
      AsrServerProfile.fromJson({'batchProtocol': 'future'}).batchProtocol,
      AsrBatchProtocol.unsupported,
    );
    expect(AsrServerProfile.fromJson(profile.toJson()), profile);
    expect(
      profile.copyWith(name: 'anders').batchProtocol,
      AsrBatchProtocol.ocideckV1,
    );
  });

  test(
    'handshake zonder audio; iedere taak onderhandelt voor het lezen',
    () async {
      final t = _Transport();
      var reads = 0;
      final e = AsrServerEngine(
        profile: profile,
        transport: t,
        audioReader: (_) async {
          reads++;
          return Uint8List(44);
        },
      );
      expect((await e.capabilities()).diarization, isTrue);
      expect(reads, 0);
      expect(t.bodies.single, isNull);
      final result = await e.transcribe(const AudioRef('local.wav'), options);
      expect(reads, 1);
      expect(result.segments.single.speakerIds, ['a']);
      expect(t.methods, ['GET', 'GET', 'POST']);
      expect(t.urls.last.path, '/base/ocideck-asr/v1/transcribe');
      expect(
        utf8.decode(t.bodies.last!),
        contains('name="diarize"\r\n\r\ntrue'),
      );
      expect(utf8.decode(t.bodies.last!), isNot(contains('local.wav')));
    },
  );

  test(
    'geen toestemming betekent ook geen capabilityverzoek bij transcribe',
    () async {
      final t = _Transport();
      final e = AsrServerEngine(
        profile: profile,
        transport: t,
        audioReader: (_) async => throw StateError('niet lezen'),
      );
      await expectLater(
        e.transcribe(
          const AudioRef('local.wav'),
          const TranscriptionOptions(diarize: true),
        ),
        throwsA(isA<ConsentRequired>()),
      );
      expect(t.methods, isEmpty);
    },
  );

  test(
    'zonder taaldetectie is een expliciete taal vóór audiolezen verplicht',
    () async {
      final t = _Transport();
      final e = AsrServerEngine(
        profile: profile,
        transport: t,
        audioReader: (_) async => throw StateError('niet lezen'),
      );
      expect((await e.capabilities()).automaticLanguage, isFalse);
      await expectLater(
        e.transcribe(
          const AudioRef('local.wav'),
          const TranscriptionOptions(
            diarize: true,
            serverConsent: ServerConsent(
              host: '127.0.0.1',
              audioPath: 'local.wav',
            ),
          ),
        ),
        throwsA(isA<EngineUnavailable>()),
      );
      expect(t.methods, ['GET', 'GET']);
    },
  );

  test('metadata maakt een leeg transcript niet tot een spraakresultaat', () {
    expect(
      formatTranscriptBody(const [
        TranscriptSegment(
          text: '  ',
          start: Duration.zero,
          end: Duration(seconds: 1),
          speakerIds: ['a'],
        ),
      ]),
      isEmpty,
    );
  });

  test('ontbrekende capability weigert vóór audiolezen en upload', () async {
    final t = _Transport()
      ..capabilities = _caps.replaceFirst(
        '"diarization":true',
        '"diarization":false',
      );
    final e = AsrServerEngine(
      profile: profile,
      transport: t,
      audioReader: (_) async => throw StateError('niet lezen'),
    );
    await expectLater(
      e.transcribe(const AudioRef('local.wav'), options),
      throwsA(isA<EngineUnavailable>()),
    );
    expect(t.methods, ['GET']);
  });

  test('annuleren tijdens handshake voorkomt audiolezen en upload', () async {
    final t = _Transport()..pending = Completer();
    final e = AsrServerEngine(
      profile: profile,
      transport: t,
      audioReader: (_) async => throw StateError('niet lezen'),
    );
    final future = e.transcribe(const AudioRef('local.wav'), options);
    await Future<void>.delayed(Duration.zero);
    e.cancel();
    await expectLater(future, throwsA(isA<Cancelled>()));
    expect(t.cancelled, isTrue);
    expect(t.methods, ['GET']);
  });

  test('A-B-A behoudt IDs; overlap en onbekend zijn geen nieuwe persoon', () {
    final result = parseAsrBatchResponse(
      _response([
        _segment('een', ['a']),
        _segment('twee', ['b'], start: 1, end: 2),
        _segment('terug', ['a'], start: 2, end: 3),
        _segment('samen', ['a', 'b'], start: 3, end: 4),
        _segment('twijfel', [], start: 4, end: 5),
      ]),
      diarize: true,
    );
    final body = formatTranscriptBody(
      result.segments,
      speakerLabel: 'Speaker',
      unknownLabel: 'Unknown',
    );
    expect(RegExp(r'\*\*Speaker 1:\*\*').allMatches(body).length, 2);
    expect(body, contains('**Speaker 1 + Speaker 2:** samen'));
    expect(body, contains('**Unknown (?):** twijfel'));
    final encoded = RegExp(
      r'ocideck:segments:v1 (\[.*\]) -->',
    ).firstMatch(body)![1]!;
    final raw = jsonDecode(encoded) as List;
    expect(raw[2]['speaker_ids'], ['a']);
    expect(raw[2]['end_us'], 3000000);
    expect(
      body.replaceAll('Speaker 1', 'Alice'),
      contains('Alice + Speaker 2'),
    );
  });

  test('uitgeschakeld resultaat krijgt nooit serverlabels', () {
    final result = parseAsrBatchResponse(
      _response([
        _segment('tekst', ['a']),
      ], applied: false),
      diarize: false,
    );
    expect(result.segments.single.speakerIds, isEmpty);
    expect(formatTranscriptBody(result.segments), isNot(contains('**')));
  });

  test('ruwe IDs kunnen het metadata-commentaar niet afsluiten', () {
    final body = formatTranscriptBody(const [
      TranscriptSegment(
        text: 'tekst',
        end: Duration(seconds: 1),
        speakerIds: ['raw--><script>'],
      ),
    ]);
    expect(RegExp('-->').allMatches(body).length, 1);
    expect(body, isNot(contains('<script>')));
    final encoded = RegExp(
      r'ocideck:segments:v1 (\[.*\]) -->',
    ).firstMatch(body)![1]!;
    final raw = jsonDecode(encoded) as List;
    expect(raw.single['speaker_ids'], ['raw--><script>']);
  });

  test('server mag de diarisatiekeuze niet stil verliezen', () {
    expect(
      () => parseAsrBatchResponse(_response([], applied: false), diarize: true),
      throwsA(isA<ServerRefused>()),
    );
  });

  for (final bad in [
    '{"protocol":"other","version":1}',
    _caps.replaceFirst('"version":1', '"version":2'),
    _caps.replaceFirst('["nl","en"]', '[1]'),
    _caps.replaceFirst('"diarization":true', '"diarization":"yes"'),
    'not json',
  ]) {
    test('weigert verkeerde protocolversie of capabilityvorm: $bad', () {
      expect(
        () => parseAsrBatchCapabilities(bad),
        throwsA(isA<ServerRefused>()),
      );
    });
  }

  for (final raw in [
    _segment('x', ['a'], end: -1),
    _segment('x', ['a'])..['start'] = '0',
    _segment('x', ['a'])..remove('end'),
    _segment('x', ['a', 'a']),
    _segment('x', ['</script>']),
    _segment('x', ['a'])..['speaker_uncertain'] = null,
  ]) {
    test('weigert ongeldige tijd of sprekerdata: $raw', () {
      expect(
        () => parseAsrBatchResponse(_response([raw]), diarize: true),
        throwsA(isA<ServerRefused>()),
      );
    });
  }
}
