import '../services/table_of_contents.dart';
import '../services/document_timeline.dart';
import '../services/markdown_table_lines.dart';
import '../services/pentest_blocks.dart';

/// Inline-code-spans: `` `…` `` op één regel. De inhoud reist als `code`-
/// attribuut door Quill en is platte tekst — hoekhaakjes en backslash-escapes
/// daarbinnen zijn géén HTML of ontsnapping. Zonder deze stripping gaf
/// `` `<persoon01>` `` een false positive die het hele document terug in
/// de bronmodus wierp (#1761).
final _inlineCode = RegExp(r'`[^`\n]+`');

// Alleen HTML-*commentaar* (`<!-- … -->`) is een beperking: dat is metadata
// (marp `<!-- _class: lead -->`, niet-herkende `<!-- toc -->`-varianten) die
// in de bron hoort, niet als letterlijke tekst in de visuele editor. HTML-*tags*
// (`<persoon1>`, `<br>`, `<div>`, …) reizen als platte tekst door de
// Markdown↔Quill codec en round-trippen byte-getrouw — geverifieerd voor de
// volle tag-reeks. Ze vroeger als `rawHtml` flaggen trapte een privacy-
// redactieconventie als `<persoon1>` de visuele modus uit (#1777).
final _rawHtml = RegExp(r'<!--');
final _escapedPunctuation = RegExp(r'\\[\\`*{}\[\]()#+.!_>-]');

/// Constructs that the current rich-text bridge cannot round-trip without
/// changing the author's Markdown source.
///
/// A GFM table is deliberately **absent** here: it round-trips losslessly as an
/// `x-embed-table` block embed (see `MarkdownQuillCodec` / `TableEmbedBuilder`),
/// so it is rendered and editable in the visual editor instead of forcing a
/// fall back to raw Markdown. Dat geldt voor de tabel als geheel: zijn regels
/// worden hieronder overgeslagen zolang ze bij zo'n blok horen — zie
/// [opensAtomicMarkdownTable] — en een tabelregel die er *niet* bij hoort levert
/// juist [MarkdownVisualLimitation.looseTableLine] op.
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
enum MarkdownVisualLimitation { rawHtml, escapedPunctuation, looseTableLine }

