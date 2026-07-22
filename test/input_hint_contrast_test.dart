import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/theme/app_theme.dart';

/// Een tip in een invoerveld moet er als een tip uitzien.
///
/// Dit is de regressie achter #583: het thema zette geen `hintStyle`, dus
/// `hintText` erfde de gewone tekstkleur. Een scorecard-editor met alleen
/// voorbeeldwaarden zag er daardoor ingevuld uit, terwijl de dia leeg was —
/// wat pas op de beamer bleek, en in de geëxporteerde PDF.
///
/// De toets is bewust niet "hint is precies kleur X" maar "hint verschilt
/// zichtbaar van echte invoer". Dat is wat de gebruiker moet kunnen zien, en
/// het blijft gelden als het palet ooit verschuift.
void main() {
  tearDown(() => AppTheme.isDark = false);

  for (final dark in [false, true]) {
    final mode = dark ? 'donker' : 'licht';

    test('een tip is in $mode thema te onderscheiden van ingevulde tekst', () {
      AppTheme.isDark = dark;
      final theme = AppTheme.fromProfile(AppAppearanceProfile.builtIns.first);

      final hint = theme.inputDecorationTheme.hintStyle?.color;
      expect(
        hint,
        isNotNull,
        reason:
            'Zonder hintStyle erft een tip de gewone tekstkleur, en dan is een '
            'leeg veld niet van een ingevuld veld te onderscheiden.',
      );

      final body =
          theme.textTheme.bodyMedium?.color ?? theme.colorScheme.onSurface;
      expect(
        hint,
        isNot(body),
        reason:
            'Een tip die dezelfde kleur heeft als invoer liegt over de '
            'toestand van het veld.',
      );

      // Zichtbaar lichter dan echte invoer, niet alleen "een andere waarde".
      final delta = (hint!.computeLuminance() - body.computeLuminance()).abs();
      expect(
        delta,
        greaterThan(0.05),
        reason:
            'Het verschil tussen tip en invoer moet met het oog te zien zijn, '
            'niet alleen met een kleurenkiezer (verschil was $delta).',
      );
    });
  }
}
