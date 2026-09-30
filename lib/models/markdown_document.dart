import 'dart:typed_data';

import '../utils/document_front_matter.dart';
import '../utils/utf8_bom.dart';
import 'deck.dart';
import 'markdown_kind.dart';
import 'markdown_outline.dart';
import 'markdown_source_document.dart';

/// Een doorlopend Markdown-document dat OciDeck bewerkt en byte-getrouw op
/// schijf bewaart als een plat `.md` (zie `docs/design/DOCUMENT_MODE.md`).
///
/// Anders dan een `Deck`, dat de Markdown deconstruéért tot getypeerde slides en
/// die terugschrijft (dus verliest wat het niet kan voorstellen), *ís* een
/// document de bron zelf: [toMarkdown] geeft exact de bytes terug die erin
/// gingen — geen `marp:`-kop, geen dia-scheiding, geen normalisatie. Het leunt
/// op [MarkdownSourceDocument], dat de bron verbatim vasthoudt en er alleen
/// structurele bereiken en een koppenoverzicht uit afleidt (voor navigatie en
/// blok-bewerkingen) zonder ook maar één byte te wijzigen.
class MarkdownDocument {
  MarkdownDocument._(this._source, this._frontMatterMetadata, this.hasUtf8Bom);

  final MarkdownSourceDocument _source;
  final DocumentFrontMatterMetadata _frontMatterMetadata;

  /// Of het bestand met een UTF-8-BOM (`EF BB BF`) begon. De BOM zit bewust
  /// **niet** in [source] — dan zag de front-matter-detectie geen `---` meer op
  /// regel één en stond er een onzichtbaar teken in de editor — maar reist als
  /// vlag mee en gaat in [toBytes] terug voor de eerste byte. Zonder die vlag
  /// verloor open → opslaan de BOM stil (DOCUMENT_MODE.md §3.1).
  final bool hasUtf8Bom;

  /// Leest een document uit de ruwe bytes van een `.md`. Normaliseert niets:
  /// regeleindes, onzichtbare tekens en een ontbrekende slot-newline blijven
  /// exact staan.
  ///
  /// [hasUtf8Bom] is iets wat alleen de aanroeper weet die de *bytes* las: in de
  /// string is de BOM al weggedecodeerd. Zie `decodeUtf8KeepingBomFlag`.
  factory MarkdownDocument.parse(String source, {bool hasUtf8Bom = false}) =>
      MarkdownDocument._(
        MarkdownSourceDocument.parse(source),
        documentFrontMatterMetadata(source),
        hasUtf8Bom,
      );

  /// De soort is per definitie [MarkdownKind.document]; een presentatie loopt
  /// via `Deck`. Bedoeld voor plekken die generiek over een geopend bestand
  /// redeneren (tabblad, recente-lijst).
  MarkdownKind get kind => MarkdownKind.document;

  /// De ruwe bron, byte-identiek aan wat is ingelezen.
  String get source => _source.source;

  /// De inhoud zonder het leidende YAML-frontmatter-blok. De editor bewerkt en
  /// toont dít — de frontmatter draagt alleen de stijl en wordt niet als tekst
  /// getoond. Altijd geldt `frontMatter + body == source`.
  String get body => source.substring(_frontMatterMetadata.frontMatter.length);

  /// Het verbatim frontmatter-blok (of `''`) dat de stijl draagt.
  String get frontMatter => _frontMatterMetadata.frontMatter;

  /// De gekozen documentstijl: de naam van een stijlprofiel uit de `theme:`-
  /// sleutel in de frontmatter, of `null` bij een platte `.md` zonder stijl.
  String? get styleName {
    final values = _frontMatterMetadata.valuesFor('theme');
    return values.isEmpty || values.first.isEmpty ? null : values.first;
  }

