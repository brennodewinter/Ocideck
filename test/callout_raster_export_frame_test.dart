import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:ocideck/models/deck.dart';
import 'package:ocideck/models/image_callout.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/privacy/privacy_projection.dart';
import 'package:ocideck/services/slide_rasterizer.dart';

/// Wat de ontvanger van een PDF, PPTX of ODP werkelijk in handen krijgt.
///
/// De rasterizer is de enige weg naar die drie. Hij laadt de dia-afbeeldingen
/// voor en vangt dan een frame; `CalloutOverlay` tekent niets zolang de
/// intrinsieke beeldmaat onbekend is. Ging die maat via een tweede frame, dan
/// vertrok het beeld zónder markeringen — zichtbaar in de app, weg in de
/// export, en niets dat erover klaagt.
///
/// Deze toets kijkt naar de pixels van het echte artefact, niet naar de
/// widgetboom.

Directory _project() {
  final dir = Directory.systemTemp.createTempSync('ocideck_rasterframe');
  Directory('${dir.path}/media').createSync();
  // Twee verschillende beelden: de rasterizer hergebruikt één diahost, dus de
  // tweede callout-dia loopt via didUpdateWidget in plaats van initState. Dat
  // is precies waar het misging.
  for (final (naam, grijs) in [('een', 200), ('twee', 170)]) {
    final image = img.Image(width: 400, height: 250);
    img.fill(image, color: img.ColorRgb8(grijs, grijs, grijs));
    File(
      '${dir.path}/media/$naam.png',
    ).writeAsBytesSync(Uint8List.fromList(img.encodePng(image)));
  }
  return dir;
}

Slide _calloutSlide(String anchor, String beeld) =>
    Slide.create(SlideType.bulletsImage).copyWith(
      anchor: anchor,
      title: 'Spelden',
      bullets: const ['Hier zit het (A)'],
      imagePath: 'media/$beeld.png',
      callouts: const [
        ImageCallout(
          reference: 'A',
          targets: [CalloutPoint(0.5, 0.5)],
          description: 'de meetkamer',
        ),
      ],
    );

Future<BuildContext> _hostContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) {
            captured = context;
            return const SizedBox.expand();
          },
        ),
      ),
    ),
  );
  await tester.pump();
  return captured;
}

Future<List<Uint8List>> _rasterize(WidgetTester tester, Deck deck) async {
  final context = await _hostContext(tester);
  final audience = PrivacyProjection.forAudience(deck);
  List<Uint8List>? result;
  Object? failure;
  await tester.runAsync(() async {
    unawaited(
      SlideRasterizer.rasterize(
        context: context,
        audience: audience,
        targetWidth: 640,
      ).then(
        (value) => result = value,
        onError: (Object error) => failure = error,
      ),
    );
    for (var i = 0; i < 900 && result == null && failure == null; i++) {
      await tester.pump(const Duration(milliseconds: 16));
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  });
  if (failure != null) fail('rasterize wierp: $failure');
  expect(result, isNotNull, reason: 'rasterize werd niet klaar binnen de lus');
  return result!;
}

/// Hoeveel pixels de accentkleur van de markering dragen. Het deck krijgt
/// daarvoor een accent dat nergens anders voorkomt (zuiver rood) tegen een
/// egaal grijs beeld: dan is elke rode pixel een markering en niets anders.
Future<int> _accentPixels(WidgetTester tester, Uint8List png) async {
  var count = 0;
  await tester.runAsync(() async {
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final data = await frame.image.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    );
    final bytes = data!.buffer.asUint8List();
    for (var i = 0; i < bytes.length; i += 4) {
      final r = bytes[i], g = bytes[i + 1], b = bytes[i + 2];
      if (r > 180 && g < 90 && b < 90) count++;
    }
    frame.image.dispose();
  });
  return count;
}

void main() {
  testWidgets('een gerasterde dia draagt haar markeringen', (tester) async {
    final project = _project();
    final deck = Deck(
      title: 'keuring',
      projectPath: project.path,
      themeProfile: const ThemeProfile(accentColor: '#FF0000'),
      slides: [
        Slide.create(SlideType.title).copyWith(title: 'Voorblad'),
        _calloutSlide('dia-2', 'een'),
        _calloutSlide('dia-3', 'twee'),
      ],
    );

    final pages = await _rasterize(tester, deck);
    expect(pages, hasLength(3));

    // Het voorblad heeft geen markering: dat is de nulmeting van de teller.
    final zonder = await _accentPixels(tester, pages[0]);
    final eerste = await _accentPixels(tester, pages[1]);
    final tweede = await _accentPixels(tester, pages[2]);

    expect(
      eerste - zonder,
      greaterThan(150),
      reason:
          'de eerste callout-dia hoort haar markering te dragen; '
          'voorblad=$zonder, dia2=$eerste',
    );
    expect(
      tweede - zonder,
      greaterThan(150),
      reason:
          'ook de tweede callout-dia hoort haar markering te dragen — die '
          'loopt via didUpdateWidget op een hergebruikte diahost; '
          'voorblad=$zonder, dia3=$tweede',
    );
  });
}
