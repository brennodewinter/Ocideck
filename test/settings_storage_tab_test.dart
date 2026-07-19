import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Het samengetrokken opslagtabblad, en de navigatie eronder.
///
/// De aanleiding voor deze suite staat in de laatste test: de tabbladen werden
/// met een volgnummer aangewezen, en toen het git-tabblad ertussen schoof bleef
/// de zoekindex naar de oude nummers wijzen. Zoeken op "checklist" sprong
/// daardoor naar Git-repository. Zulke fouten geven geen crash en geen melding —
/// je landt gewoon op het verkeerde tabblad — dus ze horen door een test
/// gevonden te worden en niet door een gebruiker.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  // De sectiekop binnen een uitgeklapt paneel — het enige opschrift dat maar bij
  // één opslagwijze hoort. De hoofdletters komen van _sectionTitle.
  final webdavPanel = find.text('WebDAV-bron'.toUpperCase());
  final gitPanel = find.text('Git-repository'.toUpperCase());

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
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () =>
                    SettingsDialog.show(context, initialSection: section),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  /// Tikt een regel aan die onder de vouw kan liggen. Het venster is hoogstens
  /// 760 hoog en het opslagtabblad is langer dan dat, dus zonder eerst scrollen
  /// tikt de test op coördinaten buiten beeld.
  Future<void> tapRow(WidgetTester tester, String label) async {
    final finder = find.text(label);
    await tester.ensureVisible(finder);
    await tester.pumpAndSettle();
    await tester.tap(finder);
    await tester.pumpAndSettle();
  }

  /// Volgt een zoektreffer. `pumpAndSettle` kan hier niet: de sprong laat de
  /// sectiekop drie seconden oplichten, en op die lopende timer loopt settle
  /// stuk. Dus met de hand doorpompen — eerst het scrollen, dan de oplichttimer
  /// helemaal uit, zodat de test hem niet als leksel achterlaat. Wat daarna
  /// overblijft is precies wat we willen nagaan: het gekozen tabblad en het
  /// opengeklapte paneel. Alleen het oplichten is weg, en dat hoort zo.
  Future<void> followHit(WidgetTester tester, String label) async {
    await tester.tap(find.text(label).last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(seconds: 3));
  }

  testWidgets('opslag draagt de bibliotheken, de exportmap en de wijzen', (
    tester,
  ) async {
    await openSettings(tester);

    // Wat er stond toen het nog verspreid lag: bibliotheken en exportmap onder
    // "Algemeen", Nextcloud en git elk op een eigen tabblad. Nu op één plek.
    expect(find.text('Bibliotheken'.toUpperCase()), findsOneWidget);
    expect(find.text('Opslagwijzen'.toUpperCase()), findsOneWidget);
    expect(find.text('Deze computer'), findsOneWidget);
    expect(find.text('WebDAV'), findsOneWidget);
    expect(find.text('Git-repository'), findsOneWidget);
  });

  testWidgets('een opslagwijze klapt open en weer dicht', (tester) async {
    await openSettings(tester);

    // De sectiekop van het paneel, niet "Server-URL": dat veldopschrift staat
    // in het git-paneel net zo goed en zegt dus niets over wélk paneel openligt.
    expect(webdavPanel, findsNothing);

    await tapRow(tester, 'WebDAV');
    expect(webdavPanel, findsOneWidget);

    await tapRow(tester, 'WebDAV');
    expect(webdavPanel, findsNothing);
  });

  testWidgets('er staat er hooguit één open', (tester) async {
    await openSettings(tester);

    await tapRow(tester, 'WebDAV');
    expect(webdavPanel, findsOneWidget);

    // Git openen sluit WebDAV: twee panelen tegelijk maken de lijst
    // onleesbaar, dus dat mag niet kunnen.
    await tapRow(tester, 'Git-repository');
    expect(gitPanel, findsOneWidget);
    expect(webdavPanel, findsNothing);
  });

  testWidgets('"Deze computer" heeft niets uit te klappen', (tester) async {
    await openSettings(tester);

    // Die regel is een mededeling, geen knop: de schijf wordt bestuurd door de
    // bibliotheken erboven. Tikken mag, maar hoort niets te openen.
    await tapRow(tester, 'Deze computer');
    expect(webdavPanel, findsNothing);
    expect(gitPanel, findsNothing);
  });

  testWidgets('de statusregel beweegt mee met wat je intypt', (tester) async {
    await openSettings(tester);
    await tapRow(tester, 'WebDAV');

    expect(find.text('Niet ingesteld'), findsWidgets);

    // Een TextEditingController laat het venster met rust, dus zonder een
    // uitdrukkelijke koppeling blijft hier "Niet ingesteld" staan terwijl de
    // server er net boven is ingevuld. Dat is precies de regel waarop je afgaat
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

    expect(find.text('Ingesteld · cloud.voorbeeld.nl'), findsOneWidget);
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

  testWidgets('een treffer in een opslagwijze klapt die wijze open', (
    tester,
  ) async {
    await openSettings(tester, section: SettingsSection.general);

    // Zonder het uitklappen staat het anker niet in de boom en komt de sprong
    // stilletjes nergens op uit: je landt op Opslag en mag zelf gaan zoeken.
    await tester.enterText(find.byType(TextField).first, 'Verbinding testen');
    await tester.pumpAndSettle();
    await followHit(tester, 'Verbinding testen');

    expect(webdavPanel, findsOneWidget);
  });
}
