import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/asr_server_profile.dart';
import 'package:ocideck/services/media/youtube_reference.dart';
import 'package:ocideck/services/media/youtube_source_client.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';

const _profile = AsrServerProfile(
  enabled: true,
  mode: AsrServerMode.loopback,
  baseUrl: 'http://127.0.0.1:8866',
);
const _consent = YoutubeSourceConsent(
  destination: 'http://127.0.0.1:8866',
  videoId: 'M7lc1UVf-VE',
);
const _track = YoutubeCaptionTrack(
  id: 'manual:en',
  language: 'en',
  automatic: false,
);
Map<String, Object?> _envelope(Map<String, Object?> fields) => {
  'protocol': 'ocideck-youtube',
  'version': 1,
  'video_id': 'M7lc1UVf-VE',
  ...fields,
};

class _Transport implements AsrTransport {
  final paths = <Uri>[];
  final bodies = <String?>[];
  bool cancelled = false;
  Completer<AsrResponse>? pending;
  int status = 200;
  Map<String, Object?> caps = _envelope({
    'captions': true,
    'audio': true,
    'audio_fragments': false,
  });
  Map<String, Object?> response = _envelope({
    'title': 'Public fixture',
    'duration_ms': 1344000,
    'status': 'completed',
    'audio': true,
    'tracks': [
      {'id': 'manual:en', 'language': 'en', 'kind': 'manual'},
    ],
  });

  @override
  AsrSendHandle send({
    required String method,
    required Uri url,
    required AiResolveStrategy strategy,
    required Uint8List? body,
    Map<String, String> headers = const {},
    Duration timeout = Duration.zero,
  }) {
    paths.add(url);
    bodies.add(body == null ? null : utf8.decode(body));
    return AsrSendHandle(
      done:
          pending?.future ??
          Future.value(
            AsrResponse(status, jsonEncode(method == 'GET' ? caps : response)),
          ),
      cancel: () {
        cancelled = true;
        final value = pending;
        if (value != null && !value.isCompleted) {
          value.completeError(const AsrRequestException('cancelled'));
        }
      },
    );
  }
}

Matcher _failure(YoutubeSourceFailure expected) => throwsA(
  isA<YoutubeSourceException>().having((e) => e.failure, 'failure', expected),
);

void main() {
  final reference = YoutubeReference.parse(
    'https://youtu.be/M7lc1UVf-VE?list=ignored&si=tracking&t=10',
  )!;

  test(
    'explicit destination and video consent precede every network request',
    () async {
      final transport = _Transport();
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      await expectLater(
        client.metadata(
          reference,
          const YoutubeSourceConsent(
            destination: 'http://127.0.0.1:8866',
            videoId: 'aqz-KE-bpKQ',
          ),
        ),
        _failure(YoutubeSourceFailure.consent),
      );
      expect(transport.paths, isEmpty);
      final result = await client.metadata(reference, _consent);
      expect(result.title, 'Public fixture');
      expect(result.tracks.single.automatic, isFalse);
      expect(transport.paths.map((p) => p.path), [
        '/ocideck-youtube/v1/capabilities',
        '/ocideck-youtube/v1/metadata',
      ]);
      expect(transport.bodies, [null, '{"video_id":"M7lc1UVf-VE"}']);
    },
  );

  test('disabled, unsafe and query-bearing destinations never send', () async {
    for (final profile in [
      const AsrServerProfile(),
      _profile.copyWith(baseUrl: 'http://example.org'),
      _profile.copyWith(baseUrl: 'http://127.0.0.1:8866?key=secret'),
    ]) {
      final transport = _Transport();
      final client = YoutubeSourceClient(
        destination: profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      await expectLater(
        client.metadata(
          reference,
          YoutubeSourceConsent(
            destination: profile.baseUrl,
            videoId: reference.videoId,
          ),
        ),
        _failure(YoutubeSourceFailure.configuration),
      );
      expect(transport.paths, isEmpty);
    }
  });

  test(
    'capability and response identity are strict, without a fallback',
    () async {
      final transport = _Transport()..caps['version'] = 2;
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      await expectLater(
        client.metadata(reference, _consent),
        _failure(YoutubeSourceFailure.protocol),
      );
      expect(transport.paths, hasLength(1));
      transport.caps['version'] = 1;
      transport.response['video_id'] = 'aqz-KE-bpKQ';
      await expectLater(
        client.metadata(reference, _consent),
        _failure(YoutubeSourceFailure.protocol),
      );
    },
  );

  test(
    'cancel aborts the actual pending transport and prevents later work',
    () async {
      final transport = _Transport()..pending = Completer<AsrResponse>();
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      final result = client.metadata(reference, _consent);
      final check = expectLater(
        result,
        _failure(YoutubeSourceFailure.cancelled),
      );
      client.cancel();
      await check;
      expect(transport.cancelled, isTrue);
      await expectLater(
        client.metadata(reference, _consent),
        _failure(YoutubeSourceFailure.cancelled),
      );
      expect(transport.paths, hasLength(1));
    },
  );

  test(
    'module or online-media revocation prevents accepting a late response',
    () async {
      var allowed = true;
      final transport = _Transport()..pending = Completer<AsrResponse>();
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => allowed,
      );
      final result = client.metadata(reference, _consent);
      final check = expectLater(
        result,
        _failure(YoutubeSourceFailure.cancelled),
      );
      allowed = false;
      transport.pending!.complete(AsrResponse(200, jsonEncode(transport.caps)));
      await check;
      expect(transport.paths, hasLength(1));
    },
  );

  test(
    'caption response remains bound to the chosen language and provenance',
    () async {
      final transport = _Transport()
        ..response = _envelope({
          'track': 'manual:en',
          'format': 'vtt',
          'text': 'WEBVTT\n\n',
        });
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      final result = await client.captions(reference, _track, _consent);
      expect(result.track.automatic, isFalse);
      expect(result.track.language, 'en');
      transport.response['track'] = 'automatic:nl';
      await expectLater(
        client.captions(reference, _track, _consent),
        _failure(YoutubeSourceFailure.protocol),
      );
    },
  );

  test(
    'audio capability, bounds and original-clock offset are explicit',
    () async {
      final transport = _Transport()
        ..response = _envelope({
          'base64': base64Encode([0, 255, 1]),
          'extension': 'm4a',
          'source_offset_ms': 0,
        });
      final client = YoutubeSourceClient(
        destination: _profile,
        transport: transport,
        mayUseNetwork: () => true,
      );
      await expectLater(
        client.audio(reference, _consent, startMs: -1),
        _failure(YoutubeSourceFailure.configuration),
      );
      expect(transport.paths, isEmpty);
      final result = await client.audio(reference, _consent);
      expect(result.bytes, [0, 255, 1]);
      expect(result.sourceOffset, Duration.zero);
      final before = transport.paths.length;
      await expectLater(
        client.audio(reference, _consent, startMs: 10000),
        _failure(YoutubeSourceFailure.audioMissing),
      );
      expect(transport.paths.length, before);
    },
  );
}
