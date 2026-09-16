// Een minimale, echte `.docx` voor de documentimport-tests: een H1, een
// alinea met vet/cursief, een ongeordende lijst en een tabel.
//
// Bewust een echt archief en geen namaak: de tests gaan door dezelfde parser
// als de gebruiker.
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _w = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main';
const _r =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';
const _pkg = 'http://schemas.openxmlformats.org/package/2006/relationships';

/// Bouw een minimale `.docx` met een op maat gemaakte body.
Uint8List docxFixture({String? body}) {
  final documentXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:document xmlns:w="$_w" xmlns:r="$_r"><w:body>'
      '${body ?? _defaultBody}'
      '</w:body></w:document>';
  final stylesXml =
      '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
      '<w:styles xmlns:w="$_w">'
      '<w:style w:type="paragraph" w:styleId="Heading1">'
      '<w:name w:val="heading 1"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Heading2">'
      '<w:name w:val="heading 2"/></w:style>'
      '<w:style w:type="paragraph" w:styleId="Title">'
      '<w:name w:val="Title"/></w:style>'
      '</w:styles>';
  final parts = <String, String>{
    'word/document.xml': documentXml,
    'word/styles.xml': stylesXml,
    'word/_rels/document.xml.rels':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<Relationships xmlns="$_pkg">'
        '<Relationship Id="rId1" Type="$_r/hyperlink" '
        'Target="https://voorbeeld.nl" TargetMode="External"/>'
        '</Relationships>',
    'word/numbering.xml':
        '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>'
        '<w:numbering xmlns:w="$_w">'
        '<w:abstractNum w:abstractNumId="0">'
        '<w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/></w:lvl>'
        '</w:abstractNum>'
        '<w:num w:numId="1"><w:abstractNumId w:val="0"/></w:num>'
        '<w:abstractNum w:abstractNumId="1">'
        '<w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/></w:lvl>'
        '</w:abstractNum>'
        '<w:num w:numId="2"><w:abstractNumId w:val="1"/></w:num>'
        '</w:numbering>',
  };
  final archive = Archive();
  parts.forEach((name, content) {
    archive.addFile(
      ArchiveFile.bytes(name, Uint8List.fromList(content.codeUnits)),
    );
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}

const _defaultBody =
    '<w:p><w:pPr><w:pStyle w:val="Heading1"/></w:pPr>'
    '<w:r><w:t>Titel</w:t></w:r></w:p>'
    '<w:p><w:r><w:t>Een alinea met </w:t></w:r>'
    '<w:r><w:rPr><w:b/></w:rPr><w:t>vet</w:t></w:r>'
    '<w:r><w:t> en </w:t></w:r>'
    '<w:r><w:rPr><w:i/></w:rPr><w:t>cursief</w:t></w:r>'
    '<w:r><w:t>.</w:t></w:r></w:p>'
    '<w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>'
    '<w:r><w:t>Eerste punt</w:t></w:r></w:p>'
    '<w:p><w:pPr><w:numPr><w:numId w:val="1"/></w:numPr></w:pPr>'
    '<w:r><w:t>Tweede punt</w:t></w:r></w:p>'
    '<w:tbl>'
    '<w:tr><w:tc><w:p><w:r><w:t>Kolom</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>Waarde</w:t></w:r></w:p></w:tc></w:tr>'
    '<w:tr><w:tc><w:p><w:r><w:t>A</w:t></w:r></w:p></w:tc>'
    '<w:tc><w:p><w:r><w:t>1</w:t></w:r></w:p></w:tc></w:tr>'
    '</w:tbl>'
    '<w:p><w:r><w:t>Zie </w:t></w:r>'
    '<w:hyperlink r:id="rId1"><w:r><w:t>de site</w:t></w:r></w:hyperlink>'
    '<w:r><w:t> voor meer.</w:t></w:r></w:p>';
