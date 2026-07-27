import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ocideck/services/import/core/result.dart';
import 'package:ocideck/services/import/importers/pptx/pptx_importer.dart';
import 'package:ocideck/services/import/models/conversion_issue.dart';

// De stabiliteitsbelofte van #877 op de PPTX-importer: één beschadigd onderdeel
// of één misvormde dia mag de rest van het deck niet meesleuren. Elk verlies
// komt als getypeerde `ConversionIssue` op de dia terug (onderdeel + oorzaak),
// zonder broninhoud.

const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

String _goodSlide(String title) =>
    '<?xml version="1.0"?>'
    '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
    '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
    '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$title</a:t></a:r></a:p>'
    '</p:txBody></p:sp>'
    '</p:spTree></p:cSld></p:sld>';

/// A slide part that exists but is not valid XML. The raw text carries a fake
/// personal-data marker so the test can prove it never surfaces.
const _piiMarker = 'BSN 123456782 Jansen';
const _malformedSlide =
    '<?xml version="1.0"?><p:sld><p:cSld><p:spTree>'
    '<a:t>$_piiMarker</a:t><oops-unclosed';

String _chartSlide(String title) =>
    '<?xml version="1.0"?>'
    '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
    '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
    '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$title</a:t></a:r></a:p>'
    '</p:txBody></p:sp>'
    '<p:graphicFrame><p:nvGraphicFramePr><p:cNvPr id="6" name="Chart"/>'
    '<p:cNvGraphicFramePr/><p:nvPr/></p:nvGraphicFramePr>'
    '<a:graphic><a:graphicData uri="$_a/chart">'
    '<c:chart xmlns:c="$_a/chart" r:id="rId4"/>'
    '</a:graphicData></a:graphic></p:graphicFrame>'
    '</p:spTree></p:cSld></p:sld>';

String _imageSlide(String title) =>
    '<?xml version="1.0"?>'
    '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
    '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
    '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
    '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$title</a:t></a:r></a:p>'
    '</p:txBody></p:sp>'
    '<p:pic><p:nvPicPr><p:cNvPr id="5" name="Photo"/><p:cNvPicPr/><p:nvPr/>'
    '</p:nvPicPr><p:blipFill><a:blip r:embed="rId3"/></p:blipFill>'
    '<p:spPr/></p:pic>'
    '</p:spTree></p:cSld></p:sld>';

String _presXml(int count) {
  final ids = List.generate(
    count,
    (i) => '<p:sldId id="${256 + i}" r:id="rId${i + 1}"/>',
  ).join();
  return '<?xml version="1.0"?>'
      '<p:presentation xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">'
      '<p:sldIdLst>$ids</p:sldIdLst></p:presentation>';
}

String _presRels(int count) {
  final rels = List.generate(
    count,
    (i) =>
        '<Relationship Id="rId${i + 1}" Type="$_r/slide" '
        'Target="slides/slide${i + 1}.xml"/>',
  ).join();
  return '<?xml version="1.0"?><Relationships xmlns="$_pkg">$rels</Relationships>';
}

