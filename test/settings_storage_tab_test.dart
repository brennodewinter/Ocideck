import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/state/settings_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het opslagtabblad: één lijst bestandsverbindingen, en de navigatie eronder.
///
/// De aanleiding voor deze suite staat in de voorlaatste test: de tabbladen
/// werden met een volgnummer aangewezen, en toen het git-tabblad ertussen schoof
/// bleef de zoekindex naar de oude nummers wijzen. Zoeken op "checklist" sprong
/// daardoor naar Git-repository. Zulke fouten geven geen crash en geen melding —
/// je landt gewoon op het verkeerde tabblad — dus ze horen door een test
/// gevonden te worden en niet door een gebruiker.
///
/// Daar is sinds de verbindingenlijst een tweede soort stille fout bij gekomen:
/// de volgorde van de lijst bepaalt wélke server de app gebruikt. Een lijst die
/// in de verkeerde volgorde terugkomt, schrijft je werk naar de verkeerde klant
/// zonder ergens te klagen.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // De sectiekop binnen een uitgeklapt paneel — het enige opschrift dat maar bij
  // één soort verbinding hoort. De hoofdletters komen van _sectionTitle.
  final webdavPanel = find.text('WebDAV-bron'.toUpperCase());
  final gitPanel = find.text('Git-repository'.toUpperCase());
  final s3Panel = find.text('S3-bucket'.toUpperCase());

  /// Zet verbindingen klaar in prefs, zoals ze na een eerdere sessie zouden
  /// staan.
  void seedConnections(List<Map<String, Object?>> connections) {
    SharedPreferences.setMockInitialValues({
      'storageConnections': jsonEncode(connections),
    });
  }

  Map<String, Object?> local(String id, String name, String path) => {
    'id': id,
    'name': name,
    'kind': 'local',
    'config': {'path': path},
  };

  Map<String, Object?> webdav(String id, String name, String host) => {
    'id': id,
    'name': name,
    'kind': 'webdav',
    'config': {'baseUrl': 'https://$host', 'username': 'brenno'},
  };

  Future<void> openSettings(
    WidgetTester tester, {
    SettingsSection section = SettingsSection.storage,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          home: Scaffold(
            body: Consumer(
              // Watcht de instellingen zodat de notifier al bestaat vóór de
              // dialoog opengaat. De dialoog kopieert de verbindingen één keer
              // in initState; laadt de provider pas daarna klaar, dan opent het
              // venster met een lege lijst en test deze suite niets.
              builder: (context, ref, _) {
                ref.watch(settingsProvider);
                return ElevatedButton(
                  onPressed: () =>
                      SettingsDialog.show(context, initialSection: section),
                  child: const Text('open'),
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Tikt iets aan dat onder de vouw kan liggen. Het venster is hoogstens 760
  /// hoog en het opslagtabblad is langer dan dat, dus zonder eerst scrollen tikt
  /// de test op coördinaten buiten beeld.
  Future<void> tapVisible(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Voegt een verbinding van de gekozen soort toe via het menu op de knop.
  Future<void> addConnection(WidgetTester tester, String kindLabel) async {
    await tapVisible(tester, find.text('Verbinding toevoegen'));
    await tapVisible(tester, find.text(kindLabel));
  }

  /// Volgt een zoektreffer. `pumpAndSettle` kan hier niet: de sprong laat de
  /// sectiekop drie seconden oplichten, en op die lopende timer loopt settle
  /// stuk. Dus met de hand doorpompen — eerst het scrollen, dan de oplichttimer
  /// helemaal uit, zodat de test hem niet als leksel achterlaat.
  Future<void> followHit(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('opslag draagt één lijst verbindingen plus de exportmap', (
    tester,
  ) async {
    await openSettings(tester);

    // Wat er stond toen het nog verspreid lag: een lijst "Bibliotheken" en
    // daaronder een aparte lijst "Opslagwijzen" met vaste regels. Nu één lijst.
    expect(find.text('Bestandsverbindingen'.toUpperCase()), findsOneWidget);
    expect(find.text('Bibliotheken'.toUpperCase()), findsNothing);
    expect(find.text('Opslagwijzen'.toUpperCase()), findsNothing);
    expect(find.text('Verbinding toevoegen'), findsOneWidget);
  });

  testWidgets('zonder verbindingen staat er een uitnodiging', (tester) async {
    await openSettings(tester);
    expect(
      find.text('Nog geen verbinding — voeg er hieronder een toe.'),
      findsOneWidget,
    );
  });

  testWidgets('de lijst houdt de opgeslagen volgorde aan', (tester) async {
    // De volgorde is geen cosmetica: de bovenste van een soort is de server
    // waar de app naartoe schrijft. Komt de lijst in de verkeerde volgorde
    // terug, dan landt je werk stilletjes bij de verkeerde klant.
    seedConnections([
      webdav('b', 'Klant B', 'b.voorbeeld.nl'),
      webdav('a', 'Klant A', 'a.voorbeeld.nl'),
      local('c', 'Privé', '/home/prive'),
    ]);
    await openSettings(tester);

    final namen = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .map((f) => f.initialValue)
        .where((v) => v != null && v.isNotEmpty)
        .toList();
    expect(namen, containsAllInOrder(['Klant B', 'Klant A', 'Privé']));
  });

  testWidgets('een WebDAV-verbinding toevoegen klapt hem meteen open', (
    tester,
  ) async {
    await openSettings(tester);
    expect(webdavPanel, findsNothing);

    // Dichtgeklapt toevoegen zou als een mislukking lezen: er is nog niets te
    // zien tot de gebruiker hem invult.
    await addConnection(tester, 'WebDAV-server');
    expect(webdavPanel, findsOneWidget);
  });

  testWidgets('er staat er hooguit één open', (tester) async {
    await openSettings(tester);

    await addConnection(tester, 'WebDAV-server');
    expect(webdavPanel, findsOneWidget);

    // Git openen sluit WebDAV: twee panelen tegelijk maken de lijst
    // onleesbaar, dus dat mag niet kunnen.
    await addConnection(tester, 'Git-repository');
    expect(gitPanel, findsOneWidget);
    expect(webdavPanel, findsNothing);
  });

  testWidgets('een S3-verbinding toevoegen klapt hem meteen open', (
    tester,
  ) async {
    await openSettings(tester);
    expect(s3Panel, findsNothing);

    await addConnection(tester, 'S3-bucket');
    expect(s3Panel, findsOneWidget);
    // De adresseringskeuze hoort meteen zichtbaar te zijn: bij een eigen MinIO
    // is dat de knop die het verschil maakt tussen werken en een 404.
    expect(find.text('Adressering'), findsOneWidget);
  });

  testWidgets('de statusregel van een S3-bron toont de bucketnaam', (
    tester,
  ) async {
    await openSettings(tester);
    await addConnection(tester, 'S3-bucket');

    expect(find.text('Niet ingesteld'), findsWidgets);

    // Niet de endpoint-host: twee buckets op hetzelfde endpoint is het
    // gangbare geval, dus de host onderscheidt de rijen juist niet.
    await tester.enterText(
      find.widgetWithText(TextField, 'Endpoint'),
      'https://s3.eu-central-1.amazonaws.com',
    );
    await tester.enterText(find.widgetWithText(TextField, 'Bucket'), 'decks');
    await tester.pumpAndSettle();

    expect(find.text('Niet ingesteld'), findsNothing);
    // Twee keer: in het invulveld zelf en in de statusregel van de rij. Anders
    // dan bij WebDAV, waar de statusregel de host uit de URL afleidt, is de
    // bucketnaam letterlijk wat je intypte.
    expect(find.text('decks'), findsNWidgets(2));
  });

  testWidgets('een lokale map heeft niets uit te klappen', (tester) async {
    seedConnections([local('a', 'Privé', '/home/prive')]);
    await openSettings(tester);

    // Een map is met het kiezen van de map al klaar; er hoort dus geen
    // uitklapknop bij te staan.
    expect(find.byTooltip('Instellingen tonen'), findsNothing);
    expect(find.text('prive'), findsOneWidget);
  });

  testWidgets('de statusregel beweegt mee met wat je intypt', (tester) async {
    await openSettings(tester);
    await addConnection(tester, 'WebDAV-server');

    expect(find.text('Niet ingesteld'), findsWidgets);

    // Een TextEditingController laat het venster met rust, dus zonder een
    // uitdrukkelijke koppeling blijft hier "Niet ingesteld" staan terwijl de
    // server er net onder is ingevuld. Dat is precies de regel waarop je afgaat
    // als de lijst weer dichtgeklapt is.
    await tester.enterText(
      find.widgetWithText(TextField, 'Server-URL'),
      'https://cloud.voorbeeld.nl',
    );
    await tester.enterText(
      find.widgetWithText(TextField, 'Gebruikersnaam'),
      'brenno',
    );
    await tester.pumpAndSettle();

    expect(find.text('cloud.voorbeeld.nl'), findsOneWidget);
  });

  testWidgets('een verbinding verwijderen haalt hem uit de lijst', (
    tester,
  ) async {
    seedConnections([
      webdav('a', 'Klant A', 'a.voorbeeld.nl'),
      local('b', 'Privé', '/home/prive'),
    ]);
    await openSettings(tester);
    // findsWidgets en niet findsOneWidget: de hosttekst staat zowel in de
    // statusregel als — onzichtbaar — als hint van het lege naamveld.
    expect(find.text('a.voorbeeld.nl'), findsWidgets);

    await tapVisible(tester, find.byTooltip('Verbinding verwijderen').first);
    expect(find.text('a.voorbeeld.nl'), findsNothing);
    expect(find.text('prive'), findsOneWidget);
  });

  testWidgets('een zoektreffer landt op het tabblad dat hij noemt', (
    tester,
  ) async {
    await openSettings(tester, section: SettingsSection.general);

    // Dit is de regressie. Met volgnummers sprong "sjabloon" naar
    // Git-repository, omdat de zoekindex onder het ingeschoven git-tabblad niet
    // was hernummerd.
    await tester.enterText(find.byType(TextField).first, 'Nieuw sjabloon');
    await tester.pumpAndSettle();
    await followHit(tester, 'Nieuw sjabloon');

    expect(find.text('Eigen checklists'.toUpperCase()), findsOneWidget);
  });

  testWidgets('een treffer in een soort klapt de bovenste ervan open', (
    tester,
  ) async {
    // De bovenste, want dat is ook de verbinding die de app als standaard
    // gebruikt — springen naar een andere zou over de verkeerde server gaan.
    seedConnections([
      webdav('a', 'Klant A', 'a.voorbeeld.nl'),
      webdav('b', 'Klant B', 'b.voorbeeld.nl'),
    ]);
    await openSettings(tester, section: SettingsSection.general);

    // Zonder het uitklappen staat het anker niet in de boom en komt de sprong
    // stilletjes nergens op uit: je landt op Opslag en mag zelf gaan zoeken.
    await tester.enterText(find.byType(TextField).first, 'Verbinding testen');
    await tester.pumpAndSettle();
    await followHit(tester, 'Verbinding testen');

    expect(webdavPanel, findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'Server-URL'),
      findsOneWidget,
      reason: 'precies één paneel open, dat van de bovenste verbinding',
    );
  });
}
