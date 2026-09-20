// OOXML-conformiteit van de DOCX-export.
//
// Word controleert een .docx bij het openen tegen het WordprocessingML-schema
// en weigert het hele bestand bij één overtreding ("Er zijn problemen met de
// inhoud"). LibreOffice weigert niet, maar herstelt — en laat daarbij
// structuur vallen: een tabel waarvan de cel-alinea's naar een stijl zonder
// `w:name` verwijzen, verdwijnt en zijn inhoud valt als losse alinea's onder
// de tabel. Beide fouten zaten in de export van een documentbeleid van
// 54 kB, dat in Pages nog wél leesbaar oogde.
//
// Deze test bewijst per overtreding dat de export hem niet meer maakt:
// 1. Geen `w:p` binnen een `w:p` (citaat met alinea, losse lijst, geneste
//    lijst, codeblok in een lijstpunt).
// 2. Geen `w:r` buiten een `w:p` (een gerasteriseerd diagram of formule).
// 3. Elke `w:style` draagt een `w:name` als eerste kind.
// 4. De kind-volgorde van `w:pPr` en `w:rPr` volgt CT_PPrBase/CT_RPr.
// 5. `w:jc` gebruikt alleen uitlijningen uit de eerste editie van het
//    formaat — de editie die de namespace van het document noemt.
//    `start`/`end` kwamen pas later bij.
// 6. `w:tbl`, `w:tr` en `w:tc` dragen alleen elementen, geen tekst.
// 7. Een tabel blijft binnen de tekstkolom: de kolommen samen zijn nooit
//    breder dan de pagina minus de marges.
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/models/privacy_disposition.dart';
import 'package:ocideck/services/docx/document_docx_export.dart';
import 'package:ocideck/services/docx/markdown_to_docx.dart';
import 'package:ocideck/services/document_export_service.dart';
import 'package:ocideck/services/export_bundle.dart';
import 'package:ocideck/services/markdown_service.dart';
import 'package:ocideck/services/privacy/privacy_own_identity.dart';
import 'package:ocideck/services/privacy/privacy_regions.dart';
import 'package:xml/xml.dart';

