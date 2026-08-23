import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/file_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/presentation_search/presentation_source.dart';
import 'package:ocideck/widgets/dialogs/import_slides_dialog.dart';
import 'package:ocideck/widgets/dialogs/slide_diff_dialog.dart';
import 'package:ocideck/widgets/dialogs/slide_finder_dialog.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';
import 'package:path/path.dart' as p;

import 'support/pump_until.dart';

/// Een remote bron met vaste inhoud, om het samenvoegen in de finder te toetsen
/// zonder een echte git/WebDAV/S3-server.
class _FakeRemoteSource implements PresentationSource {
  _FakeRemoteSource(this.label, this.items);

  @override
  final String label;
  final List<ScannedPresentation> items;

  @override
  Future<List<ScannedPresentation>> scan() async => items;
}

FileService _fileService(String homeDir) => FileService(
  MarkdownService(),
  ImageService(),
  () => const ThemeProfile(),
  homeDirectory: () => homeDir,
);

Widget _host(void Function(BuildContext context) onPressed) {
  AppLocalizations.setActiveLanguageCode('nl');
  return MaterialApp(
    localizationsDelegates: const <LocalizationsDelegate<Object?>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
      FlutterQuillLocalizations.delegate,
    ],
    home: Scaffold(
      body: Builder(
        builder: (BuildContext context) => ElevatedButton(
          onPressed: () => onPressed(context),
          child: const Text('open'),
        ),
      ),
    ),
  );
}

