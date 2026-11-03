/// De ```chart-fence als blok-embed in de rijke-tekstlaag.
///
/// Zelfde contract als [EmbeddableMermaid]: een ```chart-fence is draagbare
/// Markdown, maar de visuele editor toonde hem als monospace bron terwijl
/// lezer, voorvertoning, Pagina's, PDF en HTML-export de grafiek tekenden
/// (#2751). De embed draagt de héle fence — openingsregel, inhoud, sluitregel
/// — en [EmbeddableChart.toMdSyntax] schrijft die verbatim terug; de
/// rijke-tekstlaag komt er niet aan, zodat elke YAML-achtige waarde een
/// rondgang door de visuele editor ongeschonden overleeft.
library;

import 'package:flutter_quill/flutter_quill.dart' hide Node;
import 'package:markdown/markdown.dart';

/// Een fence-openingsregel die `chart` als taal noemt: ` ```chart `, eventueel
/// met spaties. Extra info-woorden achter de taal horen bij een gewoon
/// codeblok — die laat deze syntax met opzet liggen.
final RegExp chartFenceOpenPattern = RegExp(r'^\s{0,3}```[ \t]*chart[ \t]*$');

final RegExp _chartFenceClosePattern = RegExp(r'^\s{0,3}```[ \t]*$');

/// Herkent een volledige ```chart-fence en maakt er één [EmbeddableChart] van,
/// vóórdat de standaard-fenceregel er een codeblok van maakt.
class ChartFenceSyntax extends BlockSyntax {
  const ChartFenceSyntax();

  @override
  RegExp get pattern => chartFenceOpenPattern;

  /// Een fence eindigt niet op een lege regel.
  @override
  bool canEndBlock(BlockParser parser) => false;

  @override
  Node? parse(BlockParser parser) {
    final value = StringBuffer(parser.current.content);
    parser.advance();
    while (!parser.isDone &&
        !_chartFenceClosePattern.hasMatch(parser.current.content)) {
      value.write('\n${parser.current.content}');
      parser.advance();
    }
    if (!parser.isDone) {
      value.write('\n${parser.current.content}');
      parser.advance();
    }
    // In een alinea gewikkeld om blokopmaak-lekkage te voorkomen (#1709).
    return Element('p', [
      Element.empty(EmbeddableChart.chartType)
        ..attributes['data'] = value.toString(),
    ]);
  }
}

/// De fence als blok-embed. `data` is de fence inclusief beide ```-regels.
class EmbeddableChart extends BlockEmbed {
  EmbeddableChart(String data) : super(chartType, data);

  /// [Embeddable]-type van de chart-fence.
  static const chartType = 'x-embed-chart';

  // Statische fabrieken zijn het contract van markdown_quill.
  // ignore: prefer_constructors_over_static_methods
  static EmbeddableChart fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableChart(attributes['data']!);

  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(embed.value.data)
      ..writeln();
  }
}
