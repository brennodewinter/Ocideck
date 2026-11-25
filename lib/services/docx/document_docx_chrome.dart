import 'markdown_to_docx.dart';

/// `word/header1.xml` of `word/footer1.xml`: elke chrome-regel een alinea
/// in de bandstijl, met inline-markdown als runs (#3166).
String buildDocxBandXml(String tag, String text) {
  final lines = text
      .split('\n')
      .map(
        (line) =>
            '<w:p><w:pPr><w:pStyle w:val="${tag == 'hdr' ? 'Header' : 'Footer'}"/></w:pPr>'
            '${markdownToDocxInline(line)}</w:p>',
      )
      .join();
  return '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
      '<w:$tag xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">'
      '$lines'
      '</w:$tag>';
}