Set<MarkdownVisualLimitation> markdownVisualLimitations(String markdown) {
  final limitations = <MarkdownVisualLimitation>{};
  final lines = markdown.split('\n');
  // Eén extra lineaire pas, dezelfde orde als de lus hieronder. Bewust geen
  // echte Markdown-parse: deze functie draait per toetsaanslag over de hele
  // documenttekst.
  final pentest = scanPentestBlocks(markdown);
  var fenced = false;
  var inTable = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    // Wat als één embed reist, gaat nooit door de rijke-tekstconversie en kan
    // daar dus ook niet stukgaan.
    if (pentest.isAtomicLine(index)) continue;
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      inTable = false;
      continue;
    }
    if (fenced) continue;
    // Een GFM-tabel reist als één `x-embed-table`-blok — precies de reden dat
    // hij niet in deze opsomming staat. Zijn regels horen dus ook niet gescand
    // te worden: een `<br>` uit een celregeleinde en de `\|`, `\\` en `\<` van
    // `encodeMarkdownTableCell` zijn de eigen schrijfwijze van dat blok, niet
    // rauwe HTML of een ontsnapping van de rijke-tekstlaag. Zonder deze
    // uitzondering wierp één regeleinde of één backslash in een cel het hele
    // document terug in de brontekst, zichtbaar noch omkeerbaar (#1565).
    if (inTable) {
      if (isMarkdownTableLine(line)) continue;
      inTable = false;
    }
    if (opensAtomicMarkdownTable(
      line,
      index + 1 < lines.length ? lines[index + 1] : null,
    )) {
      inTable = true;
      continue;
    }
    // Een tabelregel die *niet* zo'n blok opent of voortzet, is juist gevaarlijk:
    // `_normalizeQuillOutput` laat de ontsnappingen van de rijke-tekstlaag op
    // elke regel die met een pijp begint bewust staan — dáár betekent `\|`
    // immers structuur. Staat die regel niet in een tabel die als blok reist,
    // dan blijven Quills `\-` en `\.` er dus in staan en verandert de tekst van
    // de gebruiker. Zichtbaar terugvallen op de bron is dan het enige eerlijke
    // antwoord; stil doorgaan sloopt de tabel (zoals bij een kop en een
    // scheidingsrij die niet even breed zijn).
    if (isMarkdownTableLine(line)) {
      limitations.add(MarkdownVisualLimitation.looseTableLine);
      continue;
    }
    var supportedTimeline = false;
    if (line.trim() == documentTimelineMarker) {
      final header = index + 1 < lines.length ? lines[index + 1] : null;
      final delimiter = index + 2 < lines.length ? lines[index + 2] : null;
      // Ook een gemarkeerde tabel die nog niet geschikt is blijft één visueel
      // embed. Zo kan de gebruiker hem in de gewone tabeleditor herstellen;
      // terugvallen naar bronmodus zou juist de vriendelijke foutweg wegnemen.
      supportedTimeline = isDocumentTimelineEnvelope(line, header, delimiter);
    }
    // Strip inline code voordat we op HTML/escapes checken: de inhoud van
    // `` `…` `` is platte tekst in Quill, geen Markdown-syntax.
    final lineWithoutCode = line.replaceAll(_inlineCode, '');
    if (!tocMarkerLinePattern.hasMatch(line) &&
        !supportedTimeline &&
        _rawHtml.hasMatch(lineWithoutCode)) {
      limitations.add(MarkdownVisualLimitation.rawHtml);
    }
    if (_escapedPunctuation.hasMatch(lineWithoutCode)) {
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

/// De eerste regel die een visuele beperking veroorzaakt, met het soort
/// beperking en het 0-gebaseerde regelnummer in de bron. `null` wanneer het
/// document verliesvrij door de rijke-tekstlaag kan.
///
/// Dezelfde scanlogica en -volgorde als [markdownVisualLimitations], maar
/// stopt bij de eerste hit. De documenteditor gebruikt dit om bij een
/// fallback automatisch naar de Bron-modus te wisselen en de cursor op de
/// probleemregel te zetten — zodat de gebruiker niet hoeft te raden wáár het
/// misgaat.
VisualLimitationHit? firstVisualLimitation(String markdown) {
  final lines = markdown.split('\n');
  final pentest = scanPentestBlocks(markdown);
  var fenced = false;
  var inTable = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (pentest.isAtomicLine(index)) continue;
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      inTable = false;
      continue;
    }
    if (fenced) continue;
    if (inTable) {
      if (isMarkdownTableLine(line)) continue;
      inTable = false;
    }
    if (opensAtomicMarkdownTable(
      line,
      index + 1 < lines.length ? lines[index + 1] : null,
    )) {
      inTable = true;
      continue;
    }
    if (isMarkdownTableLine(line)) {
      return VisualLimitationHit(
        index,
        MarkdownVisualLimitation.looseTableLine,
      );
    }
    var supportedTimeline = false;
    if (line.trim() == documentTimelineMarker) {
      final header = index + 1 < lines.length ? lines[index + 1] : null;
      final delimiter = index + 2 < lines.length ? lines[index + 2] : null;
      supportedTimeline = isDocumentTimelineEnvelope(line, header, delimiter);
    }
    final lineWithoutCode = line.replaceAll(_inlineCode, '');
    if (!tocMarkerLinePattern.hasMatch(line) &&
        !supportedTimeline &&
        _rawHtml.hasMatch(lineWithoutCode)) {
      return VisualLimitationHit(index, MarkdownVisualLimitation.rawHtml);
    }
    if (_escapedPunctuation.hasMatch(lineWithoutCode)) {
      return VisualLimitationHit(
        index,
        MarkdownVisualLimitation.escapedPunctuation,
      );
    }
  }
  return null;
}

/// Eén gevonden beperking: het soort en de regel waarop het eerste probleem
/// zit. Zie [firstVisualLimitation].
class VisualLimitationHit {
  const VisualLimitationHit(this.lineIndex, this.limitation);

  /// 0-gebaseerd regelnummer in de bron (zoals `source.split('\n')` indexeert).
  final int lineIndex;

  /// Het soort beperking dat op [lineIndex] werd aangetroffen.
  final MarkdownVisualLimitation limitation;
}
