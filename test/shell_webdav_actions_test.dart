import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/models/webdav_settings.dart';
import 'package:ocideck/services/webdav_service.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/state/webdav_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Openen uit en opslaan naar een WebDAV-server, gedreven door de échte shell:
/// `_openFromNextcloud` en `_saveToNextcloud` in
/// `lib/widgets/shell/shell_actions.dart` — samen het grootste onbeproefde blok
/// van dat bestand — plus de verbindingskeuze in
/// `shell_actions_connections.dart`.
///
/// Bewust de tegenhanger van `shell_s3_actions_test.dart` en niet er een kopie
/// van: het S3-pad spiegelt dit pad in de bron, dus als de twee uit elkaar gaan
/// lopen hoort dat hier zichtbaar te worden. Wat hier extra bij komt is het
/// verschil dat WebDAV wél kent: de herkomst wordt op server + gebruiker
/// getoetst, niet op een bucketnaam.
///
/// De naad is [WebdavService]: een server die niets over de lijn doet maar wél
/// onthoudt wát er heen ging. Wat hier NIET gebeurt is het HTTP-, PROPFIND- en
/// pinning-werk; dat hoort in `webdav_service_coverage_test.dart`.
///
/// Zie de kop van `shell_s3_actions_test.dart` voor waarom er twee soorten
/// pompen zijn: alles wat een pakket bouwt moet binnen [WidgetTester.runAsync]
/// beginnen, en dat kan alleen bij knoppen — niet bij een `PopupMenuButton`.
/// Eén frame op de nep-klok.
const _frame = Duration(milliseconds: 16);

/// Hoeveel pomp-stappen de nep-klok vooruitzetten.
///
/// Alleen de eerste stappen hoeven dat: animaties (een dialoogovergang, een
/// menu dat sluit) zijn ruim binnen anderhalve testseconde uitgespeeld. Daarna
/// pompen we frames zónder de klok te verzetten, zodat écht werk — schijf,
/// isolates — alle tijd van de wereld krijgt terwijl een `SnackBar` (vier
/// testseconden) niet door het wachten zelf verdwijnt.
///
/// Zo hangt het budget aan het aantal stappen en niet aan de klok: op een
/// zwaarbelaste machine duurt elke stap langer in échte tijd, en dat is precies
/// wat er dan nodig is.
const _clockSteps = 100;

