import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Dekking voor het toevoegen aan het afbeeldingenarchief (#2107): de
/// bestemmingskeuze (`imageArchiveDestination`) en de twee opnamepaden
/// (`adoptImageFileIntoArchive`, `adoptImageBytesIntoArchive`) zijn pure
/// file-IO en direct te bewijzen; de knop in beheermodus is een
/// widgetassertie. Het klembord zelf (Pasteboard) en de bestandskiezer zijn
/// plugin-kanalen die onder `flutter test` niet bestaan — daar zit de naad.
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
        expect(dest?.path, '${project.path}/images');
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

      expect(added, '${archive.path}/foto.png');
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

        expect(added, '${archive.path}/foto_2.png');
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

      expect(added, '${archive.path}/foto.png');
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

      expect(added, '${archive.path}/pasted_test.png');
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
}
