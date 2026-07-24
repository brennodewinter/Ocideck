import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';

/// Een zwevend veldlabel mag niet door een kleurovergang lopen.
///
/// Dit is de regressie achter #811. Het thema zette `filled: true` met de
/// oppervlaktekleur, terwijl een zwevend label half boven de bovenrand van het
/// veld staat en half erin. De gap van een [OutlineInputBorder] onderbreekt
/// alleen de *lijn*, niet het vlak — dus liep er altijd een kleurovergang dwars
/// door de letters. In het lichte profiel viel dat niet op (#F4F7FC tegen
/// #FFFFFF), in het donkere las het als een afgesneden onderste letterhelft
/// (#0F172A tegen #1E293B).
///
/// De eerste toets meet dat op pixels en niet op een themavlag: wat de
/// gebruiker ziet is het vlak, niet het veld dat het zette. De tweede bewaakt
/// de prijs ervan — zonder vulling is de rand het enige dat het veld nog
/// markeert, en dan moet die rand dat ook kunnen dragen.
void main() {
  tearDown(() => AppTheme.isDark = false);

  testWidgets('een veld legt geen eigen vlak onder zijn zwevende label', (
    tester,
  ) async {
    final profile = AppAppearanceProfile.builtIns.firstWhere((p) => p.isDark);
    AppTheme.isDark = true;
    final theme = AppTheme.fromProfile(profile);
    final key = GlobalKey();

    var fillPixels = 0;
    var total = 0;

    // `runAsync`, want `toImage` is een echte overdracht van de GPU en die komt
    // in de nagebootste klok van een widget-toets nooit terug. Zelfde reden als
    // in `test/slide_text_style_test.dart`.
    await tester.runAsync(() async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: RepaintBoundary(
            key: key,
            child: Scaffold(
              body: Center(
                child: SizedBox(
                  width: 300,
                  // [InputDecorator] en niet [TextField]: dit is de widget die
                  // de vulling, de rand en het zwevende label tekent — precies
                  // wat hier gemeten wordt. Een echt tekstveld brengt daar een
                  // knipperende cursor bovenop, en dat is ruis in een meting
                  // over pixels.
                  child: InputDecorator(
                    decoration: const InputDecoration(labelText: 'Waarde'),
                    isEmpty: false,
                    child: const Text('120'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final boundary =
          key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1.0);
      final bytes = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!.buffer.asUint8List();
      final width = image.width;

      final field = tester.getRect(find.byType(InputDecorator));
      final fill = theme.colorScheme.surface;

      // Tel elke pixel binnen het veld die de oppervlaktekleur draagt. Dat is
      // de vulling die er niet hoort te zijn; de achtergrond eromheen is de
      // scaffold-kleur en de letters dragen de tekstkleur.
      for (var y = field.top.ceil() + 1; y < field.bottom.floor() - 1; y++) {
        for (var x = field.left.ceil() + 1; x < field.right.floor() - 1; x++) {
          final i = (y * width + x) * 4;
          if (i + 3 >= bytes.length) continue;
          total++;
          if (bytes[i] == (fill.r * 255).round() &&
              bytes[i + 1] == (fill.g * 255).round() &&
              bytes[i + 2] == (fill.b * 255).round()) {
            fillPixels++;
          }
        }
      }
    });

    expect(total, greaterThan(1000), reason: 'Het veld is niet gerenderd.');
    expect(
      fillPixels / total,
      lessThan(0.01),
      reason:
          'Het veld vult zichzelf met een kleur die van zijn omgeving '
          'verschilt ($fillPixels van $total pixels). Het zwevende label loopt '
          'dan dwars door die overgang heen (#811).',
    );
  });

  for (final profile in AppAppearanceProfile.builtIns) {
    test('de veldrand is zichtbaar in profiel ${profile.name}', () {
      AppTheme.isDark = profile.isDark;
      final theme = AppTheme.fromProfile(profile);
      final border = theme.inputDecorationTheme.enabledBorder;
      final line = (border! as OutlineInputBorder).borderSide.color;

      // Een veld staat óf op de schermachtergrond óf op een oppervlak (dialoog,
      // kaart). Zonder vulling neemt het die kleur over, dus de rand moet het
      // tegen allebei redden.
      for (final under in {
        'schermachtergrond': theme.scaffoldBackgroundColor,
        'oppervlak': theme.colorScheme.surface,
      }.entries) {
        final ratio = _contrast(line, under.value);
        expect(
          ratio,
          greaterThanOrEqualTo(3.0),
          reason:
              'De rand van een invoerveld haalt ${ratio.toStringAsFixed(2)}:1 '
              'tegen de ${under.key}. Zonder vulling is die rand het enige dat '
              'het veld nog markeert; WCAG 1.4.11 vraagt 3:1 voor de grens van '
              'een bedieningselement.',
        );
      }
    });
  }
}

double _contrast(Color a, Color b) {
  final l1 = _luminance(a), l2 = _luminance(b);
  return (math.max(l1, l2) + 0.05) / (math.min(l1, l2) + 0.05);
}

double _luminance(Color c) {
  double channel(double v) =>
      v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
}
