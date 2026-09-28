import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:ocideck/services/caption_service.dart';
import 'package:ocideck/services/description_service.dart';
import 'package:ocideck/services/download_delivery.dart';
import 'package:ocideck/widgets/dialogs/image_carousel_picker.dart';

import 'support/pump_until.dart';

/// Dekking voor "Downloaden…" in de afbeeldingencarousel: een kopie van de
/// geselecteerde afbeelding op een plek naar keuze. Op desktop gaat die via
/// het systeem-bewaarvenster en `File.copy`, op web als browserdownload. De
/// twee kanten die onder `flutter test` niet bestaan — het bewaarvenster en
/// de browser zelf — zitten achter de naadjes `debugImageDownloadDestination`
/// en `debugDownloadSink`/`debugDeliversByDownload`.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tempDir;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tempDir = Directory.systemTemp.createTempSync('carousel_dl');
  });

  tearDown(() {
    debugImageDownloadDestination = null;
    debugDeliversByDownload = null;
    debugDownloadSink = null;
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

  Future<void> pumpPicker(WidgetTester tester) async {
    File('${tempDir.path}/foto.png').writeAsBytesSync(_onePixelPng);
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
                manageOnly: true,
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

  Future<void> tapDownload(WidgetTester tester) async {
    await tester.tap(find.text('Downloaden…'));
    await tester.pump();
  }

  testWidgets('de preview biedt Downloaden naast Kopiëren', (tester) async {
    await pumpPicker(tester);
    expect(find.text('Downloaden…'), findsOneWidget);
    expect(find.text('Kopiëren'), findsOneWidget);
  });

  testWidgets('desktop: de kopie landt op de gekozen bestemming', (
    tester,
  ) async {
    final target = '${tempDir.path}/uitvoer/kopie.png';
    debugImageDownloadDestination = ({fileName}) async {
      expect(fileName, 'foto.png');
      Directory('${tempDir.path}/uitvoer').createSync();
      return target;
    };
    await pumpPicker(tester);
    await tapDownload(tester);
    await pumpUntil(
      tester,
      () => File(target).existsSync(),
      reason: 'de kopie werd niet op de gekozen bestemming geschreven',
    );
    expect(File(target).readAsBytesSync(), _onePixelPng);
    // De bron blijft ongemoeid in het archief staan.
    expect(File('${tempDir.path}/foto.png').existsSync(), isTrue);
    await pumpUntil(
      tester,
      () => find
          .text('Afbeelding opgeslagen als kopie.png')
          .evaluate()
          .isNotEmpty,
      reason: 'de bevestigingssnackbar verscheen niet',
    );
  });

  testWidgets('desktop: annuleren schrijft niets en meldt niets', (
    tester,
  ) async {
    debugImageDownloadDestination = ({fileName}) async => null;
    await pumpPicker(tester);
    await tapDownload(tester);
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Afbeelding opgeslagen als kopie.png'), findsNothing);
    expect(find.text('Kon de afbeelding niet opslaan.'), findsNothing);
  });

  testWidgets('desktop: een schrijffout wordt gemeld', (tester) async {
    // Een bestemming onder een niet-bestaande map laat File.copy falen.
    debugImageDownloadDestination = ({fileName}) async =>
        '${tempDir.path}/bestaat-niet/kopie.png';
    await pumpPicker(tester);
    await tapDownload(tester);
    await pumpUntil(
      tester,
      () => find.text('Kon de afbeelding niet opslaan.').evaluate().isNotEmpty,
      reason: 'de foutsnackbar verscheen niet',
    );
  });

  testWidgets('web: de afbeelding wordt als browserdownload aangeboden', (
    tester,
  ) async {
    debugDeliversByDownload = true;
    String? deliveredName;
    List<int>? deliveredBytes;
    debugDownloadSink = (name, bytes, mime) {
      deliveredName = name;
      deliveredBytes = bytes;
      return true;
    };
    await pumpPicker(tester);
    await tapDownload(tester);
    await pumpUntil(
      tester,
      () => deliveredBytes != null,
      reason: 'er werd geen download aangeboden',
    );
    expect(deliveredName, 'foto.png');
    expect(deliveredBytes, _onePixelPng);
    await pumpUntil(
      tester,
      () => find
          .text('Opgeslagen als download in je map met downloads.')
          .evaluate()
          .isNotEmpty,
      reason: 'de download-bevestiging verscheen niet',
    );
  });

  testWidgets('web: een geweigerde download wordt gemeld', (tester) async {
    debugDeliversByDownload = true;
    debugDownloadSink = (name, bytes, mime) => false;
    await pumpPicker(tester);
    await tapDownload(tester);
    await pumpUntil(
      tester,
      () => find
          .text(
            'De browser heeft de download niet aangenomen. Sta downloads voor deze site toe en probeer het opnieuw.',
          )
          .evaluate()
          .isNotEmpty,
      reason: 'de foutsnackbar voor een geweigerde download verscheen niet',
    );
  });
}
