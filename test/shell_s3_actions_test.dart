import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
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
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/s3_browser_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Eén upload zoals de bucket hem zag.
typedef _Put = ({String path, String? ifMatch, int bytes});

/// Een bucket die niets over de lijn doet, maar wél onthoudt wát er in welke
/// volgorde heen ging en met welke voorwaarde — precies waar de beloften van
/// dit pad over gaan.
class _FakeBucket extends S3Service {
  _FakeBucket({
    required super.bucket,
    this.objects = const {},
    this.downloadFailure,
    this.uploadFailure,
    this.conflictOn,
  }) : super(secretAccessKey: 'wegwerp');

  /// Sleutel (relatief aan de wortel) → inhoud.
  final Map<String, Uint8List> objects;

  final S3Exception? downloadFailure;
  final S3Exception? uploadFailure;

  /// Pad waarop het endpoint één keer een botsing meldt (412).
  final String? conflictOn;

  final puts = <_Put>[];
  final botsingenGemeld = <String>[];

  @override
  Future<List<S3Entry>> list(String remotePath) async {
    return [
      for (final key in objects.keys)
        S3Entry(
          name: key.split('/').last,
          relativePath: key,
          isCollection: false,
          size: objects[key]!.length,
          etag: '"opgehaald"',
        ),
    ];
  }

  @override
  Future<S3File> download(String remotePath, {int maxBytes = 0}) async {
    if (downloadFailure != null) throw downloadFailure!;
    final body = objects[remotePath];
    if (body == null) throw S3Exception(S3Error.notFound, 'weg');
    return S3File(body, '"opgehaald"');
  }

  @override
  Future<String?> upload(
    String remotePath,
    List<int> bytes, {
    String? ifMatch,
    bool onlyIfAbsent = false,
  }) async {
    puts.add((path: remotePath, ifMatch: ifMatch, bytes: bytes.length));
    if (uploadFailure != null) throw uploadFailure!;
    // Eén keer botsen: daarna moet de gekozen uitweg wél doorkomen, anders
    // toetst de test alleen dat het dialoog blijft terugkomen.
    if (remotePath == conflictOn && !botsingenGemeld.contains(remotePath)) {
      botsingenGemeld.add(remotePath);
      throw const S3ConflictException(
        expectedEtag: '"nieuwer"',
        message: 'botst',
      );
    }
    return '"na-opslaan"';
  }
}

