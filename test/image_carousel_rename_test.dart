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

/// Widget-test voor de hernoem-knop in de afbeeldingencarrousel: opent de
/// dialoog, typt een nieuwe naam, bevestigt, en controleert dat het bestand op
/// schijf de nieuwe naam draagt. Het blauwdruk is de dedup-widgettest.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_rename');
    // Een naam die om hernoemen vraagt: de ODP-stijl hex-naam.
    File('${tempDir.path}/10000001000003C0.png').writeAsBytesSync(_onePixelPng);
  });

  tearDown(() {
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // Opruimen van een tijdelijke map is nooit een testoordeel waard.
    }
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
            home: Scaffold(
              body: ImageCarouselPicker(
                searchPaths: [tempDir.path],
                captionService: CaptionService(),
                descriptionService: DescriptionService(),
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

  testWidgets('Hernoemen verplaatst het bestand naar de nieuwe naam', (
    tester,
  ) async {
    await pumpPicker(tester);

    // De "Hernoemen"-knop staat in de preview-kolom.
    final renameBtn = find.text('Hernoemen');
    expect(renameBtn, findsOneWidget);

    await tester.tap(renameBtn, warnIfMissed: false);
    await pumpUntil(
      tester,
      () => find.text('Naam wijzigen').evaluate().isNotEmpty,
      reason: 'de hernoem-dialoog verscheen niet',
    );
    clearLayoutNoise(tester);

    // De dialoog toont de oude stam vooringevuld; wis en typ de nieuwe naam.
    // Het veld zit in de AlertDialog — de carrousel zelf heeft ook
    // zoek/caption/beschrijving-velden, dus descendant-vinden is nodig.
    final nameField = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.byType(TextField),
    );
    expect(nameField, findsOneWidget);
    await tester.enterText(nameField, 'logo');
    await tester.pump();
    clearLayoutNoise(tester);

    // Bevestig met de "Hernoemen"-knop in de dialoog.
    final confirm = find.widgetWithText(ElevatedButton, 'Hernoemen');
    expect(confirm, findsOneWidget);
    await tester.tap(confirm, warnIfMissed: false);

    // De rename loopt op echte file-IO; wacht op de schijf-uitkomst.
    await pumpUntil(
      tester,
      () => File('${tempDir.path}/logo.png').existsSync(),
      reason: 'het bestand werd niet hernoemd op schijf (file-IO liep nog)',
    );
    clearLayoutNoise(tester);

    expect(File('${tempDir.path}/logo.png').existsSync(), isTrue);
    expect(File('${tempDir.path}/10000001000003C0.png').existsSync(), isFalse);
    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('Annuleren laat het bestand ongemoeid', (tester) async {
    await pumpPicker(tester);

    final renameBtn = find.text('Hernoemen');
    await tester.tap(renameBtn, warnIfMissed: false);
    await pumpUntil(
      tester,
      () => find.text('Naam wijzigen').evaluate().isNotEmpty,
      reason: 'de hernoem-dialoog verscheen niet',
    );
    clearLayoutNoise(tester);

    // Annuleer — het origineel staat nog op de hex-naam. Er staan twee
    // "Annuleren"-knoppen in beeld (footer + dialoog), dus vind degene in de
    // dialoog.
    final cancel = find.descendant(
      of: find.byType(AlertDialog),
      matching: find.widgetWithText(TextButton, 'Annuleren'),
    );
    expect(cancel, findsOneWidget);
    await tester.tap(cancel, warnIfMissed: false);
    await settle(tester);

    expect(File('${tempDir.path}/10000001000003C0.png').existsSync(), isTrue);
    expect(File('${tempDir.path}/logo.png').existsSync(), isFalse);
  });
}
