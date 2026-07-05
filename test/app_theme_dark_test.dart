import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/theme/app_theme.dart';

void main() {
  // Gedeelde static — altijd terugzetten zodat andere tests in lichte modus
  // draaien.
  tearDown(() => AppTheme.isDark = false);

  test('surface/text tokens keren om tussen licht en donker', () {
    AppTheme.isDark = false;
    final lightPaper = AppTheme.paper;
    final lightInk = AppTheme.ink;
    final lightSurface = AppTheme.slate50;

    AppTheme.isDark = true;
    // Papier/oppervlak worden donker, inkt wordt licht.
    expect(AppTheme.paper, isNot(lightPaper));
    expect(AppTheme.paper.computeLuminance(), lessThan(0.15));
    expect(AppTheme.slate50, isNot(lightSurface));
    expect(AppTheme.slate50.computeLuminance(), lessThan(0.15));
    expect(AppTheme.ink, isNot(lightInk));
    expect(AppTheme.ink.computeLuminance(), greaterThan(0.6));
  });

  test('accent-kleuren blijven in beide modi gelijk', () {
    AppTheme.isDark = false;
    final teal = AppTheme.teal;
    final accent = AppTheme.accent;
    AppTheme.isDark = true;
    expect(AppTheme.teal, teal);
    expect(AppTheme.accent, accent);
  });
}
