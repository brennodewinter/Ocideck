import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/odp/odp_importer.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_chart.dart';
import 'package:ocideck/utils/image_resize.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _draw = 'urn:oasis:names:tc:opendocument:xmlns:drawing:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _presentation = 'urn:oasis:names:tc:opendocument:xmlns:presentation:1.0';

List<int> _b(String s) => Uint8List.fromList(utf8.encode(s));

String _contentXml({
  bool withImage = false,
  bool withNotes = true,
  bool withTable = false,
  bool withChart = false,
}) {
  final imageFrame = withImage
      ? '<draw:frame draw:name="Img" svg:x="10cm" svg:y="5cm" svg:width="8cm" svg:height="6cm">'
            '<draw:image xlink:href="Pictures/photo.png" xlink:type="simple"/></draw:frame>'
      : '';
  final tableFrame = withTable
      ? '<draw:frame draw:name="Tbl" svg:x="2cm" svg:y="5cm" svg:width="20cm" svg:height="6cm">'
            '<table:table xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0">'
            '<table:table-column/>'
            '<table:table-row>'
            '<table:table-cell office:value-type="string"><text:p>A</text:p></table:table-cell>'
            '<table:table-cell office:value-type="string"><text:p>B</text:p></table:table-cell>'
            '</table:table-row>'
            '<table:table-row>'
            '<table:table-cell office:value-type="string"><text:p>1</text:p></table:table-cell>'
            '<table:table-cell office:value-type="string"><text:p>2</text:p></table:table-cell>'
            '</table:table-row>'
            '</table:table></draw:frame>'
      : '';
  final chartFrame = withChart
      ? '<draw:frame draw:name="Chart" svg:x="2cm" svg:y="5cm" svg:width="20cm" svg:height="10cm">'
            '<draw:object xlink:href="ObjectCharts/1" xlink:type="simple"/></draw:frame>'
      : '';
  final notes = withNotes
      ? '<presentation:notes>'
            '<draw:frame draw:name="Notes"><draw:text-box>'
            '<text:p>Remember the budget.</text:p>'
            '</draw:text-box></draw:frame>'
            '</presentation:notes>'
      : '';
  return '<?xml version="1.0"?>'
      '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw" '
      'xmlns:text="$_text" xmlns:xlink="$_xlink" xmlns:presentation="$_presentation" '
      'office:version="1.2">'
      '<office:body><office:presentation>'
      '<draw:page draw:name="p1" svg:width="28cm" svg:height="15.75cm">'
      '<draw:frame draw:name="Title" presentation:class="title" '
      'svg:x="2cm" svg:y="1cm" svg:width="24cm" svg:height="3cm">'
      '<draw:text-box><text:p>Plan</text:p></draw:text-box></draw:frame>'
      '<draw:frame draw:name="Body" presentation:class="outline" '
      'svg:x="2cm" svg:y="5cm" svg:width="24cm" svg:height="8cm">'
      '<draw:text-box>'
      '<text:list>'
      '<text:list-item><text:p>First</text:p>'
      '<text:list><text:list-item><text:p>Sub</text:p></text:list-item></text:list>'
      '</text:list-item>'
      '<text:list-item><text:p>Second</text:p></text:list-item>'
      '</text:list>'
      '<text:p>Plain paragraph.</text:p>'
      '</draw:text-box></draw:frame>'
      '$imageFrame'
      '$tableFrame'
      '$chartFrame'
      '<draw:frame draw:name="Free" svg:x="20cm" svg:y="13cm" svg:width="6cm" svg:height="2cm">'
      '<draw:text-box><text:p>Side note</text:p></draw:text-box></draw:frame>'
      '$notes'
      '</draw:page>'
      '</office:presentation></office:body></office:document-content>';
}

String _stylesXml() =>
    '<?xml version="1.0"?>'
    '<office:document-styles xmlns:office="$_office" '
    'xmlns:style="urn:oasis:names:tc:opendocument:xmlns:style:1.0" '
    'xmlns:fo="urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0" '
    'xmlns:draw="urn:oasis:names:tc:opendocument:xmlns:drawing:1.0" '
    'office:version="1.2">'
    '<office:styles>'
    '<style:default-style style:family="paragraph">'
    '<style:text-properties fo:color="#102030" fo:font-family="Liberation Sans"/>'
    '</style:default-style>'
    '<style:style style:name="Accent" style:family="graphic">'
    '<style:graphic-properties draw:fill="solid" draw:fill-color="#2E7D64"/>'
    '</style:style>'
    '</office:styles>'
    '<office:automatic-styles>'
    '<style:page-layout style:name="M1">'
    '<style:page-layout-properties fo:background-color="#F0F0F0"/>'
    '</style:page-layout>'
    '</office:automatic-styles>'
    '</office:document-styles>';

