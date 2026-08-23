import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Smoke test for the image carousel picker — the file has no other coverage,
/// so this pins down that the dialog still scans, renders its grid and reacts
/// to the view toggle and search, before the file is split into part
/// extensions. The bar is "builds and behaves", not pixel layout.

// A valid 1×1 transparent PNG — `_loadImages` filters on extension only, but
// the thumbnail/preview widgets decode the bytes, so they must be real.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    // Pin de taal, zodat de tekstasserties op de Nederlandse bronstrings
    // kloppen ongeacht de omgeving.
    AppLocalizations.setActiveLanguageCode('nl');
    // The picker is a ConsumerStatefulWidget; its settings provider reads
    // SharedPreferences on build, which needs a mock store under flutter_test.
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_smoke');
    for (final name in ['alpha.png', 'beta.png', 'gamma.png']) {
      File('${tempDir.path}/$name').writeAsBytesSync(_onePixelPng);
    }
  });

  tearDown(() {
    // Windows houdt een net via de beeld-cache ingelezen bestand soms nog kort
    // vast (errno 32); OS-temp wordt sowieso opgeruimd, de test is dan al klaar.
    if (!tempDir.existsSync()) return;
    try {
      tempDir.deleteSync(recursive: true);
    } on FileSystemException {
      // opzettelijk genegeerd: zie hierboven
    }
  });

  // The scan and description load are real file I/O; runAsync lets the event
  // loop drain them, then a couple of pumps rebuild with the loaded images.
  // (The search field auto-focuses, so its blinking cursor rules out
  // pumpAndSettle.)
  //
  // The flutter_test font box-renders glyphs far wider than a real font, so the
  // dialog's fixed-width button/metadata rows overflow its fixed 1160px width
  // here even though they fit in the running app. Clear that cosmetic,
  // font-driven RenderFlex noise after pumping. The behavioural guard is not
  // the absence of exceptions but `expect(find.byType(ErrorWidget), ...)` in
  // each test: a builder that throws (e.g. a botched split) renders an
  // ErrorWidget, whereas an overflow does not — so real breakage still fails.
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

  Future<void> pumpPicker(
    WidgetTester tester, {
    bool manageOnly = false,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    // _loadImages wordt in initState gestart en loopt met echte bestand-I/O
    // over de map. Dat werk komt alleen vooruit in de echte async-zone, dus de
    // eerste frame gaat binnen runAsync — anders blijft de dialoog eeuwig op
    // zijn laadindicator staan.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: ImageCarouselPicker(
              searchPaths: [tempDir.path],
              captionService: CaptionService(),
              descriptionService: DescriptionService(),
              manageOnly: manageOnly,
            ),
          ),
        ),
      );
    });
    // Wachten tot de scan klaar ís: de dialoog haalt zijn laadindicator weg.
    // Hier stond 300 ms plus twee pumps — een gok op hoe traag de schijf is.
    await pumpUntil(
      tester,
      () => find.byType(CircularProgressIndicator).evaluate().isEmpty,
      reason: 'de mapscan van de afbeeldingkiezer bleef laden',
    );
    clearLayoutNoise(tester);
  }

  testWidgets('scans the directory and renders thumbnails', (tester) async {
    await pumpPicker(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
    // Three files were scanned; the grid built decodable thumbnails plus the
    // large preview, so several Image widgets are on screen.
    expect(find.byType(Image), findsWidgets);
  });

  testWidgets('toggles between grid and cover view', (tester) async {
    await pumpPicker(tester);

    final cover = find.byIcon(Icons.view_carousel_rounded);
    expect(cover, findsOneWidget);
    await tester.tap(cover);
    await settle(tester);

    final grid = find.byIcon(Icons.grid_view_rounded);
    expect(grid, findsOneWidget);
    await tester.tap(grid);
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('typing a search term keeps the dialog alive', (tester) async {
    await pumpPicker(tester);

    await tester.enterText(find.byType(TextField).first, 'alpha');
    await settle(tester);

    expect(find.byType(ImageCarouselPicker), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  // ── Beheermodus (#1108) ─────────────────────────────────────────────────

  testWidgets('kies-modus toont het kiezen én de titel', (tester) async {
    await pumpPicker(tester);

    expect(find.text('Afbeelding kiezen'), findsOneWidget);
    expect(find.text('Kiezen'), findsOneWidget);
    expect(find.text('Bladeren…'), findsOneWidget);
    // Onderhoud is er in beide modi:
    expect(find.text('Duplicaten opruimen'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });

  testWidgets('beheermodus verbergt het kiezen, houdt het onderhoud', (
    tester,
  ) async {
    await pumpPicker(tester, manageOnly: true);

    // De titel zegt "beheren", niet "kiezen".
    expect(find.text('Afbeeldingen beheren'), findsOneWidget);
    expect(find.text('Afbeelding kiezen'), findsNothing);

    // Geen kies-affordances: geen Kiezen-knop, geen Bladeren, wél een Sluiten.
    expect(find.text('Kiezen'), findsNothing);
    expect(find.text('Bladeren…'), findsNothing);
    expect(find.text('Sluiten'), findsOneWidget);

    // Het onderhoud blijft: duplicaten opruimen (verwijderen zit in de
    // previewkolom, per selectie).
    expect(find.text('Duplicaten opruimen'), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
