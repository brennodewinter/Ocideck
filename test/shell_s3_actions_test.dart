import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/s3_settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/s3/s3_service.dart';
import 'package:ocideck/state/s3_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Openen uit en opslaan naar een S3-bucket, gedreven door de échte shell:
/// `lib/widgets/shell/shell_actions_s3.dart`, plus de gedeelde stukken die het
/// gebruikt (het opslaan- en botsingsdialoog in `shell_actions.dart` en de
/// verbindingskeuze in `shell_actions_connections.dart`). Dat bestand stond op
/// nul uitgevoerde regels.
///
/// De naad is [S3Service]: die wordt hier vervangen door een bucket die niets
/// over de lijn doet maar wél onthoudt wát er heen ging (zelfde vorm als
/// `tabs_provider_s3_test.dart`). Alles daarboven — het menu, de dialogen, de
/// herkomstlogica, de conflictafhandeling, de meldingen — is de echte code.
///
/// Wat hier bewust NIET gebeurt: het pad tot en met een echte S3-server, en de
/// SigV4-ondertekening. Dat hoort in `s3_service_test.dart`; hier gaat het om
/// de opdrachtlaag erboven.
///
/// ## Waarom twee soorten pompen
///
/// Het bouwen van een pakket leest de thema-CSS uit de asset-bundel, en
/// `AssetBundle.loadString` decodeert alles boven 10 kB in een eigen isolate.
/// Een isolate die *buiten* [WidgetTester.runAsync] wordt gestart, komt in een
/// testproces precies één keer terug; elke volgende hangt. Dat maakt zo'n test
/// groen op zijn plek in de lijst en rood zodra de volgorde wisselt — en de
/// volgorde wisselt hier per run.
///
/// Daarom draait alles wat een pakket bouwt via [act]: de tik zélf gebeurt
/// binnen [WidgetTester.runAsync], zodat de hele keten in de echte async-zone
/// blijft. Dat kan alleen bij knoppen — een `PopupMenuButton` levert zijn keuze
/// af via een route-animatie die binnen [WidgetTester.runAsync] niet loopt, dus
/// menu-handelingen gaan via [settleUntil], dat nep-klok en echte async om
/// beurten de gelegenheid geeft.
void main() {
  const connectionId = 's3-verbinding';

  const bucket = S3Bucket(
    endpoint: 'https://s3.example',
    region: 'eu-central-1',
    bucket: 'presentaties',
    accessKeyId: 'AKIA-wegwerp',
  );

  late _RecordingS3 s3;
  late Directory tmp;

  /// De container van de gepompte app; nodig om het *huidige* tabblad te
  /// bevragen, want openen uit de bucket landt in een nieuw tabblad.
  late ProviderContainer container;

  /// De verbindingen die in de instellingen staan; per test aanpasbaar vóór
  /// [pumpShell].
  late List<StorageConnection> connections;

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
    s3 = _RecordingS3();
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_s3');
    connections = [
      // Een lokale map als thuisbasis: het openpad schrijft de gedownloade
      // presentatie daarin weg. Zonder deze valt het terug op
      // `getApplicationDocumentsDirectory`, dat onder `flutter test` niet
      // bestaat.
      LocalConnection(id: 'lokaal', name: 'Mijn presentaties', path: tmp.path),
      S3Connection(id: connectionId, name: 'Klant A – bucket', bucket: bucket),
    ];
    seedPrefs();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Deck sampleDeck() => Deck(
    title: 'Testrapport 2026!',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
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
  ///
  /// Voor handelingen die buiten [WidgetTester.runAsync] beginnen (het
  /// overloopmenu) en onderweg echt bestandswerk doen: de nep-klok drijft de
  /// animaties, de vensters laten het schijfwerk vorderen.
  ///
  /// Het budget is bewust een áántal stappen en geen tijdsgrens. Elke stap zet
  /// de testklok 16 ms vooruit; met een tijdsgrens zou de klok meelopen met hoe
  /// traag de machine is, en dan verdwijnt een `SnackBar` (vier testseconden)
  /// door het wachten zelf.
  Future<void> settleUntil(
    WidgetTester tester,
    bool Function() until, {
    required String reason,
    int steps = 150,
  }) async {
    for (var i = 0; i < steps && !until(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 2)),
      );
      await tester.pump(const Duration(milliseconds: 16));
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
      for (var i = 0; i < 150; i++) {
        if (until()) {
          reached = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }
      reached = reached || until();
    });
    await tester.pump();
    expect(reached, isTrue, reason: reason);
  }

  /// Pompt de app met [s3] achter de S3-verbinding en laadt [deck].
  ///
  /// Met [serviceAvailable] op `false` doet de test alsof de sleutel uit de
  /// keychain weg is — de verbinding staat er, maar er valt niets mee te doen.
  Future<TabInfo> pumpShell(
    WidgetTester tester, {
    Deck? deck,
    bool serviceAvailable = true,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          s3ServiceProvider(
            connectionId,
          ).overrideWith((ref) async => serviceAvailable ? s3 : null),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    final tab = container.read(tabsProvider).current!;
    tab.deckNotifier.loadDeck(deck ?? sampleDeck());
    await tester.pumpAndSettle();
    return tab;
  }

  S3Origin originAt(
    String remotePath, {
    String? etag,
    String bucket = 'presentaties',
    String connection = connectionId,
  }) => S3Origin(
    connectionId: connection,
    endpoint: 'https://s3.example',
    bucket: bucket,
    remotePath: remotePath,
    etag: etag,
  );

  bool saveDialogShown() => find.text('Opslaan naar S3').evaluate().isNotEmpty;
  bool conflictDialogShown() => find
      .text('Iemand anders heeft dit bestand gewijzigd')
      .evaluate()
      .isNotEmpty;

  /// Opent het overloopmenu, kiest een item en wacht tot [until] waar is.
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

  /// Tikt op de opslaanknop in de werkbalk en wacht tot [until] waar is.
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

  // ── Menu-ingangen ─────────────────────────────────────────────────────────

  testWidgets('"Opslaan naar…" stelt een naam voor die uit de decktitel volgt', (
    tester,
  ) async {
    await pumpShell(tester);
    await pickFromMenu(
      tester,
      Icons.cloud_upload_outlined,
      saveDialogShown,
      reason: 'het opslaandialoog kwam niet op',
    );

    // Eén bruikbare verbinding (de lokale map telt niet mee), dus geen
    // tussenvraag welke het moet zijn: het opslaandialoog staat er meteen.
    expect(find.text('Welke verbinding?'), findsNothing);
    // Uitroepteken en spatie eruit: de sleutel moet een nette bestandsnaam
    // zijn, niet de ruwe titel.
    expect(pathFieldText(tester), 'Testrapport_2026');
  });

  testWidgets('een leeg doelpad sluit het opslaandialoog niet', (tester) async {
    await pumpShell(tester);
    await pickFromMenu(
      tester,
      Icons.cloud_upload_outlined,
      saveDialogShown,
      reason: 'het opslaandialoog kwam niet op',
    );

    await tester.enterText(find.byType(TextField).last, '   ');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan'));
    await tester.pumpAndSettle();

    expect(saveDialogShown(), isTrue);
    expect(s3.puts, isEmpty);
  });

  testWidgets('annuleren in het opslaandialoog uploadt niets', (tester) async {
    await pumpShell(tester);
    await pickFromMenu(
      tester,
      Icons.cloud_upload_outlined,
      saveDialogShown,
      reason: 'het opslaandialoog kwam niet op',
    );

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(saveDialogShown(), isFalse);
    expect(s3.puts, isEmpty);
    expect(find.textContaining('Opgeslagen in S3:'), findsNothing);
  });

  testWidgets('"Openen uit…" haalt het gekozen deck uit de bucket', (
    tester,
  ) async {
    s3.objects['rapport.md'] = Uint8List.fromList(
      utf8.encode('---\nmarp: true\n---\n\n# Uit de bucket\n'),
    );
    await pumpShell(tester);

    // Eén verbinding, dus geen tussenvraag: de bladeraar staat er meteen, met
    // de listing van de bucket erin.
    await pickFromMenu(
      tester,
      Icons.cloud_download_outlined,
      () => find.text('rapport.md').evaluate().isNotEmpty,
      reason: 'de bladeraar toonde de bucket niet',
    );

    // Het geopende deck landt in een eigen tabblad, dus kijk naar het huidige.
    TabInfo? current() => container.read(tabsProvider).current;
    await tester.tap(find.text('rapport.md'));
    await settleUntil(
      tester,
      () => current()?.deckNotifier.currentState.deck?.title == 'Uit de bucket',
      reason: 'het gekozen object is niet als deck geopend',
    );

    expect(s3.downloads, contains('rapport.md'));
    // De herkomst blijft hangen, zodat opslaan er straks naar terug kan — en
    // met de ETag erbij, want dáárop toetst de volgende opslag.
    expect(current()?.s3Origin?.remotePath, 'rapport.md');
    expect(current()?.s3Origin?.etag, '"bestaand"');
  });

  testWidgets('een onleesbaar object levert een melding op, geen leeg tabblad', (
    tester,
  ) async {
    // Geen frontmatter, geen Marp: de importpoort weigert de bytes al vóór er
    // iets op schijf komt, en dat hoort de gebruiker te horen.
    s3.objects['rapport.md'] = Uint8List.fromList(utf8.encode('gewoon tekst'));
    await pumpShell(tester);
    final tabsBefore = container.read(tabsProvider).tabs.length;

    await pickFromMenu(
      tester,
      Icons.cloud_download_outlined,
      () => find.text('rapport.md').evaluate().isNotEmpty,
      reason: 'de bladeraar toonde de bucket niet',
    );

    await tester.tap(find.text('rapport.md'));
    await settleUntil(
      tester,
      () => find.text('Kon dit bestand niet openen.').evaluate().isNotEmpty,
      reason: 'een geweigerd object bleef stil',
    );

    expect(container.read(tabsProvider).tabs, hasLength(tabsBefore));
  });

  testWidgets('een mislukte download meldt de reden', (tester) async {
    s3.objects['rapport.md'] = Uint8List(0);
    await pumpShell(tester);

    await pickFromMenu(
      tester,
      Icons.cloud_download_outlined,
      () => find.text('rapport.md').evaluate().isNotEmpty,
      reason: 'de bladeraar toonde de bucket niet',
    );

    s3.failWith = S3Exception(S3Error.network, 'verbinding weg');
    await tester.tap(find.text('rapport.md'));
    await settleUntil(
      tester,
      () => find.textContaining('Downloaden mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukte download bleef stil',
    );

    expect(find.text('Kopiëren'), findsOneWidget);
  });

  // ── De opslaanknop: terug naar waar het vandaan kwam ───────────────────────

  testWidgets('een deck dat uit de bucket kwam gaat er stil naar terug', (
    tester,
  ) async {
    // Dít is waar de opslaanknop voor bedoeld is: waar het vandaan kwam, gaat
    // het naartoe terug — zonder opnieuw te vragen waar het heen moet, want
    // dan zou de gebruiker het elke keer bij de verkeerde klant kunnen laten
    // belanden.
    final tab = await pumpShell(tester);
    tab.s3Origin = originAt('klant/bestaand.md', etag: '"oud"');

    await tapSave(
      tester,
      () => s3.puts.isNotEmpty,
      reason: 'de opslaanknop schreef niets terug naar de bucket',
    );

    expect(saveDialogShown(), isFalse, reason: 'er mocht niets gevraagd worden');
    // Zelfde pad, en het formaat volgt de extensie die er al stond: een platte
    // spiegel blijft plat, geen pakket eroverheen.
    expect(s3.puts.first.path, 'klant/bestaand.md');
    expect(
      s3.puts.length,
      greaterThan(1),
      reason: 'een platte spiegel is meer dan alleen de markdown',
    );
    // En met de bewaking eraan: de ETag die we ophaalden gaat als If-Match mee.
    expect(s3.puts.first.ifMatch, '"oud"');
    expect(find.text('Opgeslagen in S3: /klant/bestaand.md'), findsOneWidget);
  });

  testWidgets('een pakketherkomst gaat als pakket terug', (tester) async {
    final tab = await pumpShell(tester);
    tab.s3Origin = originAt('klant/bestaand.ocideck');

    await tapSave(
      tester,
      () => s3.puts.isNotEmpty,
      reason: 'de opslaanknop schreef niets terug naar de bucket',
    );

    expect(s3.puts.single.path, 'klant/bestaand.ocideck');
    expect(
      find.text('Opgeslagen in S3: /klant/bestaand.ocideck'),
      findsOneWidget,
    );
  });

  testWidgets('een herkomst uit een ándere bucket vraagt wél opnieuw', (
    tester,
  ) async {
    // De verbinding wijst naar `presentaties`; dit deck kwam uit `archief`.
    // Blind terugschrijven zou het bij de verkeerde bucket neerzetten.
    final tab = await pumpShell(tester);
    tab.s3Origin = originAt('oud/rapport.md', bucket: 'archief');

    await tapSave(
      tester,
      saveDialogShown,
      reason: 'er werd niet om een doelpad gevraagd',
    );

    expect(s3.puts, isEmpty);
    expect(
      pathFieldText(tester),
      'Testrapport_2026',
      reason: 'een vreemde herkomst mag het doelpad niet voorstellen',
    );
  });

  testWidgets('zonder bruikbare sleutel meldt de opslaanknop wat er mist', (
    tester,
  ) async {
    // De verbinding staat er nog, maar de sleutel is uit de keychain — dan
    // valt er niets op te slaan en hoort dat gezegd te worden.
    final tab = await pumpShell(tester, serviceAvailable: false);
    tab.s3Origin = originAt('klant/bestaand.md');

    await tapSave(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'de ontbrekende sleutel bleef stil',
    );

    expect(
      find.text('Stel eerst een S3-bucket in bij Instellingen → Opslag.'),
      findsOneWidget,
    );
    expect(s3.puts, isEmpty);
  });

  testWidgets('een verdwenen verbinding meldt dat er niets is ingesteld', (
    tester,
  ) async {
    // Het deck kwam uit een bucket die intussen uit de instellingen is
    // verwijderd. Er valt dan niets te kiezen, en de melding wijst naar de plek
    // waar je het weer kunt instellen.
    connections = [
      LocalConnection(id: 'lokaal', name: 'Mijn presentaties', path: tmp.path),
    ];
    seedPrefs();
    final tab = await pumpShell(tester);
    tab.s3Origin = originAt('klant/bestaand.md', connection: 'weg');

    await tapSave(
      tester,
      () => find.byType(SnackBar).evaluate().isNotEmpty,
      reason: 'de verdwenen verbinding bleef stil',
    );

    expect(
      find.text('Stel eerst een S3-bucket in bij Instellingen → Opslag.'),
      findsOneWidget,
    );
    expect(s3.puts, isEmpty);
  });

  testWidgets('een mislukte upload meldt de reden', (tester) async {
    s3.failWith = S3Exception(S3Error.auth, 'geen toegang');
    final tab = await pumpShell(tester);
    tab.s3Origin = originAt('klant/bestaand.md');

    await tapSave(
      tester,
      () => find.textContaining('Opslaan mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukte upload bleef stil',
    );

    // De melding is te kopiëren, zodat hij door te sturen is.
    expect(find.text('Kopiëren'), findsOneWidget);
  });

  // ── Botsingen ─────────────────────────────────────────────────────────────

  /// Laat een opslag op een botsing lopen en wacht tot de vraag er staat.
  Future<void> saveIntoConflict(WidgetTester tester, TabInfo tab) async {
    s3.conflictOn = 'klant/bestaand.md';
    tab.s3Origin = originAt('klant/bestaand.md', etag: '"oud"');
    await tapSave(
      tester,
      conflictDialogShown,
      reason: 'de botsing werd niet voorgelegd',
    );
  }

  testWidgets('een botsing laat kiezen, en overschrijven schrijft alsnog', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    await saveIntoConflict(tester, tab);

    // Vanaf nu accepteert de bucket het weer; overschrijven moet dan slagen.
    s3.conflictOn = null;
    await act(
      tester,
      () => tester.tap(find.widgetWithText(TextButton, 'Overschrijven')),
      () => s3.puts.length >= 2,
      reason: 'na "Overschrijven" ging er niets alsnog omhoog',
    );

    // De tweede poging gaat naar hetzelfde pad, maar zónder bewaking — dat is
    // precies wat "overschrijven" betekent, en het verschil met de eerste.
    expect(s3.puts[1].path, 'klant/bestaand.md');
    expect(s3.puts[0].ifMatch, '"oud"');
    expect(s3.puts[1].ifMatch, isNull);
  });

  testWidgets('"Opslaan als" na een botsing vraagt om een nieuw pad', (
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
    // Het tweede opslaandialoog begint bij het pad dat botste, zodat de
    // gebruiker er alleen iets aan hoeft toe te voegen.
    expect(pathFieldText(tester), 'klant/bestaand');

    await tester.enterText(find.byType(TextField).last, 'klant/bestaand-mijn');
    await tester.pumpAndSettle();
    // Bewust als pakket: de keuze uit het dialoog moet het doelpad bepalen, en
    // niet de extensie waarmee het deck ooit binnenkwam.
    await tester.tap(
      find.text('Als .ocideck-pakket (één bestand, met assets)'),
    );
    await tester.pumpAndSettle();
    await act(
      tester,
      () => tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan')),
      () => s3.puts.length >= 2,
      reason: 'er ging niets naar het nieuwe pad',
    );

    expect(s3.puts[1].path, 'klant/bestaand-mijn.ocideck');
    // Een ánder pad hebben we nooit opgehaald, dus valt er niets te bewaken.
    expect(s3.puts[1].ifMatch, isNull);
  });

  testWidgets('een botsing wegklikken laat het bestand met rust', (
    tester,
  ) async {
    final tab = await pumpShell(tester);
    await saveIntoConflict(tester, tab);

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(conflictDialogShown(), isFalse);
    expect(s3.puts, hasLength(1), reason: 'er mag niets tweede omhoog');
    expect(find.textContaining('Opgeslagen in S3:'), findsNothing);
  });
}

/// Eén upload zoals de bucket hem zag.
typedef _Put = ({String path, String? ifMatch, int bytes});

/// Een bucket die niets over de lijn doet, maar wél onthoudt wát er in welke
/// volgorde heen ging — en die op commando kan botsen of falen.
///
/// Zelfde vorm als `_RecordingS3` in `tabs_provider_s3_test.dart`; hier met een
/// listing erbij, want de shell bladert eerst.
class _RecordingS3 extends S3Service {
  _RecordingS3()
    : super(
        bucket: const S3Bucket(
          endpoint: 'https://s3.example',
          region: 'eu-central-1',
          bucket: 'presentaties',
          accessKeyId: 'AKIA-wegwerp',
        ),
        secretAccessKey: 'wegwerp',
      );

  final puts = <_Put>[];
  final downloads = <String>[];

  /// Sleutel → inhoud; wat de bladeraar toont en wat een download oplevert.
  final objects = <String, Uint8List>{};

  /// Pad waarop het endpoint een botsing meldt (412 Precondition Failed).
  String? conflictOn;

  /// Als dit gezet is, faalt élke upload en download ermee.
  S3Exception? failWith;

  @override
  Future<List<S3Entry>> list(String remotePath) async => [
    for (final entry in objects.entries)
      S3Entry(
        name: entry.key.split('/').last,
        relativePath: entry.key,
        isCollection: false,
        size: entry.value.length,
        etag: '"bestaand"',
      ),
  ];

  @override
  Future<S3File> download(
    String remotePath, {
    int maxBytes = S3Service.maxDownloadBytes,
  }) async {
    downloads.add(remotePath);
    final fail = failWith;
    if (fail != null) throw fail;
    return S3File(objects[remotePath] ?? Uint8List(0), '"bestaand"');
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
      throw const S3ConflictException(expectedEtag: '"oud"', message: 'botst');
    }
    return '"nieuw"';
  }
}
