import 'package:flutter_quill/flutter_quill.dart' hide Node;
import 'package:markdown/markdown.dart';

import '../services/document_timeline.dart';
import '../services/markdown_table_codec.dart';

/// Houdt een gemarkeerde tijdlijntabel als één atomair Quill-blok bijeen.
/// Daardoor kan de visuele editor nooit een lege regel tussen marker en tabel
/// schrijven en blijft verwijderen/ongedaan maken één documenthandeling.
class TimelineTableSyntax extends BlockSyntax {
  const TimelineTableSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<!-- timeline -->\s*$');

  @override
  bool canEndBlock(BlockParser parser) => false;

  @override
  bool canParse(BlockParser parser) {
    final header = parser.peek(1)?.content;
    final delimiter = parser.peek(2)?.content;
    return isDocumentTimelineEnvelope(
      parser.current.content,
      header,
      delimiter,
    );
  }

  @override
  Node? parse(BlockParser parser) {
    final value = StringBuffer(parser.current.content);
    parser.advance();
    while (!parser.isDone && isMarkdownTableLine(parser.current.content)) {
      value.write('\n${parser.current.content}');
      parser.advance();
    }
    return Element.empty(EmbeddableTimelineTable.timelineType)
      ..attributes['data'] = value.toString();
  }
}

class EmbeddableTimelineTable extends BlockEmbed {
  static const timelineType = 'x-embed-document-timeline';

  EmbeddableTimelineTable(String data) : super(timelineType, data);

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableTimelineTable fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableTimelineTable(attributes['data']!);

  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(embed.value.data)
      ..writeln();
  }
}
