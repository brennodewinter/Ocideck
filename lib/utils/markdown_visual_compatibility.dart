import '../services/table_of_contents.dart';
import 'spacer_embed_syntax.dart';
import '../services/document_timeline.dart';
import '../services/markdown_table_lines.dart';
import '../services/ocideck_markers.dart';
import '../services/form_document_blocks.dart';
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
// Volledige CommonMark-interpunctieklasse — niet alleen de tekens die
// `DeltaToMarkdown` terug escapet. Ook `\;`, `\?`, `\~`, `\|` e.d. verdwijnen
// stil in de codec (de parser haalt de backslash weg, de schrijver zet hem
// nooit terug): precies de stille bronwijziging die een bronfragment juist
// moet voorkomen.
final _escapedPunctuation = RegExp(r'\\[!-/:-@\[-`{-~]');

/// Constructs that the current rich-text bridge cannot round-trip without
/// changing the author's Markdown source **als gewone tekst**.
///
/// A GFM table is deliberately **absent** here: it round-trips losslessly as an
/// `x-embed-table` block embed (see `MarkdownQuillCodec` / `TableEmbedBuilder`),
/// so it is rendered and editable in the visual editor instead of forcing a
/// fall back to raw Markdown. Dat geldt voor de tabel als geheel: zijn regels
/// worden hieronder overgeslagen zolang ze bij zo'n blok horen — zie
/// [opensAtomicMarkdownTable] — en een tabelregel die er *niet* bij hoort levert
/// juist een hit op.
///
/// Om dezelfde reden is de inhoudsopgave-marker `<!-- toc -->` géén `rawHtml`:
/// hij reist als `x-embed-toc`-blok mee (zie `MarkdownQuillCodec` /
/// `TocEmbedBuilder`). Zonder die uitzondering wierp één ingevoegde
/// inhoudsopgave het hele document terug in de brontekst. Hetzelfde geldt voor
/// de `<!-- spacer -->`-marker (`x-embed-spacer`, #2464).
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
///
/// Sinds #2463 is wat rest óók geen documentbrede blokkade meer: de regels
/// die deze pas aanwijst — HTML-commentaar, ontsnapte leestekens, losse
/// tabelregels — reizen als `x-embed-source-fragment`: een lokaal bronblok
/// midden in de visuele editor (zie [sourceFragmentRanges] en
/// `EmbeddableSourceFragment`).

/// De regelnummers (0-gebaseerd) die de rijke-tekstlaag niet verliesvrij
/// als gewone tekst kan dragen — de detector achter [sourceFragmentRanges].
/// Bewust geen echte Markdown-parse: de pas draait per toetsaanslag over de
/// hele documenttekst.
Set<int> _limitationLines(String markdown) {
  final hits = <int>{};
  final lines = markdown.split('\n');
  // Eén extra lineaire pas, dezelfde orde als de lus hieronder. Bewust geen
  // echte Markdown-parse: deze functie draait per toetsaanslag over de hele
  // documenttekst.
  final pentest = scanPentestBlocks(markdown);
  final forms = scanFormBlocks(markdown);
  var fenced = false;
  var inTable = false;
  // Regels binnen een atomaire `<!-- ocideck:* -->`-envelop (markerblok +
  // witregels + contracttabel, RISK_FORMAT §5) reizen als één
  // `x-embed-ocideck-table` en worden niet apart gescand — een marker of een
  // cel-ontsnapping is daar eigen schrijfwijze, geen rauwe invoer.
  var ociEnvelopeUntil = -1;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (index <= ociEnvelopeUntil) continue;
    // Wat als één embed reist, gaat nooit door de rijke-tekstconversie en kan
    // daar dus ook niet stukgaan.
    if (pentest.isAtomicLine(index) || forms.isAtomicLine(index)) continue;
    if (RegExp(r'^\s*```').hasMatch(line)) {
      fenced = !fenced;
      inTable = false;
      continue;
    }
    if (fenced) continue;
    if (isOciTableMarkerLine(line)) {
      var j = index + 1;
      while (j < lines.length &&
          (isOciTableMarkerLine(lines[j]) || lines[j].trim().isEmpty)) {
        j++;
      }
      if (j + 1 < lines.length &&
          isMarkdownTableLine(lines[j]) &&
          isMarkdownTableDelimiterRow(lines[j + 1])) {
        var end = j + 2;
        while (end < lines.length && isMarkdownTableLine(lines[end])) {
          end++;
        }
        ociEnvelopeUntil = end - 1;
        continue;
      }
      // Een weesmarker bindt niet en is wél gewoon gescand commentaar —
      // die hoort zichtbaar bron te blijven (bronfragment).
    }
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
      hits.add(index);
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
        !spacerMarkerLinePattern.hasMatch(line) &&
        !supportedTimeline &&
        _rawHtml.hasMatch(lineWithoutCode)) {
      hits.add(index);
    }
    if (_escapedPunctuation.hasMatch(lineWithoutCode)) {
      hits.add(index);
    }
  }
  return hits;
}

