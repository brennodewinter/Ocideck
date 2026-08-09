import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/slide.dart';
import 'package:ocideck/services/rich_text_layout.dart';
import 'package:ocideck/widgets/slides/slide_preview.dart';

/// Regression for #931: a free-markdown formula must stay above the logo band,
/// at the full presentation size and not only in the small editor preview.
///
/// The scaffold used to reserve the logo band as padding *inside* the column
/// that its `FittedBox` scales down as a whole. Tall content triggered that
/// scaling, the reserved band shrank with it, and the last block slid under the
/// fixed logo overlay. It only bit at large sizes because `Math.tex` does not
/// scale linearly with the font size (fraction rules and `\left(\right)`
/// delimiters snap to discrete sizes), so a formula that just fit in the small
/// preview crossed the line in the real presentation.
///
/// The check is geometric and render-scale independent: with tall content that
/// forces the scale-down, the formula's rendered bottom must not reach into the
/// logo band `[slideBottom - logoSafeReserve, slideBottom]`.
void main() {
  const profile = ThemeProfile(
    logoPath: 'logo.png',
    logoPosition: 'bottom-right',
    logoSize: 96,
  );

  // Genoeg regels om de kolom te laten overlopen, zodat de FittedBox echt moet
  // omlaagschalen — precies het geval dat de bug trof. De formule staat als
  // laatste blok, want dat is het blok dat het dichtst bij het logo eindigt.
  final tallBody =
      '${List.filled(30, 'Een regel met wat tekst zodat de dia overloopt.').join('\n\n')}'
      '\n\n\$\$\\lvert k \\rangle = \\tfrac{1}{\\sqrt{2}}\\left( a + b \\right)\$\$\n';

  // Het testasset 'logo.png' bestaat niet, dus het logo-overlay valt terug op
  // een placeholder die bij sommige maten een paar pixel overloopt. Dat is
  // cosmetisch en staat los van wat we meten (de placeholder zit in een aparte
  // tak van de Stack, niet in de inhoudskolom). Slik alléén die overflow-fouten.
  void drainOverflowExceptions(WidgetTester tester) {
    for (
      var ex = tester.takeException();
      ex != null;
      ex = tester.takeException()
    ) {
      if (!ex.toString().contains('overflowed')) {
        throw ex as Object; // een andere fout hoort de test wél te laten vallen
      }
    }
  }

  /// Hoeveel de formule ónder de logogrens uitkomt (positief = door het logo).
  Future<double> overlapAt(WidgetTester tester, double w) async {
    final slide = Slide.create(
      SlideType.freeMarkdown,
    ).copyWith(customMarkdown: tallBody, showLogo: true);
    // Sinds #1409 pagineert free-markdown; de formule staat als laatste blok
    // dus op de laatste pagina. De #931-regressie gaat over dat blok, dus
    // renderen we de pagina waarop het staat.
    final pages = richTextPageCountForSlide(
      slide: slide,
      profile: profile,
      splitWithImage: false,
    );
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: w,
              height: w / (16 / 9),
              child: SlidePreviewWidget(
                slide: slide,
                themeProfile: profile,
                richTextPage: pages - 1,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    drainOverflowExceptions(tester);
    final slideRect = tester.getRect(find.byType(SlidePreviewWidget));
    final reserve = logoSafeReserve(slideRect.width, profile);
    final logoTop = slideRect.bottom - reserve;
    final mathBottom = tester.getRect(find.byType(Math).last).bottom;
    return mathBottom - logoTop;
  }

  testWidgets('formula clears the logo at full presentation width', (
    tester,
  ) async {
    final overlap = await overlapAt(tester, 1280);
    expect(
      overlap,
      lessThanOrEqualTo(1.0),
      reason:
          'de formule loopt ${overlap.toStringAsFixed(1)}px door het logo op '
          'presentatiemaat (#931)',
    );
  });

  testWidgets('and stays clear at the small preview width too', (tester) async {
    final overlap = await overlapAt(tester, 320);
    expect(overlap, lessThanOrEqualTo(1.0), reason: 'preview: $overlap');
  });
}