String _chartContentXml() =>
    '<?xml version="1.0"?>'
    '<office:document-content xmlns:office="$_office" '
    'xmlns:chart="urn:oasis:names:tc:opendocument:xmlns:chart:1.0" '
    'xmlns:table="urn:oasis:names:tc:opendocument:xmlns:table:1.0" '
    'xmlns:text="$_text" office:version="1.2">'
    '<office:body><office:chart><chart:chart chart:class="chart:bar" chart:stacked="true">'
    '<chart:title><text:p>Revenue</text:p></chart:title>'
    '<chart:plot-area/>'
    '<table:table table:name="local-table">'
    '<table:table-column/><table:table-column/>'
    '<table:table-row>'
    '<table:table-cell office:value-type="string"><text:p></text:p></table:table-cell>'
    '<table:table-cell office:value-type="string"><text:p>2024</text:p></table:table-cell>'
    '</table:table-row>'
    '<table:table-row>'
    '<table:table-cell office:value-type="string"><text:p>Q1</text:p></table:table-cell>'
    '<table:table-cell office:value-type="float" office:value="10"><text:p>10</text:p></table:table-cell>'
    '</table:table-row>'
    '<table:table-row>'
    '<table:table-cell office:value-type="string"><text:p>Q2</text:p></table:table-cell>'
    '<table:table-cell office:value-type="float" office:value="14"><text:p>14</text:p></table:table-cell>'
    '</table:table-row>'
    '</table:table>'
    '</chart:chart></office:chart></office:body></office:document-content>';

String _metaXml() =>
    '<?xml version="1.0"?>'
    '<office:document-meta xmlns:office="$_office" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/" office:version="1.2">'
    '<office:meta><dc:title>Quarterly</dc:title><dc:creator>Jane</dc:creator></office:meta>'
    '</office:document-meta>';

List<int> _zip(Map<String, Object> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = content is List<int>
        ? Uint8List.fromList(content)
        : Uint8List.fromList((content as String).codeUnits);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return ZipEncoder().encode(archive);
}