Uint8List _zip(Map<String, String> parts) {
  final archive = Archive();
  parts.forEach((name, content) {
    final data = Uint8List.fromList(content.codeUnits);
    archive.addFile(ArchiveFile(name, data.length, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

void main() {
  test('één misvormde dia sleept de rest niet mee — volgorde blijft', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presXml(4),
      'ppt/_rels/presentation.xml.rels': _presRels(4),
      'ppt/slides/slide1.xml': _goodSlide('Een'),
      'ppt/slides/slide2.xml': _malformedSlide,
      'ppt/slides/slide3.xml': _goodSlide('Drie'),
      'ppt/slides/slide4.xml': _goodSlide('Vier'),
    });

    final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
    expect(result.isOk, isTrue, reason: 'de import als geheel blijft slagen');
    final slides = result.okValue!.slides;

    expect(slides, hasLength(4));
    expect(slides[0].title, 'Een');
    expect(slides[2].title, 'Drie');
    expect(slides[3].title, 'Vier');

    // De beschadigde dia zit op zijn eigen plek en is expliciet als verlies
    // genoteerd, met onderdeel + oorzaak.
    final broken = slides[1];
    expect(broken.parseIssues, hasLength(1));
    expect(broken.parseIssues.single.component, IssueComponent.slide);
    expect(broken.parseIssues.single.cause, IssueCause.malformedXml);

    // De schone dia's dragen geen verlies.
    expect(slides[0].parseIssues, isEmpty);
    expect(slides[2].parseIssues, isEmpty);
  });

  test('de broninhoud van een kapotte dia lekt niet naar de notitie', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _malformedSlide,
    });

    final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
    final issue = result.okValue!.slides.single.parseIssues.single;
    expect('${issue.feature} ${issue.description}', isNot(contains('BSN')));
    expect('${issue.feature} ${issue.description}', isNot(contains('Jansen')));
    expect(issue.args, isEmpty);
  });

  test(
    'een ontbrekend slide-part wordt gemeld, niet stil overgeslagen',
    () async {
      // De sldIdLst verwijst naar drie dia's, maar slide2.xml zit niet in het
      // archief — diepe corruptie. De dia houdt zijn plek en het verlies wordt
      // genoteerd (bewaker-kanttekening bij #877).
      final bytes = _zip({
        'ppt/presentation.xml': _presXml(3),
        'ppt/_rels/presentation.xml.rels': _presRels(3),
        'ppt/slides/slide1.xml': _goodSlide('Een'),
        // slide2.xml ontbreekt bewust.
        'ppt/slides/slide3.xml': _goodSlide('Drie'),
      });

      final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
      final slides = result.okValue!.slides;
      expect(slides, hasLength(3));
      expect(slides[0].title, 'Een');
      expect(slides[2].title, 'Drie');
      final issue = slides[1].parseIssues.single;
      expect(issue.component, IssueComponent.slide);
      expect(issue.cause, IssueCause.missingPart);
    },
  );

  test('een onleesbare grafiek wordt overgeslagen, de dia blijft', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _chartSlide('Met grafiek'),
      'ppt/slides/_rels/slide1.xml.rels':
          '<?xml version="1.0"?><Relationships xmlns="$_pkg">'
          '<Relationship Id="rId4" Type="$_r/chart" '
          'Target="../charts/chart1.xml"/></Relationships>',
      // Grafiekpart bestaat maar is geen geldige XML.
      'ppt/charts/chart1.xml': '<c:chartSpace><broken',
    });

    final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
    final slide = result.okValue!.slides.single;
    expect(slide.title, 'Met grafiek', reason: 'de titel overleeft de grafiek');
    expect(slide.chart, isNull, reason: 'de kapotte grafiek is niet gebouwd');
    final chartIssue = slide.parseIssues.singleWhere(
      (i) => i.component == IssueComponent.chart,
    );
    expect(chartIssue.cause, IssueCause.malformedXml);
  });

  test('ontbrekende media wordt als verlies genoteerd, de dia blijft', () async {
    final bytes = _zip({
      'ppt/presentation.xml': _presXml(1),
      'ppt/_rels/presentation.xml.rels': _presRels(1),
      'ppt/slides/slide1.xml': _imageSlide('Met foto'),
      // rId3 verwijst naar media/photo.png, maar dat part zit niet in het zip.
      'ppt/slides/_rels/slide1.xml.rels':
          '<?xml version="1.0"?><Relationships xmlns="$_pkg">'
          '<Relationship Id="rId3" Type="$_r/image" '
          'Target="../media/photo.png"/></Relationships>',
    });

    final result = await PptxImporter().importBytes(bytes, path: 'deck.pptx');
    final slide = result.okValue!.slides.single;
    expect(slide.title, 'Met foto');
    expect(slide.images, isEmpty);
    final mediaIssue = slide.parseIssues.singleWhere(
      (i) => i.component == IssueComponent.media,
    );
    expect(mediaIssue.cause, IssueCause.missingPart);
  });
}
