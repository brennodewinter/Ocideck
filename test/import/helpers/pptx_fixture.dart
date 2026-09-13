// Een minimale, echte `.pptx` voor de importtests: één dia met een titel en
// twee opsommingen.
//
// Bewust een echt archief en geen namaakimporter: de wachtrijtests gaan door
// dezelfde parser als de gebruiker, want daar zit het gedrag dat op het spel
// staat. Gedeeld door de wachtrij- en dialoogtests; de oudere
// `presentation_import_action_test` draagt zijn eigen kopie en blijft
// ongemoeid.
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:image/image.dart' as img;

const _p = 'http://schemas.openxmlformats.org/presentationml/2006/main';
const _a = 'http://schemas.openxmlformats.org/drawingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

Uint8List pptxFixture({String titel = 'Plan'}) {
  final slide =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
      '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$titel</a:t></a:r></a:p></p:txBody></p:sp>'
      '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Content"/><p:cNvSpPr/>'
      '<p:nvPr><p:ph type="body"/></p:nvPr></p:nvSpPr><p:spPr/>'
      '<p:txBody><a:bodyPr/><a:lstStyle/>'
      '<a:p><a:r><a:t>Eerste</a:t></a:r></a:p>'
      '<a:p><a:r><a:t>Tweede</a:t></a:r></a:p>'
      '</p:txBody></p:sp>'
      '</p:spTree></p:cSld></p:sld>';
  final parts = <String, String>{
    'ppt/presentation.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r">'
        '<p:sldSz cx="12192000" cy="6858000"/>'
        '<p:sldIdLst><p:sldId id="256" r:id="rId1"/></p:sldIdLst>'
        '</p:presentation>',
    'ppt/_rels/presentation.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="$_pkg"><Relationship Id="rId1" '
        'Type="$_r/slide" Target="slides/slide1.xml"/></Relationships>',
    'ppt/slides/slide1.xml': slide,
  };
  final archive = Archive();
  parts.forEach((name, content) {
    final data = Uint8List.fromList(content.codeUnits);
    archive.addFile(ArchiveFile.bytes(name, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

/// Bytes die géén archief zijn — de "onleesbaar bestand"-kant van de rij.
Uint8List corruptFixture() => Uint8List.fromList([1, 2, 3, 4, 5]);

/// Een klein merkdeck dat dezelfde relevante PowerPoint-opbouw gebruikt als
/// echte organisatietemplates: de omslag en slotachtergrond staan in een
/// dia-indeling, terwijl een brede merkvoet via het diamodel wordt geerfd.
///
/// De merkvoet bevat rechts een compact rood beeld op wit. Daarmee bewijst de
/// fixture ook dat OciDeck het beeldmerk uit de strook haalt, in plaats van de
/// volledige witte strook als een veel te breed logo op te slaan.
Uint8List pptxBrandFixture() {
  final cover = img.Image(width: 16, height: 9)
    ..clear(img.ColorRgb8(24, 70, 120));
  final closing = img.Image(width: 16, height: 9)
    ..clear(img.ColorRgb8(32, 118, 142));
  final content = img.Image(width: 8, height: 6)
    ..clear(img.ColorRgb8(240, 180, 40));
  final brandStrip = img.Image(width: 1280, height: 100)
    ..clear(img.ColorRgba8(255, 255, 255, 255));
  img.fillRect(
    brandStrip,
    x1: 1000,
    y1: 10,
    x2: 1179,
    y2: 69,
    color: img.ColorRgb8(210, 24, 48),
  );

  String slide(String title, {String subtitle = '', bool image = false}) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sld xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
      '<p:sp><p:nvSpPr><p:cNvPr id="2" name="Title"/><p:cNvSpPr/>'
      '<p:nvPr><p:ph type="title"/></p:nvPr></p:nvSpPr><p:spPr/>'
      '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$title</a:t></a:r></a:p></p:txBody></p:sp>'
      '${subtitle.isEmpty ? '' : '<p:sp><p:nvSpPr><p:cNvPr id="3" name="Subtitle"/><p:cNvSpPr/>'
                '<p:nvPr><p:ph type="subTitle"/></p:nvPr></p:nvSpPr><p:spPr/>'
                '<p:txBody><a:bodyPr/><a:lstStyle/><a:p><a:r><a:t>$subtitle</a:t></a:r></a:p></p:txBody></p:sp>'}'
      '${image ? '<p:pic><p:nvPicPr><p:cNvPr id="4" name="Content photo"/>'
                '<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rId2"/>'
                '</p:blipFill><p:spPr><a:xfrm><a:off x="700" y="160"/>'
                '<a:ext cx="480" cy="420"/></a:xfrm></p:spPr></p:pic>' : ''}'
      '</p:spTree></p:cSld></p:sld>';

  String layout({bool background = false, bool duplicateBrand = false}) =>
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<p:sldLayout xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
      '${background ? '<p:pic><p:nvPicPr><p:cNvPr id="10" name="Background"/>'
                '<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="rId2"/>'
                '</p:blipFill><p:spPr><a:xfrm><a:off x="0" y="0"/>'
                '<a:ext cx="1280" cy="720"/></a:xfrm></p:spPr></p:pic>' : ''}'
      '${duplicateBrand ? _brandPicture('rId3') : ''}'
      '</p:spTree></p:cSld></p:sldLayout>';

  final parts = <String, Object>{
    'ppt/presentation.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:presentation xmlns:p="$_p" xmlns:r="$_r"><p:sldSz cx="1280" cy="720"/>'
        '<p:sldIdLst><p:sldId id="256" r:id="rId1"/><p:sldId id="257" r:id="rId2"/>'
        '<p:sldId id="258" r:id="rId3"/></p:sldIdLst></p:presentation>',
    'ppt/_rels/presentation.xml.rels': _relationships([
      ('rId1', 'slide', 'slides/slide1.xml'),
      ('rId2', 'slide', 'slides/slide2.xml'),
      ('rId3', 'slide', 'slides/slide3.xml'),
    ]),
    'ppt/slides/slide1.xml': slide(
      'Merkworkshop',
      subtitle: 'Samen aan de slag',
    ),
    'ppt/slides/slide2.xml': slide('Inhoud', image: true),
    'ppt/slides/slide3.xml': slide('Bedankt'),
    'ppt/slides/_rels/slide1.xml.rels': _relationships([
      ('rId1', 'slideLayout', '../slideLayouts/slideLayout1.xml'),
    ]),
    'ppt/slides/_rels/slide2.xml.rels': _relationships([
      ('rId1', 'slideLayout', '../slideLayouts/slideLayout2.xml'),
      ('rId2', 'image', '../media/content.png'),
    ]),
    'ppt/slides/_rels/slide3.xml.rels': _relationships([
      ('rId1', 'slideLayout', '../slideLayouts/slideLayout3.xml'),
    ]),
    'ppt/slideLayouts/slideLayout1.xml': layout(
      background: true,
      duplicateBrand: true,
    ),
    'ppt/slideLayouts/slideLayout2.xml': layout(),
    'ppt/slideLayouts/slideLayout3.xml': layout(background: true),
    'ppt/slideLayouts/_rels/slideLayout1.xml.rels': _relationships([
      ('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml'),
      ('rId2', 'image', '../media/cover.png'),
      ('rId3', 'image', '../media/brand-strip.png'),
    ]),
    'ppt/slideLayouts/_rels/slideLayout2.xml.rels': _relationships([
      ('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml'),
    ]),
    'ppt/slideLayouts/_rels/slideLayout3.xml.rels': _relationships([
      ('rId1', 'slideMaster', '../slideMasters/slideMaster1.xml'),
      ('rId2', 'image', '../media/closing.png'),
    ]),
    'ppt/slideMasters/slideMaster1.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<p:sldMaster xmlns:a="$_a" xmlns:p="$_p" xmlns:r="$_r"><p:cSld><p:spTree>'
        '${_brandPicture('rId1')}</p:spTree></p:cSld></p:sldMaster>',
    'ppt/slideMasters/_rels/slideMaster1.xml.rels': _relationships([
      ('rId1', 'image', '../media/brand-strip.png'),
      ('rId2', 'theme', '../theme/theme2.xml'),
    ]),
    'ppt/theme/theme1.xml': _theme('#AA00AA', 'Georgia'),
    'ppt/theme/theme2.xml': _theme('#00A1DB', 'Arial'),
    'ppt/media/cover.png': img.encodePng(cover),
    'ppt/media/closing.png': img.encodePng(closing),
    'ppt/media/content.png': img.encodePng(content),
    'ppt/media/brand-strip.png': img.encodePng(brandStrip),
  };
  final archive = Archive();
  parts.forEach((name, content) {
    final data = content is List<int>
        ? Uint8List.fromList(content)
        : Uint8List.fromList((content as String).codeUnits);
    archive.addFile(ArchiveFile.bytes(name, data));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

String _brandPicture(String relationshipId) =>
    '<p:pic><p:nvPicPr><p:cNvPr id="20" name="Brand footer"/>'
    '<p:cNvPicPr/><p:nvPr/></p:nvPicPr><p:blipFill><a:blip r:embed="$relationshipId"/>'
    '</p:blipFill><p:spPr><a:xfrm><a:off x="0" y="620"/>'
    '<a:ext cx="1280" cy="100"/></a:xfrm></p:spPr></p:pic>';

String _relationships(List<(String, String, String)> entries) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<Relationships xmlns="$_pkg">${entries.map((entry) => '<Relationship Id="${entry.$1}" '
        'Type="$_r/${entry.$2}" Target="${entry.$3}"/>').join()}</Relationships>';

String _theme(String accent, String font) =>
    '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
    '<a:theme xmlns:a="$_a"><a:themeElements><a:clrScheme name="Merk">'
    '<a:dk1><a:srgbClr val="000000"/></a:dk1>'
    '<a:accent1><a:srgbClr val="${accent.substring(1)}"/></a:accent1>'
    '</a:clrScheme><a:fontScheme name="$font"><a:majorFont>'
    '<a:latin typeface="$font"/></a:majorFont></a:fontScheme>'
    '</a:themeElements></a:theme>';
