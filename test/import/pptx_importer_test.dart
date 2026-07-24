import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/pptx/pptx_importer.dart';
import 'package:ocideck/services/import/models/body_block.dart';
import 'package:ocideck/services/import/models/source_chart.dart';
import 'package:ocideck/services/import/models/source_video.dart';

const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

String _slideXml({
  String title = 'Plan',
  List<String> bullets = const ['First', 'Sub'],
  bool freeText = false,
  bool withImage = false,
  bool withChart = false,
  bool withTable = false,
}) {
  final bodyParas = bullets
      .asMap()
      .entries
      .map(
        (e) =>
            '<a:p><a:pPr lvl="${e.key}"/><a:r><a:t>${e.value}</a:t></a:r></a:p>',
      )
      .join('');
  final free = freeText
      ? '<p:sp>'
            '<p:nvSpPr><p:cNvPr id="4" name="TextBox"/><p:cNvSpPr/><p:nvPr/></p:nvSpPr>'
            '<p:spPr><a:xfrm><a:off x="4572000" y="4572000"/><a:ext cx="914400" cy="914400"/></a:xfrm></p:spPr>'
            '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Side note</a:t></a:r></a:p></p:txBody>'
            '</p:sp>'
      : '';
  final pic = withImage
      ? '<p:pic>'
            '<p:nvPicPr><p:cNvPr id="5" name="Photo"/><p:cNvPicPr/><p:nvPr/></p:nvPicPr>'
            '<p:blipFill><a:blip r:embed="rId3"/></p:blipFill>'
            '<p:spPr><a:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></a:xfrm></p:spPr>'
            '</p:pic>'
      : '';
  final frame = withChart
      ? '<p:graphicFrame>'
            '<p:nvGraphicFramePr><p:cNvPr id="6" name="Chart"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
            '<p:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></p:xfrm>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/chart">'
            '<c:chart xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" r:id="rId4"/>'
            '</a:graphicData></a:graphic>'
            '</p:graphicFrame>'
      : '';
  final tableFrame = withTable
      ? '<p:graphicFrame>'
            '<p:nvGraphicFramePr><p:cNvPr id="7" name="Table"/><p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
            '<p:xfrm><a:off x="0" y="0"/><a:ext cx="1" cy="1"/></p:xfrm>'
            '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/table">'
            '<a:tbl><a:tr>'
            '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>A</a:t></a:r></a:p></a:txBody></a:tc>'
            '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>B</a:t></a:r></a:p></a:txBody></a:tc>'
            '</a:tr><a:tr>'
            '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>1</a:t></a:r></a:p></a:txBody></a:tc>'
            '<a:tc><a:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>2</a:t></a:r></a:p></a:txBody></a:tc>'
            '</a:tr></a:tbl>'
            '</a:graphicData></a:graphic>'
            '</p:graphicFrame>'
      : '';
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">
  <p:cSld><p:spTree>
    <p:sp>
      <p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/><p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr>
      <p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$title</a:t></a:r></a:p></p:txBody>
    </p:sp>
    <p:sp>
      <p:nvSpPr><p:cNvPr id="3" name="Content"/><p:cNvSpPr/><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>
      <p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/>$bodyParas</p:txBody>
    </p:sp>
    $free
    $pic
    $frame
    $tableFrame
  </p:spTree></p:cSld>
</p:sld>''';
}

String _presentationXml(int count) {
  final ids = List.generate(
    count,
    (i) =>
        '<p:sldId id="${256 + i}" r:id="rId${i + 1}"${i == 1 ? ' show="0"' : ''}/>',
  ).join('');
  return '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<p:presentation xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">
  <p:sldIdLst>$ids</p:sldIdLst>
</p:presentation>''';
}

String _presRels(int count) {
  final rels = List.generate(
    count,
    (i) =>
        '<Relationship Id="rId${i + 1}" '
        'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/slide" '
        'Target="slides/slide${i + 1}.xml"/>',
  ).join('');
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<Relationships xmlns="$_pkg">$rels</Relationships>';
}

