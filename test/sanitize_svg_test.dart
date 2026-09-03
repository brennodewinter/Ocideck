import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/utils/sanitize_svg.dart';

void main() {
  test('keeps a simple SVG intact', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg"><rect width="10"/></svg>';
    final safe = sanitizeMermaidSvg(svg);
    expect(safe, contains('<svg'));
    expect(safe, contains('<rect'));
  });

  test('removes script elements', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script><rect/></svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('<script')));
    expect(safe, contains('<rect'));
  });

  test('removes foreignObject and event handlers', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<foreignObject><body onclick="x()">bad</body></foreignObject>'
        '<rect onclick="evil()"/>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('foreignObject')));
    expect(safe, isNot(contains('onclick')));
  });

  test('strips javascript: href values', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="javascript:alert(1)"><text>link</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('javascript:')));
  });

  test('strips javascript: hidden behind an in-scheme control character', () {
    // Browsers ignore ASCII whitespace/control chars inside a URL scheme, so
    // `java<newline>script:` still executes. XML attribute normalisation turns
    // the newline into a space; a naive `startsWith('javascript:')` misses both.
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="java\nscript:alert(1)"><text>x</text></a>'
        '<a xlink:href="java\tscript:alert(2)"><text>y</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('script:alert')));
  });

  test('strips javascript: hidden behind a numeric character reference', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="java&#10;script:alert(1)"><text>x</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('script:alert')));
  });

  test('strips vbscript: URLs', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<a href="vbscript:MsgBox(1)"><text>x</text></a>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('vbscript:')));
  });

  test('returns null for non-svg markup', () {
    expect(sanitizeMermaidSvg('<html></html>'), isNull);
    expect(sanitizeMermaidSvg(''), isNull);
  });

  // ── Drie gaten uit #516 ───────────────────────────────────────────────────
  // Alle drie hetzelfde patroon: de lijst was volledig voor het aanvalstype
  // waar iemand aan dacht, en blind voor het mechanisme ernaast.

  test('SMIL kan geen event-handler meer installeren', () {
    // <set> schrijft een attribuut dat er bij het parsen nog niet stond, dus
    // geen enkele attribuutcontrole op de ouder ziet dit ooit.
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect width="10" height="10">'
        '<set attributeName="onload" to="alert(1)"/>'
        '</rect></svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('<set')));
    expect(safe, isNot(contains('onload')));
    expect(safe, contains('<rect'), reason: 'de vorm zelf blijft staan');
  });

  test('de overige animatie-elementen gaan ook weg', () {
    for (final tag in ['animate', 'animateTransform', 'animateMotion']) {
      final svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<rect width="10" height="10"><$tag attributeName="x" to="1"/>'
          '</rect></svg>';
      expect(sanitizeMermaidSvg(svg)!, isNot(contains('<$tag')), reason: tag);
    }
  });

  test('een stylesheet gaat eruit, want niemand leest hier CSS', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<style>rect { fill: url(javascript:alert(1)); }</style>'
        '<rect width="10" height="10"/></svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe, isNot(contains('<style')));
    expect(safe.toLowerCase(), isNot(contains('javascript:')));
    expect(safe, contains('<rect'));
  });

  test('een puntkomma-lijst verbergt de payload niet meer', () {
    // De controle keek alleen naar het begin van de hele waarde, dus een
    // onschuldige eerste entry dekte de tweede af.
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<rect width="10" height="10" values="a;javascript:alert(1)"/></svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    expect(safe.toLowerCase(), isNot(contains('javascript:')));
  });

  // ── De allow-list ─────────────────────────────────────────────────────────
  // De drie gevallen hierboven waren alle drie hetzelfde: de deny-list was
  // volledig voor het aanvalstype waar iemand aan dacht, en blind voor het
  // mechanisme ernaast. Een allow-list draait de bewijslast om, en deze is
  // afgelezen van `flutter_svg` in plaats van geraden — wat hier wegvalt, viel
  // bij de renderer al weg.

  group('alleen wat de renderer leest komt erdoor', () {
    test('een onbekend element verdwijnt mét zijn inhoud', () {
      // De schil weghalen en de inhoud laten staan is de slechtste uitkomst:
      // die inhoud belandt dan op een plek waar niemand hem meer keurt.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<filter id="f"><feImage href="https://elders.example/pixel.png"/>'
          '</filter><rect width="10" height="10"/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, isNot(contains('filter')));
      expect(safe, isNot(contains('feImage')));
      expect(safe, isNot(contains('elders.example')));
      expect(safe, contains('<rect'));
    });

    test('de hele getekende woordenschat blijft staan', () {
      // Zou hier iets uitvallen, dan verdwijnt er beeld zonder foutmelding —
      // precies de ruil waarom deze allow-list er eerder niet was.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 10 10">'
          '<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/>'
          '</linearGradient><clipPath id="c"><rect width="1" height="1"/>'
          '</clipPath></defs>'
          '<g transform="translate(1,1)" fill="#003399" opacity="0.9">'
          '<path d="M0 0 L1 1" stroke="#000" stroke-width="2"/>'
          '<circle cx="1" cy="1" r="1"/><ellipse cx="1" cy="1" rx="1" ry="2"/>'
          '<line x1="0" y1="0" x2="1" y2="1"/><polygon points="0,0 1,1"/>'
          '<polyline points="0,0 1,1"/><rect width="1" height="1"/>'
          '<text x="1" y="2" font-size="10" text-anchor="middle">'
          '<tspan dx="1">hoi</tspan></text>'
          '<use href="#c"/></g></svg>';
      final safe = sanitizeMermaidSvg(svg)!;

      for (final tag in const [
        'defs',
        'linearGradient',
        'stop',
        'clipPath',
        'g',
        'path',
        'circle',
        'ellipse',
        'line',
        'polygon',
        'polyline',
        'rect',
        'text',
        'tspan',
        'use',
      ]) {
        expect(safe, contains('<$tag'), reason: tag);
      }
      // Op de attributen, niet alleen op de tags. Een `<line>` waarvan x1/y1
      // wegvalt is nog steeds een `<line>` — en tekent een punt.
      for (final attr in const [
        'viewBox=',
        'transform=',
        'fill=',
        'opacity=',
        'd=',
        'stroke-width=',
        'cx=',
        'cy=',
        'r=',
        'rx=',
        'ry=',
        'x1=',
        'y1=',
        'x2=',
        'y2=',
        'points=',
        'font-size=',
        'text-anchor=',
        'dx=',
        'offset=',
        'stop-color=',
        'href=',
        'id=',
      ]) {
        expect(safe, contains(attr), reason: attr);
      }
      expect(safe, contains('hoi'), reason: 'de tekst zelf hoort te blijven');
    });

    test('opsmuk die niemand leest gaat eruit, het beeld niet', () {
      // Mermaid stuurt dit mee; `flutter_svg` kijkt er niet naar. Weghalen kost
      // dus geen pixel, en het scheelt een plek om iets in te verstoppen.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg" role="graphics-document" '
          'aria-roledescription="flowchart" class="flowchart">'
          '<rect class="node" data-id="A" width="10" height="10"/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, isNot(contains('role=')));
      expect(safe, isNot(contains('aria-')));
      expect(safe, isNot(contains('class=')));
      expect(safe, isNot(contains('data-id')));
      expect(safe, contains('width="10"'));
    });

    test('de namespace-verklaringen blijven staan', () {
      // Ze dragen een URI maar halen niets op. Weghalen is juist riskant: een
      // achtergebleven `xlink:href` zonder verklaring maakt het document
      // onherleesbaar.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg" '
          'xmlns:xlink="http://www.w3.org/1999/xlink"><rect/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, contains('xmlns="http://www.w3.org/2000/svg"'));
      expect(safe, contains('xmlns:xlink'));
    });

    test('een marker gaat eruit — de renderer tekende hem toch al niet', () {
      // Verrassend genoeg geen regressie: `<marker>` staat niet in de
      // elementenlijst van vector_graphics_compiler, dus pijlpunten in een
      // flowchart verschenen ook onder de oude deny-list niet.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<defs><marker id="arrow"><path d="M0 0 L1 1"/></marker></defs>'
          '<path d="M0 0 L9 9"/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, isNot(contains('<marker')));
      expect(safe, contains('<path d="M0 0 L9 9"'));
    });

    test('een style-deel zonder ":" gaat eruit — anders crasht de parser (#886)', () {
      // Mermaid zet op ER-relatie-paden `style="undefined;;;undefined;fill:none"`.
      // `vector_graphics` (achter flutter_svg) splitst een style op ";", splitst
      // elk deel op ":" en pakt daarna blind deel[1]; een deel zónder ":" (zoals
      // `undefined`) laat het met een RangeError crashen — en dan bleef het HÉLE
      // diagram blanco. Die delen worden nu weggegooid, de geldige blijven.
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<path d="M0 0 L9 9" style="undefined;;;undefined;fill:none;stroke:red"/>'
          '</svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, isNot(contains('undefined')));
      expect(safe, contains('fill:none'));
      expect(safe, contains('stroke:red'));
    });
  });

  // Pijlpunten (#941): flutter_svg rendert `<marker>` niet, dus zet
  // svg_style_inline.js mermaids pijlen om in expliciete `<polygon>`-driehoeken.
  // Die moeten door de opschoning heen komen — en de `<marker>` er juist uit,
  // want die is precies waarom de pijlen weg waren.
  test('houdt een polygon-pijlpunt, verwijdert de marker', () {
    const svg =
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<defs><marker id="arrow"><path d="M0 0 L10 5 L0 10 z"/></marker></defs>'
        '<path d="M0 0 L100 0" marker-end="url(#arrow)" stroke="#333"/>'
        '<polygon points="100,0 92,4 92,-4" fill="#333"/>'
        '</svg>';
    final safe = sanitizeMermaidSvg(svg)!;
    // De ingespoten pijlpunt overleeft, met zijn geometrie en kleur.
    expect(safe, contains('<polygon'));
    expect(safe, contains('points="100,0 92,4 92,-4"'));
    expect(safe, contains('fill="#333"'));
    // De marker en de verwijzing ernaar zijn weg (flutter_svg leest ze toch niet).
    expect(safe, isNot(contains('<marker')));
    expect(safe, isNot(contains('marker-end')));
  });
  // Een `<defs>` die leeg overblijft (#1942): mermaid vult hem met `<marker>`
  // en `<style>`, allebei gaan ze eruit, en de serializer schrijft wat overblijft
  // als `<defs/>`. Juist die zelfsluitende vorm handelt de parser van
  // vector_graphics_compiler níet af — vandaar "unhandled element <defs/>" in
  // elke debug-run. Er ging niets verloren, maar de melding hoort weg.
  group('een leeggelopen defs', () {
    test('verdwijnt in plaats van als <defs/> te blijven staan', () {
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<defs><marker id="arrow"><path d="M0 0 L1 1"/></marker></defs>'
          '<path d="M0 0 L9 9"/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, isNot(contains('defs')));
      expect(safe, contains('<path d="M0 0 L9 9"'));
    });

    test('een defs met iets erin blijft staan', () {
      const svg =
          '<svg xmlns="http://www.w3.org/2000/svg">'
          '<defs><linearGradient id="g"><stop offset="0" stop-color="#fff"/>'
          '</linearGradient></defs>'
          '<rect width="10" height="10" fill="url(#g)"/></svg>';
      final safe = sanitizeMermaidSvg(svg)!;
      expect(safe, contains('<defs>'));
      expect(safe, contains('linearGradient'));
    });
  });
}
