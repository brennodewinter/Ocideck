import 'package:flutter_quill/flutter_quill.dart' hide Node;
import 'package:markdown/markdown.dart';

import '../services/markdown_table_codec.dart';
import '../services/ocideck_markers.dart';

/// Houdt een `<!-- ocideck:* -->`-markerblok en de contracttabel eronder als
/// één atomair Quill-blok bijeen — hetzelfde mechanisme als
/// [TimelineTableSyntax], dan kan verwijderen/ongedaan maken nooit de marker
/// van zijn tabel scheiden (RISK_FORMAT §5.1).
///
/// De embed vat de échte bindingsvorm samen: markerregels, witregels en de
/// tabel zelf reizen als één `data`-string. Een marker die níét aan een
/// tabel bindt valt hier buiten en reist als bronfragment — bewust, want
/// een weesmarker is inhoudelijk iets anders dan een tabelcontract.
class OciMarkedTableSyntax extends BlockSyntax {
  const OciMarkedTableSyntax();

  @override
  RegExp get pattern => RegExp(r'^\s*<!--\s*ocideck:[a-z]');

  @override
  bool canEndBlock(BlockParser parser) => false;

  @override
  bool canParse(BlockParser parser) {
    if (!isOciTableMarkerLine(parser.current.content)) return false;
    var i = 1;
    while (true) {
      final line = parser.peek(i)?.content;
      if (line == null) return false;
      if (isOciTableMarkerLine(line)) {
        i++;
        continue;
      }
      if (line.trim().isEmpty) {
        i++;
        continue;
      }
      // De eerste niet-marker, niet-lege regel moet een tabelkop openen met
      // de scheidingsrij eronder (§5.1).
      return isMarkdownTableLine(line) &&
          isMarkdownTableDelimiterRow(parser.peek(i + 1)?.content ?? '');
    }
  }

  @override
  Node? parse(BlockParser parser) {
    final value = StringBuffer(parser.current.content);
    parser.advance();
    // De hele envelop — markerregels, witregels en tabel — hoort bij één
    // blok. Zonder de witregels mee te nemen zou de codec ze als
    // blokscheiding terugschrijven en de marker óók bij een tabel kunnen
    // plaatsen die er niet bij hoorde.
    var inMarkers = true;
    while (!parser.isDone) {
      final line = parser.current.content;
      if (inMarkers && (isOciTableMarkerLine(line) || line.trim().isEmpty)) {
        value.write('\n$line');
        parser.advance();
        continue;
      }
      inMarkers = false;
      if (isMarkdownTableLine(line)) {
        value.write('\n$line');
        parser.advance();
        continue;
      }
      break;
    }
    // In een alinea gewikkeld, om dezelfde reden als tijdlijn en TOC: een
    // kale embed erft de blokopmaak van de volgende regel.
    return Element('p', [
      Element.empty(EmbeddableOciMarkedTable.blockType)
        ..attributes['data'] = value.toString(),
    ]);
  }
}

class EmbeddableOciMarkedTable extends BlockEmbed {
  static const blockType = 'x-embed-ocideck-table';

  EmbeddableOciMarkedTable(String data) : super(blockType, data);

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableOciMarkedTable fromMdSyntax(
    Map<String, String> attributes,
  ) => EmbeddableOciMarkedTable(attributes['data']!);

  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(embed.value.data)
      ..writeln();
  }
}
