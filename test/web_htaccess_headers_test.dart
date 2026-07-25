@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// `web/.htaccess` — de HTTP-beveiligingsheaders die met de webbundel meereizen.
///
/// De bundel levert de CSP en de Referrer-Policy als `<meta>`-tags, maar een
/// browser dwingt `frame-ancestors` (en HSTS, X-Frame-Options, Permissions-
/// Policy) alleen af als ze als échte header binnenkomen (#849). Dit bestand
/// levert die headervorm voor een Apache-host, en `flutter build web` kopieert
/// het mee naar `build/web/.htaccess`.
///
/// Deze poort draait onder `make check` (geen webbouw nodig) en bewaakt twee
/// dingen die stil kunnen wegrotten:
///
///  1. de header-CSP blijft **byte voor byte** gelijk aan de meta-CSP in
///     index.html — anders lopen de twee policies uiteen en dekt de header niet
///     meer wat de pagina belooft;
///  2. elke hardening-header die alléén als header kan bestaan, staat er nog, en
///     met de bewuste conservatieve waarde (HSTS zonder `preload`).
void main() {
  final htaccess = File('web/.htaccess').readAsStringSync();
  final indexHtml = File('web/index.html').readAsStringSync();

  /// De waarde van `Header always set <Naam> "<waarde>"` uit de `.htaccess`.
  String? headerValue(String name) {
    final match = RegExp(
      'Header\\s+always\\s+set\\s+$name\\s+"([^"]*)"',
      caseSensitive: false,
    ).firstMatch(htaccess);
    return match?.group(1);
  }

  test('web/.htaccess bestaat en staat achter een mod_headers-guard', () {
    // Zonder `<IfModule mod_headers.c>` faalt een host zonder die module hard
    // op elke request in plaats van de headers stil over te slaan.
    expect(
      htaccess,
      contains('<IfModule mod_headers.c>'),
      reason: 'de headers horen achter een mod_headers-guard',
    );
  });

  test('de header-CSP is byte voor byte gelijk aan de meta-CSP', () {
    final metaCsp = RegExp(
      r'<meta\s+http-equiv="Content-Security-Policy"\s+content="([^"]*)"',
      caseSensitive: false,
    ).firstMatch(indexHtml)?.group(1);
    expect(metaCsp, isNotNull, reason: 'index.html moet een meta-CSP dragen');

    final headerCsp = headerValue('Content-Security-Policy');
    expect(
      headerCsp,
      isNotNull,
      reason: 'de .htaccess moet de CSP als header zetten',
    );
    expect(
      headerCsp,
      equals(metaCsp),
      reason:
          'header-CSP en meta-CSP moeten identiek zijn, anders dekt de header '
          'iets anders dan de pagina belooft (#849)',
    );
  });

  test('de CSP-header maakt frame-ancestors afdwingbaar', () {
    // De hele reden dat de CSP óók als header komt: `frame-ancestors` wordt uit
    // een meta-tag genegeerd. In de header moet hij dus staan, op 'none'.
    expect(
      headerValue('Content-Security-Policy'),
      contains("frame-ancestors 'none'"),
      reason: 'de header-CSP moet clickjacking sluiten met frame-ancestors',
    );
  });

  test('de headers die alleen als header kunnen bestaan, staan er', () {
    expect(
      headerValue('X-Frame-Options'),
      equals('DENY'),
      reason: 'X-Frame-Options moet clickjacking sluiten op oude browsers',
    );
    expect(
      headerValue('X-Content-Type-Options'),
      equals('nosniff'),
      reason: 'geen MIME-sniffing',
    );
    expect(
      headerValue('Referrer-Policy'),
      equals('no-referrer'),
      reason: 'versterkt de meta-referrer die de bundel al draagt',
    );
    expect(
      headerValue('Permissions-Policy'),
      isNotNull,
      reason:
          'Permissions-Policy schakelt ongebruikte features uit (ZAP 10063)',
    );
  });

  test('Permissions-Policy zet de gevoelige features uit', () {
    final pp = headerValue('Permissions-Policy')!;
    // De features die de app nooit gebruikt horen op `()` (volledig uit).
    for (final feature in [
      'camera',
      'microphone',
      'geolocation',
      'usb',
      'payment',
    ]) {
      expect(
        pp,
        contains('$feature=()'),
        reason: '$feature hoort volledig uit te staan',
      );
    }
    // De presentatiemodus gaat schermvullend; fullscreen mag dus niet uit.
    expect(
      pp,
      contains('fullscreen=(self)'),
      reason: 'de presenter gebruikt de Fullscreen-API',
    );
  });

  test('HSTS is conservatief: includeSubDomains, geen preload', () {
    final hsts = headerValue('Strict-Transport-Security');
    expect(hsts, isNotNull, reason: 'HSTS heeft geen meta-vorm; het moet hier');
    expect(
      hsts,
      contains('includeSubDomains'),
      reason: 'de veilige standaard uit HOSTING.md §3',
    );
    expect(
      hsts,
      isNot(contains('preload')),
      reason:
          'preload is de sticky, moeilijk terug te draaien keuze en blijft er '
          'bewust af (#849)',
    );
  });
}
