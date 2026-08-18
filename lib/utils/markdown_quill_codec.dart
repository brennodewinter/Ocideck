import 'package:flutter_quill/flutter_quill.dart';
import 'package:markdown/markdown.dart' as md;
import 'package:markdown_quill/markdown_quill.dart';

import 'footnote_embed_syntax.dart';
import 'markdown_paste_cleanup.dart';
import 'toc_embed_syntax.dart';

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
      TocMarkerSyntax(),
      FootnoteDefSyntax(),
      EmbeddableTableSyntax(),
    ],
    // Vóór de standaard-inline-syntaxen: `[^1]` begint met een `[`, en de
    // link-regel zou er anders overheen lopen.
    inlineSyntaxes: [FootnoteRefSyntax()],
  );

  static final _mdToDelta = MarkdownToDelta(
    markdownDocument: _mdDocument,
    customElementToEmbeddable: {
      EmbeddableTable.tableType: EmbeddableTable.fromMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.fromMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.fromMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.fromMdSyntax,
    },
  );
  static final _deltaToMd = DeltaToMarkdown(
    customEmbedHandlers: {
      EmbeddableTable.tableType: EmbeddableTable.toMdSyntax,
      EmbeddableToc.tocType: EmbeddableToc.toMdSyntax,
      EmbeddableFootnoteRef.footnoteRefType: EmbeddableFootnoteRef.toMdSyntax,
      EmbeddableFootnoteDef.footnoteDefType: EmbeddableFootnoteDef.toMdSyntax,
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
    return normalizeRichTextMarkdown(raw).replaceAll(_writtenOutRule, '---');
  }

  /// `DeltaToMarkdown` schrijft een scheiding als `- - -`. Betekenis-identiek,
  /// maar OciDeck schrijft en documenteert `---` (het pagina-einde in de
  /// documentmodus), en zonder deze omzetting herschreef één visuele bewerking
  /// stilzwijgend elke scheiding in het bestand van de gebruiker.
  static final _writtenOutRule = RegExp(r'^- - -$', multiLine: true);
}

bool _nodeHasAttr(Node? node, String attributeKey) {
  if (node == null) return false;
  return node.style.attributes.containsKey(attributeKey);
}
