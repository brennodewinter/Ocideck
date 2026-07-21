import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/app.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/utils/zip_encryption.dart';
import 'package:ocideck/widgets/app_shell.dart';
import 'package:ocideck/widgets/dialogs/command_palette.dart';
import 'package:ocideck/widgets/dialogs/package_encrypt_dialog.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';

/// De twee uitvoerpaden die NIET door `ExportService` lopen: het `.ocideck`-
/// pakket en het auditdossier (`widgets/shell/shell_actions_export.dart`). Ze
/// schrijven de meest complete overdracht die de app kent — markdown plus élke
/// asset — en stonden op nul uitgevoerde regels.
///
/// Alles hier draait echt: de classificatiepoort, het wachtwoorddialoog, het
/// lezen van de bewijsbytes, de zip-bouw en het wegschrijven naar schijf. Het
/// enige dat onder `flutter test` niet bestaat is het systeem-bewaarvenster;
/// dat loopt via de `saveDestination`-naad van [FileService].
void main() {
  late Directory tmp;
  late List<String?> asked;
  String? destination;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    SharedPreferences.setMockInitialValues({
      // Voorbij de toestemmingspoort, en de informatieveiligheidsmodule aan —
      // anders staat het auditdossier niet in het opdrachtenpalet.
      'app_consent_accepted': true,
      'secModuleEnabled': true,
    });
    tmp = Directory.systemTemp.createTempSync('ocideck_shell_export');
    asked = [];
    destination = p.join(tmp.path, 'uitvoer.ocideck');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  FileService fakePickerService() => FileService(
    MarkdownService(),
    ImageService(),
    () => const ThemeProfile(),
    saveDestination:
        ({
          String? dialogTitle,
          String? fileName,
          String? initialDirectory,
        }) async {
          asked.add(fileName);
          return destination;
        },
  );

  Deck sampleDeck() => Deck(
    title: 'Testrapport',
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

  /// Laat het écht asynchrone werk vorderen en pompt ondertussen frames, tot
  /// [until] waar is. Geeft terug of dat binnen [timeout] gelukt is.
  ///
  /// `pumpAndSettle` volstaat hier niet: de bewijsbytes worden van schijf
  /// gelezen en het pakket wordt in een echte isolate gezipt, dus er is werk
  /// dat alleen in [WidgetTester.runAsync] vordert — en dáárbinnen levert
  /// alleen een handmatige pomp frames. De grens is een tijdsgrens, zodat een
  /// vastloper een falende test wordt en geen hangende suite.
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
          return;
        }
        await tester.pump(const Duration(milliseconds: 16));
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      reached = until();
    });
    await tester.pumpAndSettle();
    return reached;
  }

  /// Pompt de app, laadt [deck] en opent het opdrachtenpalet.
  Future<void> openPalette(WidgetTester tester, {Deck? deck}) async {
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ProviderScope(
        overrides: [fileServiceProvider.overrideWithValue(fakePickerService())],
        child: const OciDeckApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AppShell)),
    );
    container
        .read(tabsProvider)
        .current!
        .deckNotifier
        .loadDeck(deck ?? sampleDeck());
    await tester.pumpAndSettle();

    await tester.tap(appBarIcon(Icons.more_vert));
    await tester.pumpAndSettle();
    await tester.tap(menuItemIcon(Icons.keyboard_command_key));
    await tester.pumpAndSettle();
  }

  /// Filtert het palet op [query] en voert het commando met [label] uit; wacht
  /// daarna tot [until] waar is.
  ///
  /// De tik gebeurt BINNEN [WidgetTester.runAsync], en dat is geen
  /// smaakkwestie. De exportactie is één lange `async`-keten — dialoog,
  /// bestemming, zippen, wegschrijven — en die keten draait in de zone waarin
  /// hij is gestart. Vanuit de fake-async-zone komt de echte isolate die het
  /// pakket zipt in het eerste geval nog terug en daarna niet meer: groen op
  /// zijn plek in de lijst, rood zodra de volgorde wisselt. En de volgorde
  /// wisselt hier per run.
  Future<void> runCommand(
    WidgetTester tester,
    String query,
    String label, {
    required bool Function() until,
    required String reason,
  }) async {
    // Bewust binnen het palet gezocht: de shell heeft zelf ook een zoekveld
    // (dia's zoeken) en dat staat eerder in de boom.
    await tester.enterText(
      find.descendant(
        of: find.byType(CommandPalette),
        matching: find.byType(TextField),
      ),
      query,
    );
    await tester.pumpAndSettle();
    final command = find.descendant(
      of: find.byType(CommandPalette),
      matching: find.text(label),
    );
    expect(command, findsOneWidget, reason: 'commando "$label" ontbreekt');
    final ok = await settleAsync(
      tester,
      until,
      start: () => tester.tap(command),
    );
    expect(ok, isTrue, reason: reason);
  }

  bool encryptDialogShown() =>
      find.byType(PackageEncryptDialog).evaluate().isNotEmpty;

  /// Voert het pakket-exportcommando uit tot het wachtwoorddialoog er staat.
  Future<void> startPackageExport(WidgetTester tester) => runCommand(
    tester,
    'pakket export',
    'Pakket exporteren…',
    until: encryptDialogShown,
    reason: 'het wachtwoorddialoog kwam niet op',
  );

  /// Bevestigt de export en wacht tot [until] waar is.
  Future<void> confirmExport(
    WidgetTester tester,
    bool Function() until, {
    required String reason,
  }) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Exporteren'));
    await tester.pumpAndSettle();
    expect(await settleAsync(tester, until), isTrue, reason: reason);
  }

  testWidgets('de pakketexport schrijft een echt .ocideck en meldt waarheen', (
    tester,
  ) async {
    await openPalette(tester);
    await startPackageExport(tester);

    await confirmExport(
      tester,
      () => File(destination!).existsSync(),
      reason: 'er is geen pakket weggeschreven',
    );

    expect(
      asked.single,
      'Testrapport.ocideck',
      reason: 'de voorgestelde bestandsnaam komt uit de decktitel',
    );

    // Onversleuteld: de zip is te lezen en draagt de markdown van het deck.
    final bytes = File(destination!).readAsBytesSync();
    expect(isEncryptedZip(bytes), isFalse);
    final archive = ZipDecoder().decodeBytes(bytes);
    final md = archive.files.firstWhere((f) => f.name.endsWith('.md'));
    expect(
      String.fromCharCodes(md.content as List<int>),
      contains('Testrapport'),
    );

    expect(find.textContaining('Pakket geëxporteerd naar:'), findsOneWidget);
  });

  testWidgets('een wachtwoord uit het dialoog versleutelt het pakket', (
    tester,
  ) async {
    const password = 'Wachtwoord-Van-De-Test';
    await openPalette(tester);
    await startPackageExport(tester);

    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, password);
    await tester.pumpAndSettle();

    await confirmExport(
      tester,
      () => File(destination!).existsSync(),
      reason: 'er is geen versleuteld pakket weggeschreven',
    );

    final bytes = File(destination!).readAsBytesSync();
    expect(
      isEncryptedZip(bytes),
      isTrue,
      reason: 'het wachtwoord uit het dialoog moet het pakket versleutelen',
    );
    // En het is met dát wachtwoord ook echt te openen.
    final archive = ZipDecoder().decodeBytes(bytes, password: password);
    final md = archive.files.firstWhere((f) => f.name.endsWith('.md'));
    expect(
      String.fromCharCodes(md.content as List<int>),
      contains('Testrapport'),
    );
  });

  testWidgets('afbreken in het bewaarvenster schrijft niets', (tester) async {
    destination = null;
    await openPalette(tester);
    await startPackageExport(tester);

    await confirmExport(
      tester,
      () => asked.isNotEmpty,
      reason: 'er is niet eens naar een bestemming gevraagd',
    );

    expect(tmp.listSync(), isEmpty, reason: 'er mag niets geschreven zijn');
    expect(find.textContaining('Pakket geëxporteerd naar:'), findsNothing);
    expect(
      find.textContaining('Export mislukt:'),
      findsNothing,
      reason: 'afbreken is geen fout',
    );
  });

  testWidgets('een mislukte pakketexport toont een kopieerbare foutmelding', (
    tester,
  ) async {
    // Een bestemming in een map die niet bestaat: het wegschrijven klapt.
    destination = p.join(tmp.path, 'bestaat', 'niet', 'uitvoer.ocideck');
    await openPalette(tester);
    await startPackageExport(tester);

    await confirmExport(
      tester,
      () => find.textContaining('Export mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukte export bleef stil',
    );

    expect(find.textContaining('Export mislukt:'), findsOneWidget);
    // De melding is te kopiëren, zodat hij door te sturen is.
    expect(find.text('Kopiëren'), findsOneWidget);
  });

  testWidgets('de classificatiepoort houdt het pakket tegen', (tester) async {
    SharedPreferences.setMockInitialValues({
      'app_consent_accepted': true,
      'secModuleEnabled': true,
      // Beleid: exporteren mag alleen mét een TLP-niveau. Het testdeck heeft er
      // geen, dus het pakket hoort niet eens aan het wachtwoorddialoog toe te
      // komen. ARCHITECTURE.md noemt het pakket met name: geen enkel formaat
      // mag om de poort heen.
      'requireClassificationOnExport': true,
    });

    await openPalette(tester);
    await runCommand(
      tester,
      'pakket export',
      'Pakket exporteren…',
      until: () => find
          .textContaining('Export geblokkeerd door classificatiebeleid')
          .evaluate()
          .isNotEmpty,
      reason: 'de poort meldde niets',
    );

    expect(
      find.textContaining('Export geblokkeerd door classificatiebeleid'),
      findsOneWidget,
    );
    expect(asked, isEmpty, reason: 'er mag niet eens naar een pad gevraagd');
    expect(
      find.byType(PackageEncryptDialog),
      findsNothing,
      reason: 'het wachtwoorddialoog hoort niet te openen',
    );
  });

  testWidgets('het auditdossier eist eerst een verzegeld rapport', (
    tester,
  ) async {
    await openPalette(tester);
    await runCommand(
      tester,
      'auditdossier',
      'Auditdossier exporteren',
      until: () => find
          .text('Finaliseer en verzegel het rapport eerst.')
          .evaluate()
          .isNotEmpty,
      reason: 'de eis van een verzegeld rapport bleef stil',
    );

    expect(
      find.text('Finaliseer en verzegel het rapport eerst.'),
      findsOneWidget,
    );
    expect(asked, isEmpty);
    expect(find.byType(PackageEncryptDialog), findsNothing);
  });

  Deck sealedDeckWithEvidence() {
    File(
      p.join(tmp.path, 'bewijs.png'),
    ).writeAsBytesSync(const [0x89, 0x50, 0x4E, 0x47, 1, 2, 3, 4]);
    return Deck(
      title: 'Verzegeld',
      projectPath: tmp.path,
      finalized: true,
      sealHash: 'a' * 64,
      sealAlgo: 'sha256',
      sealAt: '2026-07-21T10:00:00Z',
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Verzegeld'),
        Slide.create(SlideType.image).copyWith(
          title: 'Bewijs',
          imagePath: 'bewijs.png',
          findingRole: FindingRole.evidence,
        ),
      ],
    );
  }

  testWidgets('een mislukt auditdossier meldt dat ook', (tester) async {
    destination = p.join(tmp.path, 'bestaat', 'niet', 'dossier.ocideck');

    await openPalette(tester, deck: sealedDeckWithEvidence());
    await runCommand(
      tester,
      'auditdossier',
      'Auditdossier exporteren',
      until: encryptDialogShown,
      reason: 'het wachtwoorddialoog kwam niet op',
    );

    await confirmExport(
      tester,
      () => find.textContaining('Export mislukt:').evaluate().isNotEmpty,
      reason: 'een mislukt dossier bleef stil',
    );

    expect(find.textContaining('Export mislukt:'), findsOneWidget);
    expect(find.text('Kopiëren'), findsOneWidget);
  });

  testWidgets('het auditdossier bundelt de index met de bewijs-hashes', (
    tester,
  ) async {
    await openPalette(tester, deck: sealedDeckWithEvidence());
    await runCommand(
      tester,
      'auditdossier',
      'Auditdossier exporteren',
      until: encryptDialogShown,
      reason: 'het wachtwoorddialoog kwam niet op',
    );

    await confirmExport(
      tester,
      () => File(destination!).existsSync(),
      reason: 'er is geen auditdossier weggeschreven',
    );

    expect(
      asked.single,
      'Verzegeld_auditdossier.ocideck',
      reason: 'het dossier krijgt een eigen, herkenbare naam',
    );

    final archive = ZipDecoder().decodeBytes(
      File(destination!).readAsBytesSync(),
    );
    final index = archive.files.firstWhere((f) => f.name == 'AUDIT_DOSSIER.md');
    final text = String.fromCharCodes(index.content as List<int>);
    expect(text, contains('Auditdossier'));
    // De hashtabel wordt uit de bewijsbytes van schijf opgebouwd; staat het
    // bestand er niet in, dan is de tabel leeg en is het dossier waardeloos
    // als bewijsketen.
    expect(text, contains('bewijs.png'));

    expect(
      find.textContaining('Auditdossier geëxporteerd naar:'),
      findsOneWidget,
    );
  });
}
