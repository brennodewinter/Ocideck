import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import '../services/form_document_blocks.dart';
import '../services/pentest_blocks.dart';
import 'footnote_embed_syntax.dart';
import 'form_block_embed_syntax.dart';
import 'image_embed_syntax.dart';
import 'list_block_embed_syntax.dart';
import 'markdown_paste_cleanup.dart';
import 'mermaid_embed_syntax.dart';
import 'pentest_block_embed_syntax.dart';
import 'source_fragment_embed_syntax.dart';
import 'toc_embed_syntax.dart';
import 'spacer_embed_syntax.dart';
import 'transcript_embed_syntax.dart';
import 'ocideck_table_embed_syntax.dart';
import 'timeline_table_embed_syntax.dart';

/// Round-trip conversion between stored markdown and a Quill document.
///
/// GFM-tabellen worden als **blok-embed** ([EmbeddableTable], type
/// `x-embed-table`) door de heen- en terugweg gedragen, in plaats van als losse
/// woorden uiteen te vallen. Zo blijft een tabel in de visuele editor een
/// getekend, byte-getrouw round-trippend blok — de reden dat de tabel niet meer
/// als markdown-beperking hoeft terug te vallen (zie `sourceFragmentRanges`).
///
/// De inhoudsopgave-marker `<!-- toc -->` reist langs dezelfde weg als
/// [EmbeddableToc] (`x-embed-toc`) — om dezelfde reden: hij is HTML, en zonder
/// deze embed viel de hele visuele modus terug op brontekst zodra iemand een
/// inhoudsopgave invoegde.
///
/// De **afbeelding** reist als inline-embed met haar hele markdown erin
/// ([EmbeddableMarkdownImage]). De standaardweg van `markdown_quill` maakt er
/// een `image`-embed van die alleen de bron draagt: die liet het schrijfvlak
/// omvallen (geen bouwer voor dat type) én gooide de alt-tekst weg.
///
/// Voetnoten idem, in twee delen: de verwijzing `[^1]` als inline-embed
/// ([EmbeddableFootnoteRef]) en de definitie `[^1]: …` als blok-embed
/// ([EmbeddableFootnoteDef]). Ook hier was één voetnoot genoeg om de hele
/// visuele modus op brontekst terug te werpen.
class MarkdownQuillCodec {
  MarkdownQuillCodec._();

  static final _mdDocument = md.Document(
    encodeHtml: false,
    extensionSet: md.ExtensionSet.gitHubFlavored,
    // Vóór de extensionSet toegevoegd → deze tabel-syntax wint van de standaard
    // en levert een `x-embed-table`-element met de rauwe tabel-markdown erin.
    // De TOC-marker staat vóór de HTML-blokregel, anders slokt die hem als
    // rauwe HTML op en valt hij als losse tekst uiteen.
    blockSyntaxes: const [
      // Eerst: de sentinelregels van `wrapSourceFragments` claimt niemand
      // anders, maar de syntax moet vóór de standaard-alinearegel staan.
      SourceFragmentSyntax(),
      TimelineTableSyntax(),
      // Het risicodossier-contract (RISK_FORMAT §5): een `<!-- ocideck:* -->
      // -markerblok plus de tabel eronder is één atomaire embed. Vóór de
      // HTML-blokregel, anders slokt die het commentaar op.
      OciMarkedTableSyntax(),
      // De twee pentest-syntaxen delen één patroon (de markerregel) en sluiten
      // elkaar uit op `canParse`: de bevindingkop tegenover de vier enveloppen
      // die in hun geheel atomair zijn. Ze staan vóór de HTML-blokregel, anders
      // slokt die het commentaar op.
      PentestFindingHeadSyntax(),
      PentestWholeBlockSyntax(),
      // Een formulierblok (kop, notice, heel veld) is één atomaire embed; de
      // grens woont in `packages/ocideck_form_core`. Ook vóór de HTML-regel.
      FormBlockSyntax(),
      TocMarkerSyntax(),
      SpacerMarkerSyntax(),
      // De transcript-marker (`<!-- transcript … -->`) reist als eigen embed;
      // alleen de geldige grammatica — een bijna-marker blijft bronfragment.
      TranscriptMarkerSyntax(),
      // Vóór de standaard-fenceregel: zonder deze regel werd een
      // ```mermaid-fence een gewoon codeblok en tekende de visuele editor
      // als enige weergave het diagram niet (#1920).
      MermaidFenceSyntax(),
      FootnoteDefSyntax(),
      EmbeddableTableSyntax(),
    ],
    // Vóór de standaard-inline-syntaxen: `[^1]` begint met een `[`, en de
    // link-regel zou er anders overheen lopen. `![alt](bron)` staat er om
    // dezelfde reden: de standaardweg maakt er een `image`-embed van die alleen
    // de bron draagt — geen alt-tekst meer, en geen bouwer om hem te tekenen.
    inlineSyntaxes: [FootnoteRefSyntax(), MarkdownImageSyntax()],
  );