String _slideRels({
  bool withImage = false,
  bool withChart = false,
  bool withVideo = false,
  bool withAudio = false,
}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_pkg">'
    '<Relationship Id="rId2" '
    'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/notesSlide" '
    'Target="../notesSlides/notesSlide1.xml"/>'
    '${withImage ? '<Relationship Id="rId3" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/image" '
              'Target="../media/photo.png"/>' : ''}'
    '${withChart ? '<Relationship Id="rId4" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/chart" '
              'Target="../charts/chart1.xml"/>' : ''}'
    '${withVideo ? '<Relationship Id="rId5" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/video" '
              'Target="../media/clip.mp4"/>' : ''}'
    '${withAudio ? '<Relationship Id="rId6" '
              'Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/audio" '
              'Target="../media/voice.mp3"/>' : ''}'
    '</Relationships>';

String _chartXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<c:chartSpace xmlns:c="http://schemas.openxmlformats.org/drawingml/2006/chart" '
    'xmlns:a="$_a">'
    '<c:chart><c:title><c:tx><c:rich><a:p><a:r><a:t>Revenue</a:t></a:r></a:p></c:rich></c:tx></c:title>'
    '<c:plotArea>'
    '<c:barChart><c:barDir val="col"/><c:grouping val="stacked"/>'
    '<c:ser><c:tx><c:strRef><c:strCache><c:pt idx="0"><c:v>2024</c:v></c:pt></c:strCache></c:strRef></c:tx>'
    '<c:cat><c:strRef><c:strCache><c:pt idx="0"><c:v>Q1</c:v></c:pt><c:pt idx="1"><c:v>Q2</c:v></c:pt></c:strCache></c:strRef></c:cat>'
    '<c:val><c:numRef><c:numCache><c:pt idx="0"><c:v>10</c:v></c:pt><c:pt idx="1"><c:v>14</c:v></c:pt></c:numCache></c:numRef></c:val>'
    '</c:ser>'
    '<c:ser><c:tx><c:strRef><c:strCache><c:pt idx="0"><c:v>2025</c:v></c:pt></c:strCache></c:strRef></c:tx>'
    '<c:val><c:numRef><c:numCache><c:pt idx="0"><c:v>12</c:v></c:pt><c:pt idx="1"><c:v>18</c:v></c:pt></c:numCache></c:numRef></c:val>'
    '</c:ser>'
    '</c:barChart>'
    '</c:plotArea></c:chart></c:chartSpace>';

String _coreXml({String title = 'Quarterly', String author = 'Jane'}) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<cp:coreProperties xmlns:cp="http://schemas.openxmlformats.org/package/2006/metadata/core-properties" '
    'xmlns:dc="http://purl.org/dc/elements/1.1/">'
    '<dc:title>$title</dc:title>'
    '<dc:creator>$author</dc:creator>'
    '</cp:coreProperties>';

String _themeXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<a:theme xmlns:a="$_a">'
    '<a:clrScheme name="Ops"><a:dk1><a:srgbClr val="222222"/></a:dk1>'
    '<a:accent1><a:srgbClr val="2E7D64"/></a:accent1></a:clrScheme>'
    '<a:fontScheme><a:majorFont><a:latin typeface="Georgia"/></a:majorFont></a:fontScheme>'
    '</a:theme>';

String _notesXml() =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<p:notes xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">'
    '<p:cSld><p:spTree>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2"/><p:cNvSpPr/><p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr>'
    '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>Remember the budget.</a:t></a:r></a:p></p:txBody></p:sp>'
    '<p:sp><p:nvSpPr><p:cNvPr id="3"/><p:cNvSpPr/><p:nvPr><p:ph type="sldNum"/></p:nvPr></p:nvSpPr>'
    '<p:spPr/><p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>1</a:t></a:r></a:p></p:txBody></p:sp>'
    '</p:spTree></p:cSld></p:notes>';

