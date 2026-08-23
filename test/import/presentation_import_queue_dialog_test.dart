import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/import/bulk_import_runner.dart';
import 'package:ocideck/services/import/pipeline/import_runner.dart';
import 'package:ocideck/services/import/pipeline/import_task.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/web_asset_store.dart';
import 'package:ocideck/state/deck_provider.dart';
import 'package:ocideck/state/tabs_provider.dart';
import 'package:ocideck/widgets/dialogs/presentation_import_queue_dialog.dart';
import 'package:ocideck/widgets/shell/presentation_import_action.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;

import 'helpers/pptx_fixture.dart';

/// De wachtrijdialoog van de bulk-import (#772): volgorde, doelmap, draaien,
/// samenvatting.
///
/// Wat hier bewaakt wordt is het verschil tussen "de rij werkt" en "de rij doet
/// wat de gebruiker aanwees": de volgorde die hij zette, zonder de regel die
/// hij weghaalde, in de map die hij koos — en zonder dat het ene deck het
/// andere overschrijft.
///
/// De schrijver is een `FileService` die synchroon schrijft. Niet om het
/// schrijven te vervalsen (er komen echte bestanden op schijf te staan), maar
/// omdat echte asynchrone bestands-IO onder de klok van `flutter test` niet
/// afloopt zonder `runAsync`, en pompen binnen `runAsync` in deze repo een
/// bekende bron van wisselvalligheid is. Het volledige `FileService.saveDeck`
/// is elders gedekt; hier gaat het om de bedrading.
class _SyncFileService extends FileService {
  _SyncFileService(MarkdownService md)
    : super(md, ImageService(), () => const ThemeProfile());

  final List<String> written = [];

  @override
  Future<Deck> saveDeck(Deck deck, String filePath) async {
    File(
      filePath,
    ).writeAsStringSync('---\nmarp: true\n---\n\n# ${deck.title}\n');
    written.add(filePath);
    return deck;
  }
}

