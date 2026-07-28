import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/markdown_body_blocks.dart';

/// Bewaakt de ijking van [displayMathBlockHeight] (#947).
///
/// Een display-formule rendert op een vaste grootte (`refW * 0.032`, zoals
/// `_markdownMathBlock`), maar is zelden één regel hoog: breukstrepen, wortels,
/// grote operatoren met grenzen en gestapelde scripts maken hem twee à drie keer
/// zo hoog. De richText-paginering meet elk blok om te weten hoeveel er per
/// pagina past; onderschatte de meting de formule, dan zakte een hoge formule bij
/// presentatiemaat door de logo-/footerband.
///
/// Deze test rendert een batterij formules op ware grootte, meet hun werkelijke
/// hoogte, en eist dat de schatting daar bóven ligt (nooit onder) — de enige
/// harde eis, want een onderschatting raakt het logo terwijl een overschatting
/// hooguit iets eerder pagineert. De marge blijft begrensd zodat een latere
/// wijziging niet ongemerkt naar wilde overschatting doorschiet.
void main() {
  const w = 1280.0;
  const fontSize = w * 0.032;
  const verticalPadding = w * 0.012 * 2; // de padding rond _markdownMathBlock

  // Formules met oplopende verticale complexiteit, inclusief de twee uit de
  // proefpresentatie (kat-superpositie en toetsenbord-kans).
  const formulas = <String, String>{
    'plain': r'a = b + c',
    'superscript': r'E = mc^2',
    'sub-and-superscript': r'x_i^2 + y_j^3',
    'tfrac met wortel (kat)':
        r'\lvert \text{kat} \rangle = \tfrac{1}{\sqrt{2}}\left( \lvert \text{slaapt} \rangle + \lvert \text{wil eten} \rangle \right)',
    'breuk met superscript (toetsenbord)':
        r'P(\text{toetsenbord}) = 1 - \frac{1}{9^{\,\text{levens}}} \approx 1',
    'losse wortel': r'\sqrt{x + 1}',
    'wortel over breuk': r'\sqrt{\dfrac{a^2}{b}}',
    'display-breuk': r'y = \dfrac{a+b}{c+d}',
    'geneste breuk': r'\frac{1}{1 + \frac{1}{1 + x}}',
    'som met grenzen': r'\sum_{i=0}^{n} i^2',
    'integraal met grenzen': r'\int_0^\infty e^{-x}\,dx',
  };

  Future<double> measuredHeight(WidgetTester tester, String tex) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: w,
              child: Math.tex(
                tex,
                textStyle: const TextStyle(fontSize: fontSize),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    tester
        .takeException(); // negeer eventuele horizontale overflow van de formule
    return tester.getRect(find.byType(Math)).height + verticalPadding;
  }

  // Meet via het volledige parse→meet-pad dat de paginering echt gebruikt, zodat
  // de test ook de bedrading dekt (`_measureBlock` → [displayMathBlockHeight]) en
  // niet alleen de schatting op zichzelf.
  double paginationHeight(String tex) => measureMarkdownBlocksHeight(
    blocks: parseMarkdownBodyBlocks('\$\$$tex\$\$'),
    scale: 1,
    contentW: w,
    refW: w,
    bodySize: w * 0.026,
    font: 'Arial',
  );

  formulas.forEach((label, tex) {
    testWidgets('schatting dekt de hoogte: $label', (tester) async {
      final actual = await measuredHeight(tester, tex);
      final estimate = paginationHeight(tex);
      expect(
        estimate,
        greaterThanOrEqualTo(actual),
        reason:
            '$label: paginering rekent ${estimate.toStringAsFixed(0)}px onder de '
            'gemeten ${actual.toStringAsFixed(0)}px → formule zou het logo raken',
      );
      // Begrens de overschatting zodat de meting bruikbaar tight blijft en een
      // toekomstige tweak niet ongemerkt elke formule een eigen pagina geeft.
      expect(
        estimate,
        lessThanOrEqualTo(actual * 1.8),
        reason:
            '$label: schatting ${estimate.toStringAsFixed(0)}px veel te ruim',
      );
    });
  });
}
