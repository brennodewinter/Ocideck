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

/// Regressie voor #2318: de carrouselfooter was een vaste horizontale rij en
/// liep bij bredere fontmetrics buiten beeld (10 px op macOS, 29 px op een
/// Linux-gate met compacte tekstinstelling). De deduplicatieketentest moest
/// de tekstschaal naar 0,8 verkleinen om het overloop te verhullen — een
/// functionele test die productlayout bewijst. De footer is nu een Wrap die
/// ombreekt; deze toets dekt de grenswaarden.
void main() {
  final onePixelPng = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
    'hKmMIQAAAABJRU5ErkJggg==',
  );

  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_footer');
    File('${tempDir.path}/alpha.png').writeAsBytesSync(onePixelPng);
    File('${tempDir.path}/beta.png').writeAsBytesSync(onePixelPng);
  });

  tearDown(() {
    if (tempDir.existsSync()) tempDir.deleteSync(recursive: true);
  });

  Future<void> pumpPicker(
    WidgetTester tester, {
    required Size surface,
    required double textScale,
    bool manageOnly = false,
  }) async {
    await tester.binding.setSurfaceSize(surface);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.runAsync(() async {
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: MediaQuery(
              data: MediaQueryData(
                size: surface,
                textScaler: TextScaler.linear(textScale),
              ),
              child: ImageCarouselPicker(
                searchPaths: [tempDir.path],
                captionService: CaptionService(),
                descriptionService: DescriptionService(),
                manageOnly: manageOnly,
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
  }

  for (final (surface, scale) in [
    (const Size(1400, 900), 1.0),
    (const Size(1400, 900), 1.4), // bredere fontmetrics, zoals de Linux-gate
    (const Size(1400, 900), 1.8),
    (const Size(1100, 700), 1.4), // smallere dialoog én bredere tekst
    (const Size(950, 700), 1.0), // dialoog smaller dan zijn maximum
  ]) {
    testWidgets(
      'footer loopt niet over bij ${surface.width.toInt()}px, tekst ×$scale',
      (tester) async {
        await pumpPicker(tester, surface: surface, textScale: scale);
        expect(
          tester.takeException(),
          isNull,
          reason:
              'layoutfout bij ${surface.width}×${surface.height}, '
              'tekstschaal $scale',
        );
        // Primaire acties blijven in de boom — zichtbaar en bereikbaar.
        expect(find.text('Annuleren'), findsOneWidget);
        expect(find.text('Kiezen'), findsOneWidget);
      },
    );
  }

  testWidgets('beheermodus blijft bruikbaar bij bredere tekst', (tester) async {
    await pumpPicker(
      tester,
      surface: const Size(1400, 900),
      textScale: 1.4,
      manageOnly: true,
    );
    expect(tester.takeException(), isNull);
  });
}
