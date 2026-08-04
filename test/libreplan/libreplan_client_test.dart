import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/libreplan_settings.dart';
import 'package:ocideck/services/libreplan/libreplan_client.dart';

/// Een fake transport die verzoeken onderschept en een geprogrammeerd
/// antwoord retourneert. Test de client-logica (auth, URL-bouw, gates)
/// zonder het netwerk te raken.
class _FakeTransport implements LibreplanHttpTransport {
  _FakeTransport({this.response, this.throwException});

  final LibreplanHttpResult? response;
  final LibreplanRequestException? throwException;

  /// De laatste aanroep, voor assertions.
  late final Uri lastUrl;
  late final bool lastTrustedInternal;
  late final Map<String, String> lastHeaders;

  @override
  Future<LibreplanHttpResult> get({
    required Uri url,
    required bool trustedInternal,
    Map<String, String> headers = const {},
    Duration timeout = const Duration(seconds: 30),
  }) async {
    lastUrl = url;
    lastTrustedInternal = trustedInternal;
    lastHeaders = headers;
    if (throwException != null) throw throwException!;
    return response!;
  }
}

void main() {
  group('LibreplanClient.canSend', () {
    test('false op web (fail-closed)', () {
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        isWeb: true,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, contains('desktop'));
    });

    test('false zonder server', () {
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: '',
          username: '',
        ),
        isWeb: false,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, contains('Geen server'));
    });

    test('false bij plain HTTP zonder trustedInternal', () {
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'http://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        isWeb: false,
      );
      expect(client.canSend, isFalse);
      expect(client.denialReason, contains('HTTPS'));
    });

    test('true bij HTTPS met server', () {
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        isWeb: false,
      );
      expect(client.canSend, isTrue);
      expect(client.denialReason, isNull);
    });

    test('true bij plain HTTP met trustedInternal', () {
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'http://libreplan.lan/libreplan/',
          username: 'wsreader',
          trustedInternal: true,
        ),
        isWeb: false,
      );
      expect(client.canSend, isTrue);
    });
  });

  group('LibreplanClient.fetch', () {
    test('bouwt de juiste URL met /ws/rest/ prefix', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<resource-list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await client.fetchResources();

      expect(
        transport.lastUrl.toString(),
        'https://libreplan.example.org/libreplan/ws/rest/resources/',
      );
    });

    test('stuurt Basic Auth header', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<resource-list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await client.fetchResources();

      final auth = transport.lastHeaders['authorization'];
      expect(auth, startsWith('Basic '));
      // base64("wsreader:secret") = "d3NyZWFkZXI6c2VjcmV0"
      expect(auth, 'Basic d3NyZWFkZXI6c2VjcmV0');
    });

    test('geeft trustedInternal door aan de transport', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<resource-list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'http://libreplan.lan/libreplan/',
          username: 'wsreader',
          trustedInternal: true,
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await client.fetchResources();

      expect(transport.lastTrustedInternal, isTrue);
    });

    test('werpt bij non-2xx status', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(401, 'Unauthorized'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'wrong',
        transport: transport,
        isWeb: false,
      );

      expect(
        () => client.fetchResources(),
        throwsA(isA<LibreplanRequestException>()),
      );
    });

    test('werpt bij niet-geconfigureerde client', () async {
      final transport = _FakeTransport();
      final client = LibreplanClient(
        settings: const LibreplanSettings(),
        transport: transport,
        isWeb: false,
      );

      expect(
        () => client.fetchResources(),
        throwsA(isA<LibreplanRequestException>()),
      );
    });

    test('fetchOrder bouwt URL met project-code', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<order-list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await client.fetchOrder('PROJECT-001');

      expect(
        transport.lastUrl.toString(),
        'https://libreplan.example.org/libreplan/ws/rest/orderelements/PROJECT-001/',
      );
    });

    test('fetchResourceHours bouwt URL met datums', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await client.fetchResourceHours(
        DateTime(2026, 9, 1),
        DateTime(2026, 9, 30),
      );

      expect(
        transport.lastUrl.toString(),
        'https://libreplan.example.org/libreplan/ws/rest/resourceshours/2026-09-01/2026-09-30/',
      );
    });
  });

  group('LibreplanClient.testConnection', () {
    test('slaagt bij 2xx', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(200, '<resource-list/>'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'secret',
        transport: transport,
        isWeb: false,
      );

      await expectLater(client.testConnection(), completes);
    });

    test('faalt bij non-2xx', () async {
      final transport = _FakeTransport(
        response: const LibreplanHttpResult(401, 'Unauthorized'),
      );
      final client = LibreplanClient(
        settings: const LibreplanSettings(
          enabled: true,
          baseUrl: 'https://libreplan.example.org/libreplan/',
          username: 'wsreader',
        ),
        password: 'wrong',
        transport: transport,
        isWeb: false,
      );

      await expectLater(
        client.testConnection(),
        throwsA(isA<LibreplanRequestException>()),
      );
    });
  });
}
