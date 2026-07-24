import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/appearance_scope.dart';

/// Een blad dat zich uit [AppTheme] kleurt en zich op de modus abonneert — de
/// vorm die het slidekwaliteitspaneel sinds #780 heeft.
class _AangeslotenBlad extends StatelessWidget {
  const _AangeslotenBlad();

  @override
  Widget build(BuildContext context) {
    AppearanceScope.modeOf(context);
    return ColoredBox(color: AppTheme.paper, child: const SizedBox(width: 10));
  }
}

void main() {
  tearDown(() => AppTheme.isDark = false);

  Color kleurVan(WidgetTester tester, Type blad) => tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(blad),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;

  Future<void> pomp(WidgetTester tester, AppAppearanceProfile p, Widget blad) =>
      tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(appearance: p, child: blad),
        ),
      );

  testWidgets('de vlag volgt het profiel, vanaf het eerste frame', (
    tester,
  ) async {
    await pomp(tester, AppAppearanceProfile.dark, const _AangeslotenBlad());
    expect(AppTheme.isDark, isTrue);
    // De kleur die het blad in dat éérste frame las, hoort al de donkere te
    // zijn: de vlag wordt in de constructor gezet, niet in een build die na de
    // descendants komt.
    expect(kleurVan(tester, _AangeslotenBlad), AppTheme.paper);

    await pomp(tester, AppAppearanceProfile.europa, const _AangeslotenBlad());
    expect(AppTheme.isDark, isFalse);
  });

  testWidgets('een aangesloten blad herkleurt bij een moduswisseling', (
    tester,
  ) async {
    await pomp(tester, AppAppearanceProfile.dark, const _AangeslotenBlad());
    final donker = kleurVan(tester, _AangeslotenBlad);
    await pomp(tester, AppAppearanceProfile.europa, const _AangeslotenBlad());
    expect(
      kleurVan(tester, _AangeslotenBlad),
      isNot(donker),
      reason:
          'zonder deze aansluiting blijft het blad in de kleuren van het vorige '
          'thema staan — precies wat #780 op het scherm zag',
    );
  });

  testWidgets('binnen dezelfde modus blijft de boom staan', (tester) async {
    // Een kleur bijstellen in een eigen profiel hoort géén element-boom weg te
    // gooien: dat kost schuifposities bij elke tik op een kleurenkiezer. Die
    // kleuren lopen via ThemeData en propageren zelf.
    await pomp(tester, AppAppearanceProfile.europa, const _AangeslotenBlad());
    final eerste = tester.element(find.byType(_AangeslotenBlad));
    await pomp(
      tester,
      AppAppearanceProfile.europa.copyWith(primaryColor: '#123456'),
      const _AangeslotenBlad(),
    );
    expect(tester.element(find.byType(_AangeslotenBlad)), same(eerste));
  });
}
