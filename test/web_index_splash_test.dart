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

  test('de loader weigert file:// met een uitleg in plaats van fouten', () {
    // #2661: index.html via Bestand → Openen gaf een scherm vol CORS- en
    // service-worker-fouten en een dood scherm. boot.js mag de bootstrap
    // alleen over http(s) laden en moet anders zelf de uitleg tonen.
    expect(
      html,
      contains('src="boot.js"'),
      reason: 'index.html laadt boot.js — die bewaakt de file://-grens',
    );
    final boot = File('web/boot.js').readAsStringSync();
    expect(
      boot,
      contains("location.protocol !== 'http:'"),
      reason: 'zonder protocolwacht start de bootstrap ook op file://',
    );
    expect(
      boot,
      contains('flutter_bootstrap.js'),
      reason: 'de http-tak moet de echte Flutter-bootstrap nog steeds laden',
    );
    // De melding mag geen script nodig hebben dat pas ná de boot draait:
    // hij moet het bestaande laadscherm hergebruiken of zelf iets tonen.
    expect(boot, contains('getElementById'));
  });

  test('de bundel is installeerbaar in een submap (relatieve base href)', () {
    // `<base href="/">` — wat `$FLUTTER_BASE_HREF` wordt als --base-href niet
    // wordt meegegeven — laadt flutter_bootstrap.js vanaf de documentroot en
    // laat een bundel in /ocideck/ volledig dood (#2275). De base moet
    // relatief blijven, zodat dezelfde bundel op elke diepte draait.
    final base = RegExp(
      r'<base\s+href="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(html);
    expect(base, isNotNull, reason: 'index.html draagt een <base href>');
    expect(
      base!.group(1),
      './',
      reason:
          'een absolute of token-base bindt de bundel aan de documentroot '
          '(#2275); "./" laat hem onder elk subpad werken',
    );
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
