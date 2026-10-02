// Een minimale, echte `.xlsx` voor de spreadsheet-importtests: een
// workbook met één of meer werkbladen, gedeelde strings en stijlen.
//
// Bewust een echt archief en geen namaak: de tests gaan door dezelfde parser
// als de gebruiker.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _mainNs = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main';
const _relNs =
    'http://schemas.openxmlformats.org/officeDocument/2006/relationships';

/// Bouw een `.xlsx`. [sheets] is `naam → sheetData-inhoud` (de rijen-XML die
/// onder `<sheetData>` komt). [sharedStrings] en [stylesXml] zijn optioneel.
/// [extra] voegt ruwe delen toe — `{'xl/media/logo.png': bytes}` om het
/// verlies-spoor te testen.
Uint8List xlsxFixture({
  Map<String, String> sheets = const {
    'Blad1':
        '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row>'
        '<row r="2"><c r="A2" t="s"><v>2</v></c><c r="B2"><v>42</v></c></row>',
  },
  List<String> sharedStrings = const ['Kolom', 'Waarde', 'A'],
  String? stylesXml,
  Map<String, List<int>> extra = const {},
}) {
  final sheetEntries = sheets.entries.toList();
  final workbook =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<workbook xmlns="$_mainNs" xmlns:r="$_relNs"><sheets>'
      '${[for (var i = 0; i < sheetEntries.length; i++) '<sheet name="${sheetEntries[i].key}" sheetId="${i + 1}" '
            'r:id="rId${i + 1}"/>'].join()}'
      '</sheets></workbook>';
  final rels =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
      '${[for (var i = 0; i < sheetEntries.length; i++) '<Relationship Id="rId${i + 1}" '
            'Type="$_relNs/worksheet" Target="worksheets/sheet${i + 1}.xml"/>'].join()}'
      '</Relationships>';
  final shared =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<sst xmlns="$_mainNs" count="${sharedStrings.length}" '
      'uniqueCount="${sharedStrings.length}">'
      '${[for (final s in sharedStrings) '<si><t>$s</t></si>'].join()}'
      '</sst>';

  final parts = <String, String>{
    'xl/workbook.xml': workbook,
    'xl/_rels/workbook.xml.rels': rels,
    'xl/sharedStrings.xml': shared,
    'xl/styles.xml':
        stylesXml ??
        '<?xml version="1.0" encoding="UTF-8"?>'
            '<styleSheet xmlns="$_mainNs"><numFmts count="0"/>'
            '<cellXfs count="1"><xf numFmtId="0"/></cellXfs></styleSheet>',
    for (var i = 0; i < sheetEntries.length; i++)
      'xl/worksheets/sheet${i + 1}.xml':
          '<?xml version="1.0" encoding="UTF-8"?>'
          '<worksheet xmlns="$_mainNs"><sheetData>'
          '${sheetEntries[i].value}</sheetData></worksheet>',
  };

  final archive = Archive();
  parts.forEach((name, content) {
    archive.addFile(
      ArchiveFile.bytes(name, Uint8List.fromList(utf8.encode(content))),
    );
  });
  extra.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(content)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