  static final _mdToDelta = MarkdownToDelta(
    markdownDocument: _mdDocument,
    customElementToEmbeddable: {
      EmbeddableTimelineTable.timelineType:
          EmbeddableTimelineTable.fromMdSyntax,
      EmbeddableOciMarkedTable.blockType: EmbeddableOciMarkedTable.fromMdSyntax,
      EmbeddablePentestBlock.blockType: EmbeddablePentestBlock.fromMdSyntax,
      EmbeddableFormBlock.blockType: EmbeddableFormBlock.fromMdSyntax,
      EmbeddableTable.tableType: EmbeddableTable.fromMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.fromMdSyntax,
      EmbeddableSpacer.spacerType: EmbeddableSpacer.fromMdSyntax,
      EmbeddableTranscript.transcriptType: EmbeddableTranscript.fromMdSyntax,
      EmbeddableMermaid.mermaidType: EmbeddableMermaid.fromMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.fromMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.fromMdSyntax,
      EmbeddableMarkdownImage.imageType: EmbeddableMarkdownImage.fromMdSyntax,
      EmbeddableSourceFragment.fragmentType:
          EmbeddableSourceFragment.fromMdSyntax,
    },
  );
  static final _deltaToMd = DeltaToMarkdown(
    customEmbedHandlers: {
      EmbeddableTimelineTable.timelineType: EmbeddableTimelineTable.toMdSyntax,
      EmbeddableOciMarkedTable.blockType: EmbeddableOciMarkedTable.toMdSyntax,
      EmbeddablePentestBlock.blockType: EmbeddablePentestBlock.toMdSyntax,
      EmbeddableFormBlock.blockType: EmbeddableFormBlock.toMdSyntax,
      EmbeddableTable.tableType: EmbeddableTable.toMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.toMdSyntax,
      EmbeddableSpacer.spacerType: EmbeddableSpacer.toMdSyntax,
      EmbeddableTranscript.transcriptType: EmbeddableTranscript.toMdSyntax,
      EmbeddableMermaid.mermaidType: EmbeddableMermaid.toMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.toMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.toMdSyntax,
      EmbeddableMarkdownImage.imageType: EmbeddableMarkdownImage.toMdSyntax,
      EmbeddableListBlock.listBlockType: EmbeddableListBlock.toMdSyntax,
      EmbeddableSourceFragment.fragmentType:
          EmbeddableSourceFragment.toMdSyntax,
    },
    customTextAttrsHandlers: {
      Attribute.italic.key: CustomAttributeHandler(
        beforeContent: (attribute, node, output) {
          if (!_nodeHasAttr(node.previous, attribute.key)) {
            output.write('*');
          }
        },
        afterContent: (attribute, node, output) {
          if (!_nodeHasAttr(node.next, attribute.key)) {
            output.write('*');
          }
        },
      ),
    },
  );

  static Document documentFromMarkdown(String markdown) {
    if (markdown.isEmpty) {
      return Document();
    }
    // Wat de rijke-tekstlaag niet verliesvrij kan dragen (HTML-commentaar,
    // ontsnapte leestekens, losse tabelregels) wordt vóór de parse in een
    // sentinelpaar gewikkeld; `SourceFragmentSyntax` claimt dat bereik als één
    // `x-embed-source-fragment` met de bron verbatim (#2463). Zo blijft alleen
    // dát stuk bron — de rest van het document bewerk je gewoon visueel.
    return Document.fromDelta(
      _mdToDelta.convert(wrapSourceFragments(markdown)),
    );
  }

  static String markdownFromDocument(Document document) {
    final raw = _deltaToMd.convertDocument(document).trimRight();
    return _normalizeQuillOutput(raw).replaceAll(_writtenOutRule, '---');
  }

  /// `DeltaToMarkdown` schrijft een scheiding als `- - -`. Betekenis-identiek,
  /// maar OciDeck schrijft en documenteert `---` (het pagina-einde in de
  /// documentmodus), en zonder deze omzetting herschreef één visuele bewerking
  /// stilzwijgend elke scheiding in het bestand van de gebruiker.
  static final _writtenOutRule = RegExp(r'^- - -$', multiLine: true);
}

