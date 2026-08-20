import '../services/table_of_contents.dart';
import '../services/document_timeline.dart';
import '../services/pentest_blocks.dart';

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
/// En sinds de pentestgrammatica geldt dezelfde uitzondering voor de bereiken
/// die als één **atomaire embed** reizen (PENTEST_DOCUMENT.md §5.5). De regel is
/// bewust "atomair gedragen" en niet "envelop herkend": overslaan zonder
/// atomiciteit is stille corruptie. `DeltaToMarkdown` escapet elk leesteken en
/// `_normalizeQuillOutput` haalt die escapes buiten tabelregels weer weg, dus
/// een `\## Kop` uit een sectietekst komt er als échte sectiekop uit en de
/// tekst eronder verhuist naar een ander veld. Wat niet atomair reist, wordt dus
/// gewoon gescand — ook een **weesmarker**. Die valt terug op brontekst, en dat
/// is precies goed: een half gesloopte envelop hoort zichtbaar kapot te zijn,
/// niet stilletjes iets te verliezen. (Het contractvoorstel om élke markerregel
/// onvoorwaardelijk vrij te stellen is daarom niet overgenomen.)
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
  // Eén extra lineaire pas, dezelfde orde als de lus hieronder. Bewust geen
  // echte Markdown-parse: deze functie draait per toetsaanslag over de hele
  // documenttekst.
  final pentest = scanPentestBlocks(markdown);
  var fenced = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    // Wat als één embed reist, gaat nooit door de rijke-tekstconversie en kan
    // daar dus ook niet stukgaan.
    if (pentest.isAtomicLine(index)) continue;
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      continue;
    }
    if (fenced) continue;
    var supportedTimeline = false;
    if (line.trim() == documentTimelineMarker) {
      final header = index + 1 < lines.length ? lines[index + 1] : null;
      final delimiter = index + 2 < lines.length ? lines[index + 2] : null;
      // Ook een gemarkeerde tabel die nog niet geschikt is blijft één visueel
      // embed. Zo kan de gebruiker hem in de gewone tabeleditor herstellen;
      // terugvallen naar bronmodus zou juist de vriendelijke foutweg wegnemen.
      supportedTimeline = isDocumentTimelineEnvelope(line, header, delimiter);
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
