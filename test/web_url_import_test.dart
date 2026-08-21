import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/recovery_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _goodDeck = '---\nmarp: true\ntitle: Webdeck\n---\n\n# Hallo web\n';

const _scriptDeck =
    '---\nmarp: true\ntitle: X\n---\n\n# Hi\n\n<script>steal()</script>\n';

/// De gebruiker zegt ja tegen de terugval op het fetch-hulppunt. Expliciet in
/// elke test die de terugval wil zien lopen: zonder toestemming loopt hij niet,
/// en dat is precies de bedoeling.
Future<bool> _consent({required String host}) async => true;

/// Een [http.Client] die na [close] geen request meer toestaat — zo valt de
/// owned-close-race (finally sluit de client vóór de fetch af is) hard om in
/// plaats van stil.
class _CloseAwareClient extends http.BaseClient {
  _CloseAwareClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;
  bool closed = false;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (closed) {
      throw http.ClientException('client is al gesloten', request.url);
    }
    final res = await _handler(request as http.Request);
    if (closed) {
      throw http.ClientException('client sloot tijdens de fetch', request.url);
    }
    return http.StreamedResponse(
      Stream.value(res.bodyBytes),
      res.statusCode,
      request: request,
    );
  }

  @override
  void close() => closed = true;
}

