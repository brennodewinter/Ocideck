import 'dart:convert';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/l10n/app_localizations.dart';
import 'package:ocideck/widgets/slides/image_crop_dialog.dart';
import 'package:path/path.dart' as p;

/// Het bijsnijdvenster: slepen kiest welk deel van de afbeelding op de dia
/// zichtbaar blijft.
///
/// De regel die hier telt is de sleeprichting en de schaal ervan. Slepen moet
/// de afbeelding mét de vinger meenemen — trek je hem naar rechts, dan komt
/// zijn linkerrand in beeld en schuift het brandpunt dus naar links — en het
/// moet 1-op-1 met de overloop meelopen. Loopt dat andersom of met de verkeerde
/// factor, dan voelt het venster kapot terwijl er geen fout wordt gemeld.
final _onePixelPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8z8BQDwAEhQGA'
  'hKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  late Directory tmp;
  late String foto;

  setUp(() {
    AppLocalizations.setActiveLanguageCode('nl');
    tmp = Directory.systemTemp.createTempSync('ocideck_crop');
    foto = p.join(tmp.path, 'foto.png');
    File(foto).writeAsBytesSync(_onePixelPng);
  });

  tearDown(() {
    // Windows houdt een net via de beeld-cache ingelezen bestand soms nog kort
    // vast (errno 32, "used by another process"); OS-temp wordt sowieso
    // opgeruimd en de test is dan al klaar. Op POSIX is dit een gewone delete.
    if (!tmp.existsSync()) return;
    try {
      tmp.deleteSync(recursive: true);
    } on FileSystemException {
      // opzettelijk genegeerd: zie hierboven
    }
  });

  /// Opent het venster en houdt vast wat het teruggaf.
  Future<List<ImageCropResult?>> open(
    WidgetTester tester, {
    String? imagePath,
    double frameAspect = 16 / 9,
    int imageSize = 0,
    double focalX = 0.5,
    double focalY = 0.5,
  }) async {
    final uitkomst = <ImageCropResult?>[];
    await tester.binding.setSurfaceSize(const Size(1000, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async => uitkomst.add(
                await showImageCropDialog(
                  context,
                  imagePath: imagePath ?? foto,
                  projectPath: tmp.path,
                  frameAspect: frameAspect,
                  imageSize: imageSize,
                  focalX: focalX,
                  focalY: focalY,
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Afbeelding aanpassen'), findsOneWidget);
    // Laat de échte gebeurtenislus even lopen. De voorvertoning leest dit
    // bestand asynchroon, en binnen de nep-async van `testWidgets` rondt die
    // leesbeurt nooit af — de test houdt de handle dus open zolang hij duurt.
    // Op POSIX merk je daar niets van (een geopend bestand mag je vervangen);
    // op Windows blokkeert diezelfde handle élke schrijfbeurt, en dan staat een
    // rotatietoets rood om iets wat de app niet mankeert. `runAsync` is de enige
    // manier om die leesbeurt af te laten ronden; daarna is de situatie gelijk
    // aan die van een gebruiker, die seconden later op Klaar drukt.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pumpAndSettle();
    return uitkomst;
  }

  Future<void> klaar(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(FilledButton, 'Klaar'));
    await tester.pumpAndSettle();
  }

  group('imageIsCroppable', () {
    test('een lokaal pad is bij te snijden', () {
      expect(imageIsCroppable('images/foto.png'), isTrue);
    });

    test('een lege verwijzing niet', () {
      expect(imageIsCroppable(''), isFalse);
    });

    test('een URL niet — bijsnijden mag geen ophaalactie worden', () {
      // Zou dit true zijn, dan haalde de editor het beeld door de SSRF-poort
      // op louter de wens om te kadreren.
      expect(imageIsCroppable('https://voorbeeld.nl/foto.png'), isFalse);
      expect(imageIsCroppable('http://voorbeeld.nl/foto.png'), isFalse);
    });
  });

  testWidgets('Klaar geeft het ongewijzigde kader terug als er niets sleept', (
    tester,
  ) async {
    final uitkomst = await open(tester, focalX: 0.25, focalY: 0.75);
    await klaar(tester);

    final r = uitkomst.single!;
    expect(r.focalX, 0.25);
    expect(r.focalY, 0.75);
  });

  testWidgets('Annuleren geeft niets terug', (tester) async {
    final uitkomst = await open(tester);
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    expect(uitkomst, [null]);
  });

  testWidgets('Herstel zet het brandpunt terug naar het midden', (
    tester,
  ) async {
    final uitkomst = await open(tester, focalX: 0.1, focalY: 0.9);

    await tester.tap(find.widgetWithText(TextButton, 'Herstel'));
    await tester.pumpAndSettle();
    await klaar(tester);

    expect(uitkomst.single!.focalX, 0.5);
    expect(uitkomst.single!.focalY, 0.5);
  });

  testWidgets('slepen neemt de afbeelding mee met de vinger', (tester) async {
    // Zoom 200%: de afbeelding is twee keer zo breed als het kader, dus de
    // overloop is precies één kaderbreedte en een sleep van een kwart daarvan
    // verschuift het brandpunt met 0,25.
    final uitkomst = await open(
      tester,
      imageSize: 200,
      focalX: 0.5,
      focalY: 0.5,
    );

    final kader = tester.getSize(find.byType(AspectRatio));
    await tester.drag(
      find.byType(AspectRatio),
      Offset(kader.width * 0.25, kader.height * 0.25),
    );
    await tester.pumpAndSettle();
    await klaar(tester);

    final r = uitkomst.single!;
    // Naar rechts trekken toont de linkerrand: het brandpunt schuift naar
    // links, niet mee naar rechts.
    expect(r.focalX, closeTo(0.25, 0.02));
    expect(r.focalY, closeTo(0.25, 0.02));
  });

  testWidgets('het brandpunt loopt niet voorbij de rand', (tester) async {
    final uitkomst = await open(
      tester,
      imageSize: 200,
      focalX: 0.5,
      focalY: 0.5,
    );

    final kader = tester.getSize(find.byType(AspectRatio));
    // Ver voorbij de overloop slepen: het moet op 0 blijven staan, niet
    // doorschieten naar een negatieve uitsnede.
    await tester.drag(
      find.byType(AspectRatio),
      Offset(-kader.width * 5, -kader.height * 5),
    );
    await tester.pumpAndSettle();
    await klaar(tester);

    expect(uitkomst.single!.focalX, 1.0);
    expect(uitkomst.single!.focalY, 1.0);
  });

  testWidgets('met zoom is er een schuif die de maat verandert', (
    tester,
  ) async {
    final uitkomst = await open(tester, imageSize: 200);

    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    await klaar(tester);

    expect(
      uitkomst.single!.imageSize,
      greaterThan(200),
      reason: 'de schuif hoort de zoom te veranderen',
    );
  });

  // #1856 — de schuif was alleen te bereiken met een pinch-gebaar (twee
  // vingers), niet met muis of toetsenbord. Nu staat hij altijd in beeld,
  // ook in vullende (cover) modus.
  testWidgets('op vullend formaat is de schuif wel bereikbaar (#1856)', (
    tester,
  ) async {
    await open(tester, imageSize: 0);
    expect(find.byType(Slider), findsOneWidget);
  });

  testWidgets('de schuif verlaat cover-modus en stelt zoom in (#1856)', (
    tester,
  ) async {
    final uitkomst = await open(tester, imageSize: 0);

    expect(find.byType(Slider), findsOneWidget);
    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    await klaar(tester);

    expect(
      uitkomst.single!.imageSize,
      greaterThan(0),
      reason: 'slepen op de schuif hoort cover te verlaten',
    );
  });

  testWidgets('Herstel zet de zoom terug naar de oorspronkelijke waarde', (
    tester,
  ) async {
    final uitkomst = await open(tester, imageSize: 200);

    await tester.drag(find.byType(Slider), const Offset(60, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Herstel'));
    await tester.pumpAndSettle();
    await klaar(tester);

    expect(
      uitkomst.single!.imageSize,
      200,
      reason:
          'Herstel hoort de zoom terug te zetten, niet alleen het brandpunt',
    );
  });

  // #1856 — de letterbox-balken waren zuiver zwart (rgb(0,0,0)) in elk thema.
  // De achtergrond hoort het thema-Oppervlak te volgen, niet hard te zwarten.
  testWidgets('de stage-achtergrond is niet zuiver zwart (#1856)', (
    tester,
  ) async {
    await open(tester, imageSize: 150);
    final box = tester.widget<ColoredBox>(find.byType(ColoredBox).first);
    expect(
      box.color,
      isNot(Colors.black),
      reason: 'de letterbox hoort de thema-achtergrond te volgen, niet zwart',
    );
  });

  // #1813 — boven 100% werd de zoom stil teruggeknepen: Align → SizedBox
  // binnen een StackFit.expand klemde het kind af tot het slot, zodat zoom 300
  // hetzelfde beeld gaf als zoom 100. OverflowBox laat het kind buiten de
  // oudergrenzen, en deze toets meet de échte afgelegde maat.
  testWidgets('zoom boven 100% legt een groter kind af dan 100% (#1813)', (
    tester,
  ) async {
    // Zoom 100: het kind vult precies het kader.
    await open(tester, imageSize: 100);
    final frameSize = tester.getSize(find.byType(AspectRatio));
    final imageAt100 = tester.getSize(
      find.descendant(
        of: find.byType(OverflowBox),
        matching: find.byType(Image),
      ),
    );
    expect(imageAt100.width, closeTo(frameSize.width, 1.0));
    expect(imageAt100.height, closeTo(frameSize.height, 1.0));
    await tester.tap(find.widgetWithText(TextButton, 'Annuleren'));
    await tester.pumpAndSettle();

    // Zoom 300: het kind hoort 3× zo groot te zijn, niet afgeknepen tot het
    // kader.
    await open(tester, imageSize: 300);
    final imageAt300 = tester.getSize(
      find.descendant(
        of: find.byType(OverflowBox),
        matching: find.byType(Image),
      ),
    );
    expect(imageAt300.width, closeTo(frameSize.width * 3, 1.0));
    expect(imageAt300.height, closeTo(frameSize.height * 3, 1.0));
  });

  testWidgets('een pad buiten de projectmap wordt niet getoond', (
    tester,
  ) async {
    // De insluiting geldt ook hier: een dia die naar buiten wijst, mag het
    // venster niet alsnog van schijf laten lezen. Dan een kapot-beeldteken.
    await open(tester, imagePath: '../../etc/passwd');

    expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('Escape sluit het venster zonder iets terug te geven', (
    tester,
  ) async {
    final uitkomst = await open(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    expect(find.text('Afbeelding aanpassen'), findsNothing);
    expect(uitkomst, [null]);
  });

  group('draaien', () {
    setUp(() {
      // Maak een asymmetrische 2x2 PNG zodat 90° rotatie meetbaar is.
      final original = img.Image(width: 2, height: 2);
      original.setPixelRgb(0, 0, 255, 0, 0);
      original.setPixelRgb(1, 0, 0, 0, 0);
      original.setPixelRgb(0, 1, 0, 0, 0);
      original.setPixelRgb(1, 1, 0, 0, 255);
      File(foto).writeAsBytesSync(img.encodePng(original));
    });

    testWidgets('Rechtsom draait de afbeelding 90° en schrijft terug', (
      tester,
    ) async {
      final origBytes = File(foto).readAsBytesSync();
      final uitkomst = await open(tester);

      expect(find.byIcon(Icons.rotate_right), findsOneWidget);
      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pumpAndSettle();
      await klaar(tester);

      expect(
        lastRotationWriteFailure,
        isNull,
        reason: 'de geroteerde bytes zijn niet weggeschreven',
      );

      // Het resultaat is teruggekomen.
      expect(uitkomst.single, isNotNull);
      // Het bestand op schijf moet zijn bijgewerkt met de geroteerde bytes.
      final newBytes = File(foto).readAsBytesSync();
      expect(newBytes, isNot(equals(origBytes)));
      // En de geroteerde afbeelding moet decodeerbaar zijn met dezelfde
      // afmetingen (2x2 blijft 2x2 bij 90°).
      final rotated = img.decodeImage(newBytes);
      expect(rotated, isNotNull);
      expect(rotated!.width, 2);
      expect(rotated.height, 2);
    });

    testWidgets('Herstel zet de rotatie terug naar het origineel', (
      tester,
    ) async {
      final origBytes = File(foto).readAsBytesSync();
      await open(tester);

      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pumpAndSettle();
      // Herstel zou de rotatie moeten terugdraaien.
      await tester.tap(find.widgetWithText(TextButton, 'Herstel'));
      await tester.pumpAndSettle();
      await klaar(tester);

      // Zonder rotatie wordt het bestand niet aangeraakt.
      final newBytes = File(foto).readAsBytesSync();
      expect(newBytes, equals(origBytes));
    });

    testWidgets('twee keer rechtsom draait 180°, niet twee keer 90°', (
      tester,
    ) async {
      // Een niet-vierkante 2x3 afbeelding: na 90° is ze 3x2, na 180° blijft
      // ze 2x3 maar met de pixels gespiegeld. Zo onderscheiden we 90° van 180°.
      final original = img.Image(width: 2, height: 3);
      original.setPixelRgb(0, 0, 255, 0, 0); // linksboven: rood
      original.setPixelRgb(1, 2, 0, 0, 255); // rechtsonder: blauw
      File(foto).writeAsBytesSync(img.encodePng(original));

      await open(tester);

      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.rotate_right));
      await tester.pumpAndSettle();
      await klaar(tester);

      // Eerst de reden, dan de pixels. Zonder deze regel meldt een mislukte
      // schrijfbeurt zich als "verwacht blauw, kreeg rood" — waar of niet,
      // dat vertelt niemand wat er misging, en op Windows was dat precies het
      // verschil tussen twee releases raden en het antwoord lezen.
      expect(
        lastRotationWriteFailure,
        isNull,
        reason: 'de geroteerde bytes zijn niet weggeschreven',
      );

      final rotated = img.decodeImage(File(foto).readAsBytesSync())!;
      // 180° houdt de afmetingen gelijk — 90° zou ze omwisselen.
      expect(rotated.width, 2);
      expect(rotated.height, 3);
      // 180° spiegelt linksboven ↔ rechtsonder: rood ↔ blauw.
      final tl = rotated.getPixel(0, 0);
      final br = rotated.getPixel(1, 2);
      expect([tl.r, tl.g, tl.b], [0, 0, 255]); // blauw
      expect([br.r, br.g, br.b], [255, 0, 0]); // rood
    });
  });
}
