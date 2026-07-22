@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `web/index.html` — het laadscherm en de grens die het niet mag overschrijden.
///
/// De webbouw is CanvasKit en verft pas na ongeveer tien seconden; die tien
/// seconden waren wit, zonder enig teken van leven (#589). Er ligt nu een
/// laagje onder het app-oppervlak dat "OciDeck · Laden…" toont. Twee dingen
/// moeten waar blijven, en geen van beide ziet `make check-web` (die draait
/// alleen bij een volledige webbouw):
///
///  1. het laagje bestáát — een regressie die het weghaalt geeft het witte
///     scherm terug;
///  2. het bevat **geen** inline script. De CSP van de pagina staat
///     `script-src 'self' 'wasm-unsafe-eval'` toe en nadrukkelijk geen
///     `'unsafe-inline'`, dus een `<script>…</script>` in de body zou door de
///     browser geweigerd worden — het laadscherm zou dan stil niets doen. Dit
///     is de goedkope bewaking die dat vangt zonder de hele bundel te bouwen.
void main() {
  final html = File('web/index.html').readAsStringSync();

  test('er is een laadscherm', () {
    expect(
      html,
      contains('id="splash"'),
      reason:
          'zonder dit laagje is de eerste ~10 seconden van de webbouw wit '
          '(#589)',
    );
  });

  test('het laadscherm draagt geen inline script', () {
    // Elk <script> moet een `src` hebben — een inline blok zou de CSP schenden
    // en dus nooit draaien. De regex is grof met opzet: hij vindt élke
    // openingstag en kijkt of daar een src in zit.
    final scripts = RegExp(
      r'<script\b([^>]*)>',
      caseSensitive: false,
    ).allMatches(html);
    expect(scripts, isNotEmpty, reason: 'de Flutter-loader hoort er te staan');
    for (final m in scripts) {
      expect(
        m.group(1),
        contains('src'),
        reason:
            'een inline <script> schendt de CSP (script-src zonder '
            "'unsafe-inline') en zou stil niets doen",
      );
    }
  });

  test('het laadscherm gebruikt alleen bestanden die de bundel al draagt', () {
    // De afbeelding op het laadscherm mag geen extern bestand zijn: alles wat
    // het toont moet uit de bundel zelf komen, anders is de eerste indruk een
    // gebroken plaatje achter een strak CSP.
    final splashImg = RegExp(
      r'<img[^>]*src="([^"]+)"',
      caseSensitive: false,
    ).firstMatch(html);
    expect(splashImg, isNotNull);
    final src = splashImg!.group(1)!;
    expect(src.startsWith('http'), isFalse, reason: 'geen externe afbeelding');
    expect(
      File('web/$src').existsSync(),
      isTrue,
      reason: 'de afbeelding van het laadscherm moet in web/ bestaan: $src',
    );
  });
}
