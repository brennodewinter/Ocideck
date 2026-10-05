import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:path/path.dart' as p;
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/services/image_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Dekking voor het toevoegen aan het afbeeldingenarchief (#2107): de
/// bestemmingskeuze (`imageArchiveDestination`) en de twee opnamepaden
/// (`adoptImageFileIntoArchive`, `adoptImageBytesIntoArchive`) zijn pure
/// file-IO en direct te bewijzen; de knoppen zijn widgetasserties. Het
/// klembord zelf (Pasteboard) en de systeemkiezer zijn plugin-kanalen die
/// onder `flutter test` niet bestaan — daar zit de naad
/// (`debugCarouselBrowsePick` speelt `pickImageDetailed` voor "Bladeren…").
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_add');
  });

  tearDown(() {
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Opruimen van een tijdelijke map is nooit een testoordeel waard.
    }
  });

  group('imageArchiveDestination', () {
    test('de eerste bestaande wortel wint', () async {
      final second = Directory('${tempDir.path}/lib2')..createSync();
      final dest = await imageArchiveDestination([tempDir.path, second.path]);
      expect(dest?.path, tempDir.path);
    });

    test('een afwezige wortel valt door naar de volgende', () async {
      final missing = '${tempDir.path}/weg';
      final second = Directory('${tempDir.path}/lib2')..createSync();
      final dest = await imageArchiveDestination([missing, second.path]);
      expect(dest?.path, second.path);
      // En de afwezige wortel is niet stiekem aangemaakt.
      expect(Directory(missing).existsSync(), isFalse);
    });

    test(
      'een images/-wortel onder een bestaande ouder wordt aangemaakt',
      () async {
        final project = Directory('${tempDir.path}/deck')..createSync();
        final dest = await imageArchiveDestination(['${project.path}/images']);
        expect(dest?.path, p.join(project.path, 'images'));
        expect(Directory('${project.path}/images').existsSync(), isTrue);
      },
    );

    test('null als geen enkele wortel bereikbaar is', () async {
      final dest = await imageArchiveDestination([
        '${tempDir.path}/weg1',
        '${tempDir.path}/weg2',
      ]);
      expect(dest, isNull);
    });
  });

  group('adoptImageFileIntoArchive', () {
    test('kopieert een extern bestand het archief in', () async {
      final outside = Directory('${tempDir.path}/buiten')..createSync();
      final src = File('${outside.path}/foto.png')
        ..writeAsBytesSync(_onePixelPng);
      final archive = Directory('${tempDir.path}/archief')..createSync();

      final added = await adoptImageFileIntoArchive(
        src,
        dest: archive,
        archiveRoots: [archive.path],
      );

      expect(added, p.join(archive.path, 'foto.png'));
      expect(File('${archive.path}/foto.png').existsSync(), isTrue);
    });

    test('een bron binnen een wortel wordt niet gekopieerd', () async {
      final archive = Directory('${tempDir.path}/archief')..createSync();
      final src = File('${archive.path}/al_daar.png')
        ..writeAsBytesSync(_onePixelPng);

      final added = await adoptImageFileIntoArchive(
        src,
        dest: archive,
        archiveRoots: [archive.path],
      );

      expect(added, src.path);
      expect(archive.listSync().whereType<File>().length, 1);
    });

    test(
      'een naambotsing met andere inhoud wijkt uit naar een vrije naam',
      () async {
        final archive = Directory('${tempDir.path}/archief')..createSync();
        File('${archive.path}/foto.png').writeAsBytesSync([1, 2, 3]);
        final outside = Directory('${tempDir.path}/buiten')..createSync();
        final src = File('${outside.path}/foto.png')
          ..writeAsBytesSync(_onePixelPng);

        final added = await adoptImageFileIntoArchive(
          src,
          dest: archive,
          archiveRoots: [archive.path],
        );

        expect(added, p.join(archive.path, 'foto_2.png'));
        expect(File('${archive.path}/foto.png').readAsBytesSync(), [1, 2, 3]);
      },
    );

    test('identieke inhoud hergebruikt het bestaande bestand', () async {
      final archive = Directory('${tempDir.path}/archief')..createSync();
      File('${archive.path}/foto.png').writeAsBytesSync(_onePixelPng);
      final outside = Directory('${tempDir.path}/buiten')..createSync();
      final src = File('${outside.path}/foto.png')
        ..writeAsBytesSync(_onePixelPng);

      final added = await adoptImageFileIntoArchive(
        src,
        dest: archive,
        archiveRoots: [archive.path],
      );

      expect(added, p.join(archive.path, 'foto.png'));
      expect(archive.listSync().whereType<File>().length, 1);
    });
  });

  group('adoptImageBytesIntoArchive', () {
    test('schrijft klembordbytes als bestand in de doelmap', () async {
      final archive = Directory('${tempDir.path}/archief')..createSync();

      final added = await adoptImageBytesIntoArchive(
        _onePixelPng,
        dest: archive,
        filename: 'pasted_test.png',
      );

      expect(added, p.join(archive.path, 'pasted_test.png'));
      expect(
        File('${archive.path}/pasted_test.png').readAsBytesSync(),
        _onePixelPng,
      );
    });

    test('dezelfde bytes opnieuw plakken maakt geen kopie', () async {
      final archive = Directory('${tempDir.path}/archief')..createSync();

      final first = await adoptImageBytesIntoArchive(
        _onePixelPng,
        dest: archive,
        filename: 'pasted_test.png',
      );
      final second = await adoptImageBytesIntoArchive(
        _onePixelPng,
        dest: archive,
        filename: 'pasted_test.png',
      );

      expect(second, first);
      expect(archive.listSync().whereType<File>().length, 1);
    });
  });

  group('beheermodus-knop', () {
    void clearLayoutNoise(WidgetTester tester) {
      while (tester.takeException() != null) {}
    }

    Future<void> pumpPicker(WidgetTester tester, {required bool manage}) async {
      File('${tempDir.path}/alpha.png').writeAsBytesSync(_onePixelPng);
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Scaffold(
                body: ImageCarouselPicker(
                  searchPaths: [tempDir.path],
                  captionService: CaptionService(),
                  descriptionService: DescriptionService(),
                  manageOnly: manage,
                ),
              ),
            ),
          ),
        );
      });
      await pumpUntil(
        tester,
        () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
        reason: 'de mapscan van de afbeeldingkiezer bleef laden',
      );
      clearLayoutNoise(tester);
    }

    testWidgets('beheermodus toont "Afbeelding toevoegen…"', (tester) async {
      await pumpPicker(tester, manage: true);
      expect(find.text('Afbeelding toevoegen…'), findsOneWidget);
      expect(find.text('Bladeren…'), findsNothing);
    });

    testWidgets('kiesmodus toont "Bladeren…" en geen toevoegknop', (
      tester,
    ) async {
      await pumpPicker(tester, manage: false);
      expect(find.text('Bladeren…'), findsOneWidget);
      expect(find.text('Afbeelding toevoegen…'), findsNothing);
    });
  });

  group('kiesmodus "Bladeren…"', () {
    void clearLayoutNoise(WidgetTester tester) {
      while (tester.takeException() != null) {}
    }

    /// Regressie voor #2277: "Bladeren…" sloot de kiezer direct na het kiezen
    /// van een bestand — vlak vóór het moment dat je bijschrift en
    /// beschrijving wilt invullen. Nu blijft de kiezer open met het nieuwe
    /// beeld aangewezen; pas "Kiezen" geeft het resultaat terug.
    testWidgets('blijft open met het nieuwe bestand geselecteerd', (
      tester,
    ) async {
      final lib = Directory('${tempDir.path}/bib')..createSync();
      File('${lib.path}/bestaand.png').writeAsBytesSync(_onePixelPng);
      // Buiten elke zoekwortel: bewijst dat de kiezer het pad zélf in de
      // lijst zet — een herscan van de wortels zou dit bestand niet vinden.
      final outside = Directory('${tempDir.path}/buiten')..createSync();
      final picked = File('${outside.path}/nieuwe_foto.png')
        ..writeAsBytesSync(_onePixelPng);

      debugCarouselBrowsePick = () async =>
          ImageImportOutcome.success(picked.path);
      addTearDown(() => debugCarouselBrowsePick = null);

      ImagePickResult? result;
      var dialogOpen = false;
      await tester.binding.setSurfaceSize(const Size(1400, 900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.runAsync(() async {
        await tester.pumpWidget(
          ProviderScope(
            child: MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: ElevatedButton(
                      onPressed: () async {
                        dialogOpen = true;
                        result = await ImageCarouselPicker.show(
                          context,
                          searchPaths: [lib.path],
                          captionService: CaptionService(),
                          descriptionService: DescriptionService(),
                        );
                        dialogOpen = false;
                      },
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
      });
      await pumpUntil(
        tester,
        () =>
            find.text('Bladeren…').evaluate().isNotEmpty &&
            find.byType(CircularProgressIndicator).evaluate().isEmpty,
        reason: 'de afbeeldingkiezer opende niet of bleef laden',
      );
      clearLayoutNoise(tester);

      await tester.runAsync(() => tester.tap(find.text('Bladeren…')));
      await pumpUntil(
        tester,
        () => find.text('nieuwe_foto.png').evaluate().isNotEmpty,
        reason: 'het via "Bladeren…" gekozen bestand werd niet geselecteerd',
      );
      // De kern van de bug: de kiezer sloot direct na het kiezen. Nu moet
      // hij nog open staan, met het nieuwe beeld aangewezen in de preview.
      expect(dialogOpen, isTrue);
      expect(find.text('Kiezen'), findsOneWidget);
      clearLayoutNoise(tester);

      await tester.runAsync(() => tester.tap(find.text('Kiezen')));
      await pumpUntil(
        tester,
        () => !dialogOpen,
        reason: 'de kiezer gaf geen resultaat terug',
      );
      expect(result?.path, picked.path);
    });
  });
}