const String _w =
    'http://schemas.openxmlformats.org/wordprocessingml/2006/main';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ExportBundle> buildBundle(String body) => buildDocumentExportBundle(
    body,
    projectPath: null,
    profile: PrivacyExportProfile.full,
    ownIdentity: OwnIdentity.empty,
    regions: defaultPrivacyRegions,
    disabledRules: const {},
    markdownService: MarkdownService(),
    title: 'Rapport',
  );

  /// Een brok Markdown dat elke blokvorm raakt waarin de export eerder een
  /// alinea in een alinea opende.
  const awkwardMarkdown = '''
# Beleid

> Het blokcitaat dat de scopeformulering draagt.
>
> En een tweede alinea in hetzelfde citaat.

- een punt

  met een vervolgalinea

- een punt met een geneste lijst
  - genest punt
  - nog een genest punt

- een punt met een codeblok

  ```
  regel een
  regel twee
  ```

| Fase | Trigger | Uitbreiding | Eigenaar | Datum |
|---|---|---:|:---:|---|
| 2 | Gunning | Bouwterrein | CISO | 2027 |
| 3 | Inbedrijfstelling | Procesbesturing | CISO | 2029 |

Een slotalinea.
''';

  group('docx: geen alinea in een alinea', () {
    test('citaat, lijst, geneste lijst en tabel leveren platte alinea\'s', () {
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');

      expect(_nestedParagraphs(doc), isEmpty);
      expect(_runsOutsideParagraph(doc), isEmpty);
      expect(_tablesInsideParagraph(doc), isEmpty);
    });

    test('een citaat met twee alinea\'s levert twee Quote-alinea\'s', () {
      final body = markdownToDocxBody(
        '> eerste alinea\n>\n> tweede alinea\n',
      ).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');
      final quotes = doc
          .findAllElements('p', namespace: _w)
          .where((p) => _styleOf(p) == 'Quote')
          .toList();

      expect(quotes, hasLength(2));
      expect(_textOf(quotes.first), 'eerste alinea');
      expect(_textOf(quotes.last), 'tweede alinea');
    });

    test('een vervolgalinea in een lijstpunt krijgt geen tweede bolletje', () {
      final body = markdownToDocxBody(
        '- het punt\n\n  de vervolgalinea\n',
      ).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');
      final paragraphs = doc.findAllElements('p', namespace: _w).toList();

      expect(paragraphs, hasLength(2));
      // Alleen het eerste punt draagt de opsommingsnummering.
      expect(
        paragraphs.first.findAllElements('numPr', namespace: _w),
        isNotEmpty,
      );
      expect(paragraphs.last.findAllElements('numPr', namespace: _w), isEmpty);
      expect(_textOf(paragraphs.last), 'de vervolgalinea');
    });
  });

  group('docx: schema-volgorde en toegestane waarden', () {
    test('elke stijl draagt een w:name als eerste kind', () async {
      final bundle = await buildBundle(
        '# Rapport\n\n| a | b |\n|---|---|\n| 1 | 2 |\n',
      );
      final styles = XmlDocument.parse(
        _entry(await buildDocumentExportDocx(bundle), 'word/styles.xml'),
      );

      final defined = styles.findAllElements('style', namespace: _w).toList();
      expect(defined, isNotEmpty);
      for (final style in defined) {
        final id = style.getAttribute('styleId', namespace: _w);
        final first = style.childElements.firstOrNull;
        expect(
          first?.localName,
          'name',
          reason: 'stijl $id mist <w:name> als eerste kind',
        );
        expect(
          first?.getAttribute('val', namespace: _w),
          isNotEmpty,
          reason: 'stijl $id heeft een lege naam',
        );
      }
    });

    test('elke pStyle verwijst naar een gedefinieerde stijl', () async {
      final bundle = await buildBundle(awkwardMarkdown);
      final bytes = await buildDocumentExportDocx(bundle);
      final doc = XmlDocument.parse(_entry(bytes, 'word/document.xml'));
      final styles = XmlDocument.parse(_entry(bytes, 'word/styles.xml'));

      final defined = styles
          .findAllElements('style', namespace: _w)
          .map((s) => s.getAttribute('styleId', namespace: _w))
          .toSet();
      final used = doc
          .findAllElements('pStyle', namespace: _w)
          .map((s) => s.getAttribute('val', namespace: _w))
          .toSet();

      expect(used, isNotEmpty);
      expect(used.difference(defined), isEmpty);
    });

    test('w:pPr en w:rPr houden de schema-volgorde aan', () {
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');

      expect(_outOfOrder(doc, 'pPr', _pPrOrder), isEmpty);
      expect(_outOfOrder(doc, 'rPr', _rPrOrder), isEmpty);
    });

    test('de Quote-stijl zet w:spacing vóór w:ind', () async {
      final bundle = await buildBundle('> een citaat\n');
      final styles = XmlDocument.parse(
        _entry(await buildDocumentExportDocx(bundle), 'word/styles.xml'),
      );
      final quote = styles
          .findAllElements('style', namespace: _w)
          .firstWhere(
            (s) => s.getAttribute('styleId', namespace: _w) == 'Quote',
          );

      expect(_outOfOrder(quote, 'pPr', _pPrOrder), isEmpty);
    });

    test('w:jc gebruikt geen start/end', () {
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');
      final values = doc
          .findAllElements('jc', namespace: _w)
          .map((e) => e.getAttribute('val', namespace: _w))
          .toSet();

      expect(values, isNotEmpty);
      expect(
        values,
        everyElement(isIn(const ['left', 'center', 'right', 'both'])),
      );
    });
  });

  group('docx: tabelstructuur', () {
    test('tabel, rij en cel dragen geen tekst', () {
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');

      for (final tag in const ['tbl', 'tr', 'tc']) {
        for (final el in doc.findAllElements(tag, namespace: _w)) {
          final text = el.children
              .whereType<XmlText>()
              .map((t) => t.value)
              .join();
          expect(text, isEmpty, reason: '<w:$tag> bevat tekst: ${text.trim()}');
        }
      }
    });

    test('elke rij heeft evenveel cellen als het raster kolommen', () {
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');

      final tables = doc.findAllElements('tbl', namespace: _w).toList();
      expect(tables, isNotEmpty);
      for (final tbl in tables) {
        final cols = tbl.findAllElements('gridCol', namespace: _w).length;
        for (final tr in tbl.findElements('tr', namespace: _w)) {
          expect(tr.findElements('tc', namespace: _w).length, cols);
        }
      }
    });

    test('een tabel van vijf kolommen blijft binnen de tekstkolom', () {
      const width = defaultContentWidthTwips;
      final body = markdownToDocxBody(awkwardMarkdown).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');
      final tbl = doc.findAllElements('tbl', namespace: _w).first;

      final cols = tbl
          .findAllElements('gridCol', namespace: _w)
          .map((c) => int.parse(c.getAttribute('w', namespace: _w)!))
          .toList();
      expect(cols, hasLength(5));
      expect(cols.reduce((a, b) => a + b), lessThanOrEqualTo(width));

      // De cellen volgen het raster, anders rekent Word zelf iets uit.
      for (final tc in tbl.findAllElements('tcW', namespace: _w)) {
        expect(int.parse(tc.getAttribute('w', namespace: _w)!), cols.first);
      }
    });

    test('een smallere tekstkolom maakt de tabel mee smaller', () {
      final body = markdownToDocxBody(
        '| a | b |\n|---|---|\n| 1 | 2 |\n',
        contentWidthTwips: 6000,
      ).body;
      final doc = XmlDocument.parse('<w:body xmlns:w="$_w">$body</w:body>');
      final cols = doc
          .findAllElements('gridCol', namespace: _w)
          .map((c) => int.parse(c.getAttribute('w', namespace: _w)!))
          .toList();

      expect(cols, [3000, 3000]);
    });
  });

  group('docx: het hele bestand', () {
    test('de geëxporteerde document.xml is vrij van overtredingen', () async {
      final bundle = await buildBundle(awkwardMarkdown);
      final doc = XmlDocument.parse(
        _entry(await buildDocumentExportDocx(bundle), 'word/document.xml'),
      );

      expect(_nestedParagraphs(doc), isEmpty);
      expect(_runsOutsideParagraph(doc), isEmpty);
      expect(_tablesInsideParagraph(doc), isEmpty);
      expect(_outOfOrder(doc, 'pPr', _pPrOrder), isEmpty);
      expect(_outOfOrder(doc, 'rPr', _rPrOrder), isEmpty);
    });

    test('een gerasteriseerd diagram staat in een eigen alinea', () async {
      final bundle = await buildBundle(
        'Tekst.\n\n```mermaid\ngraph TD\nA-->B\n```\n\nMeer tekst.\n',
      );
      final doc = XmlDocument.parse(
        _entry(
          await buildDocumentExportDocx(
            bundle,
            renderMermaid: (_) async => _minimalSvg,
          ),
          'word/document.xml',
        ),
      );

      final drawings = doc.findAllElements('drawing', namespace: _w).toList();
      expect(drawings, hasLength(1));
      expect(_runsOutsideParagraph(doc), isEmpty);
    });

    test(
      'een diagram zonder renderer valt terug zonder geneste alinea',
      () async {
        final bundle = await buildBundle('```mermaid\ngraph TD\nA-->B\n```\n');
        final doc = XmlDocument.parse(
          _entry(await buildDocumentExportDocx(bundle), 'word/document.xml'),
        );

        expect(_nestedParagraphs(doc), isEmpty);
        expect(_runsOutsideParagraph(doc), isEmpty);
      },
    );
  });
}