/// Quill schrijft in gewone proza enkele leestekens defensief escaped; die
/// bestaande normalisatie blijft gewenst. In een GFM-tabel is `\|` daarentegen
/// structuur: de backslash verwijderen splitst één cel in twee. Tabelregels
/// reizen daarom via de opslagnormalisatie, alle andere regels via de bestaande
/// schermnormalisatie.
///
/// De regels van een formulierblok (FORM_INTAKE.md §4.9) gaan er helemaal
/// buiten: die zijn atomair en horen byte-gelijk terug te komen. Zonder die
/// uitzondering maakte deze normalisatie van een antwoord `\*` een `*`, haalde ze
/// een zachte koppelteken uit een label en schreef ze een CRLF om — en een label
/// dat verandert is sjabloontekst die niet meer overeenkomt met het gepubliceerde
/// formulier, dus een inzending die de organisator afwijst.
///
/// Voor het atomaire bereik van een pentest-envelop (PENTEST_DOCUMENT.md §5.5,
/// `block.start..block.atomicEnd`) geldt hetzelfde: de kop van een bevinding en
/// de vier enveloppen die in hun geheel atomair zijn. Een scopeobject met `\*`,
/// een testnaam met een zacht koppelteken of een NBSP in de ondertekening is
/// anders na één visuele bewerking een andere tekst dan de tester schreef. De
/// sectieteksten onder `#### Description` e.d. liggen na `atomicEnd` en blijven
/// gewone, genormaliseerde Markdown.
///
/// Beide scans draaien op de RAUWE uitvoer van `DeltaToMarkdown`. Dat is juist:
/// een atomaire embed staat daar letterlijk in (marker, kop en veldregels
/// onaangeroerd), terwijl het proza eromheen nog ontsnapt is en dus nooit voor
/// een markerregel kan doorgaan. Een regel is atomair als één van de twee scans
/// hem opeist, zoals ook de visuele poort en de brug doen; hij wordt daarmee
/// precies één keer geschreven, nooit dubbel.
String _normalizeQuillOutput(String raw) {
  // Een bronfragment staat verbatim tussen zijn sentinelpaar in de rauwe
  // uitvoer — de regels ertussen mogen de normalisatie niet aanraken (daar
  // wonen juist de escapes en commentaar die gewone proza-normalisatie zou
  // wegstrepen). De sentinelregels zelf zijn drager, geen inhoud: ze vallen
  // weg voordat de tekst het bestand bereikt. Een begin zonder einde —
  /// kan alleen als de gebruiker de sentinel letterlijk als tekst schreef —
  // laat de resterende regels verbatim: teveel bewaren is veilig, wegstrepen
  // nooit.
  final pentest = scanPentestBlocks(raw);
  final forms = scanFormBlocks(raw);
  final begin = RegExp('^$sourceFragmentBegin\$');
  final end = RegExp('^$sourceFragmentEnd\$');
  final lines = raw.split('\n');
  final fragmentLines = <int>{};
  for (var i = 0; i < lines.length; i++) {
    if (!begin.hasMatch(lines[i])) continue;
    var j = i + 1;
    while (j < lines.length && !end.hasMatch(lines[j])) {
      fragmentLines.add(j++);
    }
    if (j < lines.length) i = j; // verder na de eindsentinel
  }
  if (pentest.isEmpty && forms.isEmpty && fragmentLines.isEmpty) {
    return _normalizeProse(raw);
  }

  final out = <String>[];
  final prose = <String>[];
  void flushProse() {
    if (prose.isEmpty) return;
    out.add(_normalizeProse(prose.join('\n')));
    prose.clear();
  }

  for (var i = 0; i < lines.length; i++) {
    if (begin.hasMatch(lines[i]) || end.hasMatch(lines[i])) continue;
    if (pentest.isAtomicLine(i) ||
        forms.isAtomicLine(i) ||
        fragmentLines.contains(i)) {
      flushProse();
      out.add(lines[i]);
    } else {
      prose.add(lines[i]);
    }
  }
  flushProse();
  return out.join('\n');
}

String _normalizeProse(String raw) {
  final stored = normalizeRichTextMarkdownForStorage(raw);
  return stored
      .split('\n')
      .map(
        (line) => line.trimLeft().startsWith('|')
            ? line
            : unescapeMarkdownEscapes(line),
      )
      .join('\n');
}

bool _nodeHasAttr(Node? node, String attributeKey) {
  if (node == null) return false;
  return node.style.attributes.containsKey(attributeKey);
}
