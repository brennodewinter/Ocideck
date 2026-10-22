import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

import '../services/transcription/transcript_marker.dart';

/// De `<!-- transcript … -->`-marker als blok-embed in de rijke-tekstlaag,
/// naar het model van `x-embed-toc` en `x-embed-spacer`.
///
/// De marker is HTML-commentaar, en dat was tot #2463 reden om de hele
/// visuele modus op brontekst terug te laten vallen. Sindsdien zou hij een
/// bronfragment worden — byte-getrouw, maar de auteur staarde naar een
/// `<!-- … -->`-vlak alsof daar iets kapots zat. Als eigen embed is de
/// marker atomair (één blok, één Delete) én toont hij wat hij is: het
/// bewijs dat dit document uit een transcriptie komt. Alleen de *geldige*
/// grammatica reist zo; een bijna-marker blijft gewoon bronfragment —
/// die hoort eruit te zien als wat hij is: rauwe bron (#2511, §14.14).
class EmbeddableTranscript extends BlockEmbed {
  EmbeddableTranscript(String markerLine) : super(transcriptType, markerLine);

  /// [Embeddable]-type van de transcript-marker.
  static const transcriptType = 'x-embed-transcript';

  /// De `data` is de verbatim markerregel — attributen en al.
  static EmbeddableTranscript fromMdSyntax(Map<String, String> attributes) =>
      EmbeddableTranscript(attributes['data'] ?? '');

  /// Terug naar markdown: exact de regel die er lag, zonder eigen
  /// regeleinde — `DeltaToMarkdown` sluit het blok zelf af.
  static void toMdSyntax(Embed embed, StringSink out) {
    out.write(embed.value.data);
  }
}

/// Herkent een regel die alleen een geldige transcript-marker bevat en maakt
/// er een [EmbeddableTranscript] van, vóórdat de HTML-blokregel van de
/// markdown-parser hem als rauwe HTML opslokt.
class TranscriptMarkerSyntax extends md.BlockSyntax {
  const TranscriptMarkerSyntax();

  @override
  RegExp get pattern => transcriptMarkerLinePattern;

  @override
  md.Node? parse(md.BlockParser parser) {
    final line = parser.current.content.trim();
    parser.advance();
    // In een alinea gewikkeld, en niet kaal: `MarkdownToDelta` sluit een blok
    // met een eigen regel af voor `hr`, voor de tabel-embed, en voor een
    // alinea die alleen embeds bevat. Een kale embed erft anders de
    // blokopmaak van de volgende regel — een marker vóór een `##`-kop werd
    // dan zelf een kop.
    return md.Element('p', [
      md.Element.empty(EmbeddableTranscript.transcriptType)
        ..attributes['data'] = line,
    ]);
  }
}