// ── Hulpstukken ────────────────────────────────────────────────────────────

/// De schema-volgorde van CT_PPrBase, voor zover de export hem gebruikt.
const List<String> _pPrOrder = [
  'pStyle',
  'keepNext',
  'keepLines',
  'pageBreakBefore',
  'numPr',
  'pBdr',
  'shd',
  'spacing',
  'ind',
  'contextualSpacing',
  'jc',
  'outlineLvl',
];

/// De schema-volgorde van CT_RPr, voor zover de export hem gebruikt.
const List<String> _rPrOrder = [
  'rStyle',
  'rFonts',
  'b',
  'i',
  'strike',
  'color',
  'sz',
  'u',
  'vertAlign',
];

List<String> _nestedParagraphs(XmlNode root) => [
  for (final p in root.findAllElements('p', namespace: _w))
    if (p.findAllElements('p', namespace: _w).isNotEmpty) _textOf(p),
];

List<String> _runsOutsideParagraph(XmlNode root) => [
  for (final r in root.findAllElements('r', namespace: _w))
    if (!_hasAncestor(r, 'p')) _textOf(r),
];

List<String> _tablesInsideParagraph(XmlNode root) => [
  for (final t in root.findAllElements('tbl', namespace: _w))
    if (_hasAncestor(t, 'p')) _textOf(t),
];

bool _hasAncestor(XmlElement node, String localName) {
  for (
    var parent = node.parentElement;
    parent != null;
    parent = parent.parentElement
  ) {
    if (parent.localName == localName && parent.namespaceUri == _w) return true;
  }
  return false;
}

/// De elementen van [container] waarvan de kinderen niet in [order] staan.
List<String> _outOfOrder(XmlNode root, String container, List<String> order) {
  final problems = <String>[];
  for (final el in root.findAllElements(container, namespace: _w)) {
    var last = -1;
    for (final child in el.childElements) {
      final rank = order.indexOf(child.localName);
      if (rank < 0) continue;
      if (rank < last) {
        problems.add('$container: ${child.localName} staat te laat');
      }
      last = rank;
    }
  }
  return problems;
}

String? _styleOf(XmlElement paragraph) => paragraph
    .findElements('pPr', namespace: _w)
    .expand((pPr) => pPr.findElements('pStyle', namespace: _w))
    .map((s) => s.getAttribute('val', namespace: _w))
    .firstOrNull;

String _textOf(XmlNode node) =>
    node.findAllElements('t', namespace: _w).map((t) => t.innerText).join();

String _entry(List<int> docxBytes, String name) {
  final entry = ZipDecoder().decodeBytes(docxBytes).find(name);
  if (entry == null) fail('Entry $name niet gevonden in DOCX-ZIP');
  return String.fromCharCodes(entry.content as List<int>);
}

/// Een minimale geldige SVG voor de rasterisatie (een rode rechthoek).
const String _minimalSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="50" viewBox="0 0 100 50">'
    '<rect width="100" height="50" fill="red"/></svg>';