/// Opent de dialoog, laat zijn schijfscan afmaken en typt [query] in het
/// zoekveld. [then] doet daarna nog één handeling.
///
/// Het wachten loopt via [pumpUntil], dat zelf afwisselend echte tijd (waarin
/// de dart:io-futures vooruitkomen) en een frame geeft. Daarom hoeft deze
/// helper niet meer als geheel binnen [WidgetTester.runAsync] te draaien — wat
/// hij eerder wél deed, met vaste wachttijden van 400 en 250 ms erin.
Future<void> _openAndSearch(
  WidgetTester tester, {
  required void Function(BuildContext context) show,
  required String query,
  Future<void> Function()? then,
}) async {
  await tester.binding.setSurfaceSize(const Size(1800, 1200));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(_host(show));
  await tester.tap(find.text('open'));
  await tester.pump(); // dialog appears (loading)
  // Wachten tot de schijfscan klaar ís — de dialoog haalt zijn
  // voortgangsindicator weg. Hier stond een vaste 400 ms plus vijf frames.
  await pumpUntil(
    tester,
    () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
    reason: 'de schijfscan van de zoekdialoog bleef laden',
  );
  await tester.enterText(find.byType(TextField).first, query);
  // Filteren op de zoekterm is een gewone setState, geen I/O: één frame
  // volstaat. De 250 ms die hier stond kocht niets — er viel niets af te
  // wachten.
  await tester.pump();
  if (then != null) await then();
  await tester.pump();
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('dedup_dialogs_');
    // Deck A: a "Netwerksegmentatie" slide (S).
    File('${dir.path}/deck_a.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Deck A\n---\n\n'
      '# Titel A\n\n'
      '---\n\n'
      '# Netwerksegmentatie\n\n- In scope\n',
    );
    // Deck B: a byte-identical copy of S (must de-duplicate away) plus a
    // same-title variant (a look-alike, so a "Verschillen" action appears).
    File('${dir.path}/deck_b.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Deck B\n---\n\n'
      '# Netwerksegmentatie\n\n- In scope\n\n'
      '---\n\n'
      '# Netwerksegmentatie\n\n- Out of scope\n',
    );
  });

  tearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });

  void showFinder(BuildContext context) => SlideFinderDialog.show(
    context,
    fileService: _fileService(dir.path),
    roots: [LibraryFolder(name: 'Test', path: dir.path)],
    onAdd: (Slide _) {},
  );

  testWidgets('Slide zoeken toont een identieke slide één keer met een teller', (
    tester,
  ) async {
    await _openAndSearch(tester, show: showFinder, query: 'Netwerksegmentatie');

    // The identical slide (deck A · slide 2 and deck B · slide 1) collapses to
    // one card carrying the "copies" badge; the summary reports one hidden dupe.
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.textContaining('verborgen'), findsOneWidget);
  });

  testWidgets('Slide zoeken markeert gelijkende slides met "Verschillen"', (
    tester,
  ) async {
    await _openAndSearch(tester, show: showFinder, query: 'Netwerksegmentatie');

    // S and the "Out of scope" variant share a title → both offer a compare.
    expect(find.text('Verschillen'), findsNWidgets(2));
  });

  testWidgets('"Verschillen" opent een vergelijking met het afwijkende veld', (
    tester,
  ) async {
    await _openAndSearch(
      tester,
      show: showFinder,
      query: 'Netwerksegmentatie',
      then: () async {
        await tester.tap(find.text('Verschillen').first);
        await pumpUntil(
          tester,
          () => find.byType(SlideDiffDialog).evaluate().isNotEmpty,
          reason: 'het vergelijkingsvenster kwam niet open',
        );
      },
    );

    expect(find.byType(SlideDiffDialog), findsOneWidget);
    // The bullets differ (In scope vs Out of scope), so the list names them.
    expect(find.text('Opsomming'), findsOneWidget);
    expect(find.textContaining('Out of scope'), findsWidgets);
  });

  testWidgets('Slide zoeken doorzoekt álle aangewezen bronmappen', (
    tester,
  ) async {
    // Een tweede bronmap, los van de map van het "huidige" deck, met een slide
    // die alleen dáár een unieke term draagt.
    final other = Directory.systemTemp.createTempSync('dedup_other_');
    addTearDown(() {
      if (other.existsSync()) other.deleteSync(recursive: true);
    });
    File('${other.path}/deck_c.md').writeAsStringSync(
      '---\nmarp: true\ntheme: ocideck\ntitle: Deck C\n---\n\n'
      '# Sleutelbeheer\n\n- Uniek in de andere bron\n',
    );

    await _openAndSearch(
      tester,
      show: (context) => SlideFinderDialog.show(
        context,
        fileService: _fileService(dir.path),
        roots: [
          LibraryFolder(name: 'Deck', path: dir.path),
          LibraryFolder(name: 'Andere bron', path: other.path),
        ],
        onAdd: (Slide _) {},
      ),
      query: 'Sleutelbeheer',
    );

    // De slide staat níet in de map van het huidige deck (dir) maar in de
    // tweede bronmap; hij hoort nu tóch tussen de resultaten te staan.
    expect(find.textContaining('unieke slide'), findsOneWidget);
    expect(find.textContaining('Deck C'), findsWidgets);
  });

  testWidgets('Slide zoeken toont ook treffers uit een remote bron', (
    tester,
  ) async {
    // Een remote deck met een unieke term, geleverd door een nagebootste bron
    // (net als een git/WebDAV/S3-verbinding). De term staat niet in de lokale
    // map, dus een treffer bewijst dat de remote bron is meegenomen.
    final remoteDeck = MarkdownService().parseDeck(
      '---\nmarp: true\ntheme: ocideck\ntitle: Remote Deck\n---\n\n'
      '# Sleutelbeheer op afstand\n\n- alleen in de remote bron\n',
    )!;
    final remote = _FakeRemoteSource('Git: test', [
      ScannedPresentation(
        path: 'git:team/presentaties/decks/r',
        fileName: 'r/deck.md',
        deck: remoteDeck,
      ),
    ]);

    await _openAndSearch(
      tester,
      show: (context) => SlideFinderDialog.show(
        context,
        fileService: _fileService(dir.path),
        roots: [LibraryFolder(name: 'Test', path: dir.path)],
        remoteSources: [remote],
        onAdd: (Slide _) {},
      ),
      query: 'Sleutelbeheer op afstand',
    );

    expect(find.textContaining('unieke slide'), findsOneWidget);
    expect(find.textContaining('Remote Deck'), findsWidgets);
  });

  testWidgets('Slides importeren ontdubbelt identieke slides over decks heen', (
    tester,
  ) async {
    await _openAndSearch(
      tester,
      show: (context) => ImportSlidesDialog.show(
        context,
        fileService: _fileService(dir.path),
        initialDirectory: dir.path,
      ),
      query: 'Netwerksegmentatie',
    );

    // The identical slide is shown once with a badge; the look-alike variant
    // offers a compare.
    expect(find.byIcon(Icons.copy_all_outlined), findsOneWidget);
    expect(find.text('Verschillen'), findsWidgets);
  });

  // Een relatief pad betekent iets anders in het bron-deck dan in de
  // presentatie waar de dia naartoe gaat. Beide dialogen maken het daarom
  // absoluut — maar deden dat alleen voor de afbeeldingsvelden, dus een
  // `![…](…)` in de vrije tekst wees na het overnemen naar de verkeerde map.
  group('een afbeelding in de vrije tekst reist mee met het juiste pad', () {
    late Directory tekstDir;

    setUp(() {
      tekstDir = Directory.systemTemp.createTempSync('dedup_tekst_');
      File('${tekstDir.path}/deck_tekst.md').writeAsStringSync(
        '---\nmarp: true\ntheme: ocideck\ntitle: Tekstdeck\n---\n\n'
        'Sleutelbeheer in tekst\n\n![de foto](images/foto.png)\n',
      );
    });

    tearDown(() {
      if (tekstDir.existsSync()) tekstDir.deleteSync(recursive: true);
    });

    testWidgets('Slide zoeken maakt het pad absoluut', (tester) async {
      Slide? toegevoegd;

      await _openAndSearch(
        tester,
        show: (context) => SlideFinderDialog.show(
          context,
          fileService: _fileService(tekstDir.path),
          roots: [LibraryFolder(name: 'Tekst', path: tekstDir.path)],
          onAdd: (Slide slide) => toegevoegd = slide,
        ),
        query: 'Sleutelbeheer in tekst',
        then: () async {
          await tester.tap(find.text('Toevoegen').first);
          // Wachten tot de dialoog weg ís, niet op een klok: dán pas heeft
          // `onAdd` gedraaid. Hier stonden vijf vaste pompjes van 100 ms.
          await pumpUntil(
            tester,
            () => find.text('Toevoegen').evaluate().isEmpty,
            reason: 'de zoekdialoog sloot niet na Toevoegen',
          );
        },
      );

      expect(toegevoegd, isNotNull);
      expect(
        toegevoegd!.customMarkdown,
        // De dialoog maakt het pad absoluut met `p.join`, dus tussen de map en
        // `images/foto.png` staat de scheiding van het platform — op Windows
        // `\`, niet de letterlijke `/` (#926).
        contains('![de foto](${p.join(tekstDir.path, 'images/foto.png')})'),
      );
    });

    testWidgets('Slides importeren maakt het pad absoluut', (tester) async {
      List<Slide>? geimporteerd;

      await _openAndSearch(
        tester,
        show: (context) async {
          geimporteerd = await ImportSlidesDialog.show(
            context,
            fileService: _fileService(tekstDir.path),
            initialDirectory: tekstDir.path,
          );
        },
        query: 'Sleutelbeheer in tekst',
        then: () async {
          // De kaart aantikken selecteert de dia; daarna importeren.
          await tester.tap(find.byType(SlidePreviewWidget).first);
          // Selecteren is een gewone setState, geen I/O: één frame volstaat.
          await tester.pump();
          await tester.tap(find.textContaining('Importeren').last);
          await pumpUntil(
            tester,
            () => find.textContaining('Importeren').evaluate().isEmpty,
            reason: 'de importdialoog sloot niet na Importeren',
          );
        },
      );

      expect(geimporteerd, hasLength(1));
      expect(
        geimporteerd!.single.customMarkdown,
        // Zie hierboven: `p.join` gebruikt de platform-scheiding tussen de map
        // en `images/foto.png` (#926).
        contains('![de foto](${p.join(tekstDir.path, 'images/foto.png')})'),
      );
    });
  });
}