/// Een regel die een eigen blok opent en daarom een fragmentgrens is: bij
/// een uitbreiding over zo'n regel zou het fragment een heel ander blok
/// meeslepen dat op zichzelf wél verliesvrij reist (een kop, een atomaire
/// tabel, een voetnootdefinitie, een marker). Binnen een brok blijft alles
/// bij elkaar — een lijstregel of een vervolgregel is géén grens.
bool _isFragmentBoundary(
  String line,
  String? next,
  bool Function(int) isAtomicLine,
  int index,
) {
  if (line.trim().isEmpty) return true;
  if (isAtomicLine(index)) return true;
  if (RegExp(r'^\s*(```|~~~)').hasMatch(line)) return true;
  if (RegExp(r'^\s{0,3}#{1,6}\s').hasMatch(line)) return true;
  if (RegExp(r'^\s{0,3}(-{3,}|\*{3,}|_{3,})\s*$').hasMatch(line)) return true;
  if (RegExp(r'^\s{0,3}\[\^[^\]]+\]:').hasMatch(line)) return true;
  if (tocMarkerLinePattern.hasMatch(line) ||
      spacerMarkerLinePattern.hasMatch(line) ||
      line.trim() == documentTimelineMarker ||
      isOciTableMarkerLine(line)) {
    return true;
  }
  return opensAtomicMarkdownTable(line, next);
}

/// De regelbereiken `[start, end)` die als bronfragment reizen — zie
/// [EmbeddableSourceFragment] (`x-embed-source-fragment`).
///
/// Eén bereik per aaneengesloten brok om elke regel die [_limitationLines]
/// aanwijst: vanaf de probleemregel naar boven en beneden tot de eerste
/// witregel of blokgrens. Witregel-begrensd is de enige grens die in beide
/// richtingen byte-getrouw is — blok-embeds worden altijd met een witregel
/// ertussen geschreven — en een bredere brok kan hooguit méér bron tonen dan
/// strikt nodig, nooit tekst kwijtraken.
///
/// Grensregels zijn koppen, fences, regels die een atomaire tabel of een
/// atomaire form/pentest-envelop openen, voetnootdefinities, `---` en de
/// herkende `<!-- toc -->`/`<!-- spacer -->`/tijdlijn-markers: die reizen zelf
/// al verliesvrij en horen niet in het bronblok thuis. Lijst- en
/// citaatregels zijn bewust géén grens — ze zijn in Markdown één blok met hun
/// vervolgregels, dus uitknippen zou de rondreis breken.
List<(int, int)> sourceFragmentRanges(String markdown) {
  final lines = markdown.split('\n');
  final hits = _limitationLines(markdown);
  if (hits.isEmpty) return const [];
  final pentest = scanPentestBlocks(markdown);
  final forms = scanFormBlocks(markdown);
  bool isAtomic(int i) => pentest.isAtomicLine(i) || forms.isAtomicLine(i);

  final ranges = <(int, int)>[];
  for (final index in hits.toList()..sort()) {
    var start = index;
    var end = index + 1;
    while (start > 0 &&
        lines[start - 1].trim().isNotEmpty &&
        !_isFragmentBoundary(
          lines[start - 1],
          lines[start],
          isAtomic,
          start - 1,
        )) {
      start--;
    }
    while (end < lines.length &&
        lines[end].trim().isNotEmpty &&
        !_isFragmentBoundary(
          lines[end],
          end + 1 < lines.length ? lines[end + 1] : null,
          isAtomic,
          end,
        )) {
      end++;
    }
    // Grenzend of overlappend met het vorige bereik → samenvoegen: twee
    // probleemregels in dezelfde brok vormen één bronblok.
    if (ranges.isNotEmpty && start <= ranges.last.$2) {
      final last = ranges.last;
      ranges[ranges.length - 1] = (last.$1, end > last.$2 ? end : last.$2);
    } else {
      ranges.add((start, end));
    }
  }
  return ranges;
}
