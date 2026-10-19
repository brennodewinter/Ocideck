import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;

import 'markdown_visual_compatibility.dart';

/// De sentinel waarmee [wrapSourceFragments] een bronfragment afbakent vóór
/// de parse. Alleen hoofdletters — de markdown-parser laat hem als gewone
/// tekst staan, net als de andere OCIDECK-sentinels in deze keten. Het paar
/// reist óók mee in de uitvoer van `DeltaToMarkdown`: daar herkent
/// `_normalizeQuillOutput` het aan, laat het de inhoud verbatim en stript de
/// markerregels, zodat ze nooit in het bestand van de gebruiker belanden.
const sourceFragmentBegin = 'OCIDECKSOURCEFRAGMENTBEGIN';
const sourceFragmentEnd = 'OCIDECKSOURCEFRAGMENTEND';

final _beginLine = RegExp('^$sourceFragmentBegin\$');
final _endLine = RegExp('^$sourceFragmentEnd\$');

/// Zet sentinelregels om elke regelreeks die de rijke-tekstlaag niet
/// verliesvrij kan dragen — zie [sourceFragmentRanges]. De [SourceFragmentSyntax]
/// claimt zo'n bereik vervolgens als één embed met de bron verbatim.
///
/// De omwegen via sentinels (en niet een syntax die zelf de grens zoekt) is
/// bewust: dan is er één autoriteit voor de fragmentgrenzen — dezelfde scan
/// die de visuele poort voedde — en hoeft de syntax niets van escapes,
/// tabelregels of commentaar te weten.
String wrapSourceFragments(String markdown) {
  final ranges = sourceFragmentRanges(markdown);
  if (ranges.isEmpty) return markdown;
  final lines = markdown.split('\n');
  final out = StringBuffer();
  var cursor = 0;
  for (final (start, end) in ranges) {
    for (var i = cursor; i < start; i++) {
      out.writeln(lines[i]);
    }
    out
      ..writeln(sourceFragmentBegin)
      ..writeln(lines.sublist(start, end).join('\n'))
      ..writeln(sourceFragmentEnd);
    cursor = end;
  }
  for (var i = cursor; i < lines.length; i++) {
    out.write(lines[i]);
    if (i < lines.length - 1) out.write('\n');
  }
  return out.toString();
}

/// Een brok brontekst die niet verliesvrij als rijke tekst kan reizen — een
/// HTML-commentaarblok, een alinea met een ontsnapt leesteken, een losse
/// tabelregel (#2463). In plaats van het hele document naar Bron te schakelen
/// wordt alleen dít stuk een atomaire embed: de rest van het document blijft
/// visueel bewerkbaar, en de bron komt er byte-getrouw weer uit.
///
/// De `data` is letterlijk de bron — geen vormgeving, geen vertaling. Bewerken
/// gebeurt in de visuele editor via het eigen bronvlak van de builder; komt de
/// inhoud binnen de grenzen van de rijke-tekstlaag, dan lost het fragment daar
/// weer op in gewone blokken.
class EmbeddableSourceFragment extends BlockEmbed {
  EmbeddableSourceFragment(String data) : super(fragmentType, data);

  /// [Embeddable]-type van het bronfragment.
  static const fragmentType = 'x-embed-source-fragment';

  static EmbeddableSourceFragment fromMdSyntax(
    Map<String, String> attributes,
  ) => EmbeddableSourceFragment(attributes['data'] ?? '');

  /// Schrijft de bron verbatim terug — gewikkeld in het sentinelpaar, zodat de
  /// uitgaande normalisatie de inhoud niet aanraakt. De sentinels worden vlak
  /// voor de terugkeer uit de uitvoer gestript.
  static void toMdSyntax(Embed embed, StringSink out) {
    out
      ..writeln(sourceFragmentBegin)
      ..writeln(embed.value.data)
      ..write(sourceFragmentEnd);
  }
}

/// Claimt een sentinel-omwikkeld bereik (zie [wrapSourceFragments]) en draagt
/// de regels ertussen verbatim als [EmbeddableSourceFragment]-data.
class SourceFragmentSyntax extends md.BlockSyntax {
  const SourceFragmentSyntax();

  @override
  RegExp get pattern => _beginLine;

  // De bron van een fragment kan witregels bevatten als die binnen het bereik
  // vielen; het bereik eindigt alleen op de eindsentinel.
  @override
  bool canEndBlock(md.BlockParser parser) => false;

  @override
  md.Node? parse(md.BlockParser parser) {
    parser.advance(); // BEGIN
    final data = StringBuffer();
    var first = true;
    while (!parser.isDone && !_endLine.hasMatch(parser.current.content)) {
      if (!first) data.write('\n');
      data.write(parser.current.content);
      parser.advance();
      first = false;
    }
    if (!parser.isDone) parser.advance(); // END
    // In een alinea gewikkeld om blokopmaak-lekkage te voorkomen — dezelfde
    // reden als bij de tabel- en formuliereeds: een kale embed erft de
    // `header`-stijl van de volgende regel.
    return md.Element('p', [
      md.Element.empty(EmbeddableSourceFragment.fragmentType)
        ..attributes['data'] = data.toString(),
    ]);
  }
}
