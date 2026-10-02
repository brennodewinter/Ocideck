// Een minimale, echte `.ods` voor de spreadsheet-importtests: een
// office:spreadsheet met één of meer `table:table`-bladen.
//
// Bewust een echt archief en geen namaak: de tests gaan door dezelfde parser
// als de gebruiker.
import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';

const _office = 'urn:oasis:names:tc:opendocument:xmlns:office:1.0';
const _text = 'urn:oasis:names:tc:opendocument:xmlns:text:1.0';
const _table = 'urn:oasis:names:tc:opendocument:xmlns:table:1.0';

/// Bouw een `.ods`. [sheets] is `naam → rijen-XML` (de `table:table-row`-
/// elementen die onder `table:table` komen). [extra] voegt ruwe delen toe.
Uint8List odsFixture({
  Map<String, String> sheets = const {
    'Blad1':
        '<table:table-row>'
        '<table:table-cell><text:p>Kolom</text:p></table:table-cell>'
        '<table:table-cell><text:p>Waarde</text:p></table:table-cell>'
        '</table:table-row>'
        '<table:table-row>'
        '<table:table-cell><text:p>A</text:p></table:table-cell>'
        '<table:table-cell office:value-type="float" office:value="42">'
        '<text:p>42</text:p></table:table-cell>'
        '</table:table-row>',
  },
  Map<String, List<int>> extra = const {},
}) {
  final contentXml =
      '<?xml version="1.0" encoding="UTF-8"?>'
      '<office:document-content xmlns:office="$_office" xmlns:text="$_text" '
      'xmlns:table="$_table">'
      '<office:body><office:spreadsheet>'
      '${[for (final e in sheets.entries) '<table:table table:name="${e.key}">${e.value}</table:table>'].join()}'
      '</office:spreadsheet></office:body>'
      '</office:document-content>';

  final archive = Archive();
  archive.addFile(
    ArchiveFile.bytes(
      'mimetype',
      Uint8List.fromList(
        utf8.encode('application/vnd.oasis.opendocument.spreadsheet'),
      ),
    ),
  );
  archive.addFile(
    ArchiveFile.bytes(
      'content.xml',
      Uint8List.fromList(utf8.encode(contentXml)),
    ),
  );
  extra.forEach((name, content) {
    archive.addFile(ArchiveFile.bytes(name, Uint8List.fromList(content)));
  });
  return Uint8List.fromList(ZipEncoder().encode(archive));
}