/// Zelfde opzet als state_providers_extra_test: wegwerp-herstelmap zodat de
/// autosave-plumbing nooit het echte app-support-pad (platformkanaal) raakt.
ProviderContainer _container() {
  final tempDir = Directory.systemTemp.createTempSync('ocideck_weburl_test_');
  addTearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });
  final container = ProviderContainer(
    overrides: [
      recoveryServiceProvider.overrideWithValue(
        RecoveryService(baseDir: tempDir),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('FileService.fetchUrlBytes', () {
    FileService fileService() => _container().read(fileServiceProvider);

    test('returns the body bytes on 200', () async {
      final client = MockClient((req) async => http.Response(_goodDeck, 200));
      final fetched = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        client: client,
      );
      expect(fetched.bytes, isNotNull);
      expect(utf8.decode(fetched.bytes!), _goodDeck);
      expect(fetched.failure, isNull);
    });

    test('reports notFound on a 404 status', () async {
      final client = MockClient((req) async => http.Response('nee', 404));
      final fetched = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        client: client,
      );
      expect(fetched.bytes, isNull);
      expect(fetched.failure, ImportFailure.notFound);
    });

    test('reports tooLarge when the body exceeds the cap', () async {
      final client = MockClient((req) async => http.Response('x' * 32, 200));
      final fetched = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        maxBytes: 16,
        client: client,
      );
      expect(fetched.bytes, isNull);
      expect(fetched.failure, ImportFailure.tooLarge);
    });

    test('valt op web terug op het same-origin fetch-hulppunt', () async {
      // Direct fetchen "faalt" zoals bij een bron zonder CORS; de tweede
      // poging moet naar het same-origin hulppunt gaan met de doel-URL als
      // query, en die bytes horen gewoon door te komen.
      const target = 'https://elders.example/deck.md';
      final client = MockClient((req) async {
        if (req.url.host == 'elders.example') {
          throw http.ClientException('CORS-weigering');
        }
        expect(req.url.path, endsWith('fetch-proxy'));
        expect(req.url.queryParameters['url'], target);
        return http.Response(_goodDeck, 200);
      });
      final fetched = await fileService().fetchUrlBytes(
        target,
        client: client,
        viaProxyFallback: true,
        onConfirmProxy: _consent,
      );
      expect(fetched.bytes, isNotNull);
      expect(utf8.decode(fetched.bytes!), _goodDeck);
    });

    test('terugval overleeft het sluiten van de eigen client', () async {
      // Regressie: de proxy-fetch werd met `return` (zonder await) gedaan,
      // waardoor het finally-blok de client sloot terwijl de fetch nog liep en
      // de terugval altijd faalde. Deze client antwoordt op de proxy pas na een
      // async gap en gooit zodra hij gesloten is — zonder de await zou de bytes
      // dus nooit compleet doorkomen.
      const target = 'https://elders.example/deck.md';
      final client = _CloseAwareClient((req) async {
        if (req.url.host == 'elders.example') {
          throw http.ClientException('CORS-weigering');
        }
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return http.Response(_goodDeck, 200);
      });
      final fetched = await fileService().fetchUrlBytes(
        target,
        client: client,
        viaProxyFallback: true,
        onConfirmProxy: _consent,
        closeInjectedClient: true,
      );
      expect(fetched.bytes, isNotNull);
      expect(utf8.decode(fetched.bytes!), _goodDeck);
      expect(client.closed, isTrue, reason: 'client hoort na afloop dicht');
    });

    test('slaat het hulppunt over wanneer direct fetchen slaagt', () async {
      var proxyCalls = 0;
      final client = MockClient((req) async {
        if (req.url.path.endsWith('fetch-proxy')) {
          proxyCalls++;
          return http.Response('nee', 500);
        }
        return http.Response(_goodDeck, 200);
      });
      final fetched = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        client: client,
        viaProxyFallback: true,
        onConfirmProxy: _consent,
      );
      expect(fetched.bytes, isNotNull);
      expect(proxyCalls, 0);
    });

    test('refuses non-web schemes without fetching', () async {
      final client = MockClient((req) async => fail('mag niet fetchen'));
      final file = await fileService().fetchUrlBytes(
        'file:///etc/passwd',
        client: client,
      );
      expect(file.bytes, isNull);
      expect(file.failure, ImportFailure.insecureScheme);
      final garbage = await fileService().fetchUrlBytes(
        'geen url',
        client: client,
      );
      expect(garbage.bytes, isNull);
      expect(garbage.failure, ImportFailure.network);
    });

    // Het hulppunt haalt server-zijdig op en krijgt daarmee de hele URL in
    // handen. Dat is een andere partij dan degene die de gebruiker aanwees, en
    // de URL kan zélf het geheim zijn. Vroeger ging hij er automatisch en
    // zonder melding heen.
    group('de terugval vraagt het eerst', () {
      /// Direct fetchen faalt (zoals bij een bron zonder CORS-headers); elke
      /// aanroep van het hulppunt wordt geteld.
      (MockClient, List<Uri>) proxyCounting() {
        final seen = <Uri>[];
        final client = MockClient((req) async {
          if (!req.url.path.endsWith('fetch-proxy')) {
            throw http.ClientException('CORS-weigering');
          }
          seen.add(req.url);
          return http.Response(_goodDeck, 200);
        });
        return (client, seen);
      }

      test('zonder bevestiger gaat er niets naar het hulppunt', () async {
        final (client, seen) = proxyCounting();
        final fetched = await fileService().fetchUrlBytes(
          'https://elders.example/deck.md',
          client: client,
          viaProxyFallback: true,
        );
        expect(fetched.bytes, isNull);
        expect(seen, isEmpty, reason: 'geen toestemming is geen toestemming');
      });

      test('een "nee" van de gebruiker houdt de URL binnen', () async {
        final (client, seen) = proxyCounting();
        final fetched = await fileService().fetchUrlBytes(
          'https://elders.example/deck.md',
          client: client,
          viaProxyFallback: true,
          onConfirmProxy: ({required String host}) async => false,
        );
        expect(fetched.bytes, isNull);
        expect(seen, isEmpty);
      });

      test('de vraag noemt de bronhost, niet de hele URL', () async {
        final (client, _) = proxyCounting();
        String? asked;
        await fileService().fetchUrlBytes(
          'https://elders.example/geheim/deck.md?sleutel=abc',
          client: client,
          viaProxyFallback: true,
          onConfirmProxy: ({required String host}) async {
            asked = host;
            return false;
          },
        );
        expect(asked, 'elders.example');
      });

      test('een URL mét inloggegevens wordt niet eens gevraagd', () async {
        // Hetzelfde slot dat GitWebTransport op zijn token zet: het hulppunt
        // zou `gebruiker:wachtwoord` in handen krijgen en namens de gebruiker
        // doorsturen. Dat staat vast — hier valt niets aan te bevestigen.
        final (client, seen) = proxyCounting();
        var asked = 0;
        const user = 'bram';
        const pw = 'hunter2';
        final fetched = await fileService().fetchUrlBytes(
          'https://$user:$pw@elders.example/deck.md',
          client: client,
          viaProxyFallback: true,
          onConfirmProxy: ({required String host}) async {
            asked++;
            return true;
          },
        );
        expect(fetched.bytes, isNull);
        expect(seen, isEmpty);
        expect(asked, 0, reason: 'dit is geen keuze van de gebruiker');
      });
    });
  });

  group('FileService.openDeckFromContent', () {
    FileService fileService() => _container().read(fileServiceProvider);

    test('opens a valid Marp deck', () {
      final outcome = fileService().openDeckFromContent(_goodDeck);
      expect(outcome.failure, isNull);
      expect(outcome.deck, isNotNull);
      expect(outcome.deck!.slides, isNotEmpty);
    });

    test('refuses executable content fail-closed', () {
      final outcome = fileService().openDeckFromContent(_scriptDeck);
      expect(outcome.deck, isNull);
      expect(outcome.failure, OpenFailure.unsafe);
    });

    test('refuses markdown without marp front matter', () {
      final outcome = fileService().openDeckFromContent('# Gewoon een README');
      expect(outcome.deck, isNull);
      expect(outcome.failure, OpenFailure.notPresentation);
    });
  });

  group('TabsNotifier.openDeckFromBytes (URL-import)', () {
    test(
      'opens a fetched Marp deck in the current empty tab, without a path',
      () async {
        final container = _container();
        final tabs = container.read(tabsProvider.notifier);
        final result = await tabs.openDeckFromBytes(
          utf8.encode(_goodDeck),
          'https://example.org/deck.md',
        );
        expect(result, OpenResult.opened);
        final tab = container.read(tabsProvider).current!;
        expect(tab.isOpen, isTrue);
        final deckState = tab.deckNotifier.currentState;
        expect(deckState.deck, isNotNull);
        // Geen lokaal bestand achter deze inhoud: opslaan moet om een
        // bestemming vragen in plaats van naar een URL-pad te schrijven.
        expect(deckState.filePath, isNull);
      },
    );

    test('records the remote origin for the privacy badge', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      const url = 'https://example.org/deck.md';
      final result = await tabs.openDeckFromBytes(
        utf8.encode(_goodDeck),
        url,
        remoteOrigin: url,
      );
      expect(result, OpenResult.opened);
      final deckState = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState;
      expect(deckState.remoteOrigin, url);
    });

    test('a locally opened deck carries no remote origin', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      // No remoteOrigin argument: mirrors the web file-picker / drag-drop,
      // where the bytes came from the user's own disk, not a URL.
      await tabs.openDeckFromBytes(utf8.encode(_goodDeck), 'deck.md');
      final deckState = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .currentState;
      expect(deckState.remoteOrigin, isNull);
    });

    test('a corrupt zip package is refused, nothing opens', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(
        Uint8List.fromList([0x50, 0x4B, 0x03, 0x04, 1, 2, 3]),
        'https://example.org/deck.ocideck',
      );
      // De zip-decoder is coulant: een kapotte zip levert een leeg archief
      // (→ geen presentatie) of een decodeerfout (→ onleesbaar) op. Beide
      // weigeren; er mag alleen nooit iets openen.
      expect(result, anyOf(OpenResult.notAPresentation, OpenResult.unreadable));
      expect(container.read(tabsProvider).current!.isOpen, isFalse);
    });

    test('blocks executable content and raises the security alarm', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      final result = await tabs.openDeckFromBytes(
        utf8.encode(_scriptDeck),
        'https://example.org/kwaad.md',
      );
      expect(result, OpenResult.blocked);
      final alarm = container.read(importSecurityAlarmProvider);
      expect(alarm, isNotNull);
      expect(alarm!.path, 'https://example.org/kwaad.md');
      expect(alarm.findings, isNotEmpty);
      expect(container.read(tabsProvider).current!.isOpen, isFalse);
    });

    test(
      'platte markdown opent als document; niet-UTF8 is onleesbaar (#1637)',
      () async {
        final container = _container();
        final tabs = container.read(tabsProvider.notifier);
        expect(
          await tabs.openDeckFromBytes(
            utf8.encode('# Gewoon een README'),
            'https://example.org/readme.md',
          ),
          OpenResult.opened,
        );
        final tab = container.read(tabsProvider).current!;
        expect(tab.documentNotifier, isNotNull);
        expect(
          await tabs.openDeckFromBytes(
            Uint8List.fromList([0xFF, 0xFE, 0x00, 0x88]),
            'https://example.org/binair.bin',
          ),
          OpenResult.unreadable,
        );
      },
    );
  });
}