/// Build an in-memory `.pptx` (a ZIP) from named parts. Strings are stored as
/// their code units; byte lists go in verbatim — no temp file needed, so the
/// suite stays `dart:io`-free and web-safe.
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
  test('parses title, bullets, notes and a hidden slide', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(2),
      'ppt/_rels/presentation.xml.rels': _presRels(2),
      'ppt/slides/slide1.xml': _slideXml(
        title: 'Plan',
        bullets: ['First', 'Sub'],
        freeText: true,
      ),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(),
      'ppt/notesSlides/notesSlide1.xml': _notesXml(),
      'ppt/slides/slide2.xml': _slideXml(title: 'Hidden', bullets: ['Secret']),
    });

    final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
    expect(result.isOk, isTrue);
    final slides = result.okValue!.slides;

    expect(slides, hasLength(2));

    expect(slides[0].title, 'Plan');
    // The free text box is preserved as body content (a paragraph, not a
    // bullet, since it is not a placeholder) and also recorded as positioned.
    expect(slides[0].bodyBlocks.map((BodyBlock b) => b.text).toList(), [
      'First',
      'Sub',
      'Side note',
    ]);
    expect(slides[0].bodyBlocks[0].kind, BodyBlockKind.bullet);
    expect(slides[0].bodyBlocks[1].level, 1);
    expect(slides[0].bodyBlocks.last.kind, BodyBlockKind.paragraph);
    expect(slides[0].notes, 'Remember the budget.');
    expect(
      slides[0].positionedTexts,
      isNotEmpty,
      reason: 'the free text box should be captured as positioned text',
    );
    expect(slides[0].positionedTexts.first.text, 'Side note');

    expect(slides[1].isHidden, isTrue);
    expect(slides[1].title, 'Hidden');
  });

  test('reports an error for a pptx with no slides', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(0),
      'ppt/_rels/presentation.xml.rels': _presRels(0),
    });

    final result = await PptxImporter().importBytes(bytes, path: 'empty.pptx');
    expect(result.isErr, isTrue);
  });

  test('extracts images via blip r:embed relationships', () async {
    final imageBytes = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A];
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(
        title: 'Photo',
        bullets: const [],
        withImage: true,
      ),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(withImage: true),
      'ppt/media/photo.png': imageBytes,
    });

    final result = await PptxImporter().importBytes(bytes, path: 'img.pptx');
    final slides = result.okValue!.slides;
    expect(slides, hasLength(1));
    expect(slides[0].images, hasLength(1));
    expect(slides[0].images.single.ext, 'png');
    expect(slides[0].images.single.name, 'Photo');
    expect(slides[0].images.single.bytes, imageBytes);
  });

  test('salvages a stacked bar chart with categories and two series', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(
        title: 'Revenue',
        bullets: const [],
        withChart: true,
      ),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(withChart: true),
      'ppt/charts/chart1.xml': _chartXml(),
    });

    final result = await PptxImporter().importBytes(bytes, path: 'chart.pptx');
    final slides = result.okValue!.slides;
    final chart = slides[0].chart;
    expect(chart, isNotNull);
    expect(chart!.type, SourceChartType.stackedBar);
    expect(chart.title, 'Revenue');
    expect(chart.x, ['Q1', 'Q2']);
    expect(chart.series, hasLength(2));
    expect(chart.series[0].name, '2024');
    expect(chart.series[0].data, [10.0, 14.0]);
    expect(chart.series[1].name, '2025');
    expect(chart.series[1].data, [12.0, 18.0]);
  });

  test('salvages a DrawingML table into a SourceTable', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(
        title: 'Costs',
        bullets: const [],
        withTable: true,
      ),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(),
    });

    final slides = await PptxImporter()
        .importBytes(bytes, path: 'table.pptx')
        .then((r) => r.okValue!.slides);
    final table = slides[0].table;
    expect(table, isNotNull);
    expect(table!.header, ['A', 'B']);
    expect(table.rows, [
      ['1', '2'],
    ]);
  });

  test('detects embedded video and audio through the slide rels', () async {
    final clip = [0x00, 0x01, 0x02, 0x03, 0x04];
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(title: 'Clip', bullets: const []),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(
        withVideo: true,
        withAudio: true,
      ),
      'ppt/media/clip.mp4': clip,
      'ppt/media/voice.mp3': [0x09],
    });

    final slides = await PptxImporter()
        .importBytes(bytes, path: 'av.pptx')
        .then((r) => r.okValue!.slides);
    expect(slides[0].video, isNotNull);
    expect(slides[0].video!.kind, SourceVideoKind.local);
    expect(slides[0].video!.ref, 'media/clip.mp4');
    expect(slides[0].video!.bytes, clip);
    expect(slides[0].audioFileName, 'voice.mp3');
  });

  test('returns an error for a non-zip file', () async {
    final result = await PptxImporter().importBytes(
      'not zip'.codeUnits,
      path: 'not_pptx.pptx',
    );
    expect(result.isErr, isTrue);
  });

  test('returns an error when presentation.xml is missing', () async {
    final bytes = _zip({'[Content_Types].xml': '<Types/>'});
    final result = await PptxImporter().importBytes(
      bytes,
      path: 'no_pres.pptx',
    );
    expect(result.isErr, isTrue);
  });

  test('salvages slide even when referenced image is missing', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(
        title: 'Image',
        bullets: const [],
        withImage: true,
      ),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(withImage: true),
      // ppt/media/photo.png is intentionally missing.
    });
    final result = await PptxImporter().importBytes(
      bytes,
      path: 'missing_image.pptx',
    );
    expect(result.isErr, isFalse);
    final slides = result.okValue!.slides;
    expect(slides, hasLength(1));
    expect(slides[0].images, isEmpty);
    expect(slides[0].title, 'Image');
  });

  test('imports a large PPTX deck with many text slides', () async {
    const slideCount = 30;
    final slides = <String, Object>{};
    for (var i = 0; i < slideCount; i++) {
      slides['ppt/slides/slide${i + 1}.xml'] = _slideXml(
        title: 'Slide $i',
        bullets: ['Bullet $i'],
      );
      slides['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _slideRels();
    }
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(slideCount),
      'ppt/_rels/presentation.xml.rels': _presRels(slideCount),
      ...slides,
    });

    final deck = (await PptxImporter().importBytes(
      bytes,
      path: 'large.pptx',
    )).okValue!;
    expect(deck.slides, hasLength(slideCount));
    expect(deck.slides.first.title, 'Slide 0');
    expect(deck.slides.last.title, 'Slide ${slideCount - 1}');
    expect(deck.slides[15].bodyBlocks.single.text, 'Bullet 15');
  });

  test('reports slide progress up to the final slide', () async {
    const slideCount = 3;
    final parts = <String, Object>{
      'ppt/presentation.xml': _presentationXml(slideCount),
      'ppt/_rels/presentation.xml.rels': _presRels(slideCount),
    };
    for (var i = 0; i < slideCount; i++) {
      parts['ppt/slides/slide${i + 1}.xml'] = _slideXml(title: 'S$i');
      parts['ppt/slides/_rels/slide${i + 1}.xml.rels'] = _slideRels();
    }
    final progress = <double>[];
    await PptxImporter().importBytes(
      _zip(parts),
      path: 'progress.pptx',
      onProgress: (p, _) => progress.add(p),
    );
    expect(progress, hasLength(slideCount));
    expect(progress.last, closeTo(1.0, 1e-9));
  });

  test('salvages deck-level title, author and theme', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presentationXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _slideXml(title: 'Hi', bullets: const []),
      'ppt/slides/_rels/slide1.xml.rels': _slideRels(),
      'docProps/core.xml': _coreXml(title: 'Quarterly', author: 'Jane'),
      'ppt/theme/theme1.xml': _themeXml(),
    });

    final deck = (await PptxImporter().importBytes(
      bytes,
      path: 'meta.pptx',
    )).okValue!;
    expect(deck.title, 'Quarterly');
    expect(deck.author, 'Jane');
    expect(deck.theme, isNotNull);
    expect(deck.theme!.accentColor, '#2E7D64');
    expect(deck.theme!.textColor, '#222222');
    expect(deck.theme!.fontFamily, 'Georgia');
  });
}
