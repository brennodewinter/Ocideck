import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/media/media_url_client.dart';
import 'package:ocideck/services/transcription/asr_transport.dart';
import 'package:ocideck/services/transcription/media_sniff.dart';
import 'package:ocideck/services/transcription/transcription_errors.dart';

class _Transport implements AsrTransport {
  final urls = <Uri>[];
  final methods = <String>[];
  final responses = <AsrResponse>[];
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
    urls.add(url);
    methods.add(method);
    expect(strategy, AiResolveStrategy.publicGuarded);
    return AsrSendHandle(
      done: pending?.future ?? Future.value(responses.removeAt(0)),
      cancel: () {
        cancelled = true;
        if (pending case final value? when !value.isCompleted) {
          value.completeError(const AsrRequestException('cancelled'));
        }
      },
    );
  }
}

void main() {
  test(
    'local URL recognition does not mistake decks, feeds or YouTube for media',
    () {
      expect(
        isDirectMediaUrl('https://cdn.example/audio.M4A?signature=x'),
        isTrue,
      );
      expect(isDirectMediaUrl('https://cdn.example/clip.webm'), isTrue);
      for (final url in [
        'https://example.org/deck.md',
        'https://example.org/feed.xml',
        'https://youtube.com/watch?v=M7lc1UVf-VE',
        'file:///tmp/a.wav',
      ]) {
        expect(isDirectMediaUrl(url), isFalse);
      }
      expect(mayProbeMediaMetadata('https://example.org/deck.md'), isFalse);
      expect(mayProbeMediaMetadata('https://example.org/stream'), isTrue);
    },
  );

  test(
    'extensionless media discovery uses only HEAD and never downloads audio',
    () async {
      final transport = _Transport()
        ..responses.add(
          AsrByteResponse(
            200,
            Uint8List(0),
            headers: {'content-type': 'audio/mpeg'},
          ),
        );
      final client = MediaUrlClient(
        mayUseNetwork: () => true,
        transport: transport,
      );
      expect(
        await client.looksLikeMedia(Uri.parse('https://example.org/stream')),
        isTrue,
      );
      expect(transport.methods, ['HEAD']);
    },
  );

  test(
    'magic bytes win over a misleading suffix and binary data stays intact',
    () async {
      final wav = encodePcmWav(Float32List.fromList([-.5, .5]));
      final transport = _Transport()..responses.add(AsrByteResponse(200, wav));
      final client = MediaUrlClient(
        mayUseNetwork: () => true,
        transport: transport,
      );
      final result = await client.download(
        Uri.parse('https://example.org/wrong.mp4'),
      );
      expect(result.extension, 'wav');
      expect(result.bytes, wav);
    },
  );

  test(
    'private targets, numeric aliases and credentials do not send a request',
    () async {
      for (final url in [
        'https://127.0.0.1/a.mp3',
        'http://localhost./a.wav',
        'https://10.0.0.1/x.m4a',
        'http://2130706433/a.wav',
        'http://127.1/a.wav',
        'http://0x7f000001/a.wav',
        'https://user:secret@example.org/a.wav',
      ]) {
        final transport = _Transport();
        final client = MediaUrlClient(
          mayUseNetwork: () => true,
          transport: transport,
        );
        await expectLater(
          client.download(Uri.parse(url)),
          throwsA(isA<UnsupportedSource>()),
        );
        expect(transport.urls, isEmpty);
      }
    },
  );

  test('every redirect is checked before the next native request', () async {
    for (final target in [
      'http://127.0.0.1/a.wav',
      'https://10.0.0.1/a.wav',
      'https://user:secret@cdn.example/a.wav',
      'http://cdn.example/a.wav',
    ]) {
      final transport = _Transport()
        ..responses.add(
          AsrByteResponse(302, Uint8List(0), headers: {'location': target}),
        );
      final client = MediaUrlClient(
        mayUseNetwork: () => true,
        transport: transport,
      );
      await expectLater(
        client.download(Uri.parse('https://example.org/a.wav')),
        throwsA(isA<UnsupportedSource>()),
      );
      expect(transport.urls, hasLength(1));
    }
  });

  test(
    'cancel aborts the pending transport and accepts no late bytes',
    () async {
      final transport = _Transport()..pending = Completer<AsrResponse>();
      final client = MediaUrlClient(
        mayUseNetwork: () => true,
        transport: transport,
      );
      final result = client.download(Uri.parse('https://example.org/a.wav'));
      final check = expectLater(result, throwsA(isA<Cancelled>()));
      client.cancel();
      await check;
      expect(transport.cancelled, isTrue);
    },
  );
}
