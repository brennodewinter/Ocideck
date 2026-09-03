import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/local_cve_status.dart';
import 'package:ocideck/state/local_cve_provider.dart';
import 'package:ocideck/widgets/dialogs/settings_dialog.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Een notifier die één vaste toestand toont, zodat elke tak van de sectie te
/// zien is zonder 500 MB binnen te halen. `cancel` en `delete` worden geteld:
/// dat zijn de twee knoppen die iets doen.
class _FrozenLocalCve extends LocalCveNotifier {
  _FrozenLocalCve(this._state);

  final LocalCveState _state;
  int afgebroken = 0;
  int verwijderd = 0;
  int opgehaald = 0;

  @override
  LocalCveState build() => _state;

  @override
  void cancel() => afgebroken++;

  @override
  Future<void> delete() async => verwijderd++;

  @override
  Future<void> download() async => opgehaald++;
}

/// De sectie "Lokale CVE-database" in het beveiligingstabblad
/// (`parts/settings_dialog_cve_local.dart`).
///
/// Het punt van die database is zwijgen: zolang je online opzoekt, verraadt
/// elke zoekopdracht wélk lek je onderzoekt. Daar staat een prijs tegenover —
/// ruim 500 MB en een kwartier — en die moet vóór de knop staan, niet in een
/// voetnoot erna. Dat is wat hier getoetst wordt: dat de sectie de prijs noemt,
/// het niet per ongeluk laat beginnen, en per fase en per mislukking iets zegt
/// waar de gebruiker wat aan heeft.
void main() {
  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({'secModuleEnabled': true});
  });

  late _FrozenLocalCve notifier;

  /// Begrensd pompen in plaats van `pumpAndSettle`.
  ///
  /// De voortgangsbalk is in twee van de vier fasen onbepaald, en die animeert
  /// eeuwig; `pumpAndSettle` wacht daar tot de testtimeout op. Dat is precies
  /// de bedoeling van die balk — hij hoort te blijven bewegen — dus de test
  /// past zich aan, niet de app.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> openSecurityTab(WidgetTester tester, LocalCveState state) async {
    notifier = _FrozenLocalCve(state);
    await tester.binding.setSurfaceSize(const Size(1500, 1100));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [localCveProvider.overrideWith(() => notifier)],
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => SettingsDialog.show(
                  context,
                  initialSection: SettingsSection.security,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await settle(tester);
    expect(
      find.text('LOKALE CVE-DATABASE'),
      findsOneWidget,
      reason: 'de sectie hoort op het beveiligingstabblad te staan',
    );
  }

  /// Het tabblad is lang; scrol naar de knop voordat je erop tikt.
  Future<void> tapIn(WidgetTester tester, Finder target) async {
    await tester.ensureVisible(target);
    await settle(tester);
    await tester.tap(target);
    await settle(tester);
  }

  const stats = LocalCveStats(
    release: 'cve_2026',
    builtOn: '2026-07-14',
    records: 271234,
    bytes: 314572800,
  );

  testWidgets('zonder database staat de prijs vóór de knop', (tester) async {
    await openSecurityTab(tester, const LocalCveState(loading: false));

    expect(
      find.textContaining('ruim 500 MB binnenhalen'),
      findsOneWidget,
      reason: 'de prijs hoort te staan voordat je op de knop drukt',
    );
    expect(
      find.widgetWithText(OutlinedButton, 'Database ophalen'),
      findsOneWidget,
    );
    // Er valt nog niets te verwijderen.
    expect(find.widgetWithText(TextButton, 'Verwijderen'), findsNothing);
  });

  testWidgets('ophalen begint pas na een bevestiging met het getal erbij', (
    tester,
  ) async {
    await openSecurityTab(tester, const LocalCveState(loading: false));

    await tapIn(
      tester,
      find.widgetWithText(OutlinedButton, 'Database ophalen'),
    );

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('tien tot dertig minuten'), findsWidgets);
    expect(notifier.opgehaald, 0, reason: 'nog niets begonnen');

    await tapIn(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(TextButton, 'Annuleren'),
      ),
    );
    expect(notifier.opgehaald, 0, reason: 'annuleren mag niets starten');

    await tapIn(
      tester,
      find.widgetWithText(OutlinedButton, 'Database ophalen'),
    );
    await tapIn(
      tester,
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.widgetWithText(ElevatedButton, 'Database ophalen'),
      ),
    );
    expect(notifier.opgehaald, 1);
  });

  testWidgets('met een database staan de cijfers er, en Bijwerken', (
    tester,
  ) async {
    await openSecurityTab(
      tester,
      const LocalCveState(loading: false, stats: stats),
    );

    expect(find.textContaining('271234'), findsOneWidget);
    expect(
      find.textContaining('300 MB'),
      findsOneWidget,
      reason: 'de omvang op schijf hoort zichtbaar te zijn',
    );
    expect(find.textContaining('cve_2026'), findsOneWidget);
    expect(find.textContaining('opzoeken gebeurt offline'), findsOneWidget);

    // Ligt er iets, dan heet de knop Bijwerken en verdwijnt de prijskader —
    // die waarschuwt voor een eerste keer die al gebeurd is.
    expect(find.widgetWithText(OutlinedButton, 'Bijwerken'), findsOneWidget);
    expect(
      find.widgetWithText(OutlinedButton, 'Database ophalen'),
      findsNothing,
    );

    await tapIn(tester, find.widgetWithText(TextButton, 'Verwijderen'));
    expect(notifier.verwijderd, 1);
  });

  group('tijdens de opbouw', () {
    Future<void> phase(WidgetTester tester, CveIngestProgress p) =>
        openSecurityTab(tester, LocalCveState(loading: false, progress: p));

    testWidgets('elke fase heeft zijn eigen zin', (tester) async {
      await phase(
        tester,
        const CveIngestProgress(phase: CveIngestPhase.discovering),
      );
      expect(find.text('De nieuwste uitgave opzoeken…'), findsOneWidget);
    });

    testWidgets('binnenhalen toont de megabytes en een echte breuk', (
      tester,
    ) async {
      await phase(
        tester,
        const CveIngestProgress(
          phase: CveIngestPhase.downloading,
          received: 100 * 1024 * 1024,
          total: 400 * 1024 * 1024,
        ),
      );

      expect(find.text('Binnenhalen… 100 / 400 MB'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        0.25,
      );
    });

    testWidgets('zonder bekende omvang geen valse nul procent', (tester) async {
      await phase(
        tester,
        const CveIngestProgress(phase: CveIngestPhase.downloading),
      );

      expect(find.text('Binnenhalen…'), findsOneWidget);
      expect(
        tester
            .widget<LinearProgressIndicator>(
              find.byType(LinearProgressIndicator),
            )
            .value,
        isNull,
        reason: 'een 0% die een kwartier blijft staan leest als vastgelopen',
      );
    });

    testWidgets('indexeren telt de records mee', (tester) async {
      await phase(
        tester,
        const CveIngestProgress(phase: CveIngestPhase.indexing, records: 4211),
      );
      expect(find.text('Indexeren… 4211'), findsOneWidget);
    });

    testWidgets('Afbreken geeft het door en de knoppen zijn weg', (
      tester,
    ) async {
      await phase(
        tester,
        const CveIngestProgress(phase: CveIngestPhase.extracting),
      );
      expect(find.text('Uitpakken…'), findsOneWidget);
      // Tijdens een opbouw hoort er geen tweede te kunnen beginnen.
      expect(
        find.widgetWithText(OutlinedButton, 'Database ophalen'),
        findsNothing,
      );

      await tapIn(tester, find.widgetWithText(TextButton, 'Afbreken'));
      expect(notifier.afgebroken, 1);
    });
  });

  group('een mislukking krijgt haar eigen zin', () {
    Future<void> failure(WidgetTester tester, CveIngestFailure f) =>
        openSecurityTab(tester, LocalCveState(loading: false, failure: f));

    testWidgets('afgebroken zegt dat er niets half achterbleef', (
      tester,
    ) async {
      await failure(tester, CveIngestFailure.cancelled);
      expect(
        find.text('Afgebroken. Er is niets half achtergebleven.'),
        findsOneWidget,
      );
    });

    testWidgets('een volle schijf noemt het benodigde getal', (tester) async {
      await failure(tester, CveIngestFailure.diskFull);
      expect(find.textContaining('1,5 GB'), findsWidgets);
    });

    testWidgets('een geweigerd archief zegt dat er niets is geïnstalleerd', (
      tester,
    ) async {
      await failure(tester, CveIngestFailure.invalidArchive);
      expect(find.textContaining('Er is niets geïnstalleerd'), findsOneWidget);
    });

    testWidgets('zonder toestemming wijst het naar de plek waar die staat', (
      tester,
    ) async {
      await failure(tester, CveIngestFailure.noConsent);
      expect(
        find.text(
          'Geef eerst toestemming voor uitgaand verkeer bij Privacy en '
          'classificatie.',
        ),
        findsOneWidget,
        reason: 'zeg waar de gebruiker het aan kan zetten',
      );
    });

    testWidgets('een netwerkfout zegt dat het halve werk is weggegooid', (
      tester,
    ) async {
      await failure(tester, CveIngestFailure.networkFailed);
      expect(
        find.textContaining('een half binnengehaalde lijst is weggegooid'),
        findsOneWidget,
      );
    });
  });

  testWidgets('tijdens de eerste blik op schijf draait er geen wieltje', (
    tester,
  ) async {
    // Een oneindige animatie laat elk scherm dat hem bevat nooit meer tot rust
    // komen — en die blik is een stat-call van milliseconden.
    await openSecurityTab(tester, const LocalCveState());

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(LinearProgressIndicator), findsNothing);
    expect(
      find.widgetWithText(OutlinedButton, 'Database ophalen'),
      findsNothing,
    );
  });
}
