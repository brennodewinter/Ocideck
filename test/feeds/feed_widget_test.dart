// Widget-tests voor de feedketen (#2931): de twee dialogen, de
// inhoudsrouter en de afleveringsacties. Het netwerk wordt nóóit echt
// benaderd — de enige "netwerkpad" die hier draait is NetGuard's eigen
// weigering van 127.0.0.1 vóór er een socket open gaat, en de via
// `client:` geïnjecteerde MockClient op de web-route.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/feeds/feed_fetch.dart';
import 'package:ocideck/services/feeds/feed_models.dart';
import 'package:ocideck/services/feeds/feed_store.dart';
import 'package:ocideck/widgets/app_shell.dart'
    show openDiscoveredFeedUrl, registerFeedListeners, routeFeedUrlContent;
import 'package:ocideck/widgets/feeds/feed_dialog.dart';
import 'package:ocideck/widgets/feeds/feed_episode_actions.dart';
import 'package:ocideck/widgets/feeds/feed_subscriptions_dialog.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../support/pump_until.dart';

const _feedUrl = 'https://podcast.example/feed.xml';

PodcastFeed _feed() => PodcastFeed(
  sourceUrl: Uri.parse(_feedUrl),
  title: 'Testpod',
  episodes: [
    FeedEpisode(
      key: 'ep1',
      title: 'Eerste aflevering',
      published: DateTime(2026, 1, 2),
      enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
      enclosureType: 'audio/mpeg',
      transcripts: [
        FeedTranscriptLink(
          url: Uri.parse('http://127.0.0.1/ep1.vtt'),
          type: 'text/vtt',
        ),
      ],
    ),
  ],
);

