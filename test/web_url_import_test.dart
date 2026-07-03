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
      final bytes = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        client: client,
      );
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!), _goodDeck);
    });

    test('returns null on a non-200 status', () async {
      final client = MockClient((req) async => http.Response('nee', 404));
      expect(
        await fileService().fetchUrlBytes(
          'https://example.org/deck.md',
          client: client,
        ),
        isNull,
      );
    });

    test('returns null when the body exceeds the cap', () async {
      final client = MockClient((req) async => http.Response('x' * 32, 200));
      expect(
        await fileService().fetchUrlBytes(
          'https://example.org/deck.md',
          maxBytes: 16,
          client: client,
        ),
        isNull,
      );
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
      final bytes = await fileService().fetchUrlBytes(
        target,
        client: client,
        viaProxyFallback: true,
      );
      expect(bytes, isNotNull);
      expect(utf8.decode(bytes!), _goodDeck);
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
      final bytes = await fileService().fetchUrlBytes(
        'https://example.org/deck.md',
        client: client,
        viaProxyFallback: true,
      );
      expect(bytes, isNotNull);
      expect(proxyCalls, 0);
    });

    test('refuses non-web schemes without fetching', () async {
      final client = MockClient((req) async => fail('mag niet fetchen'));
      expect(
        await fileService().fetchUrlBytes('file:///etc/passwd', client: client),
        isNull,
      );
      expect(
        await fileService().fetchUrlBytes('geen url', client: client),
        isNull,
      );
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

    test('reports non-presentation and non-UTF8 content as such', () async {
      final container = _container();
      final tabs = container.read(tabsProvider.notifier);
      expect(
        await tabs.openDeckFromBytes(
          utf8.encode('# Gewoon een README'),
          'https://example.org/readme.md',
        ),
        OpenResult.notAPresentation,
      );
      expect(
        await tabs.openDeckFromBytes(
          Uint8List.fromList([0xFF, 0xFE, 0x00, 0x88]),
          'https://example.org/binair.bin',
        ),
        OpenResult.unreadable,
      );
    });
  });
}