void main() {
  late Directory target;
  late _SyncFileService fileService;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    WebAssetStore.clear();
    // Widget-tests draaien onder een fake-async-klok en kunnen de echte
    // worker-isolate niet aansturen; draai de import daarom in-process (#875).
    debugImportTaskRunner = runImportTaskInline;
    SharedPreferences.setMockInitialValues({
      'presentationImportWarningDismissed': true,
    });
    target = Directory.systemTemp.createTempSync('ocideck_bulk_import');
    fileService = _SyncFileService(MarkdownService());
  });

  tearDown(() {
    debugImportTaskRunner = null;
    WebAssetStore.clear();
    if (target.existsSync()) target.deleteSync(recursive: true);
  });

  List<BulkImportItem> items(List<String> names) => [
    for (final name in names)
      BulkImportItem(
        bytes: pptxFixture(titel: name),
        name: '$name.pptx',
      ),
  ];

  /// Zet de dialoog op het scherm met een al gekozen doelmap ([withTarget] uit
  /// zet die naad uit, om de "nog niets gekozen"-toestand te toetsen).
  Future<BulkImportSummary?> pumpDialog(
    WidgetTester tester,
    List<BulkImportItem> queue, {
    bool withTarget = true,
  }) async {
    BulkImportSummary? summary;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                summary = await PresentationImportQueueDialog.show(
                  context,
                  files: queue,
                  fileService: fileService,
                  initialDirectory: withTarget ? target.path : null,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return summary;
  }

  /// De `.md`-bestanden in de doelmap, op naam gesorteerd.
  List<String> writtenNames() =>
      (target.listSync().map((e) => p.basename(e.path)).toList()..sort())
          .where((name) => name.endsWith('.md'))
          .toList();

  testWidgets('elk gekozen bestand landt als eigen presentatie in de doelmap', (
    tester,
  ) async {
    await pumpDialog(tester, items(['een', 'twee', 'drie']));
    expect(find.text(target.path), findsOneWidget);

    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(writtenNames(), ['drie.md', 'een.md', 'twee.md']);
    expect(find.textContaining('3 geslaagd'), findsOneWidget);
    expect(find.textContaining('0 mislukt'), findsOneWidget);
    // Waar het staat is het belangrijkste van de samenvatting: de decks openen
    // niet, dus zonder pad weet niemand waar zijn werk heen ging.
    expect(find.textContaining(target.path), findsWidgets);
  });

  testWidgets(
    'twee bronbestanden met dezelfde naam overschrijven elkaar niet',
    (tester) async {
      await pumpDialog(tester, [
        BulkImportItem(
          bytes: pptxFixture(titel: 'Plan'),
          name: 'plan.pptx',
        ),
        BulkImportItem(
          bytes: pptxFixture(titel: 'Plan'),
          name: 'plan.pptx',
        ),
      ]);
      await tester.tap(find.text('Importeren'));
      await tester.pumpAndSettle();

      expect(writtenNames(), ['Plan-2.md', 'Plan.md']);
    },
  );

  testWidgets('de rij draait in de volgorde die de gebruiker zet', (
    tester,
  ) async {
    await pumpDialog(tester, items(['een', 'twee']));
    // "een" een plek naar beneden: dan hoort "twee" als eerste te draaien.
    await tester.tap(find.byTooltip('Omlaag').first);
    await tester.pumpAndSettle();

    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(fileService.written.map(p.basename).toList(), ['twee.md', 'een.md']);
  });

  testWidgets('een regel uit de rij halen laat dat bestand ongemoeid', (
    tester,
  ) async {
    await pumpDialog(tester, items(['een', 'twee']));
    await tester.tap(find.byTooltip('Uit de rij halen').first);
    await tester.pumpAndSettle();
    expect(find.text('een.pptx'), findsNothing);

    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(writtenNames(), ['twee.md']);
  });

  testWidgets('zonder doelmap kan de import niet beginnen', (tester) async {
    await pumpDialog(tester, items(['een']), withTarget: false);

    expect(find.text('Nog geen doelmap gekozen'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Importeren'),
    );
    expect(
      start.onPressed,
      isNull,
      reason: 'zonder bestemming zou de rij nergens heen schrijven',
    );
  });

  testWidgets('een onleesbaar bestand stopt de rij niet en wordt gemeld', (
    tester,
  ) async {
    await pumpDialog(tester, [
      BulkImportItem(bytes: corruptFixture(), name: 'kapot.pptx'),
      BulkImportItem(
        bytes: pptxFixture(titel: 'goed'),
        name: 'goed.pptx',
      ),
    ]);
    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();

    expect(writtenNames(), ['goed.md']);
    expect(find.textContaining('1 geslaagd'), findsOneWidget);
    expect(find.textContaining('1 mislukt'), findsOneWidget);
  });

  testWidgets('sluiten geeft de uitkomst terug aan de aanroeper', (
    tester,
  ) async {
    late BulkImportSummary? summary;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                summary = await PresentationImportQueueDialog.show(
                  context,
                  files: items(['een']),
                  fileService: fileService,
                  initialDirectory: target.path,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();

    expect(summary, isNotNull);
    expect(summary!.succeeded, 1);
    expect(summary!.targetDirectory, target.path);
  });

  testWidgets('meer dan één gekozen bestand gaat naar de rij, niet naar tabs', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [fileServiceProvider.overrideWithValue(fileService)],
    );
    addTearDown(container.dispose);
    late BuildContext ctx;
    late WidgetRef reff;
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: ScaffoldMessenger(
            child: Scaffold(
              body: Consumer(
                builder: (context, ref, _) {
                  ctx = context;
                  reff = ref;
                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ),
    );

    final done = importPresentation(
      ctx,
      reff,
      filesOverride: [
        (bytes: pptxFixture(titel: 'een'), name: 'een.pptx'),
        (bytes: pptxFixture(titel: 'twee'), name: 'twee.pptx'),
      ],
      targetDirectoryOverride: target.path,
    );
    await tester.pumpAndSettle();
    expect(find.text('Presentaties importeren'), findsOneWidget);

    await tester.tap(find.text('Importeren'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sluiten'));
    await tester.pumpAndSettle();
    await done;

    expect(writtenNames(), ['een.md', 'twee.md']);
    expect(find.textContaining('geïmporteerd'), findsOneWidget);
    // De leesstap in runAsync: `TabsNotifier` start bij aanmaak een periodieke
    // timer, en een FakeTimer blijft na de test hangen.
    var opened = true;
    await tester.runAsync(() async {
      opened =
          container
              .read(tabsProvider)
              .current
              ?.deckNotifier
              .currentState
              .deck !=
          null;
    });
    expect(
      opened,
      isFalse,
      reason: 'tien bestanden openen als tien tabbladen is geen resultaat',
    );
  });
}
