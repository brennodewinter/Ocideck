import '../services/table_of_contents.dart';
import '../services/document_timeline.dart';

/// Constructs that the current rich-text bridge cannot round-trip without
/// changing the author's Markdown source.
///
/// A GFM table is deliberately **absent** here: it round-trips losslessly as an
/// `x-embed-table` block embed (see `MarkdownQuillCodec` / `TableEmbedBuilder`),
/// so it is rendered and editable in the visual editor instead of forcing a
/// fall back to raw Markdown.
///
/// Om dezelfde reden is de inhoudsopgave-marker `<!-- toc -->` géén `rawHtml`:
/// hij reist als `x-embed-toc`-blok mee (zie `MarkdownQuillCodec` /
/// `TocEmbedBuilder`). Zonder die uitzondering wierp één ingevoegde
/// inhoudsopgave het hele document terug in de brontekst.
///
/// En om dezelfde reden staat de **voetnoot** hier niet meer: `[^1]` reist als
/// inline-embed en `[^1]: …` als blok-embed (`FootnoteRefSyntax` /
/// `FootnoteDefSyntax`). Tot die embeds er waren, was één voetnoot genoeg om de
/// hele visuele modus op brontekst terug te werpen — precies bij de functie
/// waarvoor je hem het hardst nodig hebt.
enum MarkdownVisualLimitation { rawHtml, escapedPunctuation }

Set<MarkdownVisualLimitation> markdownVisualLimitations(String markdown) {
  final limitations = <MarkdownVisualLimitation>{};
  final lines = markdown.split('\n');
  var fenced = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    var supportedTimeline = false;
    if (line.trim() == documentTimelineMarker) {
      var end = index + 1;
      while (end < lines.length && lines[end].trimLeft().startsWith('|')) {
        end++;
      }
      supportedTimeline = analyzeMarkedTimeline(
        lines.sublist(index, end).join('\n'),
      ).isUsable;
    }
    if (!tocMarkerLinePattern.hasMatch(line) &&
        !supportedTimeline &&
        RegExp(r'<!--|</?[A-Za-z][^>]*>').hasMatch(line)) {
      limitations.add(MarkdownVisualLimitation.rawHtml);
    }
    if (RegExp(r'\\[\\`*{}\[\]()#+.!_>-]').hasMatch(line)) {
      limitations.add(MarkdownVisualLimitation.escapedPunctuation);
    }
  }
  return limitations;
}

/// Of [markdown] in zijn geheel door de rijke-tekstlaag kan — oftewel: of de
/// visuele stand echt de WYSIWYG-editor toont in plaats van de brontekst-
/// terugval. De aanroeper die moet weten *waar* de tekst leeft (Quill of de
/// bron-controller) heeft aan die ja/nee genoeg.
bool markdownRoundTripsVisually(String markdown) =>
    markdownVisualLimitations(markdown).isEmpty;
