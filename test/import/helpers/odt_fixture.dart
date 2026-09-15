// Een minimale, echte `.odt` voor de documentimport-tests: een H1, een
// alinea met vet/cursief, een lijst en een tabel.
//
// Bewust een echt archief en geen namaak: de tests gaan door dezelfde parser
// als de gebruiker.
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';
const _xlink = 'http://www.w3.org/1999/xlink';
const _fo = 'urn:oasis:names:tc:opendocument:xmlns:xsl-fo-compatible:1.0';
const _style = 'urn:oasis:names:tc:opendocument:xmlns:style:1.0';

/// Bouw een minimale `.odt` met een op maat gemaakte body.
Uint8List odtFixture({String? body, String? styles}) {
  final contentXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
      'xmlns:table="$_table" xmlns:xlink="$_xlink" xmlns:fo="$_fo" '
      'xmlns:style="$_style">'
      '<office:body><office:text>'
      '${body ?? _defaultBody}'
      '</office:text></office:body>'
      '</office:document-content>';
  final stylesXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-styles xmlns:office="$_office" xmlns:text="$_text" '
      'xmlns:style="$_style" xmlns:fo="$_fo">'
      '<office:styles>'
      '<style:style style:name="Bold" style:family="text">'
      '<style:text-properties fo:font-weight="bold"/></style:style>'
      '<style:style style:name="Italic" style:family="text">'
      '<style:text-properties fo:font-style="italic"/></style:style>'
      '${styles ?? ''}'
      '</office:styles>'
      '</office:document-styles>';
  final parts = <String, String>{
    'content.xml': contentXml,
    'styles.xml': stylesXml,
    'meta.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<office:document-meta xmlns:office="$_office">'
        '<office:meta><dc:title>Test</dc:title></office:meta>'
        '</office:document-meta>',
    'META-INF/manifest.xml':
        '<?xml version="1.0" encoding="UTF-8"?>'
        '<manifest:manifest xmlns:manifest="urn:oasis:names:tc:opendocument:xmlns:manifest:1.0">'
        '<manifest:file-entry manifest:full-path="/" '
        'manifest:media-type="application/vnd.oasis.opendocument.text"/>'
        '</manifest:manifest>',
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
    '<text:h text:style-name="Heading_20_1" text:outline-level="1">Titel</text:h>'
    '<text:p text:style-name="P1">Een alinea met '
    '<text:span text:style-name="Bold">vet</text:span> en '
    '<text:span text:style-name="Italic">cursief</text:span>.'
    '</text:p>'
    '<text:list text:style-name="L1">'
    '<text:list-item><text:p>Eerste punt</text:p></text:list-item>'
    '<text:list-item><text:p>Tweede punt</text:p></text:list-item>'
    '</text:list>'
    '<table:table table:name="T1">'
    '<table:table-row>'
    '<table:table-cell><text:p>Kolom</text:p></table:table-cell>'
    '<table:table-cell><text:p>Waarde</text:p></table:table-cell>'
    '</table:table-row>'
    '<table:table-row>'
    '<table:table-cell><text:p>A</text:p></table:table-cell>'
    '<table:table-cell><text:p>1</text:p></table:table-cell>'
    '</table:table-row>'
    '</table:table>'
    '<text:p>Zie <text:a xlink:href="https://voorbeeld.nl">de site</text:a> voor meer.</text:p>';
