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
import 'package:ocideck/services/pdf/document_pdf_svg.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:pdf/pdf.dart';

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

/// Dezelfde grafiek, maar met de leestekens die een tekstverwerker vanzelf
/// maakt: een gedachtestreepje in de titel. Latin-1 kent dat teken niet.
const _typographyChart = '''
```chart
{
  "type": "bar",
  "title": "Bevindingen — per kwartaal",
  "x": ["Q1", "Q2"],
  "series": [{"name": "Kritiek", "data": [3, 5]}]
}
```
''';

void main() {
  ByteData fallbackFont() => File(
    'assets/fonts/Roboto-Variable.ttf',
  ).readAsBytesSync().buffer.asByteData();

  Future<Uint8List> exportBytes(
    String document, {
    MermaidSvgResolver? renderMermaid,
    MathSvgResolver? renderMath,
    bool withFallbackFont = true,
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
      fallbackFont: withFallbackFont ? fallbackFont() : null,
      renderMermaid: renderMermaid,
      renderMath: renderMath,
    );
    return result.bytes;
  }

  Future<String> exportText(
    String document, {
    MermaidSvgResolver? renderMermaid,
    MathSvgResolver? renderMath,
    bool withFallbackFont = true,
  }) async => pdfVisibleText(
    await exportBytes(
      document,
      renderMermaid: renderMermaid,
      renderMath: renderMath,
      withFallbackFont: withFallbackFont,
    ),
  );

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

  group('de inkt van een tekening', () {
    test('currentColor wordt een kleur die de lezer kent', () async {
      // `toHex()` levert `#RRGGBBAA`; met de doorzichtigheid erin wordt het
      // `#22222ff`, en dat tekent niets. Zichtbaar in de uitvoer van de lezer,
      // onzichtbaar in een test die alleen kijkt of er bytes zijn.
      final bundle = await buildDocumentExportBundle(
        '# Rapport\n\n```mermaid\ngraph TD;\n```\n',
        projectPath: null,
        profile: PrivacyExportProfile.full,
        ownIdentity: OwnIdentity.empty,
        regions: defaultPrivacyRegions,
        disabledRules: const {},
        markdownService: MarkdownService(),
      );
      String? doorgegeven;
      await buildDocumentExportPdf(
        bundle,
        labels: _labels,
        fallbackFont: fallbackFont(),
        renderMermaid: (_) async =>
            '<svg viewBox="0 0 10 10"><path fill="currentColor" d="M0 0"/></svg>',
      );
      // De voorbereide SVG is niet van buitenaf te lezen; toets daarom de regel
      // die hem maakt op zijn eigen laag, met dezelfde vorm die daar langskomt.
      doorgegeven = prepareSvgForPdf(
        '<svg viewBox="0 0 10 10"><path fill="currentColor"/></svg>',
        inkHex: const PdfColor.fromInt(0xFF222222).toHex().substring(0, 7),
        fontSizePt: 11,
      ).svg;
      expect(doorgegeven, contains('#222222'));
      expect(RegExp(r'#[0-9a-fA-F]{7,}').hasMatch(doorgegeven), isFalse);
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

    test('een inline-formule wordt tussen de lopende tekst getekend', () async {
      String? asked;
      final text = await exportText(
        r'Voor $E = mc^2$ na.',
        renderMath: (tex) async {
          asked = tex;
          return _svg;
        },
      );
      expect(asked, 'E = mc^2');
      expect(text, contains('Voor'));
      expect(text, contains('GETEKEND'));
      expect(text, contains('na.'));
    });

    test('dezelfde inline-formule wordt maar één keer gerenderd', () async {
      var calls = 0;
      await exportText(
        r'$f \approx 25$ en nogmaals $f \approx 25$',
        renderMath: (_) async {
          calls++;
          return _svg;
        },
      );
      expect(calls, 1);
    });

    test('zonder renderer blijft inline-TeX letterlijk leesbaar', () async {
      final text = await exportText(r'Voor $f \approx 25$ na.');
      expect(text, contains(r'$f \approx 25$'));
    });

    test('onleesbare inline-SVG valt terug op de TeX in de zin', () async {
      final text = await exportText(
        r'Voor $f \approx 25$ na.',
        renderMath: (_) async => '<svg><dit is geen xml',
      );
      expect(text, contains(r'$f \approx 25$'));
      expect(text, contains('na.'));
    });

    test(
      'een onbekend TeX-commando blijft data en valt veilig terug',
      () async {
        var calls = 0;
        final text = await exportText(
          r'Voor $\onbekend{waarde}$ na.',
          renderMath: (tex) async {
            calls++;
            expect(tex, r'\onbekend{waarde}');
            return null;
          },
        );
        expect(calls, 1);
        expect(text, contains(r'$\onbekend{waarde}$'));
      },
    );

    test(
      'inline-wiskunde in een tijdlijn gebruikt dezelfde renderer',
      () async {
        final text = await exportText(
          '<!-- timeline -->\n'
          '| Tijd | Gebeurtenis |\n'
          '| --- | --- |\n'
          r'| 09:00 | Meting $f \approx 25\,Hz$ |',
          renderMath: (_) async => _svg,
        );
        expect(text, contains('Meting'));
        expect(text, contains('GETEKEND'));
      },
    );
  });
  // Tekens boven U+00FF in een tekening (#1942).
  //
  // De SVG-lezer van `package:pdf` kiest voor `<text>` hardgecodeerd een van de
  // veertien standaardsneden — en die reiken tot Latin-1. Alles daarboven laat
  // `stringMetrics` werpen, en wel vanuit `SvgImage.paint`: dat is tijdens
  // `document.save()`, ruim buiten de `try` die de tekening zelf omsluit. Eén
  // gedachtestreepje in een grafiektitel kostte zo het hele document.
  group('tekens buiten Latin-1 in een tekening', () {
    test(
      'een gedachtestreepje in een grafiektitel breekt de export niet',
      () async {
        final text = await exportText('# Rapport\n\n$_typographyChart');
        // Het document is er, met de tekening erin en niet met de bron.
        expect(text, contains('Rapport'));
        expect(text, isNot(contains('Grafiek (bron)')));
        expect(text, isNot(contains('"type": "bar"')));
      },
    );

    test('de tekening wordt dan op het Unicode-font gezet', () async {
      final bytes = await exportBytes('# Rapport\n\n$_typographyChart');
      // Het bewijs dat de tekening niet stilletjes leeg bleef: het bestand roept
      // een ingebedde snede aan, en die staat er alleen in omdat de tekening
      // hem nodig had — de lopende tekst van dit document is Latin-1.
      expect(
        pdfBaseFonts(bytes).any((name) => name.contains('Roboto')),
        isTrue,
        reason: 'de SVG-tekst hoort op het gebundelde Unicode-font te staan',
      );
    });

    test('een Cyrillisch diagramlabel breekt de export niet', () async {
      const diagram = '```mermaid\ngraph TD;\n  A-->B;\n```\n';
      final text = await exportText(
        '# Rapport\n\n$diagram',
        renderMermaid: (_) async =>
            '<svg viewBox="0 0 200 100" xmlns="http://www.w3.org/2000/svg">'
            '<text x="10" y="50" font-size="16">Пример</text></svg>',
      );
      expect(text, contains('Rapport'));
      expect(text, isNot(contains('Diagram (bron)')));
    });

    test('zonder Unicode-font valt de tekening terug op haar bron', () async {
      // Er is dan geen snede die deze tekens kán zetten. Dan is de bron meer
      // waard dan een export die halverwege afbreekt.
      final text = await exportText(
        '# Rapport\n\n$_typographyChart',
        withFallbackFont: false,
      );
      expect(text, contains('Rapport'));
      expect(text, contains('Grafiek (bron)'));
    });

    test(
      'een tekening zonder zulke tekens blijft op de standaardsneden',
      () async {
        // Geen bijwerking op het gewone geval: de standaardsneden dragen een
        // echte vette en cursieve snede, en dat is precies waarom ze gekozen
        // zijn.
        final bytes = await exportBytes('# Rapport\n\n$_chartBlock');
        expect(pdfVisibleText(bytes), contains('Bevindingen per kwartaal'));
      },
    );
  });
}
