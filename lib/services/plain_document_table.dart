import 'package:markdown/markdown.dart' as md;

import 'markdown_table_lines.dart';

const plainDocumentTableMarker = '<!-- ocideck:plain_table v1 -->';
const plainDocumentTableAttribute = 'ocideck-plain-table';

bool opensPlainDocumentTable(String line, String? header, String? delimiter) =>
    line.trim() == plainDocumentTableMarker &&
    header != null &&
    opensAtomicMarkdownTable(header, delimiter);

String plainDocumentTableBody(String source) =>
    source.startsWith(plainDocumentTableMarker)
    ? source.substring(plainDocumentTableMarker.length + 1)
    : source;

/// Gebruik dezelfde GFM-node voor een blanco tabel. Alleen de vormgeving wijkt af.
class PlainDocumentTableSyntax extends md.BlockSyntax {
  const PlainDocumentTableSyntax({this.embedTag});

  final String? embedTag;

  static final _pattern = RegExp('^ *$plainDocumentTableMarker *\$');

  @override
  RegExp get pattern => _pattern;

  @override
  bool canParse(md.BlockParser parser) => opensPlainDocumentTable(
    parser.current.content,
    parser.peek(1)?.content,
    parser.peek(2)?.content,
  );

  @override
  md.Node? parse(md.BlockParser parser) {
    final marker = parser.current.content.trim();
    parser.advance();
    if (embedTag case final tag?) {
      final source = StringBuffer(marker);
      while (!parser.isDone && isMarkdownTableLine(parser.current.content)) {
        source.write('\n${parser.current.content}');
        parser.advance();
      }
      return md.Element.empty(tag)..attributes['data'] = source.toString();
    }
    final table = const md.TableSyntax().parse(parser);
    if (table is md.Element) table.attributes[plainDocumentTableAttribute] = '';
    return table;
  }
}
