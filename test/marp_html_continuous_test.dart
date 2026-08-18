import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/models/page_size.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Reads the vendored libraries straight from the repo (tests run at the root).
Future<String> _diskLoader(String asset) => File(asset).readAsString();

/// Body met een uniek token in elke sectie, een `---`-thematische breuk en een
/// GFM-tabel — genoeg om te bewijzen dat de hele stroom in één payload belandt.
const _md = '''
---
marp: true
theme: ocideck
---

# TOKEN_HEADING

TOKEN_PARAGRAPH van de eerste sectie.

---

| Kolom A | Kolom B |
| --- | --- |
| TOKEN_CELL | tweede |
''';

void main() {
  group('build(continuous: true) — doorlopende documentmodus', () {
    test(
      'rendert de body als één <section class="document">, geen dia',
      () async {
        final service = MarpHtmlService(loadAsset: _diskLoader);
        final html = await service.build(_md, continuous: true);

        // Precies één documentsectie, en geen enkele diasectie.
        expect('<section class="document"'.allMatches(html), hasLength(1));
        expect(html, isNot(contains('<section class="slide')));
      },
    );

    test('de payload draagt de HELE body, niet meerdere losse secties', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_md, continuous: true);

      // Elk uniek token uit elke sectie zit in de (guarded) markdown-payload.
      expect(html, contains('# TOKEN_HEADING'));
      expect(html, contains('TOKEN_PARAGRAPH'));
      expect(html, contains('TOKEN_CELL'));

      // De front matter is gestript net als bij marpSlides.
      expect(html, isNot(contains('marp: true')));

      // De body loopt door de inerte poort — een payload-houder, geen
      // rechtstreeks geïnjecteerde gerenderde HTML.
      expect(html, contains('<script type="text/markdown">'));

      // De `---` splitst het document niet in dia's: één document-sectie, de
      // `---` blijft in de payload (marked maakt er client-side een <hr> van).
      expect('<section class='.allMatches(html), hasLength(1));

      // Bij afdrukken/PDF is die <hr> wél een pagina-einde (DOCUMENT_MODE.md):
      // op het scherm doorlopend, in print een nieuw blad.
      expect(html, contains('.document hr{page-break-after:always'));
    });

    test('chapterPageBreak spuit de hoofdstuk-print-CSS in', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final on = await service.build(
        _md,
        continuous: true,
        chapterPageBreak: true,
      );
      // Elke H1 breekt in print naar een nieuw blad; de eerste niet (geen leeg blad).
      expect(on, contains('.document h1{page-break-before:always'));
      expect(on, contains('.document h1:first-child{page-break-before:auto'));
      // Uit (standaard): geen hoofdstuk-breuk-regel.
      final off = await service.build(_md, continuous: true);
      expect(off, isNot(contains('.document h1{page-break-before:always')));
    });

    test('een kop blijft bij het afdrukken niet alleen onderaan', () async {
      // #2: dezelfde regel als de Pagina's-weergave in de app hanteert. De
      // browser kent hem als `break-after: avoid` plus weduwen/wezen; zonder
      // deze regels zei het scherm iets anders dan de druk.
      final html = await MarpHtmlService(
        loadAsset: _diskLoader,
      ).build(_md, continuous: true);
      expect(html, contains('page-break-after:avoid'));
      expect(html, contains('break-after:avoid'));
      expect(html, contains('orphans:2;widows:2'));
    });

    test('de renderroute-selector dekt de documentsectie', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_md, continuous: true);
      expect(html, contains('section.slide,section.document'));
      // Er is een leesbare-pagina-opmaak voor de documentsectie.
      expect(html, contains('.document{'));
    });

    test('het stijllogo reist zichtbaar en offline mee', () async {
      final service = MarpHtmlService(
        loadAsset: _diskLoader,
        loadBytes: (_) async => Uint8List.fromList([1, 2, 3, 4]),
      );
      final html = await service.build(
        _md,
        continuous: true,
        theme: ThemeProfile.vigilis,
      );

      expect(html, contains('class="document-logo right"'));
      expect(html, contains('data:image/png;base64,AQIDBA=='));
      expect(html, contains('.document-logo img{'));
    });

    test(
      'kop- en voettekst reizen mee en gelden alleen voor documenten',
      () async {
        final service = MarpHtmlService(loadAsset: _diskLoader);
        const theme = ThemeProfile(
          documentLogoSize: 240,
          documentHeaderText: '**Bestuurlijk rapport**\nTweede regel',
          documentFooterText: 'Vigilis · *Vertrouwelijk*',
          documentBandTextColor: '#F8FAFC',
          documentBandBackgroundColor: '#172033',
          documentShowPageNumbers: true,
        );

        final document = await service.build(
          _md,
          continuous: true,
          theme: theme,
        );
        expect(document, contains('class="document-header"'));
        expect(
          document,
          contains('<strong>Bestuurlijk rapport</strong><br>Tweede regel'),
        );
        expect(document, contains('class="document-footer"'));
        expect(document, contains('Vigilis · <em>Vertrouwelijk</em>'));
        expect(document, contains('class="document-page-number"'));
        expect(document, contains('width:240px'));
        expect(document, contains('color:#F8FAFC'));
        expect(document, contains('background:#172033'));
        expect(document, contains('@media print'));

        final slides = await service.build(
          _md,
          continuous: false,
          theme: theme,
        );
        expect(slides, isNot(contains('class="document-header"')));
        expect(slides, isNot(contains('class="document-footer"')));
      },
    );

    test('documentchrome laat onveilige Markdown-links niet door', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        _md,
        continuous: true,
        theme: const ThemeProfile(
          documentHeaderText:
              '[veilig](https://example.test) '
              '[onveilig](javascript:alert(1))',
        ),
      );

      expect(html, contains('href="https://example.test"'));
      expect(html, isNot(contains('href="javascript:')));
      expect(html, contains('onveilig'));
    });

    test(
      'blijft self-contained, met CSP en zonder externe url() in <style>',
      () async {
        final service = MarpHtmlService(loadAsset: _diskLoader);
        final html = await service.build(_md, continuous: true);

        expect(html, startsWith('<!doctype html>'));
        expect(html, contains('http-equiv="Content-Security-Policy"'));
        expect(html, isNot(contains('<script src')));

        // Geen externe http(s)-url() in het <style>-blok (data:-URI's mogen).
        final styleStart = html.indexOf('<style>');
        final styleEnd = html.indexOf('</style>', styleStart);
        final style = html.substring(styleStart, styleEnd);
        expect(
          style,
          isNot(
            matches(
              RegExp(
                r'url\(\s*["'
                "'"
                r']?https?://',
              ),
            ),
          ),
        );
        // En geen @font-face die naar buiten wijst.
        expect(style, isNot(contains('@font-face{font-family:\'X')));
      },
    );
  });

  group('paginamaat, marges en tabelstijl in de export-CSS', () {
    test('zonder paginamaat en marges staat er geen @page-regel', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(_md, continuous: true);
      expect(html, isNot(contains('@page{')));
    });

    test('een afloop vergroot het vel en belooft geen snijtekens', () async {
      // De vergrote `size` is wat élke afdrukmotor honoreert. `marks` staat er
      // bewust niet bij: de gedocumenteerde PDF-route is afdrukken vanuit de
      // browser, en geen browser kent die eigenschap — een schakelaar die niets
      // doet is erger dan geen schakelaar.
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        _md,
        continuous: true,
        pageSize: PageSizeSpec.a4,
        pageMargins: const PageMargins(bleedMm: 3),
      );
      // Alleen de @page-regel zelf bekijken: de gebundelde mermaid-JS bevat
      // het woord "marks" in heel andere betekenissen.
      final rule = RegExp(r'@page\{([^}]*)\}').firstMatch(html)?.group(1);
      expect(rule, isNotNull, reason: 'er hoort een @page-regel te staan');
      // A4 (210×297) plus 3 mm rondom.
      expect(rule, contains('size:216mm 303mm'));
      expect(rule, contains('bleed:3mm'));
      expect(rule, isNot(contains('marks')));
      // De tekstspiegel schuift mee, zodat hij op zijn plek blijft.
      expect(rule, contains('margin:28mm 23mm 28mm 23mm'));
    });

    test('paginamaat en marges landen in één @page-regel', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      final html = await service.build(
        _md,
        continuous: true,
        pageSize: PageSizeSpec.a4Landscape,
        pageMargins: const PageMargins(
          topMm: 30,
          bottomMm: 30,
          leftMm: 15,
          rightMm: 15,
        ),
      );
      expect(
        html,
        contains('@page{size:A4 landscape;margin:30mm 15mm 30mm 15mm}'),
      );
    });

    test('de tabelstijl van het profiel staat in de document-CSS', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      const profile = ThemeProfile(
        name: 'Huisstijl',
        tableZebraStriped: true,
        tableZebraColor: '#EEF2FF',
        tableBorderStyle: TableBorderStyle.lined,
        tableBorderColor: '#1E293B',
        tableCellPaddingPx: 10,
        tableAccentHeaderBorder: true,
        accentColor: '#003399',
      );
      final html = await service.build(_md, continuous: true, theme: profile);
      // lined: alleen een onderlijn per cel, geen kader.
      expect(html, contains('border-bottom:1px solid #1E293B80;'));
      // Celopvulling: verticaal 0.6×, horizontaal +4 — dezelfde verhouding als
      // de Flutter-weergave (`EdgeInsets.symmetric(horizontal: pad + 4,
      // vertical: pad * 0.6)`), zodat beide werelden dezelfde tabel tekenen.
      expect(html, contains('padding:6.0px 14.0px'));
      // Zebra op elke tweede body-rij — `r.isEven` in de Flutter-tabel raakt
      // dezelfde rijen (rij 0 is daar de koprij).
      expect(
        html,
        contains('.document tbody tr:nth-child(even){background:#EEF2FF}'),
      );
      expect(
        html,
        contains('.document thead th{border-bottom:2px solid #003399}'),
      );
    });

    test('een profiel zonder randen levert geen border-CSS op', () async {
      final service = MarpHtmlService(loadAsset: _diskLoader);
      const profile = ThemeProfile(
        name: 'Kaal',
        tableBorderStyle: TableBorderStyle.none,
      );
      final html = await service.build(_md, continuous: true, theme: profile);
      final td = RegExp(r'\.document td\{[^}]*\}').firstMatch(html)!.group(0)!;
      expect(td, isNot(contains('border')));
    });
  });

  test('build(continuous: false) laat de dia-modus onaangetast', () async {
    final service = MarpHtmlService(loadAsset: _diskLoader);
    final html = await service.build(_md, continuous: false);

    // Nog steeds meerdere diasecties (twee dia's rond de `---`), geen document.
    expect(html.contains('<section class="slide'), isTrue);
    expect('<section class="slide'.allMatches(html).length, greaterThan(1));
    expect(html, isNot(contains('<section class="document"')));
    expect(html, isNot(contains('class="document-logo')));
  });
}
