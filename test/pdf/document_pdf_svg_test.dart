// Een gerenderde SVG klaarmaken voor de PDF-lezer.
//
// Elk geval hieronder is één keer echt misgegaan in een render, en dat is geen
// toeval: een SVG die in een browser klopt, klopt niet vanzelf voor een lezer
// die geen CSS kent en geen eenheden omrekent. Wat hier stilletjes fout gaat
// levert geen foutmelding op maar een tekening van drie millimeter, of niets.

import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/pdf/document_pdf_svg.dart';

void main() {
  PreparedSvg prepare(String svg, {double fontSize = 11}) =>
      prepareSvgForPdf(svg, inkHex: '#222222', fontSizePt: fontSize);

  group('de maat', () {
    test('pixels worden punten', () {
      // Mermaid geeft zijn maat in CSS-pixels; die zijn kleiner dan een punt.
      final size = prepare(
        '<svg width="96" height="48" viewBox="0 0 96 48"></svg>',
      ).size;
      expect(size!.width, closeTo(72, 0.01));
      expect(size.height, closeTo(36, 0.01));
    });

    test('ex wordt omgerekend met de letterhoogte van het document', () {
      // MathJax meet in `ex`. Zonder omrekening is `2.5ex` tweeënhalve punt en
      // is de formule op papier een stipje — precies wat de eerste echte render
      // liet zien.
      final size = prepare(
        '<svg width="10ex" height="2.5ex" viewBox="0 0 4400 1100"></svg>',
        fontSize: 20,
      ).size;
      expect(size!.height, greaterThan(15));
      expect(size.width, greaterThan(60));
    });

    test('een grotere letter geeft een grotere formule', () {
      const svg = '<svg width="10ex" height="2ex" viewBox="0 0 100 20"></svg>';
      final klein = prepare(svg, fontSize: 9).size!;
      final groot = prepare(svg, fontSize: 18).size!;
      expect(groot.height, greaterThan(klein.height));
    });

    test('een percentage zegt niets over een absolute maat', () {
      // Onze eigen grafiekgenerator schrijft `width="100%"` — in HTML "vul de
      // kolom". De lezer maakte daar honderd punten van.
      final size = prepare(
        '<svg width="100%" viewBox="0 0 800 450"></svg>',
      ).size;
      // Dan telt de viewBox, gelezen als pixels.
      expect(size!.width, closeTo(600, 0.01));
      expect(size.height, closeTo(337.5, 0.01));
    });

    test('zonder maat én zonder viewBox blijft de maat onbekend', () {
      expect(prepare('<svg><rect/></svg>').size, isNull);
    });

    test('een onleesbare of nulmaat valt terug op de viewBox', () {
      final size = prepare(
        '<svg width="0" height="auto" viewBox="0 0 200 100"></svg>',
      ).size;
      expect(size!.width, closeTo(150, 0.01));
    });
  });

  group('een streepjespatroon van niets', () {
    // Mermaid schrijft dit op élke verbindingslijn. Een browser negeert het; de
    // lezer van package:pdf tekent er streepjes van lengte nul mee — en dan
    // staat het stroomdiagram er met vakjes en pijlpunten maar zonder één lijn
    // ertussen. Precies zoals de eerste echte render liet zien.
    test('nul in een style-regel gaat eruit', () {
      final out = prepare(
        '<svg viewBox="0 0 10 10">'
        '<path style="fill:none;stroke:#333;stroke-dasharray:0px;stroke-width:1px;"/>'
        '</svg>',
      ).svg;
      expect(out, isNot(contains('stroke-dasharray')));
      // En de rest van de stijl blijft heel.
      expect(out, contains('stroke:#333'));
      expect(out, contains('stroke-width:1px'));
    });

    test('nul als los attribuut gaat eruit', () {
      final out = prepare(
        '<svg viewBox="0 0 10 10"><path stroke-dasharray="0" stroke="#333"/></svg>',
      ).svg;
      expect(out, isNot(contains('stroke-dasharray')));
      expect(out, contains('stroke="#333"'));
    });

    test('een echt streepjespatroon blijft staan', () {
      // Een gestippelde lijn hoort gestippeld te blijven; dit haalt alleen weg
      // wat niets tekent.
      final out = prepare(
        '<svg viewBox="0 0 10 10"><path stroke-dasharray="4 2" stroke="#333"/></svg>',
      ).svg;
      expect(out, contains('stroke-dasharray="4 2"'));
    });

    test('meerdere nullen tellen ook als niets', () {
      final out = prepare(
        '<svg viewBox="0 0 10 10"><path stroke-dasharray="0, 0" /></svg>',
      ).svg;
      expect(out, isNot(contains('stroke-dasharray')));
    });
  });

  group('de opmaak zelf', () {
    test('de maat wordt uit de tag gehaald, de viewBox blijft staan', () {
      // Wat blijft staan leest de lezer als punten; de viewBox is de tekening.
      final out = prepare(
        '<svg width="10ex" height="2ex" viewBox="0 0 100 20"><rect/></svg>',
      ).svg;
      expect(out, isNot(contains('width=')));
      expect(out, isNot(contains('height=')));
      expect(out, contains('viewBox="0 0 100 20"'));
      expect(out, contains('<rect/>'));
    });

    test('een maat binnenin de tekening blijft ongemoeid', () {
      // Alleen de openingstag wordt gestript: een `width` op een rechthoek is
      // onderdeel van de tekening, geen opgave van de totale maat.
      final out = prepare(
        '<svg viewBox="0 0 100 20"><rect width="30" height="10"/></svg>',
      ).svg;
      expect(out, contains('<rect width="30" height="10"/>'));
    });

    test('currentColor wordt de inkt van het document', () {
      // MathJax kleurt zijn glyphs met `currentColor` — erf de tekstkleur. Deze
      // lezer kent die kleur niet, en een onbekende kleur tekent niets: de
      // formule verdween.
      final out = prepare(
        '<svg viewBox="0 0 10 10"><path fill="currentColor" d="M0 0"/></svg>',
      ).svg;
      expect(out, isNot(contains('currentColor')));
      expect(out, contains('#222222'));
    });

    test('een SVG zonder openingstag komt er ongeschonden uit', () {
      // Niet iets stils kapotmaken aan invoer die toch al niet klopt; de
      // renderer valt er verderop netjes op terug.
      const rommel = 'dit is geen svg';
      expect(prepare(rommel).svg, rommel);
      expect(prepare(rommel).size, isNull);
    });
  });
  // Wat er in een tekening als tekst gezet wordt (#1942). Krap gelezen met
  // opzet: een teken dat ten onrechte als "ontbreekt" gemeld wordt, leert de
  // gebruiker de melding negeren.
  group('svgTextContent', () {
    test('leest de tekst uit text- en tspan-knopen', () {
      const svg =
          '<svg viewBox="0 0 10 10">'
          '<text x="1" y="2">Bevindingen — per kwartaal</text>'
          '<text x="1" y="8"><tspan>Kritiek</tspan><tspan> → hoog</tspan></text>'
          '</svg>';
      final text = svgTextContent(svg);
      expect(text, contains('Bevindingen — per kwartaal'));
      expect(text, contains('Kritiek'));
      expect(text, contains('→ hoog'));
    });

    test('leest geen attribuutwaarden en geen opmaak', () {
      // Een `font-family` of een `id` staat niet op het papier; hem meetellen
      // zou een teken melden dat gewoon in het bestand staat.
      const svg =
          '<svg viewBox="0 0 10 10">'
          '<rect id="vlak—één" fill="#eee"/>'
          '<path d="M0 0 L9 9" font-family="Grüße→"/>'
          '</svg>';
      expect(svgTextContent(svg).trim(), isEmpty);
    });

    test('een tekening zonder tekst levert niets op', () {
      expect(svgTextContent('<svg><path d="M0 0"/></svg>').trim(), isEmpty);
    });
  });
}
