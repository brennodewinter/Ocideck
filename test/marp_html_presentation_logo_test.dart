import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Reads the vendored libraries straight from the repo (tests run at the root).
Future<String> _diskLoader(String asset) => File(asset).readAsString();

/// A deck with one ordinary slide (keeps the logo) and one that opts out via the
/// `no-logo` class the export serialiser writes for a slide with `showLogo:
/// false`.
const _md = '''
---
marp: true
---

# Dia met logo

Inhoud.

---

<!-- _class: no-logo -->

# Dia zonder logo
''';

MarpHtmlService _service() => MarpHtmlService(
  loadAsset: _diskLoader,
  // Elke asset — het logo én het gebundelde font — komt als dezelfde vier bytes
  // terug, base64 `AQIDBA==`, zodat de test kan vastpinnen dat juist het
  // logobestand offline in het document belandt.
  loadBytes: (_) async => Uint8List.fromList([1, 2, 3, 4]),
);

void main() {
  // Het presentatielogo — dat de presentator, de beamer en de PDF/PPTX op elke
  // dia tonen — hoort ook in de zelfstandige HTML-dia-export te zitten. Vóór de
  // fix kwam het niet mee: de export kende alleen het documentlogo van de
  // doorlopende modus.
  const bottomRight = ThemeProfile(
    logoPath: 'asset:assets/images/vigilis-logo.png',
    logoPosition: 'bottom-right',
    logoSize: 96,
  );

  test(
    'het presentatielogo reist zichtbaar en offline mee in de dia-modus',
    () async {
      final html = await _service().build(_md, theme: bottomRight);

      // Het logo staat als ingesloten data:-URI in de opmaak — geen los bestand.
      expect(html, contains('.slide.logo-safe::before{'));
      expect(
        html,
        contains(
          'background:url("data:image/png;base64,AQIDBA==") '
          'center/contain no-repeat',
        ),
      );
      // Zelfde vak en zelfde hoekinzet als _LogoOverlay bij een 1280px-dia:
      // 96×96, rechtsonder op 96·0.28 en 96·0.12.
      expect(html, contains('width:96px;height:96px'));
      expect(html, contains('bottom:12px;right:27px'));
    },
  );

  test('alleen logo-dia\'s krijgen het logo; een no-logo-dia niet', () async {
    final html = await _service().build(_md, theme: bottomRight);

    // De eerste dia toont het logo en houdt er ruimte voor vrij (logoSafeReserve
    // bij 1280px, #1932: gereduceerd tot size*edgeInset + gap), de tweede zet
    // het uit.
    expect(html, contains('<section class="slide logo-safe">'));
    // 96*0.12 + 1280*0.014 = 11.52 + 17.92 ≈ 29px.
    expect(html, contains('.slide.logo-safe{padding-bottom:29px}'));
    // De no-logo-dia blijft een kale dia zonder de logo-safe-haak.
    expect(html, contains('<section class="slide">'));
  });

  test('een linksboven-logo krijgt de spiegelbeeldige hoek en strook', () async {
    const topLeft = ThemeProfile(
      logoPath: 'asset:assets/images/vigilis-logo.png',
      logoPosition: 'top-left',
      logoSize: 96,
    );
    final html = await _service().build(_md, theme: topLeft);

    // 96·0.42 vanaf boven, 96·0.28 vanaf links; de strook staat nu bovenaan.
    // #1932: gereduceerd tot size*edgeInset + gap = 96*0.42 + 1280*0.014 ≈ 58px.
    expect(html, contains('top:40px;left:27px'));
    expect(html, contains('.slide.logo-safe{padding-top:58px}'));
  });

  test('een thema zonder logo laat de dia-export ongemoeid', () async {
    const noLogo = ThemeProfile(logoPath: null);
    final html = await _service().build(_md, theme: noLogo);

    expect(html, isNot(contains('.slide.logo-safe::before')));
    expect(html, isNot(contains('class="slide logo-safe"')));
  });

  test(
    'een logo dat niet ingesloten kan worden, laat geen haak achter',
    () async {
      // Een bestandspad-logo zonder resolver kan niet in het document; dan hoort
      // er ook geen lege logo-opmaak te verschijnen (spiegelt de app, die een
      // onvindbaar logo geruisloos weglaat).
      const missing = ThemeProfile(
        logoPath: 'logos/staat-niet-op-schijf.png',
        logoPosition: 'bottom-right',
      );
      final html = await _service().build(_md, theme: missing);

      expect(html, isNot(contains('.slide.logo-safe::before')));
    },
  );

  test('de doorlopende documentmodus houdt zijn eigen logo-band', () async {
    // Documentmodus heeft het documentlogo al (band boven/onder); de dia-haak
    // hoort daar niet ook nog eens te verschijnen.
    final html = await _service().build(
      _md,
      theme: bottomRight,
      continuous: true,
    );

    expect(html, isNot(contains('.slide.logo-safe::before')));
  });
}
