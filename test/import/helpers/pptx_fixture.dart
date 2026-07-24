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
