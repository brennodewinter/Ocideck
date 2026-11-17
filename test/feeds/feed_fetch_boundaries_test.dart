import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/feeds/feed_fetch.dart';
import 'package:ocideck/services/file_service.dart' show ImportFailure;

void main() {
  test(
    'native feeds and enclosures reject private hosts before network or file writes',
    () async {
      final directory = await Directory.systemTemp.createTemp('feed-refusal-');
      final original = File('${directory.path}/existing.wav');
      await original.writeAsString('owned source must survive refusal');
      var clients = 0;
      try {
        await HttpOverrides.runZoned(
          () async {
            for (final source in [
              'http://127.0.0.1/feed.xml',
              'http://[::1]/feed.xml',
            ]) {
              final result = await fetchFeed(Uri.parse(source));
              expect(result.failure, ImportFailure.blockedHost);
              expect(result.ok, isFalse);
              expect(result.bytes, isNull);
              final download = await downloadFeedMedia(
                Uri.parse(source),
                original.path,
                maxBytes: 1024,
              );
              expect(download.failure, ImportFailure.blockedHost);
              expect(download.path, isNull);
              expect(
                await original.readAsString(),
                'owned source must survive refusal',
              );
            }
            final insecure = await downloadFeedMedia(
              Uri.parse('file:///unavailable/source.wav'),
              original.path,
              maxBytes: 1024,
            );
            expect(insecure.failure, ImportFailure.insecureScheme);
            expect(insecure.path, isNull);
            expect(
              await original.readAsString(),
              'owned source must survive refusal',
            );
          },
          createHttpClient: (_) {
            clients++;
            throw StateError('a refused source must never create a client');
          },
        );
        expect(clients, 0);
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );
}
