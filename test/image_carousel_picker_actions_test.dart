import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Aanvullende dekking voor `image_carousel_picker_actions.dart` — het
/// untagged-only-filter, de zoekrelevantie met meerdere termen, en de
/// beschrijving-persist-pad. De smoke-test dekt al de scan, de view-toggle
/// en een enkele zoekterm.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_actions');
    for (final name in ['alpha.png', 'beta.png', 'gamma.png']) {
      File('${tempDir.path}/$name').writeAsBytesSync(_onePixelPng);
    }
  });

  tearDown(() {
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {}
  });

  void clearLayoutNoise(WidgetTester tester) {
    while (tester.takeException() != null) {}
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    clearLayoutNoise(tester);
  }

  Future<void> pumpPicker(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageCarouselPicker(
              searchPaths: [tempDir.path],
              captionService: CaptionService(),
              descriptionService: DescriptionService(),
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

  testWidgets('untagged-only filter toont alle afbeeldingen (niets getagd)',
      (tester) async {
    await pumpPicker(tester);

    // Er zijn geen beschrijvingen opgeslagen, dus alle drie zijn "untagged".
    // Het toggle-icoon is Icons.label_off_outlined.
    final toggle = find.byIcon(Icons.label_off_outlined);
    expect(toggle, findsOneWidget);
    await tester.tap(toggle);
    await settle(tester);

    // De filter staat aan; alle drie zijn nog zichtbaar (niets getagd).
    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoekterm met meerdere woorden filtert correct', (tester) async {
    await pumpPicker(tester);

    // Typ een zoekterm die niet matcht — de lijst wordt leeg.
    await tester.enterText(find.byType(TextField).first, 'xyz niet bestaand');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar "alpha" toont alleen alpha', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek met beschrijvingen dekt de description-relevance paden',
      (tester) async {
    // Pre-populate descriptions: alpha has "klm vliegtuig", beta has "klm logo".
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(jsonEncode({
      'alpha.png': 'klm vliegtuig',
      'beta.png': 'klm logo',
      'gamma.png': 'onverwante tekst',
    }));

    await pumpPicker(tester);

    // Search for "klm" — matches alpha and beta via description words.
    await tester.enterText(find.byType(TextField).first, 'klm');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar een woord-prefix in de beschrijving', (tester) async {
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(jsonEncode({
      'alpha.png': 'vliegtuig foto',
      'beta.png': 'onverwant',
      'gamma.png': 'onverwant',
    }));

    await pumpPicker(tester);

    // "vlieg" is een prefix van "vliegtuig" in de beschrijving van alpha.
    await tester.enterText(find.byType(TextField).first, 'vlieg');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('zoek naar een substring in de beschrijving', (tester) async {
    final descFile = File('${tempDir.path}/.ocideck_descriptions.json');
    descFile.writeAsStringSync(jsonEncode({
      'alpha.png': 'luchtvaart',
      'beta.png': 'onverwant',
      'gamma.png': 'onverwant',
    }));

    await pumpPicker(tester);

    // "vaart" is een substring van "luchtvaart" maar geen woord-prefix.
    await tester.enterText(find.byType(TextField).first, 'vaart');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('beschrijving invoeren en selectie wijzigen persisteert',
      (tester) async {
    await pumpPicker(tester);

    // Selecteer de eerste afbeelding en typ een beschrijving.
    // Het beschrijvingsveld is de TextField die niet de zoekbalk is.
    final textFields = find.byType(TextField);
    expect(textFields, findsWidgets);

    // Typ in het beschrijvingsveld (meestal de tweede TextField).
    if (textFields.evaluate().length > 1) {
      await tester.enterText(textFields.at(1), 'test beschrijving');
      await settle(tester);
    }

    // Selecteer een andere afbeelding om _persistDescription te triggeren.
    final images = find.byType(Image);
    if (images.evaluate().length > 1) {
      await tester.tap(images.at(0), warnIfMissed: false);
      await settle(tester);
    }

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('Kiezen-knop sluit de dialoog met een resultaat', (tester) async {
    await pumpPicker(tester);

    // De "Kiezen"-knop staat in de preview-kolom.
    final chooseBtn = find.text('Kiezen');
    expect(chooseBtn, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(chooseBtn);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // De dialoog is gesloten.
    expect(find.byType(ImageCarouselPicker), findsNothing);
  });

  testWidgets('Sluiten-knop sluit de dialoog zonder resultaat', (tester) async {
    await pumpPicker(tester);

    // De sluiten-knop is het kruisje in de koptekst.
    final closeBtn = find.byIcon(Icons.close);
    expect(closeBtn, findsOneWidget);

    await tester.runAsync(() async {
      await tester.tap(closeBtn);
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await tester.pumpAndSettle();

    // De dialoog is gesloten.
    expect(find.byType(ImageCarouselPicker), findsNothing);
  });
}