void main() {
  const connectionId = 'webdav-verbinding';

  const server = WebdavServer(
    baseUrl: 'https://cloud.example.org',
    username: 'tester',
  );

  late _RecordingWebdav dav;
  late Directory tmp;
  late List<StorageConnection> connections;
  late ProviderContainer container;

  void seedPrefs() {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([
        for (final c in connections) c.toJson(),
      ]),
    });
  }

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    dav = _RecordingWebdav();
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_webdav');
    connections = [
      // Thuisbasis voor het openpad; zonder deze valt het terug op
      // `getApplicationDocumentsDirectory`, dat onder `flutter test` ontbreekt.
      LocalConnection(id: 'lokaal', name: 'Mijn presentaties', path: tmp.path),
      WebdavConnection(
        id: connectionId,
        name: 'Klant B – cloud',
        server: server,
      ),
    ];
    seedPrefs();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Deck sampleDeck() => Deck(
    title: 'Kwartaalrapport #3',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Kwartaalrapport'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Een', 'Twee']),
    ],
  );

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Pompt tot [until] waar is, met echte async-vensters tussen de frames.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() until, {
    required String reason,
    int steps = 400,
  }) async {
    for (var i = 0; i < steps && !until(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(i < _clockSteps ? _frame : Duration.zero);
    }
    expect(until(), isTrue, reason: reason);
  }

  /// Voert [gesture] uit binnen [WidgetTester.runAsync] en pompt daar tot
  /// [until] waar is — de weg voor alles wat een pakket bouwt.
  Future<void> act(
    WidgetTester tester,
    Future<void> Function() gesture,
    bool Function() until, {
    required String reason,
  }) async {
    var reached = false;
    await tester.runAsync(() async {
      await gesture();
      for (var i = 0; i < 400; i++) {
        if (until()) {
          reached = true;
          break;
        }
        await tester.pump(i < _clockSteps ? _frame : Duration.zero);
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = reached || until();
    });
    await tester.pump();
    expect(reached, isTrue, reason: reason);
  }

  Future<TabInfo> pumpShell(
    WidgetTester tester, {
    bool serviceAvailable = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          webdavServiceProvider(
            connectionId,
          ).overrideWith((ref) async => serviceAvailable ? dav : null),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(sampleDeck());
    await tester.pumpAndSettle();
    return tab;
  }

  WebdavOrigin originAt(
    String remotePath, {
    String? etag,
    String username = 'tester',
    String connection = connectionId,
  }) => WebdavOrigin(
    connectionId: connection,
    baseUrl: 'https://cloud.example.org',
    username: username,
    remotePath: remotePath,
    etag: etag,
  );

  bool saveDialogShown() =>
      find.text('Opslaan naar WebDAV').evaluate().isNotEmpty;

  Future<void> pickFromMenu(
    WidgetTester tester,
    IconData icon,
    bool Function() until, {
    required String reason,
  }) async {
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(icon));
    await settleUntil(tester, until, reason: reason);
  }

  Future<void> tapSave(
    WidgetTester tester,
    bool Function() until, {
    required String reason,
  }) => act(
    tester,
    () => tester.tap(appBarIcon(Icons.save_outlined)),
    until,
    reason: reason,
  );

  String pathFieldText(WidgetTester tester) =>
      tester.widget<TextField>(find.byType(TextField).last).controller!.text;

  testWidgets('"Opslaan naar…" vraagt om een pad op de server', (tester) async {
    await pumpShell(tester);
    await pickFromMenu(
      tester,
      Icons.cloud_upload_outlined,
      saveDialogShown,
      reason: 'het opslaandialoog kwam niet op',
    );

    // Eén bruikbare verbinding (de lokale map telt niet mee), dus geen
    // tussenvraag welke het moet zijn.
    expect(find.text('Welke verbinding?'), findsNothing);
    // Het hekje en de spaties zijn eruit: dit wordt een bestandsnaam.
    expect(pathFieldText(tester), 'Kwartaalrapport_3');
  });

  testWidgets('een deck dat van de server kwam gaat er stil naar terug', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    tab.webdavOrigin = originAt('map/bestaand.md', etag: '"oud"');

    await tapSave(
      tester,
      () => dav.puts.isNotEmpty,
      reason: 'de opslaanknop schreef niets terug naar de server',
    );

    expect(
      saveDialogShown(),
      isFalse,
      reason: 'er mocht niets gevraagd worden',
    );
    expect(dav.puts.first.path, 'map/bestaand.md');
    // De ETag die we ophaalden gaat als If-Match mee: alleen zó merkt de app
    // dat iemand anders er ondertussen aan heeft gezeten.
    expect(dav.puts.first.ifMatch, '"oud"');
    expect(find.text('Opgeslagen op WebDAV: /map/bestaand.md'), findsOneWidget);
  });

  testWidgets('een herkomst van een ándere gebruiker vraagt wél opnieuw', (
    tester,
  ) async {
    // Zelfde server, andere account. Blind terugschrijven zou het in de
    // bestanden van de verkeerde persoon zetten — de herkomst telt hier op
    // server én gebruiker, en dát is het verschil met een S3-bucket.
    final tab = await pumpShell(tester);
    tab.webdavOrigin = originAt('map/bestaand.md', username: 'iemand-anders');

    await tapSave(
      tester,
      saveDialogShown,
      reason: 'er werd niet om een doelpad gevraagd',
    );

    expect(dav.puts, isEmpty);
    expect(
      pathFieldText(tester),
      'Kwartaalrapport_3',
      reason: 'een vreemde herkomst mag het doelpad niet voorstellen',
    );
  });

  testWidgets('zonder bruikbaar wachtwoord meldt de opslaanknop wat er mist', (
    tester,
  ) async {
    final tab = await pumpShell(tester, serviceAvailable: false);
    tab.webdavOrigin = originAt('map/bestaand.md');

    await tapSave(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'de ontbrekende server bleef stil',
    );

    expect(
      find.text('Stel eerst een WebDAV-server in bij Instellingen → Opslag.'),
      findsOneWidget,
    );
    expect(dav.puts, isEmpty);
  });

  testWidgets('een verdwenen verbinding meldt dat er niets is ingesteld', (
    tester,
  ) async {
    connections = [
      LocalConnection(id: 'lokaal', name: 'Mijn presentaties', path: tmp.path),
    ];
    seedPrefs();
    final tab = await pumpShell(tester);
    tab.webdavOrigin = originAt('map/bestaand.md', connection: 'weg');

    await tapSave(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'de verdwenen verbinding bleef stil',
    );

    expect(
      find.text('Stel eerst een WebDAV-server in bij Instellingen → Opslag.'),
      findsOneWidget,
    );
  });

  testWidgets('een mislukte upload meldt de reden', (tester) async {
    dav.failWith = WebdavException(WebdavError.auth, 'geen toegang');
    final tab = await pumpShell(tester);
    tab.webdavOrigin = originAt('map/bestaand.md');

    await tapSave(
      tester,
      () => find.textContaining('Opslaan mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukte upload bleef stil',
    );

    expect(find.text('Kopiëren'), findsOneWidget);
  });

  /// Laat een opslag op een botsing lopen en wacht tot de vraag er staat.
  Future<void> saveIntoConflict(WidgetTester tester, TabInfo tab) async {
    dav.conflictOn = 'map/bestaand.md';
    tab.webdavOrigin = originAt('map/bestaand.md', etag: '"oud"');
    await tapSave(
      tester,
      () => find
          .text('Iemand anders heeft dit bestand gewijzigd')
          .evaluate()
          .isNotEmpty,
      reason: 'de botsing werd niet voorgelegd',
    );
  }

  testWidgets('een botsing laat kiezen, en overschrijven schrijft alsnog', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    await saveIntoConflict(tester, tab);

    dav.conflictOn = null;
    await act(
      tester,
      () => tester.tap(find.widgetWithText(TextButton, 'Overschrijven')),
      () => dav.puts.length >= 2,
      reason: 'na "Overschrijven" ging er niets alsnog omhoog',
    );

    expect(dav.puts[1].path, 'map/bestaand.md');
    expect(dav.puts[0].ifMatch, '"oud"');
    expect(
      dav.puts[1].ifMatch,
      isNull,
      reason: 'overschrijven laat precies de bewaking los, en niets anders',
    );
  });

  testWidgets('"Opslaan als" na een botsing schrijft naar het nieuwe pad', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    await saveIntoConflict(tester, tab);

    await act(
      tester,
      () => tester.tap(find.widgetWithText(FilledButton, 'Opslaan als')),
      saveDialogShown,
      reason: 'er werd niet om een nieuw pad gevraagd',
    );
    expect(pathFieldText(tester), 'map/bestaand');

    await tester.enterText(find.byType(TextField).last, '/map/van-mij');
    await tester.pumpAndSettle();
    await act(
      tester,
      () => tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan')),
      () => dav.puts.length >= 2,
      reason: 'er ging niets naar het nieuwe pad',
    );

    // De leidende slash is eraf: het pad is relatief aan de wortelmap.
    expect(dav.puts[1].path, 'map/van-mij.ocideck');
    expect(dav.puts[1].ifMatch, isNull);
  });

  testWidgets('een botsing wegklikken laat het bestand met rust', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    await saveIntoConflict(tester, tab);

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(dav.puts, hasLength(1), reason: 'er mag niets tweede omhoog');
    expect(find.textContaining('Opgeslagen op WebDAV:'), findsNothing);
  });

  testWidgets('"Openen uit…" haalt het gekozen deck van de server', (
    tester,
  ) async {
    dav.files['rapport.md'] = Uint8List.fromList(
      utf8.encode('---\nmarp: true\n---\n\n# Van de server\n'),
    );
    await pumpShell(tester);

    await pickFromMenu(
      tester,
      Icons.cloud_download_outlined,
      () => find.text('rapport.md').evaluate().isNotEmpty,
      reason: 'de bladeraar toonde de map niet',
    );

    TabInfo? current() => container.read(tabsProvider).current;
    await tester.tap(find.text('rapport.md'));
    await settleUntil(
      tester,
      () => current()?.deckNotifier.currentState.deck?.title == 'Van de server',
      reason: 'het gekozen bestand is niet als deck geopend',
    );

    expect(dav.downloads, contains('rapport.md'));
    expect(current()?.webdavOrigin?.remotePath, 'rapport.md');
    expect(current()?.webdavOrigin?.etag, '"bestaand"');
  });

  testWidgets('een mislukte download meldt de reden', (tester) async {
    dav.files['rapport.md'] = Uint8List(0);
    await pumpShell(tester);

    await pickFromMenu(
      tester,
      Icons.cloud_download_outlined,
      () => find.text('rapport.md').evaluate().isNotEmpty,
      reason: 'de bladeraar toonde de map niet',
    );

    dav.failWith = WebdavException(WebdavError.network, 'verbinding weg');
    await tester.tap(find.text('rapport.md'));
    await settleUntil(
      tester,
      () => find.textContaining('Downloaden mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukte download bleef stil',
    );

    expect(find.text('Kopiëren'), findsOneWidget);
  });
}

