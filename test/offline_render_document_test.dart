import 'dart:io';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/offline_render_document_io.dart';
import 'package:ocideck/services/offline_render_document_stub.dart' as browser;

void main() {
  test(
    'offline document host serves generated HTML and releases its socket',
    () async {
      final document = await OfflineRenderDocument.start(
        '<!doctype html><title>offline</title>',
      );
      final client = HttpClient();
      addTearDown(() => client.close(force: true));
      final response = await (await client.getUrl(document.uri)).close();
      expect(
        await response.transform(utf8.decoder).join(),
        contains('<title>offline</title>'),
      );
      await document.close();
      await expectLater(
        Socket.connect(document.uri.host, document.uri.port),
        throwsA(isA<SocketException>()),
      );
    },
  );

  test('browser renderer never opens a native document server', () async {
    expect(
      () => browser.OfflineRenderDocument.start('html'),
      throwsUnsupportedError,
    );
    final stub = browser.OfflineRenderDocument();
    expect(() => stub.uri, throwsUnsupportedError);
    await stub.close();
  });
}