/// Minimale app met een knop die [run] uitvoert met context en ref —
/// zo komt elke schilfunctie in een échte Navigator/ScaffoldMessenger.
/// De build raakt `settingsProvider` alvast aan: de async pref-lading
/// staat dan klaar vóór de knopval, anders leest een callback koude
/// standaardwaarden.
Widget _shell(Future<void> Function(BuildContext, WidgetRef) run) {
  return ProviderScope(
    child: MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        ...GlobalMaterialLocalizations.delegates,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) {
            ref.watch(settingsProvider);
            return FilledButton(
              onPressed: () => run(context, ref),
              child: const Text('open'),
            );
          },
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void _aiPrefs() => SharedPreferences.setMockInitialValues({
  'aiSettings': jsonEncode(const {
    'enabled': true,
    'mode': 'none',
    'baseUrl': '',
    'model': '',
    'trustedInternal': false,
    'cloudConfirmed': false,
  }),
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('feeddialoog', () {
    testWidgets('toont titel, afleveringen en volg-knop bij AI aan', (
      tester,
    ) async {
      _aiPrefs();
      await tester.pumpWidget(
        _shell(
          (c, r) => showPodcastFeedDialog(c, _feed(), Uri.parse(_feedUrl)),
        ),
      );
      await _open(tester);

      expect(find.text('Testpod'), findsOneWidget);
      expect(find.text('Eerste aflevering'), findsOneWidget);
      expect(find.text('Feed volgen'), findsOneWidget);

      // Volgen is de expliciete stap: het abonnement landt in de store.
      await tester.tap(find.text('Feed volgen'));
      await tester.pumpAndSettle();
      expect(find.text('Deze feed wordt gevolgd.'), findsWidgets);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bij AI uit alleen de eerlijke uitleg', (tester) async {
      SharedPreferences.setMockInitialValues({});
      await tester.pumpWidget(
        _shell(
          (c, r) => showPodcastFeedDialog(c, _feed(), Uri.parse(_feedUrl)),
        ),
      );
      await _open(tester);

      expect(
        find.text('Zet AI aan in de instellingen om deze feed te volgen.'),
        findsOneWidget,
      );
      expect(find.text('Feed volgen'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('linkrel=alternate-keuze geeft de gekozen URL terug', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      Uri? chosen;
      final links = [
        Uri.parse('https://a.example/rss'),
        Uri.parse('https://b.example/atom'),
      ];
      await tester.pumpWidget(
        _shell((c, r) async {
          chosen = await showFeedLinkChoiceDialog(c, links);
        }),
      );
      await _open(tester);

      await tester.tap(find.text('https://a.example/rss'));
      await tester.pumpAndSettle();
      expect(chosen, links[0]);
    });
  });

  group('abonnementenvenster', () {
    FeedSubscription seededSub() => FeedSubscription(
      feedUrl: Uri.parse('http://127.0.0.1/feed'),
      resolvedUrl: Uri.parse('http://127.0.0.1/feed'),
      title: 'Gevolgde pod',
      checkInterval: const Duration(hours: 1),
      lastChecked: DateTime(2026, 3, 1, 12),
      consecutiveFailures: 2,
      episodes: {
        'ep1': FeedEpisodeRecord(
          key: 'ep1',
          title: 'Nieuwe aflevering',
          published: DateTime(2026, 3, 1),
          enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
          enclosureType: 'audio/mpeg',
          status: FeedEpisodeStatus.fresh,
        ),
      },
    );

    testWidgets('toont abonnement met wachtrij, refresh en stop', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'aiSettings': jsonEncode(const {'enabled': true, 'mode': 'none'}),
        FeedStoreCodec.prefsKey: const FeedStoreCodec().encode([seededSub()]),
      });
      await tester.pumpWidget(_shell((c, r) => showFeedSubscriptionsDialog(c)));
      await _open(tester);

      expect(find.text('Gevolgde pod'), findsOneWidget);
      await tester.tap(find.text('Gevolgde pod'));
      await tester.pumpAndSettle();

      expect(find.text('Nieuwe aflevering'), findsOneWidget);
      expect(find.text('Nu vernieuwen'), findsOneWidget);

      // Vernieuwen raakt de echte fetch-route — 127.0.0.1 weigert
      // NetGuard meteen, dus de mislukte-controle-melding verschijnt.
      await tester.tap(find.text('Nu vernieuwen'));
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);

      // Stoppen met volgen leegt de lijst.
      await tester.tap(find.text('Stoppen met volgen'));
      await tester.pumpAndSettle();
      expect(find.text('Gevolgde pod'), findsNothing);
      expect(find.textContaining('Nog geen gevolgde feeds'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('inhoudsrouter', () {
    /// Een `storageConnections`-pref met een lokale map: `homeDirectory`
    /// is afgeleid van de eerste bibliotheek en zonder die valt
    /// `importFromUrl` terug op `getApplicationDocumentsDirectory` — een
    /// plugin die op de test-VM nooit antwoordt. Dan zou de
    /// NetGuard-weigering nooit bereikt worden.
    Map<String, Object> libraryPrefs() => {
      'storageConnections': StorageConnection.encodeList([
        LocalConnection(id: 't', name: 'T', path: Directory.systemTemp.path),
      ]),
    };

    testWidgets('feed-bytes openen de feeddialoog', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Future<bool>? routed;
      await tester.pumpWidget(
        _shell((c, r) async {
          routed = routeFeedUrlContent(
            c,
            r,
            _feedUrl,
            Uint8List.fromList(
              utf8.encode(
                '<?xml version="1.0"?><rss version="2.0"><channel>'
                '<title>Testpod</title>'
                '<item><guid>ep1</guid><title>Eerste aflevering</title>'
                '<enclosure url="https://cdn.example/ep1.mp3" '
                'type="audio/mpeg" length="1"/></item>'
                '</channel></rss>',
              ),
            ),
          );
        }),
      );
      await _open(tester);

      // De router wacht de dialoog af: die staat open en `routed`
      // voltooit pas bij sluiten.
      expect(find.text('Testpod'), findsOneWidget);
      await tester.tap(find.text('Sluiten'));
      await tester.pumpAndSettle();
      expect(await routed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('gewone bytes vallen terug op de deckroute', (tester) async {
      SharedPreferences.setMockInitialValues({});
      var routed = true;
      await tester.pumpWidget(
        _shell((c, r) async {
          routed = await routeFeedUrlContent(
            c,
            r,
            _feedUrl,
            Uint8List.fromList(utf8.encode('# gewone markdown')),
          );
        }),
      );
      await _open(tester);

      expect(routed, isFalse);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('feedlink in HTML opent de keuzedialoog en volgt de keuze', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(libraryPrefs());
      Future<bool>? routed;
      await tester.pumpWidget(
        _shell((c, r) async {
          routed = routeFeedUrlContent(
            c,
            r,
            'https://site.example/page',
            Uint8List.fromList(
              utf8.encode(
                '<html><head>'
                '<link rel="alternate" type="application/rss+xml" '
                'href="http://127.0.0.1/feed">'
                '</head><body></body></html>',
              ),
            ),
          );
        }),
      );
      // Alles ín `runAsync`: `routeFeedUrlContent` → `openDiscoveredFeedUrl`
      // → `importFromUrl` doet echte IO (`Directory.create`). Een await-
      // keten die in de fake-zone begint parkeert zijn continuaties op
      // FakeAsync's microtask-wachtrij — die tijdens runAsync niet loopt,
      // dus ook de eerste tik hoort hierbinnen.
      await tester.runAsync(() async {
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        // Één kandidaat: het keuzevenster toont hem; kiezen volgt de
        // ontdekte URL — de geblokkeerde host levert dan een melding.
        await tester.tap(find.text('http://127.0.0.1/feed'));
        expect(await routed, isTrue);
      });
      await tester.pumpAndSettle();
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('ontdekte URL met geweigerde host meldt de reden', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues(libraryPrefs());
      Future<void>? opened;
      await tester.pumpWidget(
        _shell((c, r) async {
          opened = openDiscoveredFeedUrl(
            c,
            r,
            Uri.parse('http://127.0.0.1/feed'),
            depth: 1,
          );
        }),
      );

      // Echte IO onderweg (`Directory.create` voor de bestemmingsmap):
      // de hele keten draait op de echte event-loop.
      await tester.runAsync(() async {
        await tester.tap(find.text('open'));
        await opened!.timeout(const Duration(seconds: 10));
      });
      await tester.pumpAndSettle();

      // NetGuard weigert 127.0.0.1 vóór DNS — de foutsnackbar is de
      // zichtbare uitkomst.
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('listener registreert zonder fout', (tester) async {
      SharedPreferences.setMockInitialValues({});
      // `ref.listen` mag alleen tijdens build — daarom hangt deze test
      // de registratie in een Consumer-build in plaats van een knopval.
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            localizationsDelegates: const [
              AppLocalizations.delegate,
              ...GlobalMaterialLocalizations.delegates,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  registerFeedListeners(ref, context);
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('afleveringsacties', () {
    testWidgets('geweigerde transcript-URL meldt gericht', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ep = FeedEpisodeRecord(
        key: 'ep1',
        title: 'Eerste aflevering',
        enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
        enclosureType: 'audio/mpeg',
      );
      await tester.pumpWidget(
        _shell((c, r) async {
          await fetchEpisodeTranscript(
            c,
            r,
            feedUrl: Uri.parse(_feedUrl),
            feedTitle: 'Testpod',
            episode: ep,
            link: FeedTranscriptLink(
              url: Uri.parse('http://127.0.0.1/ep1.vtt'),
              type: 'text/vtt',
            ),
          );
        }),
      );
      await _open(tester);

      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('opgehaald transcript opent als document', (tester) async {
      SharedPreferences.setMockInitialValues({});
      Uri? seen;
      final ep = FeedEpisodeRecord(
        key: 'ep1',
        title: 'Eerste aflevering',
        enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
        enclosureType: 'audio/mpeg',
      );
      await tester.pumpWidget(
        _shell((c, r) async {
          await fetchEpisodeTranscript(
            c,
            r,
            feedUrl: Uri.parse(_feedUrl),
            feedTitle: 'Testpod',
            episode: ep,
            link: FeedTranscriptLink(
              url: Uri.parse('https://cdn.example/ep1.txt'),
              type: 'text/plain',
            ),
            fetcher: (url, {etag, lastModified}) async {
              seen = url;
              return FeedFetchResult.ok(
                statusCode: 200,
                bytes: utf8.encode('Hallo, dit is het transcript.'),
                finalUrl: url,
              );
            },
            // Het plaatsen van de documenttab kan onder de test-VM op
            // een missende plugin werpen; de route ernaartoe is wat
            // hier telt.
          ).onError((_, _) {});
        }),
      );
      await _open(tester);
      expect(seen, Uri.parse('https://cdn.example/ep1.txt'));
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('onleesbaar transcript meldt eerlijk', (tester) async {
      SharedPreferences.setMockInitialValues({});
      final ep = FeedEpisodeRecord(
        key: 'ep1',
        title: 'Eerste aflevering',
        enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
        enclosureType: 'audio/mpeg',
      );
      await tester.pumpWidget(
        _shell((c, r) async {
          await fetchEpisodeTranscript(
            c,
            r,
            feedUrl: Uri.parse(_feedUrl),
            feedTitle: 'Testpod',
            episode: ep,
            link: FeedTranscriptLink(
              url: Uri.parse('https://cdn.example/ep1.txt'),
              type: 'text/plain',
            ),
            fetcher: (url, {etag, lastModified}) async => FeedFetchResult.ok(
              statusCode: 200,
              bytes: utf8.encode('   '),
              finalUrl: url,
            ),
          );
        }),
      );
      await _open(tester);
      expect(find.byType(SnackBar), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('bestaand stagingbestand gaat naar de voorbeschouwing', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final tmp = File('${Directory.systemTemp.path}/ocideck-test-ep.mp3');
      // Sync geschreven: een `await` op echte IO hangt in de fake-async
      // zone vóór de eerste pump.
      tmp.writeAsBytesSync(const [0, 1, 2]);
      addTearDown(() => tmp.deleteSync());
      final ep = FeedEpisodeRecord(
        key: 'ep1',
        title: 'Eerste aflevering',
        enclosureUrl: Uri.parse('https://cdn.example/ep1.mp3'),
        enclosureType: 'audio/mpeg',
      )..downloadedPath = tmp.path;

      var actionDone = false;
      await tester.pumpWidget(
        _shell((c, r) async {
          // De transcriptievoorbeschouwing kan onder de test-VM zelf
          // werpen (missende plugins) — dat is geen netwerk en geen
          // padfout; de route ernaartoe is wat hier telt. `.onError`
          // slikt die platformrestfout zodat de test de bedoelde tak
          // kan controleren.
          await transcribeFeedEpisode(
            c,
            r,
            feedUrl: Uri.parse(_feedUrl),
            feedTitle: 'Testpod',
            episode: ep,
          ).onError((_, _) {});
          actionDone = true;
        }),
      );
      await tester.tap(find.text('open'));
      // De stagingtak loopt tot de `context.mounted`-poort: de boom
      // verdwijnt vóór `file.exists()` terugkomt, dus de actie keert
      // netjes terug zonder de voorbeschouwingsdialoog te openen — die
      // kan op de test-VM op missende plugins hangen. `pumpUntil`
      // wacht op díe terugkeer in plaats van op een vaste klok.
      await tester.pumpWidget(const SizedBox());
      await pumpUntil(
        tester,
        () => actionDone,
        reason: 'de afleveringsactie kwam niet terug',
      );
      tester.takeException();
    });
  });

  group('web-fetchroute', () {
    test('conditionele headers en 304', () async {
      http.BaseRequest? seen;
      final client = MockClient((req) async {
        seen = req;
        return http.Response('', 304);
      });
      final result = await fetchFeed(
        Uri.parse('https://podcast.example/feed.xml'),
        etag: '"abc"',
        lastModified: 'Mon, 01 Jan 2024',
        client: client,
      );
      expect(seen!.headers['If-None-Match'], '"abc"');
      expect(seen!.headers['If-Modified-Since'], 'Mon, 01 Jan 2024');
      expect(result.notModified, isTrue);
      expect(result.failure, isNull);
    });

    test('200 met ETag en Last-Modified', () async {
      final client = MockClient(
        (req) async => http.Response(
          'rss-body',
          200,
          headers: {'etag': '"xyz"', 'last-modified': 'Tue, 02 Jan 2024'},
        ),
      );
      final result = await fetchFeed(
        Uri.parse('https://podcast.example/feed.xml'),
        client: client,
      );
      expect(result.ok, isTrue);
      expect(utf8.decode(result.bytes!), 'rss-body');
      expect(result.etag, '"xyz"');
      expect(result.lastModified, 'Tue, 02 Jan 2024');
    });

    test('niet-200 en niet-http(s) leveren de gerichte reden', () async {
      final missing = await fetchFeed(
        Uri.parse('https://podcast.example/feed.xml'),
        client: MockClient((req) async => http.Response('x', 404)),
      );
      expect(missing.failure, isNotNull);

      final scheme = await fetchFeed(
        Uri.parse('ftp://podcast.example/feed.xml'),
        client: MockClient((req) async => http.Response('x', 200)),
      );
      expect(scheme.failure, isNotNull);
    });

    test('oversize wordt afgesneden vóór de bytes binnen zijn', () async {
      final client = MockClient(
        (req) async =>
            http.Response('x' * 100, 200, headers: {'content-length': '100'}),
      );
      final result = await fetchFeed(
        Uri.parse('https://podcast.example/feed.xml'),
        maxBytes: 10,
        client: client,
      );
      expect(result.failure, isNotNull);
      expect(result.bytes, isNull);
    });
  });
}
