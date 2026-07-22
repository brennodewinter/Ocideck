import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// "Importeren via URL" uit het overloopmenu: het invoervenster
/// (`_UrlImportDialog` in `lib/widgets/shell/shell_actions.dart`) en de
/// afhandeling erna (`_importFromUrl`). Beide stonden op nul uitgevoerde
/// regels.
///
/// Het venster is hier het onderwerp, en met reden: de Ophalen-knop staat uit
/// zolang er geen ophaalbare URL staat. Dat is de enige plek waar een tikfout
/// of een `file:`-pad wordt tegengehouden vóór er iets gebeurt — daarna is het
/// een netwerkverzoek.
///
/// Wat hier NIET gebeurt: een geslaagde ophaalactie. Daarvoor zou een echte
/// server nodig zijn, en dat hoort niet in een widgettest; het ophaalpad zelf
/// staat in `file_service`- en `tabs_provider`-toetsen. Wat hier wél wordt
/// vastgelegd is dat een mislukte ophaalactie niet in stilte eindigt.
void main() {
  late Directory tmp;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_url');
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'storageConnections': jsonEncode([
        LocalConnection(
          id: 'lokaal',
          name: 'Mijn presentaties',
          path: tmp.path,
        ).toJson(),
      ]),
    });
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

  late ProviderContainer container;

  Future<void> pumpShell(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const ProviderScope(child: OciDeckApp()));
    await tester.pumpAndSettle();
    container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(
          Deck(
            title: 'Testrapport',
            slides: [
              Slide.create(SlideType.title).copyWith(title: 'Testrapport'),
            ],
          ),
        );
    await tester.pumpAndSettle();
  }

  Future<void> openUrlDialog(WidgetTester tester) async {
    await pumpShell(tester);
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.link));
    await tester.pumpAndSettle();
  }

  /// Staat de Ophalen-knop aan?
  bool fetchEnabled(WidgetTester tester) =>
      tester
          .widget<ElevatedButton>(
            find.widgetWithText(ElevatedButton, 'Ophalen'),
          )
          .onPressed !=
      null;

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      ),
      text,
    );
    await tester.pumpAndSettle();
  }

  testWidgets('het venster begint met een uitgeschakelde Ophalen-knop', (
    tester,
  ) async {
    await openUrlDialog(tester);

    expect(find.text('Importeren via URL'), findsOneWidget);
    expect(
      fetchEnabled(tester),
      isFalse,
      reason: 'zonder URL valt er niets op te halen',
    );
  });

  testWidgets('alleen een http(s)-adres met host zet de knop aan', (
    tester,
  ) async {
    await openUrlDialog(tester);

    // Losse tekst is geen adres.
    await type(tester, 'zomaar wat tekst');
    expect(fetchEnabled(tester), isFalse);

    // http(s) zonder host is evenmin ophaalbaar.
    await type(tester, 'https://');
    expect(fetchEnabled(tester), isFalse);

    // Wél een host, maar een schema dat we niet ophalen. Dit is het geval dat
    // de host-controle níet vangt en de schema-controle wél — zonder dit zou
    // die tweede controle onbewezen blijven.
    await type(tester, 'ftp://voorbeeld.test/deck.md');
    expect(fetchEnabled(tester), isFalse);

    // Idem voor een UNC-achtig `file:`-adres: dat zou de bestandsserver van de
    // gebruiker langs deze weg bereikbaar maken.
    await type(tester, 'file://bestandsserver/share/deck.md');
    expect(fetchEnabled(tester), isFalse);

    await type(tester, 'https://voorbeeld.test/deck.ocideck');
    expect(fetchEnabled(tester), isTrue);

    // En hoofdletters in het schema tellen ook mee.
    await type(tester, 'HTTP://voorbeeld.test/deck.md');
    expect(fetchEnabled(tester), isTrue);
  });

  testWidgets('annuleren haalt niets op', (tester) async {
    await openUrlDialog(tester);
    await type(tester, 'https://voorbeeld.test/deck.md');

    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(find.text('Importeren via URL'), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
    expect(container.read(tabsProvider).tabs, hasLength(1));
  });

  testWidgets('Enter in het veld doet hetzelfde als de knop', (tester) async {
    await openUrlDialog(tester);
    // Een niet-ophaalbaar adres mag ook via Enter niet doorgaan: het venster
    // blijft staan.
    await type(tester, 'zomaar wat tekst');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('Importeren via URL'), findsOneWidget);
  });

  testWidgets('een URL die niets oplevert eindigt in een melding, niet in '
      'stilte', (tester) async {
    await openUrlDialog(tester);
    // Poort 9 (discard) op de loopback: het verzoek komt nooit ergens aan, en
    // de SSRF-poort weigert een privé-adres sowieso. Zo faalt dit zonder ooit
    // het netwerk op te gaan.
    await type(tester, 'http://127.0.0.1:9/deck.md');
    expect(fetchEnabled(tester), isTrue);

    var reached = false;
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
      for (var i = 0; i < 150; i++) {
        if (find.byType(SnackBar).evaluate().isNotEmpty) {
          reached = true;
          break;
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();

    expect(reached, isTrue, reason: 'een mislukte import bleef stil');
    expect(
      find.textContaining('Kon van deze URL geen presentatie ophalen'),
      findsOneWidget,
    );
    expect(
      container.read(tabsProvider).tabs,
      hasLength(1),
      reason: 'een mislukte import mag geen leeg tabblad achterlaten',
    );
  });
}