  /// De ene TLP-classificatie van het hele document. Documenten hebben geen
  /// pagina- of sectieniveau: de markering geldt overal of nergens.
  TlpLevel get tlp => _frontMatterMetadata
      .valuesFor('tlp')
      .fold(
        TlpLevel.none,
        (strictest, value) => effectiveTlp(
          deckTlp: strictest,
          slideTlp: TlpLevelX.fromKey(value),
        ),
      );

  /// Vrije scalaire velden voor documentkop en -voet, in bronvolgorde.
  Map<String, String> get fields => _frontMatterMetadata.fields;

  /// Een nieuw document met dezelfde frontmatter maar een vervangen body. De
  /// stijl blijft staan; alleen de inhoud verandert.
  ///
  /// Delegeert naar [withSource], dat al controleert of de frontmatter in de
  /// nieuwe bron dezelfde is. Zonder die controle — wanneer het document geen
  /// frontmatter heeft en de body opent met `---` — zou de oude (lege) metadata
  /// worden hergebruikt terwijl de bron wel een frontmatter-blok heeft, en
  /// zouden [body] en [frontMatter] niet meer kloppen (#1682).
  MarkdownDocument withBody(String nextBody) =>
      withSource(frontMatter + nextBody);

  /// Een nieuw document met de stijl gezet op [name] (of verwijderd bij `null`).
  /// Byte-chirurgisch: een platte `.md` zonder stijl blijft byte-identiek als je
  /// stijl zet en weer wist (zie [withDocumentStyleName]).
  MarkdownDocument withStyleName(String? name) =>
      withSource(withDocumentStyleName(source, name));

  /// Zet de documentbrede classificatie byte-chirurgisch in de front matter.
  MarkdownDocument withTlp(TlpLevel level) => withSource(
    withDocumentFrontMatterKey(
      source,
      'tlp',
      level == TlpLevel.none ? null : level.key,
    ),
  );

  /// Vervangt alle vrije scalaire documentvelden byte-chirurgisch.
  MarkdownDocument withFields(Map<String, String> fields) =>
      withSource(withDocumentFields(source, fields));

  /// De tekst die naar schijf gaat: exact de bron. Nooit her-serialiseren — dat
  /// is de rode lijn die een plat document plat en maximaal uitwisselbaar houdt.
  /// Let op: dit is de *tekst*; een eventuele BOM zit er niet in, zie [toBytes].
  String toMarkdown() => _source.source;

  /// De bytes die naar schijf gaan: [toMarkdown] als UTF-8, met de BOM ervoor
  /// wanneer het bestand er een had ([hasUtf8Bom]). Schrijven en hashen lopen
  /// hierlangs, nooit langs `utf8.encode(toMarkdown())`, anders klopt de hash
  /// niet met het bestand.
  Uint8List toBytes() => encodeUtf8WithBom(source, hasBom: hasUtf8Bom);

  /// De koppenstructuur (voor de Overzicht-rail), afgeleid zonder te reparsen.
  List<MarkdownOutlineEntry> get outline => _source.outline;

  /// Het onderliggende bronmodel, voor blok-precieze bewerkingen (bv. één tabel
  /// of grafiek vervangen zonder de rest aan te raken).
  MarkdownSourceDocument get sourceDocument => _source;

  bool get isEmpty => _source.source.isEmpty;

  /// Vervangt de hele inhoud — bijvoorbeeld na een bewerking in de editor — en
  /// levert een nieuw document op. De identiteit van ongewijzigde blokken blijft
  /// behouden, zodat cursor- en selectiestand niet nodeloos verspringen.
  MarkdownDocument withSource(String next) {
    final keepsFrontMatter = frontMatter.isEmpty
        ? !next.startsWith('---\n') && !next.startsWith('---\r\n')
        : next.startsWith(frontMatter);
    return MarkdownDocument._(
      _source.reparse(next),
      keepsFrontMatter
          ? _frontMatterMetadata
          : documentFrontMatterMetadata(next),
      hasUtf8Bom,
    );
  }
}