/// Eén upload zoals de server hem zag.
typedef _Put = ({String path, String? ifMatch, int bytes});

/// Een WebDAV-server die niets over de lijn doet, maar wél onthoudt wát er in
/// welke volgorde heen ging — en die op commando kan botsen of falen.
class _RecordingWebdav extends WebdavService {
  _RecordingWebdav()
    : super(
        server: const WebdavServer(
          baseUrl: 'https://cloud.example.org',
          username: 'tester',
        ),
        password: 'wegwerp',
      );

  final puts = <_Put>[];
  final downloads = <String>[];

  /// Pad → inhoud; wat de bladeraar toont en wat een download oplevert.
  final files = <String, Uint8List>{};

  /// Pad waarop de server een botsing meldt (412 Precondition Failed).
  String? conflictOn;

  /// Als dit gezet is, faalt élke upload en download ermee.
  WebdavException? failWith;

  @override
  Future<List<WebdavEntry>> list(String remotePath) async => [
    for (final entry in files.entries)
      WebdavEntry(
        name: entry.key.split('/').last,
        relativePath: entry.key,
        isCollection: false,
        size: entry.value.length,
        etag: '"bestaand"',
      ),
  ];

  @override
  Future<WebdavFile> download(
    String remotePath, {
    int maxBytes = WebdavService.maxDownloadBytes,
  }) async {
    downloads.add(remotePath);
    final fail = failWith;
    if (fail != null) throw fail;
    return WebdavFile(files[remotePath] ?? Uint8List(0), '"bestaand"');
  }

  @override
  Future<String?> upload(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool onlyIfAbsent = false,
  }) async {
    puts.add((path: remotePath, ifMatch: ifMatch, bytes: bytes.length));
    final fail = failWith;
    if (fail != null) throw fail;
    if (remotePath == conflictOn) {
      throw WebdavConflictException(expectedEtag: '"oud"', message: 'botst');
    }
    return '"nieuw"';
  }
}
