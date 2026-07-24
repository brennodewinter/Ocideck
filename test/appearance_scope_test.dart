import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';
import 'package:ocideck/theme/appearance_scope.dart';

/// Een blad dat zich uit [AppTheme] kleurt en **niet** van `Theme.of(context)`
/// afhangt — precies zoals het slidekwaliteitspaneel, en zoals de tientallen
/// andere widgets die een `AppTheme.slateX` of `AppTheme.successBg` gebruiken.
///
/// Dat is geen kunstmatig geval maar de normale manier waarop deze app kleurt.
/// Juist daardoor bleef het paneel na een themawisseling donkergroen op een
/// lichte interface staan (#780): het herbouwde niet, want zijn eigen invoer
/// veranderde niet.
class _StatischGekleurdBlad extends StatelessWidget {
  const _StatischGekleurdBlad();

  @override
  Widget build(BuildContext context) =>
      ColoredBox(color: AppTheme.paper, child: const SizedBox(width: 10));
}

void main() {
  tearDown(() => AppTheme.isDark = false);

  Color gelezenKleur(WidgetTester tester) => tester
      .widget<ColoredBox>(
        find.descendant(
          of: find.byType(_StatischGekleurdBlad),
          matching: find.byType(ColoredBox),
        ),
      )
      .color;

  Future<void> pompProfiel(WidgetTester tester, AppAppearanceProfile p) =>
      tester.pumpWidget(
        MaterialApp(
          home: AppearanceScope(
            appearance: p,
            child: const _StatischGekleurdBlad(),
          ),
        ),
      );

  testWidgets('de vlag volgt het profiel', (tester) async {
    await pompProfiel(tester, AppAppearanceProfile.dark);
    expect(AppTheme.isDark, isTrue);
    await pompProfiel(tester, AppAppearanceProfile.europa);
    expect(AppTheme.isDark, isFalse);
  });

  testWidgets('een statisch gekleurd blad herbouwt bij een moduswisseling', (
    tester,
  ) async {
    await pompProfiel(tester, AppAppearanceProfile.dark);
    final donker = gelezenKleur(tester);

    await pompProfiel(tester, AppAppearanceProfile.europa);
    final licht = gelezenKleur(tester);

    // Dit is de assertie die zonder de sleutel faalt: het blad houdt dan de
    // ColoredBox van de eerste pomp vast, en `donker == licht`.
    expect(
      licht,
      isNot(donker),
      reason:
          'Het blad kleurde zich opnieuw niet. Zonder een sleutel op de modus '
          'blijft elke widget die uit AppTheme leest en niet van Theme.of() '
          'afhangt in de kleuren van het vorige thema staan — en dat was '
          'precies wat #780 op het scherm zag.',
    );
  });

  testWidgets('binnen dezelfde modus blijft de boom staan', (tester) async {
    // Een kleur bijstellen in een eigen profiel hoort géén element-boom weg te
    // gooien: dat kost schuifposities en uitgeklapte panelen bij elke tik op
    // een kleurenkiezer. Die kleuren lopen via ThemeData en propageren zelf.
    await pompProfiel(tester, AppAppearanceProfile.europa);
    final eerste = tester.element(find.byType(_StatischGekleurdBlad));

    await pompProfiel(
      tester,
      AppAppearanceProfile.europa.copyWith(primaryColor: '#123456'),
    );
    expect(
      tester.element(find.byType(_StatischGekleurdBlad)),
      same(eerste),
      reason:
          'de sleutel staat op de modus, niet op het profiel — anders herbouwt '
          'de hele boom bij elke kleurtik',
    );
  });
}