void main() {
  test(
    'parses title, nested bullets, paragraph, free text and notes',
    () async {
      final bytes = _zip({
        'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
        'content.xml': _contentXml(),
        'meta.xml': _metaXml(),
      });
      const name = 'deck.odp';

      final result = await OdpImporter().importBytes(bytes, path: name);
      expect(result.isOk, isTrue);
      final deck = result.okValue!;
      expect(deck.title, 'Quarterly');
      expect(deck.author, 'Jane');
      expect(deck.slides, hasLength(1));

      final s = deck.slides[0];
      expect(s.title, 'Plan');
      final bullets = s.bodyBlocks
          .where((b) => b.kind == BodyBlockKind.bullet)
          .toList();
      expect(bullets.map((b) => b.text).toList(), ['First', 'Sub', 'Second']);
      expect(bullets[0].level, 0);
      expect(bullets[1].level, 1);
      expect(
        s.bodyBlocks.any(
          (b) =>
              b.kind == BodyBlockKind.paragraph && b.text == 'Plain paragraph.',
        ),
        isTrue,
      );
      expect(s.notes, 'Remember the budget.');
      expect(s.positionedTexts, isNotEmpty);
      expect(s.positionedTexts.first.text, 'Side note');
    },
  );

  test('extracts images via xlink:href', () async {
    final imageBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _contentXml(withImage: true, withNotes: false),
      'Pictures/photo.png': imageBytes,
    });
    const name = 'img.odp';

    final deck = (await OdpImporter().importBytes(bytes, path: name)).okValue!;
    expect(deck.slides[0].images, hasLength(1));
    expect(deck.slides[0].images.single.ext, 'png');
    expect(deck.slides[0].images.single.bytes, imageBytes);
  });

  test('salvages a table from a draw:frame', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _contentXml(withTable: true, withNotes: false),
    });
    const name = 'tbl.odp';

    final slide = (await OdpImporter().importBytes(
      bytes,
      path: name,
    )).okValue!.slides[0];
    expect(slide.table, isNotNull);
    expect(slide.table!.header, ['A', 'B']);
    expect(slide.table!.rows, [
      ['1', '2'],
    ]);
  });

  test('salvages a stacked-bar chart via a draw:object sub-document', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _contentXml(withChart: true, withNotes: false),
      'ObjectCharts/1/content.xml': _chartContentXml(),
    });
    const name = 'chart.odp';

    final slide = (await OdpImporter().importBytes(
      bytes,
      path: name,
    )).okValue!.slides[0];
    expect(slide.chart, isNotNull);
    expect(slide.chart!.title, 'Revenue');
    expect(slide.chart!.type, SourceChartType.stackedBar);
    expect(slide.chart!.x, ['Q1', 'Q2']);
    expect(slide.chart!.series.single.name, '2024');
    expect(slide.chart!.series.single.data, [10.0, 14.0]);
  });

  test('imports a large ODP deck with many pages', () async {
    const pageCount = 20;
    final pages = StringBuffer();
    for (var i = 0; i < pageCount; i++) {
      pages.write(
        '<draw:page draw:name="p${i + 1}" svg:width="28cm" svg:height="15.75cm">'
        '<draw:frame draw:name="Title" presentation:class="title" '
        'svg:x="2cm" svg:y="1cm" svg:width="24cm" svg:height="3cm">'
        '<draw:text-box><text:p>Slide $i</text:p></draw:text-box></draw:frame>'
        '<draw:frame draw:name="Body" presentation:class="outline" '
        'svg:x="2cm" svg:y="5cm" svg:width="24cm" svg:height="8cm">'
        '<draw:text-box><text:list><text:list-item><text:p>Bullet $i</text:p></text:list-item></text:list></draw:text-box></draw:frame>'
        '</draw:page>',
      );
    }
    final content =
        '<?xml version="1.0"?>'
        '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw" '
        'xmlns:text="$_text" xmlns:presentation="$_presentation" office:version="1.2">'
        '<office:body><office:presentation>$pages</office:presentation></office:body></office:document-content>';
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': content,
    });
    const name = 'large.odp';

    final deck = (await OdpImporter().importBytes(bytes, path: name)).okValue!;
    expect(deck.slides, hasLength(pageCount));
    expect(deck.slides.first.title, 'Slide 0');
    expect(deck.slides.last.title, 'Slide ${pageCount - 1}');
    expect(deck.slides[10].bodyBlocks.single.text, 'Bullet 10');
  });

  test('salvages a deck theme from styles.xml', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _contentXml(withNotes: false),
      'meta.xml': _metaXml(),
      'styles.xml': _stylesXml(),
    });
    const name = 'themed.odp';

    final deck = (await OdpImporter().importBytes(bytes, path: name)).okValue!;
    expect(deck.theme, isNotNull);
    expect(deck.theme!.slideBackgroundColor, '#F0F0F0');
    expect(deck.theme!.accentColor, '#2E7D64');
    expect(deck.theme!.textColor, '#102030');
    expect(deck.theme!.fontFamily, 'Liberation Sans');
  });

  test('returns an error for a non-zip file', () async {
    final bytes = 'not zip'.codeUnits;
    const name = 'not_odp.odp';
    final result = await OdpImporter().importBytes(bytes, path: name);
    expect(result.isErr, isTrue);
  });

  test('returns an error when content.xml is missing', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
    });
    const name = 'no_content.odp';
    final result = await OdpImporter().importBytes(bytes, path: name);
    expect(result.isErr, isTrue);
  });

  test('salvages slide even when referenced image is missing', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _contentXml(withImage: true, withNotes: false),
      // Pictures/photo.png is intentionally missing.
    });
    const name = 'missing_image.odp';
    final result = await OdpImporter().importBytes(bytes, path: name);
    expect(result.isErr, isFalse);
    final slides = result.okValue!.slides;
    expect(slides, hasLength(1));
    expect(slides[0].images, isEmpty);
    expect(slides[0].title, 'Plan');
  });

  test('reports an error for an odp with no pages', () async {
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _b(
        '<?xml version="1.0"?>'
        '<office:document-content xmlns:office="$_office">'
        '<office:body><office:presentation/></office:body></office:document-content>',
      ),
    });
    const name = 'empty.odp';

    final result = await OdpImporter().importBytes(bytes, path: name);
    expect(result.isErr, isTrue);
  });

  // #1194: content.xml is UTF-8. Byte-voor-byte lezen trok een typografisch
  // aanhalingsteken (3 UTF-8-bytes) uiteen tot mojibake ("â" + twee tekens).
  test('preserves UTF-8 typographic quotes and accents in body text', () async {
    // Openingsaanhalingsteken U+201C, sluitend U+201D, apostrof U+2019, é.
    const quoted = 'Of “we don’t trust voting computers” famé';
    final content =
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw" '
        'xmlns:text="$_text" xmlns:presentation="$_presentation" '
        'office:version="1.2">'
        '<office:body><office:presentation>'
        '<draw:page draw:name="p1" svg:width="28cm" svg:height="15.75cm">'
        '<draw:frame draw:name="Body" presentation:class="outline" '
        'svg:x="2cm" svg:y="5cm" svg:width="24cm" svg:height="8cm">'
        '<draw:text-box><text:list><text:list-item>'
        '<text:p>$quoted</text:p>'
        '</text:list-item></text:list></draw:text-box></draw:frame>'
        '</draw:page>'
        '</office:presentation></office:body></office:document-content>';
    final bytes = _zip({
      'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
      'content.xml': _b(content),
    });

    final deck = (await OdpImporter().importBytes(
      bytes,
      path: 'quotes.odp',
    )).okValue!;
    final texts = deck.slides.single.bodyBlocks.map((b) => b.text).toList();
    expect(texts, contains(quoted));
    // Vang de specifieke regressie: geen mojibake-voorloopbyte.
    expect(texts.join(), isNot(contains('â')));
  });

  test(
    'draait een afbeelding tegen de klok in, met de EXIF-hoek verrekend',
    () async {
      // Een cameraopname: liggend opgeslagen, met een EXIF-tag die zegt dat hij
      // een kwartslag met de klok mee moet. Impress negeert die tag net als
      // PowerPoint, en telt zijn eigen `rotate` — tegen de klok in — vanaf de
      // ruwe pixels. Getoetst tegen wat LibreOffice zelf van dit bestand maakt.
      final original = img.Image(width: 40, height: 20);
      for (var y = 0; y < 20; y++) {
        for (var x = 0; x < 40; x++) {
          original.setPixelRgb(x, y, x < 20 ? 255 : 0, 0, x < 20 ? 0 : 255);
        }
      }
      original.exif.imageIfd.orientation = 6; // 90° met de klok mee
      final jpegBytes = Uint8List.fromList(
        img.encodeJpg(original, quality: 100),
      );

      final content =
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<office:document-content xmlns:office="$_office" xmlns:draw="$_draw" '
          'xmlns:text="$_text" xmlns:xlink="$_xlink" '
          'xmlns:presentation="$_presentation" '
          'xmlns:svg="urn:oasis:names:tc:opendocument:xmlns:svg-compatible:1.0">'
          '<office:body><office:presentation><draw:page draw:name="p1">'
          '<draw:frame draw:name="Img" svg:width="8cm" svg:height="4cm" '
          'draw:transform="rotate (1.5707963) translate (4cm 11cm)">'
          '<draw:image xlink:href="Pictures/photo.jpg" xlink:type="simple"/>'
          '</draw:frame>'
          '</draw:page></office:presentation></office:body>'
          '</office:document-content>';
      final bytes = _zip({
        'mimetype': _b('application/vnd.oasis.opendocument.presentation'),
        'content.xml': _b(content),
        'Pictures/photo.jpg': jpegBytes,
      });

      final deck = (await OdpImporter().importBytes(
        bytes,
        path: 'gedraaid.odp',
      )).okValue!;
      final imported = img.decodeImage(deck.slides.single.images.single.bytes);
      expect(imported, isNotNull);
      expect([imported!.width, imported.height], [20, 40]);
      // Een kwartslag tegen de klok in brengt de blauwe helft naar boven; met de
      // klok mee (de oude fout) zou rood boven staan.
      expect(imported.getPixel(10, 5).b, greaterThan(200));
      expect(imported.getPixel(10, 35).r, greaterThan(200));
      // En de tag mag niet blijven staan, anders draait een EXIF-lezende
      // renderer er nog een kwartslag overheen.
      expect(
        jpegExifRotationDegrees(deck.slides.single.images.single.bytes),
        0,
      );
    },
  );
}
