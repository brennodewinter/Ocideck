import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/settings.dart';
import 'package:ocideck/services/marp_html_service.dart';

/// Reads the vendored libraries straight from the repo (tests run at the root).
Future<String> _diskLoader(String asset) => File(asset).readAsString();

/// Body met een uniek token in elke sectie, een `---`-thematische breuk en een
/// GFM-tabel — genoeg om te bewijzen dat de hele stroom in één payload beландt.
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