/// Openen uit en opslaan naar een S3-bucket zoals de shell het aanstuurt
/// (`widgets/shell/shell_actions_s3.dart`, plus het gedeelde opslaan- en
/// botsingsdialoog uit `shell_actions.dart`). Die bestanden draaiden geen
/// enkele regel: alles zit achter de bladeraar en een netwerkaanroep.
///
/// De netwerkkant zelf (ondertekening, pinning, paginering) staat in
/// `s3_service_test.dart`; hier gaat het om wat de shell ermee doet — waar een
/// deck heen gaat, of er eerst gevraagd wordt, en of de bewaking tegen
/// andermans versie blijft staan.
void main() {
  late Directory tmp;
  late _FakeBucket fake;

  const validDeck = '''
---
marp: true
theme: ocideck
---

# Kwartaalcijfers

---

## Tweede dia

- punt één
''';

  Uint8List bytes(String s) => Uint8List.fromList(utf8.encode(s));

  void useSettings({List<StorageConnection> extra = const []}) {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': StorageConnection.encodeList([
        // De eerste lokale map is tegelijk de "home": daar landt een import.
        LocalConnection(id: 'lokaal', name: 'Werkmap', path: tmp.path),
        const S3Connection(id: 'bucket-1', name: 'Klant A', bucket: _bucket),
        ...extra,
      ]),
    });
  }

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_s3');
    fake = _FakeBucket(bucket: _bucket, objects: {'deck.md': bytes(validDeck)});
    useSettings();
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Finder appBarIcon(IconData icon) =>
      find.descendant(of: find.byType(AppBar), matching: find.byIcon(icon));
  Finder menuItemIcon(IconData icon) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.byIcon(icon),
  );

  /// Pompt de app met de nep-bucket in plaats van de echte dienst.
  ///
  /// Alleen `s3ServiceProvider` gaat om: de bladeraar leest zijn listing via
  /// datzelfde element, dus hij bladert door dezelfde nep als waar de shell
  /// naartoe schrijft.
  Future<ProviderContainer> pumpShell(
    WidgetTester tester, {
    Deck? deck,
    _FakeBucket? service,
  }) async {
    final bucketService = service ?? fake;
    // Zet de asset-cache warm vóór er iets te doen valt.
    //
    // Het pakket krijgt zijn thema-CSS uit `rootBundle`, en het testbinding
    // leegt die cache tussen tests. Een kóude lees vraagt een echte beurt op de
    // gebeurtenislus, en die krijgt de opslaanketen binnen [runAsync] niet: de
    // eerste opslag in een testproces lukte, de volgende bleef hangen — groen
    // of rood puur afhankelijk van de plek in de lijst. Eén keer vooraf lezen
    // maakt dat deterministisch zonder iets van het pad over te slaan: het
    // bouwen van het pakket loopt daarna gewoon door `_packageThemeCss`.
    await tester.runAsync(
      () => rootBundle.loadString('assets/themes/ocideck.css'),
    );
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          s3ServiceProvider(
            'bucket-1',
          ).overrideWith((ref) async => bucketService),
        ],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    if (deck != null) {
      container.read(tabsProvider).current!.deckNotifier.loadDeck(deck);
      await tester.pumpAndSettle();
    }
    return container;
  }


  /// Laat het echte werk (bestanden lezen/schrijven, het pakket bouwen)
  /// vorderen en pompt ondertussen frames, tot [until] waar is.
  ///
  /// `pumpAndSettle` volstaat niet: de import schrijft naar schijf en het
  /// pakket wordt in een isolate gebouwd, en dat vordert alleen binnen
  /// [WidgetTester.runAsync]. De klok wordt bewust niet vooruitgezet — anders
  /// verdwijnt een melding door het wachten zelf. Zie
  /// `shell_export_actions_test.dart`, waar dit patroon vandaan komt.
  Future<bool> settleAsync(
    WidgetTester tester,
    bool Function() until, {
    Future<void> Function()? start,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    var reached = false;
    await tester.runAsync(() async {
      if (start != null) {
        await start();
        await tester.pump();
      }
      final deadline = DateTime.now().add(timeout);
      while (DateTime.now().isBefore(deadline)) {
        if (until()) {
          reached = true;
          break;
        }
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = reached || until();
      // Staart: de voorwaarde is bereikt, maar de rest van de keten (tot en met
      // het frame met de melding) moet nog vallen, en buiten deze zone kan dat
      // niet meer.
      for (var i = 0; i < 20; i++) {
        await tester.pump();
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pumpAndSettle();
    return reached;
  }

  /// Tikt op [target] en wacht tot [until] waar is — voor elke tik die echt
  /// werk in gang zet of hervat.
  ///
  /// De tik hoort BINNEN [WidgetTester.runAsync] te vallen, en dat is geen
  /// smaakkwestie: opslaan en openen zijn één lange async-keten (dialoog →
  /// pakket bouwen → uploaden), en die keten draait in de zone waarin hij is
  /// begonnen. Start hij in de fake-async-zone, dan komt het echte werk in het
  /// eerste geval nog terug en daarna niet meer — groen op zijn plek in de
  /// lijst, rood zodra de volgorde wisselt. En hier wisselt de volgorde per
  /// run. Zie `shell_export_actions_test.dart`, waar dit is uitgezocht.
  Future<void> startChain(
    WidgetTester tester,
    Finder target,
    bool Function() until, {
    required String reason,
  }) async {
    expect(
      await settleAsync(tester, until, start: () => tester.tap(target)),
      isTrue,
      reason: reason,
    );
  }

  /// "Openen uit…" op het welkomscherm — de ingang zolang er nog geen deck
  /// open is, en daarmee de plek waar dit pad in de praktijk begint.
  Future<void> openFromWelcome(WidgetTester tester) => startChain(
    tester,
    find.widgetWithText(OutlinedButton, 'Openen uit\u2026'),
    () => find.byType(S3BrowserDialog).evaluate().isNotEmpty,
    reason: 'de bladeraar kwam niet op',
  );

  bool textShown(String needle) =>
      find.textContaining(needle).evaluate().isNotEmpty;

  /// Het invoerveld ín het geopende dialoog. Ongescoopt zou dit het zoekveld
  /// of een editorveld van de shell kunnen pakken.
  Finder dialogField() => find.descendant(
    of: find.byType(AlertDialog),
    matching: find.byType(TextField),
  );

  Deck sampleDeck() => Deck(
    title: 'Rapport: Klant A/B',
    slides: [
      Slide.create(SlideType.title).copyWith(title: 'Rapport'),
      Slide.create(
        SlideType.bullets,
      ).copyWith(title: 'Bevindingen', bullets: const ['Een']),
    ],
  );

  group('openen uit de bucket', () {
    testWidgets('een gekozen deck wordt geopend en onthoudt zijn herkomst', (
      tester,
    ) async {
      final container = await pumpShell(tester);
      await openFromWelcome(tester);

      // Eén S3-verbinding: geen keuzedialoog, meteen de bladeraar.
      expect(find.byType(S3BrowserDialog), findsOneWidget);
      await startChain(
        tester,
        find.text('deck.md'),
        () => container.read(tabsProvider).current?.s3Origin != null,
        reason: 'het deck is niet geopend',
      );

      final tab = container.read(tabsProvider).current!;
      expect(tab.deckNotifier.currentState.deck!.title, 'Kwartaalcijfers');
      final origin = tab.s3Origin!;
      expect(origin.connectionId, 'bucket-1');
      expect(origin.remotePath, 'deck.md');
      expect(
        origin.etag,
        '"opgehaald"',
        reason: 'zonder de opgehaalde versie is er later niets te bewaken',
      );
    });

    testWidgets('een mislukte download meldt waaróm', (tester) async {
      final stuk = _FakeBucket(
        bucket: _bucket,
        objects: {'deck.md': bytes(validDeck)},
        downloadFailure: S3Exception(S3Error.auth, '403'),
      );
      final container = await pumpShell(tester, service: stuk);
      await openFromWelcome(tester);

      await startChain(
        tester,
        find.text('deck.md'),
        () => textShown('Downloaden mislukt:'),
        reason: 'een mislukte download bleef stil',
      );

      expect(find.textContaining('Aanmelden mislukt.'), findsOneWidget);
      expect(container.read(tabsProvider).current?.s3Origin, isNull);
    });

    testWidgets('de bladeraar sluiten opent niets', (tester) async {
      final container = await pumpShell(tester);
      await openFromWelcome(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();

      expect(find.byType(S3BrowserDialog), findsNothing);
      expect(container.read(tabsProvider).current?.s3Origin, isNull);
      expect(
        container.read(tabsProvider).current?.deckNotifier.currentState.isOpen,
        isFalse,
      );
    });
  });

  group('opslaan naar de bucket', () {
    /// Voert "Opslaan naar…" uit tot het opslaandialoog er staat.
    Future<void> openSaveDialog(WidgetTester tester) async {
      await tester.tap(appBarIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await startChain(
        tester,
        menuItemIcon(Icons.cloud_upload_outlined),
        () => find.text('Opslaan naar S3').evaluate().isNotEmpty,
        reason: 'het opslaanvenster kwam niet op',
      );
    }

    Future<void> confirmSave(WidgetTester tester, bool Function() until) async {
      expect(
        await settleAsync(
          tester,
          until,
          start: () => tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan')),
        ),
        isTrue,
        reason: 'het opslaan kwam niet af',
      );
    }

    testWidgets('het voorstelpad komt uit de decktitel, ontdaan van tekens', (
      tester,
    ) async {
      await pumpShell(tester, deck: sampleDeck());
      await openSaveDialog(tester);

      // 'Rapport: Klant A/B' → geen dubbele punt, geen slash, spaties als _.
      expect(
        tester.widget<TextField>(dialogField()).controller!.text,
        'Rapport_Klant_AB',
      );
    });

    testWidgets('opslaan als pakket schrijft één object op het gekozen pad', (
      tester,
    ) async {
      await pumpShell(tester, deck: sampleDeck());
      await openSaveDialog(tester);

      await tester.enterText(dialogField(), 'klanten/rapport');
      await tester.pumpAndSettle();
      await confirmSave(tester, () => fake.puts.isNotEmpty);

      expect(fake.puts, hasLength(1));
      expect(fake.puts.single.path, 'klanten/rapport.ocideck');
      expect(
        fake.puts.single.ifMatch,
        isNull,
        reason: 'een zelfgekozen pad hebben we nooit opgehaald',
      );
      expect(find.textContaining('/klanten/rapport.ocideck'), findsOneWidget);
    });

    testWidgets('losse bestanden zetten de .md vóór de afbeeldingen', (
      tester,
    ) async {
      await pumpShell(tester, deck: sampleDeck());
      await openSaveDialog(tester);

      await tester.tap(find.text('Als losse .md plus afbeeldingen'));
      await tester.pumpAndSettle();
      await confirmSave(tester, () => fake.puts.isNotEmpty);

      expect(fake.puts.first.path, 'Rapport_Klant_AB.md');
    });

    testWidgets('een leeg doelpad sluit het venster niet', (tester) async {
      await pumpShell(tester, deck: sampleDeck());
      await openSaveDialog(tester);

      await tester.enterText(dialogField(), '   ');
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan'));
      await tester.pumpAndSettle();

      expect(find.text('Opslaan naar S3'), findsOneWidget);
      expect(fake.puts, isEmpty);
    });

    testWidgets('annuleren schrijft niets', (tester) async {
      await pumpShell(tester, deck: sampleDeck());
      await openSaveDialog(tester);

      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();

      expect(fake.puts, isEmpty);
      expect(find.textContaining('Opgeslagen in S3:'), findsNothing);
    });

    testWidgets('een mislukte upload meldt waaróm', (tester) async {
      final stuk = _FakeBucket(
        bucket: _bucket,
        uploadFailure: S3Exception(S3Error.conditionalUnsupported, '501'),
      );
      await pumpShell(tester, deck: sampleDeck(), service: stuk);
      await openSaveDialog(tester);
      await confirmSave(tester, () => textShown('Opslaan mislukt:'));

      expect(
        find.textContaining('Dit endpoint kan niet voorwaardelijk schrijven'),
        findsOneWidget,
      );
    });
  });

  group('terug naar waar het vandaan kwam', () {
    /// Opent `deck.md` uit de bucket, zodat het tabblad een herkomst draagt.
    Future<ProviderContainer> openFromBucket(
      WidgetTester tester, {
      _FakeBucket? service,
    }) async {
      final container = await pumpShell(tester, service: service);
      await openFromWelcome(tester);
      await startChain(
        tester,
        find.text('deck.md'),
        () => container.read(tabsProvider).current?.s3Origin != null,
        reason: 'het deck is niet geopend',
      );
      return container;
    }

    testWidgets('de opslaanknop vraagt niets en bewaakt de opgehaalde versie', (
      tester,
    ) async {
      await openFromBucket(tester);

      await startChain(
        tester,
        appBarIcon(Icons.save_outlined),
        () => fake.puts.isNotEmpty,
        reason: 'er is niets opgeslagen',
      );

      expect(
        find.text('Opslaan naar S3'),
        findsNothing,
        reason: 'een deck dat ergens vandaan komt hoort niet opnieuw te vragen',
      );
      expect(fake.puts.first.path, 'deck.md');
      expect(
        fake.puts.first.ifMatch,
        '"opgehaald"',
        reason: 'zonder If-Match overschrijft de knop stil andermans werk',
      );
      expect(find.textContaining('Opgeslagen in S3: /deck.md'), findsOneWidget);
    });

    testWidgets('een botsing vraagt, en Overschrijven laat de bewaking los', (
      tester,
    ) async {
      final botsend = _FakeBucket(
        bucket: _bucket,
        objects: {'deck.md': bytes(validDeck)},
        conflictOn: 'deck.md',
      );
      await openFromBucket(tester, service: botsend);

      await startChain(
        tester,
        appBarIcon(Icons.save_outlined),
        () => textShown('Iemand anders heeft dit bestand gewijzigd'),
        reason: 'de botsing werd niet gemeld',
      );

      expect(
        await settleAsync(
          tester,
          () => botsend.puts.length > 1,
          start: () =>
              tester.tap(find.widgetWithText(TextButton, 'Overschrijven')),
        ),
        isTrue,
        reason: 'overschrijven leverde geen tweede poging op',
      );

      // De eerste twee pogingen zijn allebei het markdownbestand: de botsing
      // viel vóórdat er één asset was aangeraakt. Ging de `.md` niet eerst,
      // dan stond andermans afbeelding al overschreven op het moment dat de
      // shell meldde dat er niets was gebeurd.
      expect(botsend.puts.take(2).map((p) => p.path), ['deck.md', 'deck.md']);
      expect(botsend.puts.first.ifMatch, '"opgehaald"');
      expect(
        botsend.puts[1].ifMatch,
        isNull,
        reason: 'overschrijven betekent: zonder voorwaarde opnieuw',
      );
      expect(
        botsend.puts.skip(2).map((p) => p.path),
        everyElement(isNot(endsWith('.md'))),
        reason: 'de assets horen pas ná het deck te gaan',
      );
      expect(find.textContaining('Opgeslagen in S3: /deck.md'), findsOneWidget);
    });

    testWidgets('een botsing afbreken laat de bucket met rust', (tester) async {
      final botsend = _FakeBucket(
        bucket: _bucket,
        objects: {'deck.md': bytes(validDeck)},
        conflictOn: 'deck.md',
      );
      await openFromBucket(tester, service: botsend);

      await startChain(
        tester,
        appBarIcon(Icons.save_outlined),
        () => textShown('Iemand anders heeft dit bestand gewijzigd'),
        reason: 'de botsing werd niet gemeld',
      );
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();

      expect(
        botsend.puts,
        hasLength(1),
        reason: 'na afbreken mag er geen tweede poging komen',
      );
      expect(find.textContaining('Opgeslagen in S3:'), findsNothing);
    });

    testWidgets('na een botsing onder een andere naam opslaan doet dat ook', (
      tester,
    ) async {
      final botsend = _FakeBucket(
        bucket: _bucket,
        objects: {'deck.md': bytes(validDeck)},
        conflictOn: 'deck.md',
      );
      await openFromBucket(tester, service: botsend);

      await startChain(
        tester,
        appBarIcon(Icons.save_outlined),
        () => textShown('Iemand anders heeft dit bestand gewijzigd'),
        reason: 'de botsing werd niet gemeld',
      );

      await startChain(
        tester,
        find.widgetWithText(FilledButton, 'Opslaan als'),
        () => dialogField().evaluate().isNotEmpty,
        reason: 'het opslaanvenster kwam niet terug',
      );
      // Het opslaandialoog begint bij het pad dat botste.
      expect(
        tester.widget<TextField>(dialogField()).controller!.text,
        'deck',
        reason: 'het venster hoort te beginnen bij het pad dat botste',
      );
      await tester.enterText(dialogField(), 'deck-van-mij');
      await tester.pumpAndSettle();

      expect(
        await settleAsync(
          tester,
          () => botsend.puts.length > 1,
          start: () =>
              tester.tap(find.widgetWithText(ElevatedButton, 'Opslaan')),
        ),
        isTrue,
        reason: 'de tweede poging kwam er niet',
      );

      // Eerste poging: het oude pad, bewaakt. Tweede: het nieuwe pad, en dan
      // valt er niets te bewaken — dat object hebben we nooit opgehaald.
      expect(botsend.puts.map((p) => p.path), [
        'deck.md',
        'deck-van-mij.ocideck',
      ]);
      expect(
        botsend.puts.last.ifMatch,
        isNull,
        reason: 'een ander pad hebben we nooit opgehaald',
      );
    });
  });

  testWidgets('zonder bucket zegt de app waar je er een instelt', (
    tester,
  ) async {
    // Het deck kwam van een bucket die daarna uit de instellingen verdween;
    // dan valt de opslaanknop terug op de keuze, en die is leeg.
    final container = await pumpShell(tester);
    await openFromWelcome(tester);
    await startChain(
      tester,
      find.text('deck.md'),
      () => container.read(tabsProvider).current?.s3Origin != null,
      reason: 'het deck is niet geopend',
    );

    await container.read(settingsProvider.notifier).removeConnection('bucket-1');
    await tester.pumpAndSettle();

    await startChain(
      tester,
      appBarIcon(Icons.save_outlined),
      () => textShown('Stel eerst een S3-bucket in'),
      reason: 'de app zweeg over de verdwenen bucket',
    );
    expect(fake.puts, isEmpty);
  });
}

const _bucket = S3Bucket(
  endpoint: 'https://s3.example',
  region: 'eu-central-1',
  bucket: 'presentaties',
  accessKeyId: 'AKIA-wegwerp',
);
