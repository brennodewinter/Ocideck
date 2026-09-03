import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'footnote_embed_syntax.dart';
import 'image_embed_syntax.dart';
import 'list_block_embed_syntax.dart';
import 'markdown_paste_cleanup.dart';
import 'mermaid_embed_syntax.dart';
import 'pentest_block_embed_syntax.dart';
import 'toc_embed_syntax.dart';
import 'timeline_table_embed_syntax.dart';

/// Round-trip conversion between stored markdown and a Quill document.
///
/// GFM-tabellen worden als **blok-embed** ([EmbeddableTable], type
/// `x-embed-table`) door de heen- en terugweg gedragen, in plaats van als losse
/// woorden uiteen te vallen. Zo blijft een tabel in de visuele editor een
/// getekend, byte-getrouw round-trippend blok — de reden dat de tabel niet meer
/// als markdown-beperking hoeft terug te vallen (zie [markdownVisualLimitations]).
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
      TimelineTableSyntax(),
      // De twee pentest-syntaxen delen één patroon (de markerregel) en sluiten
      // elkaar uit op `canParse`: de bevindingkop tegenover de vier enveloppen
      // die in hun geheel atomair zijn. Ze staan vóór de HTML-blokregel, anders
      // slokt die het commentaar op.
      PentestFindingHeadSyntax(),
      PentestWholeBlockSyntax(),
      TocMarkerSyntax(),
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
      EmbeddablePentestBlock.blockType: EmbeddablePentestBlock.fromMdSyntax,
      EmbeddableTable.tableType: EmbeddableTable.fromMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.fromMdSyntax,
      EmbeddableMermaid.mermaidType: EmbeddableMermaid.fromMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.fromMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.fromMdSyntax,
      EmbeddableMarkdownImage.imageType: EmbeddableMarkdownImage.fromMdSyntax,
    },
  );
  static final _deltaToMd = DeltaToMarkdown(
    customEmbedHandlers: {
      EmbeddableTimelineTable.timelineType: EmbeddableTimelineTable.toMdSyntax,
      EmbeddablePentestBlock.blockType: EmbeddablePentestBlock.toMdSyntax,
      EmbeddableTable.tableType: EmbeddableTable.toMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.toMdSyntax,
      EmbeddableMermaid.mermaidType: EmbeddableMermaid.toMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.toMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.toMdSyntax,
      EmbeddableMarkdownImage.imageType: EmbeddableMarkdownImage.toMdSyntax,
      EmbeddableListBlock.listBlockType: EmbeddableListBlock.toMdSyntax,
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
    return Document.fromDelta(_mdToDelta.convert(markdown));
  }

  static String markdownFromDocument(Document document) {
    final raw = _deltaToMd.convert(document.toDelta()).trimRight();
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
String _normalizeQuillOutput(String raw) {
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
