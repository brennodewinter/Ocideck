import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:ociserve_file_contract/ociserve_file_contract.dart';
import 'package:ocideck/models/ociserve_file_origin.dart';
import 'package:ocideck/widgets/dialogs/ociserve_file_browser.dart';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/models/storage_connection.dart';
import 'package:ocideck/services/file_service.dart';
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
    // ⋮ → "Importeren…" → bronkiezer → "Openen via URL…" (#2359).
    await tester.tap(menuItemIcon(Icons.file_upload_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Openen via URL…'));
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

  testWidgets(
    'OciServe opens through the validated bytes gate and preserves safe provenance',
    (tester) async {
      await pumpShell(tester);
      await tester.tap(appBarIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(find.text('OciServe-bestanden'));
      await tester.pumpAndSettle();
      expect(find.byType(OciServeFileBrowser), findsOneWidget);
      final bytes = Uint8List.fromList(
        utf8.encode('---\nmarp: true\n---\n# Organisatiebron\n'),
      );
      Navigator.of(tester.element(find.byType(OciServeFileBrowser))).pop(
        OciServeFileSelection(
          bytes,
          const CatalogEntry(
            id: '12345678-1234-4234-8234-123456789abc',
            name: 'Bron.md',
            directory: false,
          ),
          const OciServeFileOrigin(
            server: 'https://files.example',
            organizationId: 'org',
            fileId: '12345678-1234-4234-8234-123456789abc',
            name: 'Bron.md',
            etag: '"v1"',
          ),
        ),
      );
      await tester.pumpAndSettle();
      final origin = container.read(tabsProvider).current!.ociServeOrigin;
      expect(origin?.etag, '"v1"');
      expect(origin?.organizationId, 'org');
      expect(container.read(tabsProvider).current!.origin, isNull);
    },
  );

  testWidgets('sharing a local file explains the deliberate publication step', (
    tester,
  ) async {
    await pumpShell(tester);
    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delen via OciServe…'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Delen vereist een gepubliceerd OciServe-bestand.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'a malformed OciServe share never becomes a generic import or recent source',
    (tester) async {
      await openUrlDialog(tester);
      await type(
        tester,
        'https://files.example/api/v1/public/file-shares/open#canary-share-secret',
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining('OciServe kon het verzoek niet afronden.'),
        findsOneWidget,
      );
      expect(container.read(tabsProvider).current!.ociServeOrigin, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('direct media URL proposes transcription before downloading', (
    tester,
  ) async {
    await openUrlDialog(tester);
    final before = container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .state
        .deck;
    await type(tester, 'https://example.com/source.mp4?signature=private');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
    await tester.pumpAndSettle();
    expect(find.text('Audio of video transcriberen'), findsOneWidget);
    expect(find.text('Instellingen openen'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();
    expect(
      container.read(tabsProvider).current!.deckNotifier.state.deck,
      same(before),
    );
  });

  testWidgets(
    'deck link action retains duplicate slide references and rejection keeps the deck',
    (tester) async {
      await pumpShell(tester);
      final original = Deck(
        title: 'Source references',
        slides: [
          Slide.create(SlideType.title).copyWith(
            title: 'First',
            customMarkdown: '[one](https://youtu.be/M7lc1UVf-VE)',
          ),
          Slide.create(SlideType.title).copyWith(
            title: 'Second',
            customMarkdown:
                '[two](https://www.youtube.com/watch?v=M7lc1UVf-VE)',
          ),
        ],
      );
      container.read(tabsProvider).current!.deckNotifier.loadDeck(original);
      await tester.pumpAndSettle();
      final before = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .state
          .deck;
      await tester.tap(appBarIcon(Icons.more_vert));
      await tester.pumpAndSettle();
      await tester.tap(menuItemIcon(Icons.file_upload_outlined));
      await tester.pumpAndSettle();
      await tester.tap(find.text('YouTube-video transcriberen…'));
      await tester.pumpAndSettle();
      expect(find.text('Dia 1, 2 · M7lc1UVf-VE'), findsOneWidget);
      expect(find.byType(SimpleDialogOption), findsOneWidget);
      await tester.tap(find.text('Dia 1, 2 · M7lc1UVf-VE'));
      await tester.pumpAndSettle();
      expect(find.text('Deze video transcriberen?'), findsOneWidget);
      expect(
        find.text('https://www.youtube.com/watch?v=M7lc1UVf-VE'),
        findsOneWidget,
      );
      expect(find.text('Instellingen openen'), findsOneWidget);
      expect(find.byType(LinearProgressIndicator), findsNothing);
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();
      expect(
        container.read(tabsProvider).current!.deckNotifier.state.deck,
        same(before),
      );
      expect(container.read(tabsProvider).tabs, hasLength(1));
    },
  );

  testWidgets('het venster begint met een uitgeschakelde Ophalen-knop', (
    tester,
  ) async {
    await openUrlDialog(tester);

    expect(find.text('Openen via URL'), findsOneWidget);
    expect(
      fetchEnabled(tester),
      isFalse,
      reason: 'zonder URL valt er niets op te halen',
    );
  });

  testWidgets(
    'YouTube URL proposes transcription before deck fetch and rejection preserves the deck',
    (tester) async {
      await openUrlDialog(tester);
      final before = container
          .read(tabsProvider)
          .current!
          .deckNotifier
          .state
          .deck;
      await type(tester, 'https://youtu.be/M7lc1UVf-VE?list=discarded');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
      await tester.pumpAndSettle();
      expect(find.text('Deze video transcriberen?'), findsOneWidget);
      expect(
        find.text('https://www.youtube.com/watch?v=M7lc1UVf-VE'),
        findsOneWidget,
      );
      expect(find.text('Instellingen openen'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
      await tester.pumpAndSettle();
      expect(
        container.read(tabsProvider).current!.deckNotifier.state.deck,
        same(before),
      );
      expect(container.read(tabsProvider).tabs, hasLength(1));
    },
  );

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

    expect(find.text('Openen via URL'), findsNothing);
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
    expect(find.text('Openen via URL'), findsOneWidget);
  });

  testWidgets('een URL die niets oplevert eindigt in een melding, niet in '
      'stilte', (tester) async {
    await openUrlDialog(tester);
    // Poort 9 (discard) op de loopback: het verzoek komt nooit ergens aan, en
    // de SSRF-poort weigert een privé-adres sowieso. Zo faalt dit zonder ooit
    // het netwerk op te gaan.
    await type(tester, 'http://127.0.0.1:9/deck.md');
    expect(fetchEnabled(tester), isTrue);
    // Een eerdere, andere openpoging mag deze CORS/netwerkfout niet als een
    // vol mediabudget laten lezen.
    container.read(openFailureProvider.notifier).state =
        OpenFailure.memoryBudgetExceeded;

    var reached = false;
    await tester.runAsync(() async {
      await tester.tap(find.widgetWithText(ElevatedButton, 'Ophalen'));
      for (var i = 0; i < 400; i++) {
        if (find.byType(SnackBar).evaluate().isNotEmpty) {
          reached = true;
          break;
        }
        // Alleen de eerste stappen zetten de nep-klok vooruit (genoeg voor de
        // dialoogovergang); daarna pompen we frames zonder klok, zodat het
        // netwerkverzoek alle tijd krijgt zonder dat de melding erna door het
        // wachten zelf weer verdwijnt.
        await tester.pump(
          i < 100 ? const Duration(milliseconds: 16) : Duration.zero,
        );
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
    });
    await tester.pump();

    expect(reached, isTrue, reason: 'een mislukte import bleef stil');
    // Een loopback-adres is een SSRF-weigering, geen tikfout of CORS: sinds de
    // reden-splitsing toont de import dáár de specifieke melding over een
    // privé/LAN-adres, in plaats van de generieke netwerk-/CORS-zin.
    expect(find.textContaining('privé- of LAN-adres'), findsOneWidget);
    expect(find.textContaining('presentatiemedia is vol'), findsNothing);
    expect(
      container.read(tabsProvider).tabs,
      hasLength(1),
      reason: 'een mislukte import mag geen leeg tabblad achterlaten',
    );
  });
}
