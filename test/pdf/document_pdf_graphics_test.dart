// Formules, mermaid-diagrammen en grafieken in de PDF.
//
// De vraag die deze test stelt is telkens dezelfde: staat het beeld erin, of de
// bron? Allebei zijn geldige uitkomsten — een blok dat niet getekend kan worden
// hoort zijn bron te tonen — maar het verschil moet komen doordat er wél of
// géén tekening beschikbaar was, en nooit doordat er onderweg iets stilviel.

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/pdf/document_pdf_export.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';

import 'pdf_text_probe.dart';

const _labels = DocumentPdfLabels(
  footnotesTitle: 'Noten',
  mathLabel: 'Formule (bron)',
  mermaidLabel: 'Diagram (bron)',
  chartLabel: 'Grafiek (bron)',
);

/// Een grafiekblok met cijfers erin.
const _chartBlock = '''
```chart
{
  "type": "bar",
  "title": "Bevindingen per kwartaal",
  "x": ["Q1", "Q2"],
  "series": [{"name": "Kritiek", "data": [3, 5]}]
}
```
''';

/// Een SVG die zichzelf tekent en waarvan de tekst terug te lezen is.
const _svg =
    '<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">'
    '<rect x="10" y="10" width="180" height="80" fill="#dddddd"/>'
    '<text x="100" y="55" text-anchor="middle" font-family="sans-serif" '
    'font-size="16" fill="#000000">GETEKEND</text>'
    '</svg>';

void main() {
  ByteData fallbackFont() => File(
    'assets/fonts/Roboto-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  Future<String> exportText(
    String document, {
    MermaidSvgResolver? renderMermaid,
    MathSvgResolver? renderMath,
  }) async {
    final bundle = await buildDocumentExportBundle(
      document,
      projectPath: null,
      profile: PrivacyExportProfile.full,
      ownIdentity: OwnIdentity.empty,
      regions: defaultPrivacyRegions,
      disabledRules: const {},
      markdownService: MarkdownService(),
    );
    final result = await buildDocumentExportPdf(
      bundle,
      labels: _labels,
      fallbackFont: fallbackFont(),
      renderMermaid: renderMermaid,
      renderMath: renderMath,
    );
    return pdfVisibleText(result.bytes);
  }

  group('grafieken', () {
    test('een grafiek wordt getekend, niet als bron afgedrukt', () async {
      final text = await exportText('# Rapport\n\n$_chartBlock');
      // De titel staat in de tekening zelf — als tekst, want de SVG-tekst wordt
      // met dezelfde sneden gezet als de rest van het document.
      expect(text, contains('Bevindingen per kwartaal'));
      // En de bron staat er dus níet als codeblok in.
      expect(text, isNot(contains('"type": "bar"')));
      expect(text, isNot(contains('Grafiek (bron)')));
    });

    test('de tekening komt van dezelfde generator als de HTML-export', () async {
      // Geen vierde renderwereld: de aslabels die de HTML-export tekent, tekent
      // de PDF ook.
      final text = await exportText('# Rapport\n\n$_chartBlock');
      expect(text, contains('Q1'));
      expect(text, contains('Q2'));
      expect(text, contains('Kritiek'));
    });

    test('zonder cijfers valt de grafiek terug op zijn bron', () async {
      // Staan de cijfers in een los `data/*.json` dat niet meekwam, dan levert
      // de generator een leeg vlak. De bron is dan meer waard.
      const external =
          '```chart\n{"type": "bar", "source": "cijfers.csv"}\n```\n';
      final text = await exportText('# Rapport\n\n$external');
      expect(text, contains('Grafiek (bron)'));
      expect(text, contains('cijfers.csv'));
    });
  });

  group('mermaid', () {
    const diagram = '```mermaid\ngraph TD;\n  A-->B;\n```\n';

    test(
      'met een renderer komt het diagram als tekening in het bestand',
      () async {
        final text = await exportText(
          '# Rapport\n\n$diagram',
          renderMermaid: (_) async => _svg,
        );
        expect(text, contains('GETEKEND'));
        expect(text, isNot(contains('Diagram (bron)')));
      },
    );

    test('zonder renderer blijft de bron leesbaar', () async {
      // Geen leeg vlak: wie het diagram nodig heeft weet dan tenminste wát er
      // hoort te staan.
      final text = await exportText('# Rapport\n\n$diagram');
      expect(text, contains('Diagram (bron)'));
      expect(text, contains('graph TD;'));
    });

    test('een renderer die niets oplevert valt netjes terug', () async {
      final text = await exportText(
        '# Rapport\n\n$diagram',
        renderMermaid: (_) async => null,
      );
      expect(text, contains('graph TD;'));
    });

    test('onleesbare SVG breekt de export niet af', () async {
      // Eén diagram dat tegenvalt mag nooit het hele document kosten.
      final text = await exportText(
        '# Rapport\n\n$diagram',
        renderMermaid: (_) async => '<svg><dit is geen xml',
      );
      expect(text, contains('Rapport'));
      expect(text, contains('graph TD;'));
    });

    test('hetzelfde diagram wordt één keer gerenderd', () async {
      // Op de bron gesleuteld: een document dat een diagram herhaalt, betaalt
      // dat niet twee keer.
      var calls = 0;
      await exportText(
        '# Rapport\n\n$diagram\n\ntekst\n\n$diagram',
        renderMermaid: (_) async {
          calls++;
          return _svg;
        },
      );
      expect(calls, 1);
    });
  });

  group('wiskunde', () {
    const formula = r'$$E = mc^2$$';

    test('met een renderer wordt de formule gezet', () async {
      String? asked;
      final text = await exportText(
        '# Rapport\n\n$formula\n',
        renderMath: (tex) async {
          asked = tex;
          return _svg;
        },
      );
      // De renderer krijgt de kale TeX, zonder de dollartekens eromheen.
      expect(asked, 'E = mc^2');
      expect(text, contains('GETEKEND'));
    });

    test('zonder renderer blijft de formule als bron leesbaar', () async {
      final text = await exportText('# Rapport\n\n$formula\n');
      expect(text, contains('Formule (bron)'));
      expect(text, contains('E = mc^2'));
    });
  });
}
